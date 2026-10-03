/*
Script Name : Get-BackupRestoreDurationEstimate
Category    : backups-and-recovery
Purpose     : Analyze backup duration and throughput metrics from msdb for performance baseline.
              One row per database, per backup type, per compression setting: the largest set,
              with every column on the row taken from that same set.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-restore-duration-estimate/)
Requires    : db_datareader on msdb
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH sets AS (
    SELECT
        bs.database_name,
        CASE bs.type WHEN 'D' THEN 'FULL'
                     WHEN 'I' THEN 'DIFF'
                     WHEN 'L' THEN 'LOG'
                     WHEN 'F' THEN 'FILE'
                     WHEN 'G' THEN 'FILEDIFF'
                     WHEN 'P' THEN 'PARTIAL'
                     WHEN 'Q' THEN 'PARTIALDIFF'
                     ELSE bs.type END                                   AS backup_type,
        CASE WHEN COALESCE(bs.compressed_backup_size, bs.backup_size)
                  < bs.backup_size THEN 1 ELSE 0 END                    AS is_compressed,
        bs.backup_size / 1024.0 / 1024                                  AS size_mb,
        COALESCE(bs.compressed_backup_size, bs.backup_size)
            / 1024.0 / 1024                                             AS written_mb,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)   AS duration_seconds,
        bs.backup_finish_date,
        ROW_NUMBER() OVER (
            PARTITION BY bs.database_name, bs.type,
                         CASE WHEN COALESCE(bs.compressed_backup_size, bs.backup_size)
                                   < bs.backup_size THEN 1 ELSE 0 END
            ORDER BY bs.backup_size DESC, bs.backup_set_id DESC)        AS largest_set
    FROM msdb.dbo.backupset AS bs
    WHERE bs.backup_start_date IS NOT NULL
      AND bs.backup_finish_date IS NOT NULL
)
SELECT
    s.database_name,
    s.backup_type,
    s.is_compressed,
    CAST(s.size_mb    AS DECIMAL(18,2))                                 AS backup_size_mb,
    CAST(s.written_mb AS DECIMAL(18,2))                                 AS written_mb,
    s.duration_seconds,
    CAST(s.size_mb    / NULLIF(s.duration_seconds, 0) AS DECIMAL(18,2)) AS mb_per_second,
    CAST(s.written_mb / NULLIF(s.duration_seconds, 0) AS DECIMAL(18,2)) AS written_mb_per_second,
    CONVERT(char(16), s.backup_finish_date, 120)                        AS measured_on
FROM sets AS s
WHERE s.largest_set = 1
ORDER BY backup_size_mb DESC, s.database_name, s.backup_type;
