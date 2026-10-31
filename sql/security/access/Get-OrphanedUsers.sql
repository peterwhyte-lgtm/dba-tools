/*
Script Name : Get-OrphanedUsers
Category    : security-and-permissions
Purpose     : Find database users whose SID matches no server login, the state that makes an
              account fail to authenticate after a restore, an attach, or a dropped login.
              Reports whether a login of the same name exists, which is what decides between
              a straight remap and creating a login first.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-orphaned-users/)
Requires    : VIEW ANY DATABASE, plus access to each online database it inspects (it opens every database)
HealthCheck : Yes
Notes       : Orphaned users cause login failures for that account. Fix with
              ALTER USER [username] WITH LOGIN = [login_name]; or DROP USER [username].
              Users created WITHOUT LOGIN (authentication_type NONE) and contained database
              users (authentication_type DATABASE) also have no server login by design and are
              deliberately excluded, they are not orphans.
              The matching_login lookup compares names in the server collation, so a database on
              another collation (e.g. case-sensitive) no longer stops the run with Msg 468.
              SQL Server 2012+ (sys.database_principals.authentication_type). Tested on 2025.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('tempdb..#orphaned') IS NOT NULL DROP TABLE #orphaned;

CREATE TABLE #orphaned (
    database_name NVARCHAR(128),
    user_name NVARCHAR(128),
    user_type NVARCHAR(60),
    matching_login NVARCHAR(128) NULL,
    create_date DATETIME
);

DECLARE @sql NVARCHAR(MAX) = N'';
/* Login names resolve in the server collation. A database on a different collation (a case-sensitive
   vendor database, say) makes a bare sp2.name = dp.name fail with Msg 468 and abort the whole run. */
DECLARE @server_collation SYSNAME = CONVERT(SYSNAME, SERVERPROPERTY('Collation'));

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #orphaned
SELECT
    DB_NAME() AS database_name,
    dp.name AS user_name,
    dp.type_desc AS user_type,
    (SELECT TOP (1) sp2.name
     FROM sys.server_principals AS sp2
     WHERE sp2.name = dp.name COLLATE ' + @server_collation + N'
       AND sp2.type IN (''S'', ''U'', ''G'')) AS matching_login,
    dp.create_date
FROM sys.database_principals AS dp
WHERE dp.type IN (''S'', ''U'', ''G'')
  AND dp.principal_id > 4
  AND dp.sid IS NOT NULL
  AND dp.authentication_type IN (1, 3)   /* 1 INSTANCE, 3 WINDOWS. Excludes 0 NONE (WITHOUT LOGIN) and 2 DATABASE (contained). */
  AND dp.name NOT IN (''guest'', ''INFORMATION_SCHEMA'', ''sys'', ''dbo'')
  AND NOT EXISTS (
      SELECT 1
      FROM sys.server_principals AS sp
      WHERE sp.sid = dp.sid
  );
'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id <> 2            /* tempdb is rebuilt at every startup */
  AND HAS_DBACCESS(name) = 1;     /* skip what this account cannot open, rather than failing the whole run */

EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    user_name,
    user_type,
    matching_login,
    create_date
FROM #orphaned
ORDER BY CASE WHEN matching_login IS NULL THEN 1 ELSE 0 END, database_name, user_name;

DROP TABLE #orphaned;
