/*
Script Name : Get-SuspectPages
Category    : maintenance-and-reliability
Purpose     : Show any pages recorded in msdb.dbo.suspect_pages, evidence of I/O or corruption errors.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-suspect-pages-and-integrity-checks/)
Requires    : any login that can connect (msdb grants SELECT on dbo.suspect_pages
              to public); database_name is NULL without VIEW ANY DATABASE
Notes       : Any rows here indicate a serious integrity concern. Cross-reference with
              the error log and run DBCC CHECKDB immediately on the affected database.
              Rows stay until deleted: a restore marks them event_type 4, a repair 5 or 7.
              Only DROP DATABASE or ALTER DATABASE REMOVE FILE removes them. At 1,000
              rows SQL Server stops logging new errors, so delete old 4/5/7 rows.
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    DB_NAME(sp.database_id) AS database_name,
    sp.file_id,
    sp.page_id,
    CASE sp.event_type
        WHEN 1 THEN '823/824 hard I/O error'
        WHEN 2 THEN 'Bad checksum'
        WHEN 3 THEN 'Torn page'
        WHEN 4 THEN 'Restored (no longer suspect)'
        WHEN 5 THEN 'Repaired by DBCC'
        WHEN 7 THEN 'Deallocated by DBCC CHECKDB'
        ELSE CAST(sp.event_type AS VARCHAR(10))
    END AS event_type,
    sp.error_count,
    sp.last_update_date
FROM msdb.dbo.suspect_pages AS sp
ORDER BY sp.last_update_date DESC;
