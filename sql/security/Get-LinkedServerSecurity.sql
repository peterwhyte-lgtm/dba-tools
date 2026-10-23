/*
Script Name : Get-LinkedServerSecurity
Category    : security
Purpose     : Lists linked servers with their security context — how local logins are
              mapped to remote logins. Catch-all mappings with stored credentials are
              the highest-risk configuration.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-linked-servers/)
Requires    : VIEW ANY DEFINITION or sysadmin
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

/*
  DESIGN: sys.linked_logins contains one row per mapping. local_principal_id = 0
  means the mapping applies to any login without a specific mapping (catch-all).
  There is no local_login_name column; the local login is resolved with SUSER_SNAME.
  Risk assessment:
    HIGH — catch-all or specific mapping with stored remote credentials
    MEDIUM — self-credentials (impersonation) mapping
    LOW — a mapping row with uses_self_credential = 0 and no remote_name, which is what
          sp_addlinkedsrvlogin @useself = 'FALSE' with no @rmtuser stores ("Be made without
          using a security context"). It connects with no credentials; it is not a missing mapping.
          LOW, not NONE: nothing is stored to leak, and a SQL Server target refuses it
          (Msg 7399 "Authentication failed"), but a source that accepts anonymous connections
          (a file or ODBC provider) would be open to every local login, so it is worth seeing.
    NONE — no sys.linked_logins row at all for the server ("Not be made"): the LEFT JOIN
          leaves every ll column NULL and every connection is refused (Msg 7416).
    UNKNOWN — any row that matches none of the above.
*/

SELECT
    s.name AS linked_server,
    s.product,
    s.provider,
    s.data_source,
    ISNULL(s.catalog, '') AS remote_catalog,
    CASE
        WHEN ll.server_id IS NULL THEN '(no login mappings)'
        ELSE ISNULL(SUSER_SNAME(NULLIF(ll.local_principal_id, 0)), '(any login)')
    END AS local_login,
    CASE
        WHEN ll.uses_self_credential = 1
            THEN 'Impersonate - context of the calling login'
        WHEN ll.remote_name IS NOT NULL AND ll.local_principal_id = 0
            THEN 'Catch-all mapping -> ' + ll.remote_name
        WHEN ll.remote_name IS NOT NULL
            THEN 'Explicit mapping -> ' + ll.remote_name
        WHEN ll.server_id IS NULL
            THEN 'Not be made - no login mappings, connections are refused'
        ELSE 'No security context - connects with no credentials'
    END AS security_context,
    ll.uses_self_credential,
    ll.remote_name AS remote_login,
    CASE
        WHEN ll.remote_name IS NOT NULL AND ll.local_principal_id = 0
            THEN 'HIGH - catch-all with stored credentials'
        WHEN ll.remote_name IS NOT NULL AND ll.local_principal_id != 0
            THEN 'HIGH - explicit mapping with stored credentials'
        WHEN ll.uses_self_credential = 1
            THEN 'MEDIUM - impersonation (caller context)'
        WHEN ll.remote_name IS NULL AND ll.uses_self_credential = 0
            THEN 'LOW - no security context (connects with no credentials)'
        WHEN ll.server_id IS NULL
            THEN 'NONE - no login mappings (all connections refused)'
        ELSE 'UNKNOWN'
    END AS risk_level,
    s.is_remote_login_enabled,
    s.is_rpc_out_enabled,
    s.modify_date AS last_modified
FROM sys.servers s
LEFT JOIN sys.linked_logins ll ON ll.server_id = s.server_id
WHERE s.is_linked = 1
ORDER BY
    CASE
        WHEN ll.remote_name IS NOT NULL AND ll.local_principal_id = 0 THEN 1
        WHEN ll.remote_name IS NOT NULL THEN 2
        WHEN ll.uses_self_credential = 1 THEN 3
        ELSE 4
    END,
    s.name,
    ll.local_principal_id;
