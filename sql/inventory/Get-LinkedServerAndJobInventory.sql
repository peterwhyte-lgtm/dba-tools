/*
Script Name : Get-LinkedServerAndJobInventory
Category    : configuration-and-environment
Purpose     : Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-linked-servers/)
Requires    : VIEW ANY DEFINITION, db_datareader on msdb
Notes       : Returns three result sets (logins, linked servers, jobs) with the same four
              columns: object_type, name, detail, state. state reads Enabled/Disabled for
              logins and jobs and Data access on/off for linked servers (it was a column
              named status holding 0/1 for logins and the data source for linked servers).
              Run in SSMS or use the individual focused scripts for CSV export.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    'LOGIN' AS object_type,
    sp.name AS name,
    sp.type_desc AS detail,
    CASE sp.is_disabled WHEN 1 THEN 'Disabled' ELSE 'Enabled' END AS state
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.name;

SELECT
    'LINKED SERVER' AS object_type,
    s.name AS name,
    ISNULL(NULLIF(s.product, ''), '(not set)') + ' / ' + s.provider + ' -> ' + ISNULL(s.data_source, '(no data source)') AS detail,
    CASE s.is_data_access_enabled WHEN 1 THEN 'Data access on' ELSE 'Data access off' END AS state
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;

SELECT
    'JOB' AS object_type,
    j.name AS name,
    ISNULL(sp.name, '(unknown)') AS detail,
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS state
FROM msdb.dbo.sysjobs AS j
LEFT JOIN sys.server_principals AS sp ON j.owner_sid = sp.sid
ORDER BY j.name;
