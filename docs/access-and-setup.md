# Access and setup

## Database and cloud permissions

The lab used `ADMIN` for administrative setup and `APP_DEV` for the application objects and file tests. Three separate configurations are involved:

| Layer | Purpose |
| --- | --- |
| Database grants | Allow `APP_DEV` to use the directory, credentials and required packages/types |
| OCI IAM | Allow the database resource or OCI user to perform operations on the bucket |
| ORDS privileges and roles | Allow the supplier OAuth client to invoke the application endpoints |

A SQL grant does not grant bucket access in OCI. An IAM policy does not grant access to an Oracle directory.

## Authentication used in the tests

| Method | Identity or authorization | Example |
| --- | --- | --- |
| Resource Principal | Autonomous Database resource, authorized through IAM | `OCI$RESOURCE_PRINCIPAL` in PL/SQL |
| OCI auth-token credential | OCI user associated with the token, authorized through that user's IAM permissions | `OCI_STORAGE_LAB_CRED` |
| PAR | Temporary permission represented by the object URL | Direct HTTP upload or download |
| ORDS OAuth client | Registered application client with the required ORDS role | Supplier requests to `/storage-lab/` |

The OAuth token is for ORDS. It is not passed to Object Storage. The final application uses Resource Principal internally to create PARs, while the supplier receives only the temporary object URLs.

## Resource Principal and the dynamic group

The dynamic-group rule identifies the Autonomous Database resource. For a single database, the rule can match its resource type and OCID:

```text
ALL {resource.type = 'autonomousdatabase', resource.id = '<ADB_OCID>'}
```

This selects the database, not a schema inside it. Resource Principal is enabled for the database and made available to `APP_DEV` through database privileges. Oracle documents `DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL` for enabling it for `ADMIN` and for another database user.

Reference: [Resource Principal on Autonomous Database](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/resource-principal.html).

## Bucket access used by the lab

The final IAM policy allowed reading objects in `adb-oci-storage-lab`, creating and overwriting objects under `incoming/` and `outgoing/`, and managing PARs on that bucket.

| Permission area | Reason |
| --- | --- |
| Read objects in the lab bucket | Direct reads, read-back checks and read PARs |
| `OBJECT_CREATE` and `OBJECT_OVERWRITE` under `outgoing/` | Earlier PL/SQL upload tests |
| `OBJECT_CREATE` and `OBJECT_OVERWRITE` under `incoming/` | Supplier upload PARs |
| `PAR_MANAGE` on the lab bucket | Programmatic PAR creation and revocation |

The policy used `target.bucket.name` to select the bucket and `target.object.name` to restrict the write prefixes. Its statements used `in tenancy` with these conditions; they did not give unrestricted access to every bucket. Permission to manage PARs alone does not supply the object permissions required by the PAR's access type.

Reference: [PAR permissions and behaviour](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingpreauthenticatedrequests.htm).

These are the four statements used by the lab, with the dynamic-group OCID replaced by a placeholder:

```text
Allow dynamic-group id <DYNAMIC_GROUP_OCID> to read objects in tenancy where target.bucket.name = 'adb-oci-storage-lab'

Allow dynamic-group id <DYNAMIC_GROUP_OCID> to manage objects in tenancy where all {target.bucket.name = 'adb-oci-storage-lab', target.object.name = 'outgoing/*', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_OVERWRITE'}}

Allow dynamic-group id <DYNAMIC_GROUP_OCID> to manage buckets in tenancy where all {target.bucket.name = 'adb-oci-storage-lab', request.permission = 'PAR_MANAGE'}

Allow dynamic-group id <DYNAMIC_GROUP_OCID> to manage objects in tenancy where all {target.bucket.name = 'adb-oci-storage-lab', target.object.name = 'incoming/*', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_OVERWRITE'}}
```

`<DYNAMIC_GROUP_OCID>` represents the actual OCID of the dynamic group whose matching rule selects the database. It is replaced in each statement, including the angle brackets.

These statements authorize the database Resource Principal. The auth-token test uses the OCI user's own IAM permissions, which must independently allow reading the sample object. The [final policy screenshot](../screenshots/022_iam_supplier_upload_policy.jpg) shows the four permission areas together.

A PAR can grant read-only, write-only, or read/write access to a single object, all objects in a bucket, or objects whose names start with a specified prefix. Object listing is a separate option for bucket and prefix scopes. PARs do not grant permission to delete objects or administer the bucket.

## PAR scope and lifetime

The final package creates a PAR for one generated object name. Uploads use `ObjectWrite`; downloads use `ObjectRead`. Each PAR has a 15-minute lifetime, set in this example.

The URL carries the authorization. Someone who obtains it can perform its permitted operation while it remains valid. Restricting the object, operation and lifetime limits that access. Fifteen minutes is the lab setting, not a universal safe duration.

The application revokes the write PAR before issuing the read PAR. A repeated download request replaces the previous read PAR. Expiry or revocation ends PAR access, but does not delete the stored object. The earlier manual tests exercised expired or unauthorized requests; their HTTP status alone is not used as a universal diagnosis of every access failure.

## Configuration values

The scripts use `APP_DEV`, the private bucket `adb-oci-storage-lab`, and region `eu-frankfurt-1`. The application schema was already REST-enabled with the alias `app_dev` before the ORDS module was created.

| Value | Where it is configured |
| --- | --- |
| Application schema | Directory grant in `001`, Resource Principal checks in `004` and `005`, and SDK grants in `011`; `<APP_SCHEMA>`, where present, represents `APP_DEV` in this lab |
| Object Storage namespace | Object URI literals in `005` to `008` and `010`; `c_namespace` in `012` and `014` |
| Bucket and region | Object URI literals in the earlier tests; constants in `012` and `014`; bucket conditions in IAM |
| `<ADB_OCID>` and `<DYNAMIC_GROUP_OCID>` | Dynamic-group matching rule and IAM policy statements |
| `<OCI_USERNAME>` and `<OCI_AUTH_TOKEN>` | Credential creation in `009` |
| ORDS schema URL | The manual HTTP requests, using `https://<adb-host>/ords/app_dev` in this lab |
| OAuth client ID and secret | Generated by `016` and used for the token request in Postman |

Namespace placeholders appear as `BUCKET_NAMESPACE` or `<BUCKET_NAMESPACE>`. Configuration replaces the whole placeholder in the URI or constant value. Placeholder checks retain their original comparison text; a global replacement across the entire script would also change those checks.

Script `004` includes the Resource Principal enablement calls as comments for environments where it has not yet been enabled. Script `011` grants access to the SDK package and types used by `012` and `014`. The OAuth client script runs once and prints the newly generated credentials for the token request.

Client secrets, OCI auth tokens, access tokens and complete PAR URLs are credentials or temporary access material. The published examples use placeholders for these values. Screenshots retain the request method, object path, response status and useful results while concealing the secret values.

