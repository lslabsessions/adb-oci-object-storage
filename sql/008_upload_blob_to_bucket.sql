-- Run as application schema 
-- Replace BUCKET_NAMESPACE with the bucket's Object Storage namespace.
-- Repeating the upload replaces outgoing/from_blob.txt
SET SERVEROUTPUT ON
DECLARE
  c_base CONSTANT VARCHAR2(2048) :=
  'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/BUCKET_NAMESPACE/b/adb-oci-storage-lab/o/outgoing/';	
  c_cred CONSTANT VARCHAR2(30) := 'OCI$RESOURCE_PRINCIPAL';
  -- Reproduce the text and both Linux line endings written by 002.
  l_bytes RAW(32767) := UTL_I18N.STRING_TO_RAW(
    'OCI storage lab' || CHR(10) ||
    'Created with UTL_FILE in a database DIRECTORY.' || CHR(10), 'AL32UTF8');
  l_generated BLOB;
  l_reference BLOB;
  l_uploaded  BLOB;

  PROCEDURE release_temp(p_lob IN OUT NOCOPY BLOB) IS
  BEGIN
    IF DBMS_LOB.ISTEMPORARY(p_lob) = 1 THEN DBMS_LOB.FREETEMPORARY(p_lob); END IF;
  END;
BEGIN
  l_reference := DBMS_CLOUD.GET_OBJECT(credential_name => c_cred,
                                       object_uri => c_base || 'from_directory.txt');
  DBMS_LOB.CREATETEMPORARY(l_generated, TRUE, DBMS_LOB.CALL);
  DBMS_LOB.WRITEAPPEND(l_generated, UTL_RAW.LENGTH(l_bytes), l_bytes);

  DBMS_CLOUD.PUT_OBJECT(credential_name => c_cred,
                        object_uri => c_base || 'from_blob.txt',
                        contents => l_generated);
  l_uploaded := DBMS_CLOUD.GET_OBJECT(credential_name => c_cred,
                                      object_uri => c_base || 'from_blob.txt');
  DBMS_OUTPUT.PUT_LINE('User: ' || USER);
  DBMS_OUTPUT.PUT_LINE('outgoing/from_directory.txt: ' || DBMS_LOB.GETLENGTH(l_reference) || ' bytes');
  DBMS_OUTPUT.PUT_LINE('outgoing/from_blob.txt: ' || DBMS_LOB.GETLENGTH(l_uploaded) || ' bytes');
  IF DBMS_LOB.GETLENGTH(l_reference) <> DBMS_LOB.GETLENGTH(l_uploaded)
     OR DBMS_LOB.COMPARE(l_reference, l_uploaded) <> 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'Objects differ. Check the source text and line endings.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('Byte comparison: MATCH');
  release_temp(l_uploaded);
  release_temp(l_reference);
  release_temp(l_generated);
EXCEPTION WHEN OTHERS THEN
  release_temp(l_uploaded);
  release_temp(l_reference);
  release_temp(l_generated);
  RAISE;
END;
/
