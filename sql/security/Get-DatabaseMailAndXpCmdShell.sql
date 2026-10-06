/*
Script Name : Get-DatabaseMailAndXpCmdShell
Category    : security
Purpose     : Security surface area audit: xp_cmdshell, CLR, Database Mail, force encryption, and active NTLM connections.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-mail-and-xp-cmd-shell/)
Requires    : VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE on SQL Server 2022 and later);
              without it the script fails with a permission error and returns
              no rows. sysadmin is not needed.
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ForceEncryption sits on the SuperSocketNetLib key itself, which sys.dm_server_registry
-- does not return (only its Tcp, Np, Sm and Via subkeys), so read it directly.
-- NULL when the registry cannot be read; reported as 'unknown', never as 0.
DECLARE @force_encryption INT;
BEGIN TRY
    EXEC master.dbo.xp_instance_regread
        N'HKEY_LOCAL_MACHINE',
        N'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib',
        N'ForceEncryption',
        @force_encryption OUTPUT;
END TRY
BEGIN CATCH
    SET @force_encryption = NULL;
END CATCH;

SELECT
    name,
    CAST(value        AS VARCHAR(20)) AS configured_value,
    CAST(value_in_use AS VARCHAR(20)) AS running_value,
    description
FROM sys.configurations
WHERE name IN (
    'xp_cmdshell',
    'clr enabled',
    'clr strict security',
    'Database Mail XPs'
)

UNION ALL

-- Force encryption: 1 = all connections must encrypt; 0 = encryption optional
SELECT
    'force encryption'                                                              AS name,
    '0'                                                                             AS configured_value,
    ISNULL(CAST(@force_encryption AS VARCHAR(20)), 'unknown')                      AS running_value,
    'ForceEncryption - 1 = all connections must encrypt; 0 = unencrypted allowed'  AS description

UNION ALL

-- Active user sessions authenticated via NTLM (Kerberos is preferred for Windows auth)
SELECT
    'ntlm connections'                                                              AS name,
    '0'                                                                             AS configured_value,
    CAST(
        (SELECT COUNT(*)
         FROM   sys.dm_exec_sessions    AS s
         JOIN   sys.dm_exec_connections AS c ON c.session_id = s.session_id
         WHERE  c.auth_scheme     = 'NTLM'
         AND    s.is_user_process = 1)
    AS VARCHAR(20))                                                                 AS running_value,
    'Active user sessions using NTLM authentication (Kerberos preferred)'           AS description

ORDER BY name;





