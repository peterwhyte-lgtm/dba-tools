/*
Script Name : Get-BackupRestoreProgress
Category    : performance-troubleshooting
Purpose     : Show active backup/restore progress and estimated completion for long-running operations.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-restore-progress/)
Requires    : VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE is enough on SQL Server 2022 and later)
Notes       : At 100 percent and 0 sec remaining a RESTORE can still be running recovery (redo
              and undo) under the same command name; the ERRORLOG reports that phase.
              Without the permission the DMV shows only your own session, so a restore started
              by someone else returns no rows, not an error. DBCC CHECKDB reports as
              DBCC ALLOC CHECK then DBCC TABLE CHECK and is not included.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT 
    er.command AS command,
    est.text AS sql_text,
    er.start_time AS start_time,
    er.percent_complete AS percent_complete,
    CAST(((DATEDIFF(SECOND, er.start_time, GETDATE())) / 3600) AS VARCHAR)
        + ' hour(s), ' 
        + CAST((DATEDIFF(SECOND, er.start_time, GETDATE()) % 3600) / 60 AS VARCHAR)
        + ' min, ' 
        + CAST((DATEDIFF(SECOND, er.start_time, GETDATE()) % 60) AS VARCHAR)
        + ' sec' AS running_time,
    CAST((er.estimated_completion_time / 3600000) AS VARCHAR)
        + ' hour(s), ' 
        + CAST((er.estimated_completion_time % 3600000) / 60000 AS VARCHAR)
        + ' min, ' 
        + CAST((er.estimated_completion_time % 60000) / 1000 AS VARCHAR)
        + ' sec' AS estimated_time_remaining,
    DATEADD(SECOND, er.estimated_completion_time / 1000, GETDATE()) AS estimated_completion_time
FROM sys.dm_exec_requests er
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) est
WHERE er.command LIKE 'BACKUP%'     -- BACKUP DATABASE, BACKUP LOG
   OR er.command LIKE 'RESTORE%'    -- RESTORE DATABASE, RESTORE LOG; RESTORE VERIFYONLY reports as RESTORE HEADERONLY
   OR er.command IN ('DbccSpaceReclaim', 'DbccFilesCompact');  -- DBCC SHRINKFILE and SHRINKDATABASE both report DbccFilesCompact
