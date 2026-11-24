-- Run as ADMIN 
-- Replace APP_SCHEMA with application schema

CREATE DIRECTORY OCI_STORAGE_LAB_DIR AS 'oci_storage_lab';

GRANT READ, WRITE ON DIRECTORY OCI_STORAGE_LAB_DIR TO <APP_SCHEMA>;

SELECT directory_name, directory_path
FROM all_directories
WHERE directory_name = 'OCI_STORAGE_LAB_DIR';

SELECT * FROM DBMS_CLOUD.LIST_FILES('OCI_STORAGE_LAB_DIR');
