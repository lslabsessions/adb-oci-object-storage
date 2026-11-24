# Storage concepts

## Objects and prefixes

The lab bucket contains objects such as `incoming/hello.txt` and `outgoing/from_directory.txt`. An object consists of its contents and metadata, identified by its name within the bucket.

Object names can include `/`. For example:

```text
incoming/1/<upload_id>/hello.txt
```

The console presents these prefixes as folders, but the complete string is the object name. There is no corresponding `incoming` database directory. Multiple prefix levels are possible, and a prefix is optional.

In the supplier application, `file_name` is `hello.txt`; `object_name` adds the supplier ID and generated upload ID. The application chooses this full name when it creates the upload request.

An object URL may encode `/` inside the object name as `%2F`. This is URL encoding, not a different filename. The lab also successfully used `incoming/hello.txt` after the `/o/` segment of the regular Object Storage URL.

Reference: [Object Storage objects](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/managingobjects.htm).

## A database DIRECTORY

`OCI_STORAGE_LAB_DIR` is a database object that provides a name for a filesystem location. Autonomous Database manages the underlying storage; the lab accesses it through SQL and PL/SQL rather than an operating-system login.

The directory was created as `ADMIN`:

```sql
CREATE DIRECTORY OCI_STORAGE_LAB_DIR AS 'oci_storage_lab';
GRANT READ, WRITE ON DIRECTORY OCI_STORAGE_LAB_DIR TO APP_DEV;
```

In Autonomous Database, `oci_storage_lab` is a relative path. The database resolves it under its managed filesystem location. `ALL_DIRECTORIES` shows the resulting path:

```sql
SELECT directory_name, directory_path
FROM all_directories
WHERE directory_name = 'OCI_STORAGE_LAB_DIR';
```

Directory objects share a single database namespace; they are not owned by an individual application schema. The grants allow `APP_DEV` to work with files through this directory. The OCI bucket is a separate cloud resource, not an object owned by `APP_DEV`.

References: [Autonomous Database directories](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/create-manage-directory.html) and [CREATE DIRECTORY](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/CREATE-DIRECTORY.html).

## Direct object access and local files

| Operation | Interface used in the lab | Result |
| --- | --- | --- |
| Read an object directly | `DBMS_CLOUD.GET_OBJECT` function | A BLOB available to PL/SQL |
| Copy an object to local storage | `DBMS_CLOUD.GET_OBJECT` procedure with a directory | A file accessible through the directory |
| Upload a local file | `DBMS_CLOUD.PUT_OBJECT` with `directory_name` and `file_name` | An object in the bucket |
| Upload binary contents directly | `DBMS_CLOUD.PUT_OBJECT` with `contents` | An object created from a BLOB |
| Write or read local text | `UTL_FILE` | Files in the database directory |

A BLOB is not automatically a file on disk or a row in a table. In these examples, PL/SQL uses it to hold bytes during processing. Text display requires decoding those bytes; the small sample uses UTF-8.

The two upload tests produced the same 63-byte text through different routes: a file written with `UTL_FILE`, and a BLOB generated in PL/SQL. Both objects were downloaded and compared successfully.

Reference: [DBMS_CLOUD subprograms](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-subprograms.html).

## When a directory is useful

The directory tests demonstrate a local-file workflow. This is useful when an existing procedure already writes files with `UTL_FILE`, or when a database API expects a directory and filename.

Directories also appear in other Oracle features:

| Feature | Example use |
| --- | --- |
| Data Pump | Dump and log files; Autonomous Database provides `DATA_PUMP_DIR` |
| Local data loading | `DBMS_CLOUD` can load or query supported files from a directory |
| Customer-managed wallets | A wallet file can be copied from a bucket to a directory for an API that requires it |

These are additional use cases, not additional tests performed by this project. A wallet is a file or collection of files containing security material; it is not itself a storage location. Its directory is the location used by the relevant API. Wallet requirements depend on the connection and service configuration.

The supplier demonstration does not need a local directory because it exchanges the file through Object Storage URLs.

References: [directory management and Data Pump](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/create-manage-directory.html), [loading from directories](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/load-data-directory.html), and [customer-managed wallets](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/external-calls-with-customer-managed-wallet.html).

