-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.
SET SERVEROUTPUT ON
DECLARE
  c_uri CONSTANT VARCHAR2(2048) :=
    'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/BUCKET_NAMESPACE/b/adb-oci-storage-lab/o/incoming/hello.txt';
  c_dir CONSTANT VARCHAR2(30) := 'OCI_STORAGE_LAB_DIR';
  c_file CONSTANT VARCHAR2(30) := 'hello.txt';
  l_exists BOOLEAN;
  l_size NUMBER;
  l_block_size BINARY_INTEGER;
  l_handle UTL_FILE.FILE_TYPE;
  l_open BOOLEAN := FALSE;
  l_local RAW(32767);
  l_source BLOB;
BEGIN
  UTL_FILE.FGETATTR(c_dir, c_file, l_exists, l_size, l_block_size);
  IF l_exists THEN
    RAISE_APPLICATION_ERROR(-20002, 'Local hello.txt already exists. Inspect it before repeating this exercise.');
  END IF;

  DBMS_CLOUD.GET_OBJECT(credential_name => 'OCI$RESOURCE_PRINCIPAL',
                        object_uri => c_uri, directory_name => c_dir, file_name => c_file);

  UTL_FILE.FGETATTR(c_dir, c_file, l_exists, l_size, l_block_size);
  IF NOT l_exists OR l_size NOT BETWEEN 1 AND 32767 THEN
    RAISE_APPLICATION_ERROR(-20003, 'Expected a small, non-empty local file.');
  END IF;
  l_handle := UTL_FILE.FOPEN(c_dir, c_file, 'rb', 32767);
  l_open := TRUE;
  UTL_FILE.GET_RAW(l_handle, l_local, l_size);
  UTL_FILE.FCLOSE(l_handle);
  l_open := FALSE;

  -- Read the source again for byte-for-byte comparison with the local file.
  l_source := DBMS_CLOUD.GET_OBJECT(credential_name => 'OCI$RESOURCE_PRINCIPAL', object_uri => c_uri);
  IF DBMS_LOB.GETLENGTH(l_source) <> l_size
     OR UTL_RAW.LENGTH(l_local) <> l_size
     OR UTL_RAW.COMPARE(l_local, DBMS_LOB.SUBSTR(l_source, l_size, 1)) <> 0 THEN
    RAISE_APPLICATION_ERROR(-20004, 'Local file differs from the source object.');
  END IF;
  IF DBMS_LOB.ISTEMPORARY(l_source) = 1 THEN DBMS_LOB.FREETEMPORARY(l_source); END IF;
  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('Local file: ' || c_dir || '/' || c_file);
  DBMS_OUTPUT.PUT_LINE('Bytes verified: ' || l_size);
  DBMS_OUTPUT.PUT_LINE(UTL_I18N.RAW_TO_CHAR(l_local, 'AL32UTF8'));
EXCEPTION WHEN OTHERS THEN
  IF l_open THEN UTL_FILE.FCLOSE(l_handle); END IF;
  RAISE;
END;
/
SELECT object_name, bytes FROM DBMS_CLOUD.LIST_FILES('OCI_STORAGE_LAB_DIR')
WHERE object_name = 'hello.txt';
