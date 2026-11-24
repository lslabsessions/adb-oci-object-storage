-- Run as application schema
-- Replace username and auth token placeholders
SET DEFINE OFF

BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'OCI_STORAGE_LAB_CRED',
    username        => '<OCI_USERNAME>',
    password        => '<OCI_AUTH_TOKEN>'
  );
END;
/

SELECT credential_name
FROM user_credentials
WHERE credential_name = 'OCI_STORAGE_LAB_CRED';