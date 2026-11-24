-- Run as application schema 
-- Tables DDL used in the supplier upload flow lab.

CREATE TABLE storage_suppliers (
    supplier_id       NUMBER PRIMARY KEY,
    supplier_name     VARCHAR2(100) NOT NULL,
    ords_username     VARCHAR2(255) UNIQUE
);

-- ORDS_USERNAME will be set when OAuth is configured
-- The API identifies the supplier from the authenticated ORDS user.
INSERT INTO storage_suppliers (supplier_id, supplier_name)
VALUES (1, 'Supplier A');

COMMIT;

CREATE TABLE storage_uploads (
    upload_id         VARCHAR2(32) PRIMARY KEY,
    supplier_id       NUMBER NOT NULL REFERENCES storage_suppliers (supplier_id),
    file_name         VARCHAR2(128) NOT NULL,
    object_name       VARCHAR2(512) NOT NULL UNIQUE,
    status            VARCHAR2(20) DEFAULT 'PENDING' NOT NULL
                      CHECK (status IN ('PENDING', 'UPLOADED')),
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    upload_par_id     VARCHAR2(1024),
    upload_expires_at TIMESTAMP WITH TIME ZONE,
    read_par_id       VARCHAR2(1024),
    read_expires_at   TIMESTAMP WITH TIME ZONE
);

-- One row per upload, with its upload PAR and latest read PAR.
-- PAR IDs allow revocation. Secret PAR URLs are returned to the client only.
-- PENDING: upload requested. UPLOADED: the API has checked the object.
-- The package will revoke the upload PAR before setting UPLOADED.



-- Expected: two tables, both VALID.
SELECT object_name, status
FROM user_objects
WHERE object_type = 'TABLE'
  AND object_name IN ('STORAGE_SUPPLIERS', 'STORAGE_UPLOADS')
ORDER BY object_name;

-- Expected: Supplier A. ORDS_USERNAME is empty until OAuth is configured.
SELECT supplier_id, supplier_name, ords_username
FROM storage_suppliers;

-- Expected: 0.
SELECT COUNT(*) AS upload_count
FROM storage_uploads;


