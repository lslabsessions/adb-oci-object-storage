-- Run as application schema 

SET SERVEROUTPUT ON
DECLARE
  l_file  UTL_FILE.FILE_TYPE;
  l_open  BOOLEAN := FALSE;
  l_line  VARCHAR2(32767);
  l_count PLS_INTEGER := 0;
BEGIN
  l_file := UTL_FILE.FOPEN('OCI_STORAGE_LAB_DIR', '001_local_result.txt', 'r', 32767);
  l_open := TRUE;
  LOOP
    BEGIN
      UTL_FILE.GET_LINE(l_file, l_line);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN EXIT;
    END;
    l_count := l_count + 1;
    DBMS_OUTPUT.PUT_LINE(l_line);
  END LOOP;
  UTL_FILE.FCLOSE(l_file);
  l_open := FALSE;
  DBMS_OUTPUT.PUT_LINE('Lines read: ' || l_count);
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

SELECT * FROM DBMS_CLOUD.LIST_FILES('OCI_STORAGE_LAB_DIR');
