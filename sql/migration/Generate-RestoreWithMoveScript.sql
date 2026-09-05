/*
Script Name : Generate-RestoreWithMoveScript
Category    : migration
Purpose     : Generate RESTORE DATABASE ... WITH MOVE statements from each database's latest
              full backup, relocating every file to a new data and log folder on the target.
              Run on the SOURCE server. Review the output, then run it on the TARGET.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-restore-with-move-script/)
Requires    : VIEW ANY DEFINITION, plus read access to msdb backup history
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @NewDataRoot   nvarchar(260) = N'D:\SQLData';   -- data files land here on the TARGET
DECLARE @NewLogRoot    nvarchar(260) = N'L:\SQLLogs';   -- log files land here on the TARGET
DECLARE @Databases     nvarchar(max) = NULL;            -- NULL = all; else 'DB1,DB2'
DECLARE @WithReplace   bit           = 0;               -- 1 overwrites a same-named target database
DECLARE @WithRecovery  bit           = 1;               -- 0 for NORECOVERY when a diff/log chain follows
DECLARE @StatsInterval int           = 5;

IF RIGHT(@NewDataRoot, 1) = N'\' SET @NewDataRoot = LEFT(@NewDataRoot, LEN(@NewDataRoot) - 1);
IF RIGHT(@NewLogRoot, 1)  = N'\' SET @NewLogRoot  = LEFT(@NewLogRoot,  LEN(@NewLogRoot)  - 1);

;WITH latest AS (
    -- The most recent full backup of each database that still exists and is online.
    SELECT bs.database_name, bs.backup_set_id, bs.media_set_id,
           ROW_NUMBER() OVER (PARTITION BY bs.database_name
                              ORDER BY bs.backup_finish_date DESC, bs.backup_set_id DESC) AS rn
    FROM msdb.dbo.backupset AS bs
    INNER JOIN sys.databases AS d ON d.name = bs.database_name
    WHERE bs.type = 'D'
      AND d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND (@Databases IS NULL
           OR bs.database_name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Databases, ',')))
),
device AS (   -- one DISK clause per media family, so striped backups are handled
    SELECT l.database_name,
           STRING_AGG(CAST(N'DISK = N''' + mf.physical_device_name + N'''' AS nvarchar(max)),
                      N', ') AS disks
    FROM latest AS l
    INNER JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = l.media_set_id
    WHERE l.rn = 1
    GROUP BY l.database_name
),
moves AS (
    -- Logical names come from the BACKUP, not from the live instance, so a file added since the
    -- backup was taken cannot produce "Logical file is not part of database" (error 3234).
    -- Each file keeps its own name and moves to the new root.
    SELECT l.database_name,
           STRING_AGG(CAST(
               N'    MOVE N''' + REPLACE(bf.logical_name, N'''', N'''''') + N''' TO N'''
               + CASE WHEN bf.file_type = 'L' THEN @NewLogRoot ELSE @NewDataRoot END + N'\'
               + REVERSE(LEFT(REVERSE(bf.physical_name),
                              CHARINDEX(N'\', REVERSE(bf.physical_name) + N'\') - 1))
               + N'''' AS nvarchar(max)), N',' + CHAR(13) + CHAR(10))
               WITHIN GROUP (ORDER BY bf.file_type, bf.logical_name) AS move_list
    FROM latest AS l
    INNER JOIN msdb.dbo.backupfile AS bf ON bf.backup_set_id = l.backup_set_id
    WHERE l.rn = 1
    GROUP BY l.database_name
)
SELECT x.restore_script
FROM (
    -- A database with no full backup cannot be scripted, and dropping it silently is the one
    -- way this script could lose you a database. One line, and only when it happens.
    SELECT 0 AS seq, N'' AS name,
           CAST(N'-- NO FULL BACKUP IN msdb, NOT SCRIPTED BELOW: '
                + STRING_AGG(CAST(d.name AS nvarchar(max)), N', ')
                  WITHIN GROUP (ORDER BY d.name) AS nvarchar(max)) AS restore_script
    FROM sys.databases AS d
    WHERE d.database_id > 4 AND d.state_desc = N'ONLINE'
      AND (@Databases IS NULL
           OR d.name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Databases, ',')))
      AND NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset AS bs
                      WHERE bs.database_name = d.name AND bs.type = 'D')
    HAVING COUNT(*) > 0

    UNION ALL

    SELECT 1, m.database_name,
        CAST(N'RESTORE DATABASE [' + m.database_name + N'] FROM ' + d.disks + CHAR(13) + CHAR(10)
        + N'  WITH ' + CASE WHEN @WithReplace = 1 THEN N'REPLACE, ' ELSE N'' END
                     + CASE WHEN @WithRecovery = 0 THEN N'NORECOVERY, ' ELSE N'' END
                     + N'STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + N',' + CHAR(13) + CHAR(10)
        + m.move_list + N';' AS nvarchar(max))
    FROM moves AS m
    INNER JOIN device AS d ON d.database_name = m.database_name
) AS x
ORDER BY x.seq, x.name;
