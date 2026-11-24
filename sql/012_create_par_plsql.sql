-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.
-- Prerequisites: incoming/hello.txt exists, Resource Principal is enabled,
-- and the ADB dynamic group has OBJECT_READ and PAR_MANAGE on this bucket
-- Each run creates a new 15-minute ObjectRead PAR and deletes it after testing
-- Successful output contains no PAR URL

SET DEFINE OFF
SET SERVEROUTPUT ON

DECLARE
  c_namespace CONSTANT VARCHAR2(128) := '<BUCKET_NAMESPACE>';
  c_bucket    CONSTANT VARCHAR2(128) := 'adb-oci-storage-lab';
  c_region    CONSTANT VARCHAR2(64)  := 'eu-frankfurt-1';
  c_object    CONSTANT VARCHAR2(256) := 'incoming/hello.txt';
  c_credential CONSTANT VARCHAR2(128) := 'OCI$RESOURCE_PRINCIPAL';
  c_endpoint  CONSTANT VARCHAR2(256) :=
    'https://objectstorage.eu-frankfurt-1.oraclecloud.com';

  l_details  DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T;
  l_created  DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
  l_deleted  DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE_DELETE_PREAUTHENTICATED_REQUEST_RESPONSE_T;
  l_par_id   VARCHAR2(32767);
  l_par_url  VARCHAR2(32767);
  l_reference BLOB;
  l_download  BLOB;

  PROCEDURE release_temp(p_lob IN OUT NOCOPY BLOB) IS
  BEGIN
    IF DBMS_LOB.ISTEMPORARY(p_lob) = 1 THEN
      DBMS_LOB.FREETEMPORARY(p_lob);
    END IF;
  END;

  PROCEDURE revoke_par IS
  BEGIN
    IF l_par_id IS NOT NULL THEN
      l_deleted := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.DELETE_PREAUTHENTICATED_REQUEST(
        namespace_name  => c_namespace,
        bucket_name     => c_bucket,
        par_id          => l_par_id,
        region          => c_region,
        credential_name => c_credential
      );

      IF l_deleted.status_code IS NULL OR l_deleted.status_code <> 204 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Unexpected PAR deletion status.');
      END IF;

      l_par_id := NULL;
      DBMS_OUTPUT.PUT_LINE('PAR revoked: HTTP ' || l_deleted.status_code);
    END IF;
  END;
BEGIN
  IF c_namespace = '<BUCKET_NAMESPACE>' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Replace <BUCKET_NAMESPACE> before running this script.');
  END IF;

  -- Obtain a reference using the ADB identity before creating the PAR.
  l_reference := DBMS_CLOUD.GET_OBJECT(
    credential_name => c_credential,
    object_uri      => c_endpoint || '/n/' || c_namespace ||
                       '/b/' || c_bucket || '/o/' || c_object
  );

  l_details := DBMS_CLOUD_OCI_OBJECT_STORAGE_CREATE_PREAUTHENTICATED_REQUEST_DETAILS_T();
  l_details.name := 'lab-plsql-read-' || LOWER(RAWTOHEX(SYS_GUID()));
  l_details.object_name := c_object;
  l_details.access_type := 'ObjectRead';
  l_details.time_expires := SYSTIMESTAMP + INTERVAL '15' MINUTE;

  l_created := DBMS_CLOUD_OCI_OBS_OBJECT_STORAGE.CREATE_PREAUTHENTICATED_REQUEST(
    namespace_name => c_namespace,
    bucket_name => c_bucket,
    create_preauthenticated_request_details => l_details,
    region => c_region,
    credential_name => c_credential
  );

  l_par_id := l_created.response_body.id;

  IF l_created.status_code IS NULL OR l_created.status_code <> 200
     OR l_par_id IS NULL OR l_created.response_body.access_uri IS NULL THEN
    RAISE_APPLICATION_ERROR(-20002, 'Incomplete or unsuccessful PAR creation response.');
  END IF;

  l_par_url := c_endpoint || l_created.response_body.access_uri;

  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('PAR created: HTTP ' || l_created.status_code);
  DBMS_OUTPUT.PUT_LINE('PAR name: ' || l_created.response_body.name);
  DBMS_OUTPUT.PUT_LINE('Object: ' || c_object);
  DBMS_OUTPUT.PUT_LINE('Access type: ' || l_created.response_body.access_type);
  DBMS_OUTPUT.PUT_LINE('Expires UTC: ' ||
    TO_CHAR(SYS_EXTRACT_UTC(l_created.response_body.time_expires),
            'YYYY-MM-DD HH24:MI:SS'));

  -- The PAR supplies authorization for this GET.
  l_download := DBMS_CLOUD.GET_OBJECT(
    credential_name => NULL,
    object_uri      => l_par_url
  );

  IF DBMS_LOB.GETLENGTH(l_reference) <> DBMS_LOB.GETLENGTH(l_download)
     OR DBMS_LOB.COMPARE(l_reference, l_download) <> 0 THEN
    RAISE_APPLICATION_ERROR(-20004, 'PAR download differs from the reference object.');
  END IF;

  DBMS_OUTPUT.PUT_LINE('Bytes read via PAR: ' || DBMS_LOB.GETLENGTH(l_download));
  DBMS_OUTPUT.PUT_LINE('Byte comparison: MATCH');

  revoke_par;
  release_temp(l_download);
  release_temp(l_reference);
  DBMS_OUTPUT.PUT_LINE('Result: PASS');
EXCEPTION
  WHEN OTHERS THEN
    -- Attempt cleanup while preserving the original exception.
    BEGIN
      revoke_par;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('PAR cleanup failed. Check the bucket PAR list for this run.');
    END;
    BEGIN
      release_temp(l_download);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
    BEGIN
      release_temp(l_reference);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
    RAISE;
END;
/
