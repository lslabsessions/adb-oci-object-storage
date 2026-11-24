-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.
SET SERVEROUTPUT ON

DECLARE
  l_data BLOB;

  PROCEDURE release_temp IS
  BEGIN
    IF DBMS_LOB.ISTEMPORARY(l_data) = 1 THEN
      DBMS_LOB.FREETEMPORARY(l_data);
    END IF;
  END;
BEGIN
  l_data := DBMS_CLOUD.GET_OBJECT(
    credential_name => 'OCI_STORAGE_LAB_CRED',
    object_uri      =>
      'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/BUCKET_NAMESPACE/b/adb-oci-storage-lab/o/incoming/hello.txt'
  );

  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('Credential: OCI_STORAGE_LAB_CRED');
  DBMS_OUTPUT.PUT_LINE('Bytes: ' || DBMS_LOB.GETLENGTH(l_data));

  -- The lab sample is a short UTF-8 text file.
  DBMS_OUTPUT.PUT_LINE(
    UTL_I18N.RAW_TO_CHAR(
      DBMS_LOB.SUBSTR(l_data, 2000, 1),
      'AL32UTF8'
    )
  );

  release_temp;
EXCEPTION
  WHEN OTHERS THEN
    release_temp;
    RAISE;
END;
/