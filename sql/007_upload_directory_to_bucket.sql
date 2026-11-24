-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.
-- Source: the text file produced by 002_write_local_file.sql. Reruns replace the same output object
SET SERVEROUTPUT ON
DECLARE
  c_dir CONSTANT VARCHAR2(30) := 'OCI_STORAGE_LAB_DIR';
  c_file CONSTANT VARCHAR2(64) := '001_local_result.txt';
  c_key CONSTANT VARCHAR2(128) := 'outgoing/from_directory.txt';
  c_uri CONSTANT VARCHAR2(2048) :=
  'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/BUCKET_NAMESPACE/b/adb-oci-storage-lab/o/' || c_key;
  l_exists BOOLEAN;
  l_bytes NUMBER;
  l_block_size BINARY_INTEGER;
  l_uploaded BLOB;
BEGIN
  UTL_FILE.FGETATTR(c_dir, c_file, l_exists, l_bytes, l_block_size);
  IF NOT l_exists THEN
    RAISE_APPLICATION_ERROR(-20002, 'Source file missing. Check the output of script 002_write_local_file.sql');
  END IF;

  DBMS_CLOUD.PUT_OBJECT(credential_name => 'OCI$RESOURCE_PRINCIPAL',
                        object_uri => c_uri, directory_name => c_dir, file_name => c_file);

  l_uploaded := DBMS_CLOUD.GET_OBJECT(credential_name => 'OCI$RESOURCE_PRINCIPAL',
                                      object_uri => c_uri);
  IF DBMS_LOB.GETLENGTH(l_uploaded) <> l_bytes THEN
    RAISE_APPLICATION_ERROR(-20003, 'Uploaded object length differs from local file length.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('Source: ' || c_dir || '/' || c_file);
  DBMS_OUTPUT.PUT_LINE('Object: ' || c_key);
  DBMS_OUTPUT.PUT_LINE('Bytes read back: ' || DBMS_LOB.GETLENGTH(l_uploaded));
  DBMS_OUTPUT.PUT_LINE(UTL_I18N.RAW_TO_CHAR(DBMS_LOB.SUBSTR(l_uploaded, 2000, 1), 'AL32UTF8'));
  IF DBMS_LOB.ISTEMPORARY(l_uploaded) = 1 THEN DBMS_LOB.FREETEMPORARY(l_uploaded); END IF;
END;
/
