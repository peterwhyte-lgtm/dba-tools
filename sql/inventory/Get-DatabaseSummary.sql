/*
Script Name : Get-DatabaseSummary
Category    : monitoring
Purpose     : One-row-per-database view of every database on the instance: state,
              recovery model, log reuse wait, file sizes, backup currency, and
              configuration flags. Notes column aggregates actionable issues.
              Reads from system metadata and msdb only — no per-database scan.
              For used vs free space detail run Get-DatabaseSizesAndFreeSpace.
              For file-level detail run Get-DatabaseFilesDetail.
              Backup flags follow Microsoft's system database guidance: master, model and
              msdb need full backups (model's age is not checked), tempdb and database
              snapshots cannot be backed up. A distribution database is checked like a user
              database. Tested on SQL Server 2025.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-summary/)
Requires    : VIEW ANY DATABASE, SELECT on msdb.dbo.backupset
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH backup_dates AS (
    SELECT
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS last_full,
        /* Copy-only log backups do not truncate the log, so they must not satisfy the
           WARN:log-backup-overdue test below. Copy-only fulls stay counted above. */
        MAX(CASE WHEN type = 'L' AND is_copy_only = 0 THEN backup_finish_date END) AS last_log
    FROM msdb.dbo.backupset
    GROUP BY database_name
),
file_sizes AS (
    SELECT
        database_id,
        CAST(ROUND(SUM(CASE WHEN type = 0 THEN size * 8.0 / 1024 ELSE 0 END), 1) AS DECIMAL(18,1)) AS data_mb,
        CAST(ROUND(SUM(CASE WHEN type = 1 THEN size * 8.0 / 1024 ELSE 0 END), 1) AS DECIMAL(18,1)) AS log_mb,
        SUM(CASE WHEN type = 0 THEN 1 ELSE 0 END) AS data_file_count
    FROM sys.master_files
    GROUP BY database_id
)
SELECT
    d.name AS database_name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc AS recovery_model,
    d.log_reuse_wait_desc AS log_reuse_wait,
    d.compatibility_level AS compat_level,
    SUSER_SNAME(d.owner_sid) COLLATE DATABASE_DEFAULT AS owner,
    CAST(d.create_date AS DATE) AS create_date,
    fs.data_mb,
    fs.log_mb,
    fs.data_file_count,
    CASE d.is_auto_shrink_on WHEN 1 THEN 'YES' ELSE 'no' END AS auto_shrink,
    CASE d.is_auto_close_on WHEN 1 THEN 'YES' ELSE 'no' END AS auto_close,
    CASE d.is_read_only WHEN 1 THEN 'YES' ELSE 'no' END AS read_only,
    CAST(bd.last_full AS DATE) AS last_full_backup,
    CAST(bd.last_log AS DATE) AS last_log_backup,
    DATEDIFF(DAY, bd.last_full, GETDATE()) AS days_since_full,
    -- Severity-prefixed issue flags; NULL = clean
    NULLIF(RTRIM(
          CASE WHEN d.state_desc <> 'ONLINE'
               THEN 'CRIT:not-online ' ELSE '' END
        + CASE WHEN d.is_auto_shrink_on = 1
               THEN 'WARN:auto_shrink ' ELSE '' END
        + CASE WHEN d.is_auto_close_on = 1
               THEN 'WARN:auto_close ' ELSE '' END
        -- Full backup warnings cover master, model and msdb too: Microsoft lists all three as
        -- "backups required". tempdb (2) cannot be backed up, and a database snapshot
        -- (source_database_id set) cannot either, so both are skipped.
        + CASE WHEN d.database_id <> 2 AND d.source_database_id IS NULL AND bd.last_full IS NULL
               THEN 'WARN:never-backed-up ' ELSE '' END
        -- model rarely changes (back it up after customising it), so its age is not checked
        + CASE WHEN d.database_id NOT IN (2, 3) AND d.source_database_id IS NULL AND bd.last_full IS NOT NULL
                    AND DATEDIFF(DAY, bd.last_full, GETDATE()) > 7
               THEN 'WARN:full-' + CAST(DATEDIFF(DAY, bd.last_full, GETDATE()) AS VARCHAR) + 'd-ago '
               ELSE '' END
        -- Log backups: user databases only. master does not support them and model does not
        -- need them, even though model ships in FULL recovery.
        + CASE WHEN d.database_id > 4 AND d.source_database_id IS NULL AND d.recovery_model_desc = 'FULL'
                    AND (bd.last_log IS NULL OR DATEDIFF(HOUR, bd.last_log, GETDATE()) > 24)
               THEN 'WARN:log-backup-overdue ' ELSE '' END
        -- Log reuse waits other than NOTHING and LOG_BACKUP (expected) are worth noting
        + CASE WHEN d.log_reuse_wait_desc NOT IN ('NOTHING', 'LOG_BACKUP')
               THEN 'INFO:log-wait=' + d.log_reuse_wait_desc + ' ' ELSE '' END
    ), '') AS notes
FROM sys.databases d
LEFT JOIN file_sizes fs ON fs.database_id = d.database_id
LEFT JOIN backup_dates bd ON bd.database_name = d.name
ORDER BY d.database_id;
