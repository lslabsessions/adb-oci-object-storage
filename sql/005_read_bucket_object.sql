-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.

SET SERVEROUTPUT ON
DECLARE
  l_uri CONSTANT VARCHAR2(2048) :=
    'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/BUCKET_NAMESPACE/b/adb-oci-storage-lab/o/incoming/hello.txt';
  l_data BLOB;
BEGIN
  IF USER <> 'APP_DEV' OR INSTR(l_uri, 'BUCKET_NAMESPACE') > 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Connect as APP_DEV and set the Object Storage namespace.');
  END IF;
  l_data := DBMS_CLOUD.GET_OBJECT(
    credential_name => 'OCI$RESOURCE_PRINCIPAL',
    object_uri => l_uri);
  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('Object: incoming/hello.txt');
  DBMS_OUTPUT.PUT_LINE('Bytes: ' || DBMS_LOB.GETLENGTH(l_data));
  -- The lab sample is short UTF-8 text.
  DBMS_OUTPUT.PUT_LINE(UTL_I18N.RAW_TO_CHAR(DBMS_LOB.SUBSTR(l_data, 2000, 1), 'AL32UTF8'));
  IF DBMS_LOB.ISTEMPORARY(l_data) = 1 THEN
    DBMS_LOB.FREETEMPORARY(l_data);
  END IF;
END;
/