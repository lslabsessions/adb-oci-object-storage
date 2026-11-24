-- Run as ADMIN. Review both query results before run the commands

SELECT owner, credential_name FROM dba_credentials
WHERE owner = 'ADMIN' AND credential_name = 'OCI$RESOURCE_PRINCIPAL';

SELECT grantee, privilege, table_name FROM dba_tab_privs
WHERE owner = 'ADMIN' AND table_name = 'OCI$RESOURCE_PRINCIPAL'
  AND grantee = 'APP_DEV' AND privilege = 'EXECUTE';

-- If the first result is empty, run the following command:
-- EXECUTE DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL();

-- If the second result is empty, run the following command:
-- EXECUTE DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'APP_DEV');
