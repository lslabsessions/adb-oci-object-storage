-- Run as application schema after STORAGE_API package compiles successfully
-- Application schema must already be REST-enabled. Keep its existing ORDS schema alias
-- This script creates the storage.lab ORDS module and its access privilege

SET DEFINE OFF
SET SERVEROUTPUT ON


DECLARE
    l_count    NUMBER;
    l_roles    OWA.VC_ARR;
    l_patterns OWA.VC_ARR;
    l_modules  OWA.VC_ARR;
BEGIN

    ORDS.DEFINE_MODULE(
        p_module_name => 'storage.lab',
        p_base_path   => '/storage-lab/',
        p_status      => 'NOT_PUBLISHED',
        p_comments    => 'Request temporary access to files in OCI Object Storage.'
    );

    SELECT COUNT(*) INTO l_count
    FROM user_ords_roles WHERE name = 'storage_supplier';
    IF l_count = 0 THEN
        ORDS.CREATE_ROLE(p_role_name => 'storage_supplier');
    END IF;

    l_roles(1) := 'storage_supplier';
    l_modules(1) := 'storage.lab';
    ORDS.DEFINE_PRIVILEGE(
        p_privilege_name => 'storage.lab.access',
        p_roles          => l_roles,
        p_patterns       => l_patterns,
        p_modules        => l_modules,
        p_label          => 'Storage lab access'
    );

    -- POST /storage-lab/uploads
    -- JSON body: {"file_name":"hello.txt"}
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'storage.lab',
        p_pattern     => 'uploads'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name   => 'storage.lab',
        p_pattern       => 'uploads',
        p_method        => 'POST',
        p_source_type   => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_source        => q'~
DECLARE
    l_body       CLOB := :body_text;
    l_request    JSON_OBJECT_T;
    l_file_value JSON_ELEMENT_T;
    l_response   JSON_OBJECT_T := JSON_OBJECT_T();
    l_file_name  VARCHAR2(32767);
    l_upload_id  VARCHAR2(32);
    l_par_url    VARCHAR2(32767);
    l_expires_at TIMESTAMP WITH TIME ZONE;
    l_error_code NUMBER;
BEGIN
    BEGIN
        IF :current_user IS NULL THEN
            RAISE_APPLICATION_ERROR(-20011, 'Authentication required.');
        END IF;

        BEGIN
            l_request := JSON_OBJECT_T.parse(l_body);
            l_file_value := l_request.get('file_name');
            IF l_file_value IS NULL OR NOT l_file_value.is_string() THEN
                RAISE_APPLICATION_ERROR(-20010, 'file_name must be a JSON string.');
            END IF;
            l_file_name := l_request.get_string('file_name');
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20010, 'Invalid JSON or file_name.');
        END;

        storage_api.request_upload(
            p_ords_username => :current_user,
            p_file_name     => l_file_name,
            p_upload_id     => l_upload_id,
            p_par_url       => l_par_url,
            p_expires_at    => l_expires_at
        );

        :status_code := 201;
        l_response.put('upload_id', l_upload_id);
        l_response.put('par_url', l_par_url);
        l_response.put('expires_at',
            TO_CHAR(SYS_EXTRACT_UTC(l_expires_at), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            l_response := JSON_OBJECT_T();
            CASE
                WHEN l_error_code = -20011 THEN
                    :status_code := 401;
                    l_response.put('error', 'Authentication required.');
                WHEN l_error_code = -20001 THEN
                    :status_code := 403;
                    l_response.put('error', 'Supplier is not registered.');
                WHEN l_error_code IN (-20002, -20010) THEN
                    :status_code := 400;
                    l_response.put('error', 'Send a simple file_name in a JSON object.');
                ELSE
                    :status_code := 500;
                    l_response.put('error', 'Could not create the upload request.');
            END CASE;
            -- Return the error number without a stack trace or request URL.
            l_response.put('error_code', l_error_code);
    END;

    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    HTP.p('Cache-Control: no-store');
    OWA_UTIL.http_header_close;
    HTP.prn(l_response.to_string());
END;
~'
    );

    -- POST /storage-lab/uploads/{upload_id}/download
    -- Call after the PUT to Object Storage has completed. No body is needed.
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'storage.lab',
        p_pattern     => 'uploads/:upload_id/download'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'storage.lab',
        p_pattern     => 'uploads/:upload_id/download',
        p_method      => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_source      => q'~
DECLARE
    l_upload_id  VARCHAR2(32767) := :upload_id;
    l_response   JSON_OBJECT_T := JSON_OBJECT_T();
    l_par_url    VARCHAR2(32767);
    l_expires_at TIMESTAMP WITH TIME ZONE;
    l_error_code NUMBER;
BEGIN
    BEGIN
        IF :current_user IS NULL THEN
            RAISE_APPLICATION_ERROR(-20011, 'Authentication required.');
        END IF;

        storage_api.request_download(
            p_ords_username => :current_user,
            p_upload_id     => l_upload_id,
            p_par_url       => l_par_url,
            p_expires_at    => l_expires_at
        );

        :status_code := 200;
        l_response.put('upload_id', l_upload_id);
        l_response.put('par_url', l_par_url);
        l_response.put('expires_at',
            TO_CHAR(SYS_EXTRACT_UTC(l_expires_at), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            l_response := JSON_OBJECT_T();
            CASE l_error_code
                WHEN -20011 THEN
                    :status_code := 401;
                    l_response.put('error', 'Authentication required.');
                WHEN -20001 THEN
                    :status_code := 403;
                    l_response.put('error', 'Supplier is not registered.');
                WHEN -20003 THEN
                    :status_code := 404;
                    l_response.put('error', 'Upload not found for this supplier.');
                ELSE
                    :status_code := 500;
                    l_response.put('error', 'Could not prepare the download.');
            END CASE;
            l_response.put('error_code', l_error_code);
    END;

    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    HTP.p('Cache-Control: no-store');
    OWA_UTIL.http_header_close;
    HTP.prn(l_response.to_string());
END;
~'
    );

    -- Publish after the access privilege and handlers have been defined.
    ORDS.PUBLISH_MODULE(p_module_name => 'storage.lab', p_status => 'PUBLISHED');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Expected: storage.lab, /storage-lab/, PUBLISHED.
SELECT name, uri_prefix, status
FROM user_ords_modules
WHERE name = 'storage.lab';

-- Expected: two POST handlers.
SELECT t.uri_template, h.method
FROM user_ords_modules m
JOIN user_ords_templates t ON t.module_id = m.id
JOIN user_ords_handlers h ON h.template_id = t.id
WHERE m.name = 'storage.lab'
ORDER BY t.uri_template;

SELECT name FROM user_ords_roles WHERE name = 'storage_supplier';
SELECT name FROM user_ords_privileges WHERE name = 'storage.lab.access';
