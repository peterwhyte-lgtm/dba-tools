/*
Script Name : Get-UserPermissionsAudit
Category    : security
Purpose     : Audit one login's effective access across the whole instance in a single pass:
              server roles/connection principals, plus per-database role membership,
              resolved through the real security token, so nested AD group membership
              shows up automatically. EDIT @LoginName below before running.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-user-permissions-audit/)
Requires    : sysadmin, or IMPERSONATE permission on the target login plus VIEW ANY DATABASE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;   -- the XML .value() below needs it; sqlcmd defaults it OFF

-- EDIT THIS: the login to investigate. Works for SQL logins and Windows users/groups.
DECLARE @LoginName SYSNAME = N'DOMAIN\username';   -- e.g. N'CONTOSO\jsmith' or a SQL login name
DECLARE @IncludeDatabasesWithoutAccess BIT = 0;    -- 1 = also list databases this login can't reach

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
BEGIN
    RAISERROR('Login "%s" not found, or not visible to you (you need sysadmin or IMPERSONATE on it). Check spelling (DOMAIN\name for Windows logins).', 16, 1, @LoginName);
    RETURN;
END;

IF OBJECT_ID('tempdb..#myuser') IS NOT NULL DROP TABLE #myuser;
IF OBJECT_ID('tempdb..#dbs') IS NOT NULL DROP TABLE #dbs;

-- Database list read as the CALLER, before impersonating. Read under the target login instead,
-- a login denied VIEW ANY DATABASE sees no user databases and every row would vanish silently.
SELECT name, state_desc INTO #dbs FROM sys.databases WHERE database_id > 4;   -- skip system databases

CREATE TABLE #myuser (
    server_name  NVARCHAR(128),
    database_name SYSNAME,
    principal_id INT,
    sid          VARBINARY(85),
    name         NVARCHAR(128),
    type         NVARCHAR(128),
    usage_desc   NVARCHAR(128)
);

DECLARE @impersonating BIT = 0;
DECLARE @sql NVARCHAR(MAX);

BEGIN TRY
    EXECUTE AS LOGIN = @LoginName;
    SET @impersonating = 1;

    -- Server-level token, captured before REVERT so it reflects the target login, not the caller.
    INSERT INTO #myuser (server_name, database_name, principal_id, sid, name, type, usage_desc)
    SELECT @@SERVERNAME, N'[CONNECTION]', lt.principal_id, lt.sid, lt.name,
           CASE WHEN lt.type = 'SERVER ROLE' THEN 'ROLE'
                WHEN lt.type = 'WINDOWS GROUP' THEN 'WINDOWS GROUP'
                ELSE 'SQL USER' END,
           lt.usage
    FROM sys.login_token AS lt
    WHERE lt.sid IN (SELECT sid FROM sys.server_principals);

    -- Only databases this login can actually reach (HAS_DBACCESS under impersonation),
    -- otherwise USE on an inaccessible database raises Msg 916 and aborts the whole script.
    SET @sql = N'';
    SELECT @sql = @sql + N'
    USE ' + QUOTENAME(name) + N';
    INSERT INTO #myuser (server_name, database_name, principal_id, sid, name, type, usage_desc)
    SELECT DISTINCT @@SERVERNAME, DB_NAME(), principal_id, sid, name,
           CASE WHEN type = ''ROLE'' THEN ''ROLE''
                WHEN type = ''WINDOWS GROUP'' THEN ''WINDOWS GROUP''
                ELSE ''SQL USER'' END,   -- a Windows user (and dbo owned by one) is WINDOWS LOGIN here
           usage
    FROM sys.user_token
    WHERE sid IN (SELECT sid FROM sys.database_principals)
      AND name <> ''public'';'
    FROM #dbs
    WHERE state_desc = 'ONLINE'
      AND HAS_DBACCESS(name) = 1;

    IF LEN(@sql) > 0
        EXEC (@sql);

    IF @IncludeDatabasesWithoutAccess = 1
    BEGIN
        INSERT INTO #myuser (server_name, database_name, principal_id, sid, name, type, usage_desc)
        SELECT
            @@SERVERNAME,
            d.name,
            NULL,
            NULL,
            CASE WHEN d.state_desc = 'ONLINE' THEN 'MISSING' ELSE d.state_desc END,
            'ROLE',
            'MISSING'
        FROM #dbs AS d
        WHERE (d.state_desc <> 'ONLINE' OR HAS_DBACCESS(d.name) = 0);
    END;

    REVERT;
    SET @impersonating = 0;
END TRY
BEGIN CATCH
    IF @impersonating = 1
    BEGIN
        REVERT;
    END;
    THROW;
END CATCH;

-- One row per scope: [CONNECTION] (server-level) plus one row per database.
SELECT
    x.server_name,
    x.database_name,
    ISNULL(STUFF((
        SELECT ',' + t.name
        FROM #myuser AS t
        WHERE t.type = 'ROLE'
          AND t.server_name = x.server_name
          AND t.database_name = x.database_name
        ORDER BY t.name
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, ''), '')                              AS [ROLE],
    ISNULL(STUFF((
        SELECT ',' + t.name
        FROM #myuser AS t
        WHERE t.type = 'WINDOWS GROUP'
          AND t.server_name = x.server_name
          AND t.database_name = x.database_name
        ORDER BY t.name
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, ''), '')                              AS [WINDOWS GROUP],
    ISNULL(STUFF((
        SELECT ',' + t.name
        FROM #myuser AS t
        WHERE t.type = 'SQL USER'
          AND t.server_name = x.server_name
          AND t.database_name = x.database_name
        ORDER BY t.name
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, ''), '')                              AS [SQL USER]
FROM #myuser AS x
GROUP BY x.server_name, x.database_name
ORDER BY
    CASE WHEN x.database_name = N'[CONNECTION]' THEN 0 ELSE 1 END,
    x.database_name;

DROP TABLE #myuser;
DROP TABLE #dbs;
