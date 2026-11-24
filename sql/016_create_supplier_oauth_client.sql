-- Run as application schema
-- Requires Supplier A (supplier_id = 1) and the storage_supplier ORDS role
-- Creates an OAuth client for the supplier and generates its secret
-- The output includes the credentials
-- The credentials should be kept private

SET DEFINE OFF
SET SERVEROUTPUT ON


DECLARE
    l_client_id VARCHAR2(255);
BEGIN
    ORDS_SECURITY.REGISTER_CLIENT(
        p_name            => 'storage_supplier_a',
        p_grant_type      => 'client_credentials',
        p_support_email   => 'support@example.com',
        p_description     => 'Supplier A - Object Storage lab',
        p_privilege_names => 'storage.lab.access',
        p_token_duration  => 3600
    );

    ORDS_SECURITY.GRANT_CLIENT_ROLE(
        p_client_name => 'storage_supplier_a',
        p_role_name   => 'storage_supplier'
    );

    SELECT client_id INTO l_client_id
    FROM user_ords_clients
    WHERE name = 'storage_supplier_a';

    -- ORDS identifies this client through :current_user in the REST handlers.
    UPDATE storage_suppliers
    SET ords_username = l_client_id
    WHERE supplier_id = 1;

    IF SQL%ROWCOUNT <> 1 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Supplier A was not found.');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Client created: storage_supplier_a');
    DBMS_OUTPUT.PUT_LINE('CLIENT_ID: ' || l_client_id);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Generate a secret for the registered client.
-- Save the returned value: it cannot be retrieved from USER_ORDS_CLIENTS.
DECLARE
    l_client_secret VARCHAR2(32767);
BEGIN
    l_client_secret := ORDS_SECURITY.ROTATE_CLIENT_SECRET(
        p_name => 'storage_supplier_a'
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CLIENT_SECRET: ' || l_client_secret);
END;
/

-- Confirm the supplier mapping without displaying credentials.
SELECT s.supplier_id, s.supplier_name, c.name AS oauth_client
FROM storage_suppliers s
JOIN user_ords_clients c ON c.client_id = s.ords_username
WHERE s.supplier_id = 1;

SELECT client_name, role_name
FROM user_ords_client_roles
WHERE client_name = 'storage_supplier_a';
