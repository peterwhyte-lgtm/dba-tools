/*
Script Name : Generate-LoginScript
Category    : migration
Purpose     : Generate CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-login-script/)
Requires    : CONTROL SERVER (sysadmin has it), or on SQL Server 2022 and later VIEW ANY DEFINITION
              plus VIEW ANY CRYPTOGRAPHICALLY SECURED DEFINITION. With less, other logins are
              invisible or their password hashes read as NULL, so the script stops with an error.
Notes       : Disabled logins are re-created and then DISABLED again. CREATE LOGIN always
              produces an enabled login, so the state has to be re-applied explicitly.
              Without it a decommissioned account comes back live on the target.
              Each section is built with STRING_AGG, not SELECT @var = @var + ... ORDER BY.
              That older pattern is documented as unreliable and silently dropped most server
              role memberships when tested on SQL Server 2025. Needs SQL Server 2017 or later.
              A DEFAULT_DATABASE missing on the target makes CREATE LOGIN fail (Msg 15010),
              so restore databases first or edit that login's block to [master].
              NOT scripted, by design: server-level permissions and explicit DENY CONNECT SQL.
              Run Get-MigrationLoginAudit.sql on the source and compare after migrating.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- Without the right permissions the output is NULL or partial with no error, so fail loudly instead:
-- other logins are invisible without VIEW ANY DEFINITION, hashes read NULL without CONTROL SERVER
-- (or VIEW ANY CRYPTOGRAPHICALLY SECURED DEFINITION on SQL Server 2022 and later).
IF HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW ANY DEFINITION') <> 1
   OR EXISTS (SELECT 1 FROM sys.sql_logins WHERE password_hash IS NULL AND name NOT LIKE N'##%##')
BEGIN
    RAISERROR(N'Generate-LoginScript needs CONTROL SERVER (or VIEW ANY DEFINITION plus VIEW ANY CRYPTOGRAPHICALLY SECURED DEFINITION). Without it logins are invisible or their password hashes read as NULL, so the generated script would be empty or incomplete.', 16, 1);
    RETURN;
END;

DECLARE @ddl  NVARCHAR(MAX) = N'';
DECLARE @crlf NCHAR(2)      = CHAR(13) + CHAR(10);
DECLARE @len  INT;   -- section length marker: an empty section must SAY it is empty

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Login Migration Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Run on TARGET server AFTER databases are restored.' + @crlf
    + N'-- SQL logins include hashed passwords and original SIDs to avoid' + @crlf
    + N'-- orphaned users after restore.' + @crlf
    + N'-- NOTE: If a login''s DEFAULT_DATABASE does not exist on the target,' + @crlf
    + N'-- CREATE LOGIN fails with Msg 15010 and that login is NOT created.' + @crlf
    + N'-- Restore the database first, or change DEFAULT_DATABASE to [master]' + @crlf
    + N'-- in that login''s block before running it.' + @crlf
    + N'-- NOTE: Logins disabled on the source are re-disabled below. Server-level' + @crlf
    + N'-- permissions and explicit DENY CONNECT SQL are NOT scripted, audit those' + @crlf
    + N'-- separately with Get-MigrationLoginAudit.sql.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

-- ── SQL logins ────────────────────────────────────────────────────────────────

SET @ddl = @ddl + N'-- SQL Logins' + @crlf + N'GO' + @crlf + @crlf;
SET @len = LEN(@ddl);

SELECT @ddl = @ddl + ISNULL(STRING_AGG(CAST(
      N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(p.name, N'''', N'''''') + N''')' + @crlf
    + N'BEGIN' + @crlf
    + N'    CREATE LOGIN ' + QUOTENAME(p.name) + @crlf
    + N'        WITH PASSWORD = ' + CONVERT(NVARCHAR(MAX), sl.password_hash, 1) + N' HASHED,' + @crlf
    + N'             SID      = ' + CONVERT(NVARCHAR(MAX), p.sid, 1) + N',' + @crlf
    + N'             DEFAULT_DATABASE = ' + QUOTENAME(ISNULL(p.default_database_name, N'master')) + N',' + @crlf
    + N'             DEFAULT_LANGUAGE = ' + QUOTENAME(ISNULL(p.default_language_name, N'us_english')) + N',' + @crlf
    + N'             CHECK_POLICY     = ' + CASE sl.is_policy_checked     WHEN 1 THEN N'ON' ELSE N'OFF' END + N',' + @crlf
    + N'             CHECK_EXPIRATION = ' + CASE sl.is_expiration_checked WHEN 1 THEN N'ON' ELSE N'OFF' END + @crlf
    -- Disabled state is NOT carried by CREATE LOGIN. Re-apply it, or the account
    -- comes back enabled on the target with its original password still valid.
    -- Inside the guard, so it only touches logins this script actually created.
    + CASE WHEN p.is_disabled = 1
           THEN N'    ALTER LOGIN ' + QUOTENAME(p.name) + N' DISABLE;  -- disabled on source' + @crlf
           ELSE N'' END
    + N'END' + @crlf
    + N'GO' + @crlf + @crlf AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY p.name), N'')
FROM sys.server_principals p
INNER JOIN sys.sql_logins sl ON p.principal_id = sl.principal_id
WHERE p.type = 'S'
  AND p.name NOT LIKE N'##%##'
  AND p.name NOT IN (N'sa', N'guest', N'public');

-- ── Windows logins and groups ─────────────────────────────────────────────────

IF LEN(@ddl) = @len
    SET @ddl = @ddl + N'-- (none found)' + @crlf + @crlf;

SET @ddl = @ddl + N'-- Windows Logins and Groups' + @crlf + N'GO' + @crlf + @crlf;
SET @len = LEN(@ddl);

SELECT @ddl = @ddl + ISNULL(STRING_AGG(CAST(
      N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(p.name, N'''', N'''''') + N''')' + @crlf
    + N'BEGIN' + @crlf
    + N'    CREATE LOGIN ' + QUOTENAME(p.name) + N' FROM WINDOWS' + @crlf
    + N'        WITH DEFAULT_DATABASE = ' + QUOTENAME(ISNULL(p.default_database_name, N'master')) + N',' + @crlf
    + N'             DEFAULT_LANGUAGE = ' + QUOTENAME(ISNULL(p.default_language_name, N'us_english')) + @crlf
    + CASE WHEN p.is_disabled = 1
           THEN N'    ALTER LOGIN ' + QUOTENAME(p.name) + N' DISABLE;  -- disabled on source' + @crlf
           ELSE N'' END
    + N'END' + @crlf
    + N'GO' + @crlf + @crlf AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY p.name), N'')
FROM sys.server_principals p
-- 'U' = WINDOWS_LOGIN, 'G' = WINDOWS_GROUP. There is no type 'W' in
-- sys.server_principals, so a 'W' here matches nothing and silently
-- scripts no Windows logins at all.
WHERE p.type IN ('U', 'G')
  AND p.name NOT LIKE N'##%##'
  AND p.name NOT IN (N'sa', N'guest', N'public')
  AND p.name NOT LIKE N'NT SERVICE\%'
  AND p.name NOT LIKE N'NT AUTHORITY\%'
  AND p.name NOT LIKE N'BUILTIN\%';

-- ── Server role memberships ───────────────────────────────────────────────────

IF LEN(@ddl) = @len
    SET @ddl = @ddl + N'-- (none found)' + @crlf + @crlf;

SET @ddl = @ddl + N'-- Server Role Memberships' + @crlf + N'GO' + @crlf + @crlf;
SET @len = LEN(@ddl);

SELECT @ddl = @ddl + ISNULL(STRING_AGG(CAST(
      N'IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(m.name, N'''', N'''''') + N''')' + @crlf
    + N'    ALTER SERVER ROLE ' + QUOTENAME(r.name) + N' ADD MEMBER ' + QUOTENAME(m.name) + N';' + @crlf
    + N'GO' + @crlf + @crlf AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY r.name, m.name), N'')
FROM sys.server_role_members srm
INNER JOIN sys.server_principals r ON srm.role_principal_id  = r.principal_id
INNER JOIN sys.server_principals m ON srm.member_principal_id = m.principal_id
WHERE r.name <> N'public'
  AND m.name NOT LIKE N'##%##'
  AND m.name NOT IN (N'sa')
  AND m.name NOT LIKE N'NT SERVICE\%'
  AND m.name NOT LIKE N'NT AUTHORITY\%';

IF LEN(@ddl) = @len
    SET @ddl = @ddl + N'-- (none found)' + @crlf + @crlf;

SELECT @ddl AS ddl;
