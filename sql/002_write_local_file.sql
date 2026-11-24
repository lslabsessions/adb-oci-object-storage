-- Run as application schema 
-- DIRECTORY writes are not undone by ROLLBACK
-- The file check on directory is not a concurrency lock
SET SERVEROUTPUT ON
DECLARE
  l_file       UTL_FILE.FILE_TYPE;
  l_open       BOOLEAN := FALSE;
  l_exists     BOOLEAN;
  l_length     NUMBER;
  l_block_size BINARY_INTEGER;
BEGIN
  UTL_FILE.FGETATTR('OCI_STORAGE_LAB_DIR', '001_local_result.txt',
                    l_exists, l_length, l_block_size);
  IF l_exists THEN
    RAISE_APPLICATION_ERROR(-20001,
      '001_local_result.txt already exists; inspect it before repeating this test.');
  END IF;

  l_file := UTL_FILE.FOPEN('OCI_STORAGE_LAB_DIR', '001_local_result.txt', 'w', 32767);
  l_open := TRUE;
  UTL_FILE.PUT_LINE(l_file, 'OCI storage lab');
  UTL_FILE.PUT_LINE(l_file, 'Created with UTL_FILE in a database DIRECTORY.');
  UTL_FILE.FCLOSE(l_file);
  l_open := FALSE;
  DBMS_OUTPUT.PUT_LINE('Created 001_local_result.txt.');
EXCEPTION
  WHEN OTHERS THEN
    IF l_open THEN
      BEGIN
        UTL_FILE.FCLOSE(l_file);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    RAISE;
END;
/
