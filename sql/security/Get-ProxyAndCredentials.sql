/*
Script Name : Get-ProxyAndCredentials
Category    : security
Purpose     : Lists SQL Agent proxies and server-level credentials with their identity
              and associated subsystems. Proxies that use stored credentials to run Agent
              steps under a different account are a common privilege escalation path.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/)
Requires    : VIEW ANY DEFINITION, plus db_datareader on msdb (or sysadmin); the Agent roles alone cannot SELECT sysproxylogin
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Two row sources unified via UNION ALL:
    1. SQL Agent proxies (msdb.dbo.sysproxies), run steps under an alternate Windows account
    2. Server-level credentials (sys.credentials), used by proxies, logins mapped to a credential, and BACKUP TO URL
  The subsystem list for each proxy is aggregated from msdb.dbo.sysproxysubsystem.
  Credential identity is the Windows account or certificate the credential maps to.
*/

-- SQL Agent proxies
SELECT
    'Proxy' AS type,
    p.name AS name,
    p.enabled AS is_enabled,
    c.name AS credential_name,
    c.credential_identity AS runs_as,
    (
        SELECT STRING_AGG(ss.subsystem, ', ')
        FROM msdb.dbo.sysproxysubsystem ps
        JOIN msdb.dbo.syssubsystems ss ON ss.subsystem_id = ps.subsystem_id
        WHERE ps.proxy_id = p.proxy_id
    ) AS allowed_subsystems,
    (
        SELECT STRING_AGG(COALESCE(l.name, r.name + N' (msdb role)'), ', ')
        FROM msdb.dbo.sysproxylogin pl
        LEFT JOIN sys.server_principals l ON l.sid = pl.sid AND pl.flags <> 2
        LEFT JOIN msdb.sys.database_principals r ON r.sid = pl.sid AND pl.flags = 2 -- flags 2 = msdb role
        WHERE pl.proxy_id = p.proxy_id
    ) AS allowed_logins,
    p.description
FROM msdb.dbo.sysproxies p
LEFT JOIN sys.credentials c ON c.credential_id = p.credential_id

UNION ALL

-- Server-level credentials not used by any proxy (standalone)
SELECT
    'Credential' AS type,
    c.name AS name,
    1 AS is_enabled,
    c.name AS credential_name,
    c.credential_identity AS runs_as,
    NULL AS allowed_subsystems,
    NULL AS allowed_logins,
    NULL AS description
FROM sys.credentials c
WHERE NOT EXISTS (
    SELECT 1 FROM msdb.dbo.sysproxies p WHERE p.credential_id = c.credential_id
)

ORDER BY type, name;
