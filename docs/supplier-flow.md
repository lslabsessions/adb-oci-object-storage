# Supplier file exchange through ORDS and PARs

The final example uses one supplier, one small text file and two application endpoints. The supplier authenticates to ORDS and obtains temporary access to an object in the private lab bucket.

## Application objects

| Script | Objects and purpose |
| --- | --- |
| [013_create_supplier_flow_tables.sql](../sql/013_create_supplier_flow_tables.sql) | `STORAGE_SUPPLIERS` and `STORAGE_UPLOADS` |
| [014_create_storage_api.sql](../sql/014_create_storage_api.sql) | `STORAGE_API`, which creates and revokes PARs |
| [015_create_storage_ords.sql](../sql/015_create_storage_ords.sql) | The two POST handlers, access privilege and role |
| [016_create_supplier_oauth_client.sql](../sql/016_create_supplier_oauth_client.sql) | OAuth client and its association with Supplier A |

`STORAGE_SUPPLIERS` maps the OAuth client identity to `supplier_id`. In this client-credentials flow, ORDS resolves the Bearer token and supplies the client identity through `:current_user`. The handlers pass that value to `p_ords_username`; it is not taken from the JSON body.

`STORAGE_UPLOADS` stores metadata, not file contents:

| Fields | Meaning |
| --- | --- |
| `upload_id`, `supplier_id` | The upload and its associated supplier |
| `file_name`, `object_name` | Original filename and complete name in the bucket |
| `status`, `created_at` | Application state and time the upload request was registered |
| `upload_par_id`, `upload_expires_at` | Write PAR identifier and expiry |
| `read_par_id`, `read_expires_at` | Read PAR identifier and expiry |

The PAR IDs allow the application to revoke the requests. The table does not retain the complete PAR URLs returned to the client.

## HTTP requests

The following requests were executed manually in Postman. `<ords-base-url>` represents the REST-enabled schema root, for example `https://<adb-host>/ords/app_dev`, without a trailing slash.

### 1. Obtain an OAuth token

```http
POST <ords-base-url>/oauth/token
Content-Type: application/x-www-form-urlencoded
```

Postman uses **Basic Auth**, with the OAuth client ID as the username and its client secret as the password. The **x-www-form-urlencoded** body contains:

```text
grant_type=client_credentials
```

The successful response was `200 OK`, with `token_type` equal to `bearer` and `expires_in` equal to `3600`. Its `access_token` is used by the two ORDS application requests below.

### 2. Request a write PAR

```http
POST <ords-base-url>/storage-lab/uploads
Authorization: Bearer <access-token>
Content-Type: application/json
```

Postman uses **Bearer Token** and **Body → raw → JSON**:

```json
{
  "file_name": "hello.txt"
}
```

The response was `201 Created`, containing `upload_id`, `par_url` and `expires_at`.

`STORAGE_API` identifies the supplier, validates the filename, generates an upload ID, and creates an `ObjectWrite` PAR for:

```text
incoming/<supplier_id>/<upload_id>/hello.txt
```

It inserts a `PENDING` row in `STORAGE_UPLOADS`. No file has been sent at this stage. The filename check allows a letter or digit first, followed by letters, digits, dots, underscores or hyphens, with a maximum of 128 bytes.

### 3. Upload the file

```http
PUT <write-par-url>
```

Postman uses **No Auth** and **Body → binary**, with `samples/hello.txt` selected. The exact `par_url` returned by the API is the request URL.

The request returned `200 OK`. The OCI console showed the object under the generated prefix, with a size of 57 bytes and the expected text. The PUT goes directly to Object Storage; it does not call an ORDS handler or update the upload row.

### 4. Request a read PAR

```http
POST <ords-base-url>/storage-lab/uploads/<upload_id>/download
Authorization: Bearer <access-token>
```

Postman uses **Bearer Token** and **Body → none**. The upload ID is the one associated with the file uploaded in step 3.

The procedure checks that the upload belongs to the authenticated supplier. It then reads the object using `DBMS_CLOUD.GET_OBJECT` and Resource Principal, and releases the temporary BLOB. This transfers the small sample into the database to confirm it can be read; it does not validate a business format or persist the contents in a table.

The procedure revokes the write PAR, clears its stored ID and expiry, and sets the row to `UPLOADED`. It also replaces an existing read PAR if there is one. It creates a new `ObjectRead` PAR and returns `upload_id`, `par_url` and `expires_at` with `200 OK`.

The API uses POST because this request changes application state and creates temporary access. The file itself is retrieved with GET in the next step.

### 5. Download the file

```http
GET <read-par-url>
```

Postman uses **No Auth** and **Body → none**. The response was `200 OK` with:

```text
OCI storage lab
Sample uploaded from an external system.
```

The read PAR authorizes the request directly in Object Storage. No supplier OAuth token is sent to the bucket.

## State and results

The normal sequence is `PENDING` after the upload request and `UPLOADED` after the download request confirms the object. A successful PUT by itself leaves the database row at `PENDING` because Object Storage does not notify this application automatically.

The package commits its metadata updates and performs separate Object Storage API calls. A database rollback cannot undo an upload or restore a revoked PAR. The example keeps this flow small and sequential; its purpose is to demonstrate the storage and authentication steps.

| Screenshot | Result |
| --- | --- |
| [024_oauth_token_obtained.jpg](../screenshots/024_oauth_token_obtained.jpg) | OAuth token response, HTTP 200 |
| [025_upload_par_requested.jpg](../screenshots/025_upload_par_requested.jpg) | Upload registration and write PAR response, HTTP 201 |
| [026_supplier_file_uploaded.jpg](../screenshots/026_supplier_file_uploaded.jpg) | Direct PUT, HTTP 200 |
| [027_supplier_object_in_bucket.jpg](../screenshots/027_supplier_object_in_bucket.jpg) | Stored object, 57 bytes and sample contents |
| [028_download_par_requested.jpg](../screenshots/028_download_par_requested.jpg) | Read PAR response, HTTP 200 |
| [029_supplier_file_downloaded.jpg](../screenshots/029_supplier_file_downloaded.jpg) | Direct GET, HTTP 200 and expected text |

## References

- [Oracle: developing ORDS applications](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.3/orddg/developing-REST-applications.html)
- [Oracle: ORDS_SECURITY package](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.3/orddg/ords_security-pl-sql-package-reference.html)
- [Oracle: Object Storage PARs](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingpreauthenticatedrequests.htm)

