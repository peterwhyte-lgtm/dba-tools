/*
Script Name : Get-LoginLastActivity
Category    : monitoring
Purpose     : All SQL and Windows logins with current session status, connection details, and
              disabled state, plus sysadmin and securityadmin membership.
              Note: SQL Server does not record "last login time" natively without a SQL Server
              Audit configured. This script shows what is available: current active sessions
              and login metadata.
              For historical last-login tracking, enable a Server Audit with LOGIN action group.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-security-audit/)
Requires    : VIEW SERVER STATE, VIEW ANY DEFINITION
Notes       : Role membership is read from sys.server_role_members AND IS_SRVROLEMEMBER, not
              from IS_SRVROLEMEMBER alone. IS_SRVROLEMEMBER returned 0 for a virtual service
              account that sys.server_role_members shows as a direct sysadmin (SQL Server 2025
              CU8), so the catalog is the primary source and the function adds Windows group
              membership the catalog cannot see.
              is_securityadmin additionally excludes sysadmins: IS_SRVROLEMEMBER returns 1 for
              every role when the principal is a sysadmin, which reported 11 logins as
              securityadmin on a lab instance whose catalog holds only 3. Without that
              exclusion the column means "sysadmin or securityadmin", not securityadmin.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH role_direct AS (
    SELECT
        rm.member_principal_id,
        MAX(CASE WHEN r.name = 'sysadmin'      THEN 1 ELSE 0 END) AS in_sysadmin,
        MAX(CASE WHEN r.name = 'securityadmin' THEN 1 ELSE 0 END) AS in_securityadmin
    FROM sys.server_role_members AS rm
    JOIN sys.server_principals  AS r ON r.principal_id = rm.role_principal_id
    WHERE r.name IN ('sysadmin', 'securityadmin')
    GROUP BY rm.member_principal_id
)
SELECT
    sp.name AS login_name,
    sp.type_desc AS login_type,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date,
    /* Current session info, 0 and NULL when not connected right now */
    COUNT(s.session_id) AS active_sessions,
    MIN(s.login_time) AS earliest_current_session,
    MAX(s.login_time) AS latest_current_session,
    /* Connection detail across the login's current sessions */
    MAX(c.client_net_address) AS last_client_ip,
    MAX(s.host_name) AS last_host_name,
    MAX(s.program_name) AS last_program_name,
    MAX(c.auth_scheme) AS auth_scheme,
    /* Permission summary: catalog membership first, function second */
    CAST(CASE WHEN ISNULL(rd.in_sysadmin, 0) = 1
                OR ISNULL(IS_SRVROLEMEMBER('sysadmin', sp.name), 0) = 1
              THEN 1 ELSE 0 END AS BIT) AS is_sysadmin,
    CAST(CASE WHEN ISNULL(rd.in_securityadmin, 0) = 1
                OR (ISNULL(IS_SRVROLEMEMBER('securityadmin', sp.name), 0) = 1
                    AND ISNULL(IS_SRVROLEMEMBER('sysadmin', sp.name), 0) = 0)
              THEN 1 ELSE 0 END AS BIT) AS is_securityadmin
FROM sys.server_principals AS sp
LEFT JOIN role_direct AS rd ON rd.member_principal_id = sp.principal_id
LEFT JOIN sys.dm_exec_sessions AS s
       ON s.login_name = sp.name AND s.is_user_process = 1
LEFT JOIN sys.dm_exec_connections AS c
       ON c.session_id = s.session_id
WHERE sp.type IN ('S', 'U', 'G') /* SQL login, Windows user, Windows group */
  AND sp.name NOT LIKE '##%'     /* exclude internal system logins */
GROUP BY sp.name, sp.type_desc, sp.is_disabled, sp.create_date, sp.modify_date,
         sp.principal_id, rd.in_sysadmin, rd.in_securityadmin
ORDER BY active_sessions DESC, sp.is_disabled, sp.name;
