-- Run as application schema
-- Replace <BUCKET_NAMESPACE> below. Compiling this script does not create any PAR.
-- ORDS must pass :current_user as p_ords_username, never a value from the JSON body.

SET DEFINE OFF

CREATE OR REPLACE PACKAGE storage_api AUTHID DEFINER AS
    PROCEDURE request_upload (
        p_ords_username IN VARCHAR2,
        p_file_name     IN VARCHAR2,
        p_upload_id     OUT VARCHAR2,
        p_par_url       OUT VARCHAR2,
        p_expires_at    OUT TIMESTAMP WITH TIME ZONE
    );

    PROCEDURE request_download (
        p_ords_username IN VARCHAR2,
        p_upload_id     IN VARCHAR2,
        p_par_url       OUT VARCHAR2,
        p_expires_at    OUT TIMESTAMP WITH TIME ZONE
    );
END storage_api;
/

CREATE OR REPLACE PACKAGE BODY storage_api AS
    c_namespace  CONSTANT VARCHAR2(128) := '<BUCKET_NAMESPACE>';
    c_bucket     CONSTANT VARCHAR2(128) := 'adb-oci-storage-lab';
    c_region     CONSTANT VARCHAR2(64)  := 'eu-frankfurt-1';
    c_credential CONSTANT VARCHAR2(128) := 'OCI$RESOURCE_PRINCIPAL';
    c_endpoint   CONSTANT VARCHAR2(256) :=
        'https://objectstorage.' || c_region || '.oraclecloud.com';

    FUNCTION get_supplier_id(p_ords_username VARCHAR2) RETURN NUMBER IS
        l_supplier_id NUMBER;
    BEGIN
        SELECT supplier_id INTO l_supplier_id
        FROM storage_suppliers
        WHERE ords_username = p_ords_username;
        RETURN l_supplier_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Supplier is not registered.');
    END get_supplier_id;

    PROCEDURE revoke_par(p_par_id VARCHAR2) IS
        l_response DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
    BEGIN
        IF p_par_id IS NULL THEN RETURN; END IF;

        l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_PREAUTHENTICATED_REQUEST(
            namespace_name => c_namespace,
            bucket_name => c_bucket,
            par_id => p_par_id,
            region => c_region,
            credential_name => c_credential
        );

        IF NVL(l_response.status_code, 0) <> 204 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Could not revoke the PAR.');
        END IF;
    END revoke_par;

    FUNCTION create_par(p_object_name VARCHAR2, p_access_type VARCHAR2)
        RETURN DBMS_CLOUD_OCI_OBJECT_STORAGE_PREAUTHENTICATED_REQUEST_T
    IS
        l_details DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T;
        l_response DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
    BEGIN
        IF c_namespace = '<BUCKET_NAMESPACE>' THEN
            RAISE_APPLICATION_ERROR(-20005, 'Set c_namespace and recompile the package.');
        END IF;

        l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T();
        l_details.name := 'storage-lab-' || LOWER(RAWTOHEX(SYS_GUID()));
        l_details.object_name := p_object_name;
        l_details.access_type := p_access_type;
        l_details.time_expires := SYSTIMESTAMP + INTERVAL '15' MINUTE;

        l_response := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_PREAUTHENTICATED_REQUEST(
            namespace_name => c_namespace,
            bucket_name => c_bucket,
            create_preauthenticated_request_details => l_details,
            region => c_region,
            credential_name => c_credential
        );

        IF NVL(l_response.status_code, 0) <> 200 THEN
            RAISE_APPLICATION_ERROR(-20006, 'Could not create the PAR.');
        END IF;
        RETURN l_response.response_body;
    END create_par;

    PROCEDURE request_upload (
        p_ords_username IN VARCHAR2,
        p_file_name     IN VARCHAR2,
        p_upload_id     OUT VARCHAR2,
        p_par_url       OUT VARCHAR2,
        p_expires_at    OUT TIMESTAMP WITH TIME ZONE
    ) IS
        l_supplier_id NUMBER;
        l_upload_id   VARCHAR2(32) := LOWER(RAWTOHEX(SYS_GUID()));
        l_object_name VARCHAR2(512);
        l_par_id      VARCHAR2(32767);
        l_par         DBMS_CLOUD_OCI_OBJECT_STORAGE_PREAUTHENTICATED_REQUEST_T;
    BEGIN
        l_supplier_id := get_supplier_id(p_ords_username);

        -- Keep sample names simple, for example hello.txt or orders_2026.csv.
        IF p_file_name IS NULL OR LENGTHB(p_file_name) > 128
           OR NOT REGEXP_LIKE(p_file_name, '^[A-Za-z0-9][A-Za-z0-9._-]*$', 'c') THEN
            RAISE_APPLICATION_ERROR(-20002, 'Use a simple file name, up to 128 bytes.');
        END IF;

        l_object_name := 'incoming/' || TO_CHAR(l_supplier_id, 'TM9') ||
                         '/' || l_upload_id || '/' || p_file_name;
        l_par := create_par(l_object_name, 'ObjectWrite');
        l_par_id := l_par.id;

        INSERT INTO storage_uploads (
            upload_id, supplier_id, file_name, object_name,
            upload_par_id, upload_expires_at
        ) VALUES (
            l_upload_id, l_supplier_id, p_file_name, l_object_name,
            l_par.id, l_par.time_expires
        );

        p_upload_id := l_upload_id;
        p_par_url := c_endpoint || l_par.access_uri;
        p_expires_at := l_par.time_expires;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            -- If saving the row failed, revoke the new PAR as well.
            revoke_par(l_par_id);
            RAISE;
    END request_upload;

    PROCEDURE request_download (
        p_ords_username IN VARCHAR2,
        p_upload_id     IN VARCHAR2,
        p_par_url       OUT VARCHAR2,
        p_expires_at    OUT TIMESTAMP WITH TIME ZONE
    ) IS
        l_supplier_id NUMBER;
        l_upload      storage_uploads%ROWTYPE;
        l_data        BLOB;
        l_par_id      VARCHAR2(32767);
        l_par         DBMS_CLOUD_OCI_OBJECT_STORAGE_PREAUTHENTICATED_REQUEST_T;
    BEGIN
        l_supplier_id := get_supplier_id(p_ords_username);

        BEGIN
            SELECT * INTO l_upload
            FROM storage_uploads
            WHERE upload_id = p_upload_id
              AND supplier_id = l_supplier_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'Upload not found for this supplier.');
        END;

        -- Check the small lab file using Resource Principal.
        -- The BLOB is temporary; the file remains in the bucket.
        l_data := DBMS_CLOUD.GET_OBJECT(
            credential_name => c_credential,
            object_uri => c_endpoint || '/n/' || c_namespace ||
                          '/b/' || c_bucket || '/o/' || l_upload.object_name
        );
        IF DBMS_LOB.ISTEMPORARY(l_data) = 1 THEN
            DBMS_LOB.FREETEMPORARY(l_data);
        END IF;

        -- End write access before returning a read URL.
        revoke_par(l_upload.upload_par_id);
        UPDATE storage_uploads
        SET upload_par_id = NULL, upload_expires_at = NULL, status = 'UPLOADED'
        WHERE upload_id = p_upload_id;
        COMMIT;

        -- Keep only the latest read PAR for this upload.
        revoke_par(l_upload.read_par_id);
        UPDATE storage_uploads
        SET read_par_id = NULL, read_expires_at = NULL
        WHERE upload_id = p_upload_id;
        COMMIT;

        l_par := create_par(l_upload.object_name, 'ObjectRead');
        l_par_id := l_par.id;

        UPDATE storage_uploads
        SET read_par_id = l_par.id, read_expires_at = l_par.time_expires
        WHERE upload_id = p_upload_id;

        p_par_url := c_endpoint || l_par.access_uri;
        p_expires_at := l_par.time_expires;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF DBMS_LOB.ISTEMPORARY(l_data) = 1 THEN
                DBMS_LOB.FREETEMPORARY(l_data);
            END IF;
            revoke_par(l_par_id);
            RAISE;
    END request_download;
END storage_api;
/

SHOW ERRORS PACKAGE storage_api
SHOW ERRORS PACKAGE BODY storage_api

-- Expected: PACKAGE and PACKAGE BODY are both VALID.
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'STORAGE_API'
  AND object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY object_type;

-- Expected: no rows.
SELECT line, position, text
FROM user_errors
WHERE name = 'STORAGE_API'
ORDER BY sequence;
