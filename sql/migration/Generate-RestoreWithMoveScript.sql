/*
Script Name : Generate-RestoreWithMoveScript
Category    : migration
Purpose     : Generate RESTORE DATABASE scripts with WITH MOVE for all online user databases.
              Run on SOURCE server. Supply the backup path and path prefix mappings for
              data and log files before executing the output on TARGET.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-restore-with-move-script/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Reads file layout from source server's sys.master_files to generate WITH MOVE
  clauses. Path prefixes are replaced using @OldDataRoot→@NewDataRoot and
  @OldLogRoot→@NewLogRoot substitutions. Adjust these four variables before running.

  If source and target have IDENTICAL drive layouts, use Generate-RestoreScript.sql instead
  (no WITH MOVE needed). Use this script when drive letters or folder paths differ.

  After running the output on the target:
    1. Verify all databases are ONLINE: SELECT name, state_desc FROM sys.databases WHERE database_id > 4
    2. Run Fix-OrphanedUsers.sql to re-map database users to logins
    3. Run Get-PostMigrationValidation.sql on both servers and compare
*/

-- ── Adjust these four variables ───────────────────────────────────────────────
DECLARE @BackupPath    nvarchar(260) = N'\\BACKUP-SERVER\SQL-Backups';  -- UNC or local path to .bak files
DECLARE @OldDataRoot   nvarchar(260) = N'E:\SQLData';                   -- data path prefix on SOURCE
DECLARE @NewDataRoot   nvarchar(260) = N'D:\SQLData';                   -- data path prefix on TARGET
DECLARE @OldLogRoot    nvarchar(260) = N'L:\SQLLogs';                   -- log path prefix on SOURCE
DECLARE @NewLogRoot    nvarchar(260) = N'L:\SQLLogs';                   -- log path prefix on TARGET
DECLARE @StatsInterval int           = 5;
DECLARE @WithReplace   bit           = 0;   -- 0 = no REPLACE. Set to 1 ONLY when overwriting an
                                            -- existing database of the same name on the target is
                                            -- intended. The safe value is the default on purpose.
DECLARE @WithRecovery  bit           = 1;   -- 0 = NORECOVERY (leave in restoring state for diff/log chain)
-- ─────────────────────────────────────────────────────────────────────────────

IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);
IF RIGHT(@OldDataRoot, 1) = N'\' SET @OldDataRoot = LEFT(@OldDataRoot, LEN(@OldDataRoot) - 1);
IF RIGHT(@NewDataRoot, 1) = N'\' SET @NewDataRoot = LEFT(@NewDataRoot, LEN(@NewDataRoot) - 1);
IF RIGHT(@OldLogRoot, 1) = N'\' SET @OldLogRoot = LEFT(@OldLogRoot, LEN(@OldLogRoot) - 1);
IF RIGHT(@NewLogRoot, 1) = N'\' SET @NewLogRoot = LEFT(@NewLogRoot, LEN(@NewLogRoot) - 1);

DECLARE @cmd   nvarchar(max);
DECLARE @block nvarchar(max);
DECLARE @crlf  nchar(2)  = CHAR(13) + CHAR(10);

-- Every file whose path did NOT start with the configured prefix, so it was left pointing at
-- the SOURCE path. Collected here as well as warned about inline, because the whole reason to
-- generate a script is that it is long, and a comment 400 lines up is a comment nobody reads.
DECLARE @unmatched TABLE (db sysname, logical_name sysname, file_type nvarchar(60),
                          source_path nvarchar(260));

-- ONE ROW PER DATABASE, not a single text blob. A blob makes you hand-edit out the databases you
-- did not want and scroll to find the warnings. A grid lets you sort on `unmapped`, see at a
-- glance which databases are ready, and copy only the rows you are actually migrating.
-- seq 0 is the preamble and seq 9999 the summary, so ORDER BY seq and copying the whole `script`
-- column still yields one valid script, exactly as before.
DECLARE @out TABLE (seq int, database_name sysname NULL, files int NULL, unmapped int NULL,
                    status nvarchar(60) NULL, script nvarchar(max));

INSERT @out (seq, database_name, files, unmapped, status, script)
VALUES (0, NULL, NULL, NULL, N'-- preamble, run once',
    N'-- ================================================================' + @crlf +
    N'-- RESTORE with MOVE script' + @crlf +
    N'-- Source  : ' + @@SERVERNAME + @crlf +
    N'-- Generated: ' + CONVERT(nvarchar(30), GETDATE(), 120) + @crlf +
    N'-- Backup path : ' + @BackupPath + @crlf +
    N'-- Data root : ' + @OldDataRoot + N' -> ' + @NewDataRoot + @crlf +
    N'-- Log  root : ' + @OldLogRoot  + N' -> ' + @NewLogRoot  + @crlf +
    N'-- A root is applied ONLY to files whose path already starts with it. Check the' + @crlf +
    N'-- unmapped column per database, and the summary row, for what it did NOT cover.' + @crlf +
    N'-- ================================================================' + @crlf +
    N'-- Set @ts to the actual timestamp of your backup files.' + @crlf +
    N'DECLARE @ts varchar(15) = ''yyyyMMdd_HHmmss''; -- REPLACE WITH ACTUAL TIMESTAMP' + @crlf +
    N'DECLARE @path nvarchar(500);' + @crlf);

-- One block per database using file layout from sys.master_files
DECLARE @dbname       nvarchar(128);
DECLARE @logical_name nvarchar(128);
DECLARE @old_path     nvarchar(260);
DECLARE @new_path     nvarchar(260);
DECLARE @file_type    nvarchar(60);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT d.name
    FROM sys.databases d
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
    ORDER BY d.name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Build the WITH MOVE clause for this database
    SET @block = N'';

    DECLARE file_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT mf.name, mf.physical_name, mf.type_desc
        FROM sys.master_files mf
        INNER JOIN sys.databases d ON mf.database_id = d.database_id
        WHERE d.name = @dbname
        ORDER BY mf.file_id;

    OPEN file_cur;
    FETCH NEXT FROM file_cur INTO @logical_name, @old_path, @file_type;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Replace old path prefix with new path prefix.
        -- Only when the source path actually STARTS with the configured prefix.
        -- If it does not, the prefix arithmetic below would chop a fixed number of
        -- characters off an unrelated path and produce a plausible-looking but wrong
        -- target (E:\SQLData against a real D:\MSSQL\DATA\x.mdf yields
        -- D:\SQLDataATA\x.mdf). Fall back to the UNCHANGED source path instead: the
        -- restore then either works, because the layout already matches, or fails
        -- loudly on a path that does not exist. It never silently invents one.
        SET @new_path = CASE
            WHEN @file_type = 'LOG' AND LEFT(@old_path, LEN(@OldLogRoot)) = @OldLogRoot
                THEN @NewLogRoot  + SUBSTRING(@old_path, LEN(@OldLogRoot)  + 1, LEN(@old_path))
            WHEN @file_type <> 'LOG' AND LEFT(@old_path, LEN(@OldDataRoot)) = @OldDataRoot
                THEN @NewDataRoot + SUBSTRING(@old_path, LEN(@OldDataRoot) + 1, LEN(@old_path))
            ELSE @old_path
        END;

        SET @block = @block
            + CASE
                WHEN @file_type = 'LOG' AND LEFT(@old_path, LEN(@OldLogRoot)) <> @OldLogRoot
                    THEN N'       -- WARNING: source path does not start with @OldLogRoot (''' + @OldLogRoot + N'''), so NO remap was applied. The MOVE below still points at the SOURCE path. Set @OldLogRoot to match, or edit this line by hand.' + @crlf
                WHEN @file_type <> 'LOG' AND LEFT(@old_path, LEN(@OldDataRoot)) <> @OldDataRoot
                    THEN N'       -- WARNING: source path does not start with @OldDataRoot (''' + @OldDataRoot + N'''), so NO remap was applied. The MOVE below still points at the SOURCE path. Set @OldDataRoot to match, or edit this line by hand.' + @crlf
                ELSE N''
              END
            + N'       ,MOVE N''' + REPLACE(@logical_name, N'''', N'''''') + N''' TO N''' + REPLACE(@new_path, N'''', N'''''') + N'''' + @crlf;

        IF (@file_type = 'LOG'  AND LEFT(@old_path, LEN(@OldLogRoot))  <> @OldLogRoot)
        OR (@file_type <> 'LOG' AND LEFT(@old_path, LEN(@OldDataRoot)) <> @OldDataRoot)
            INSERT @unmatched (db, logical_name, file_type, source_path)
            VALUES (@dbname, @logical_name, @file_type, @old_path);

        FETCH NEXT FROM file_cur INTO @logical_name, @old_path, @file_type;
    END

    CLOSE file_cur;
    DEALLOCATE file_cur;

    -- Assemble the full RESTORE statement as this database's own row
    DECLARE @db_files    int = (SELECT COUNT(*) FROM sys.master_files mf
                                INNER JOIN sys.databases d ON mf.database_id = d.database_id
                                WHERE d.name = @dbname);
    DECLARE @db_unmapped int = (SELECT COUNT(*) FROM @unmatched WHERE db = @dbname);

    INSERT @out (seq, database_name, files, unmapped, status, script)
    VALUES (
        (SELECT COUNT(*) FROM @out),
        @dbname, @db_files, @db_unmapped,
        CASE WHEN @db_unmapped = 0 THEN N'ready'
             WHEN @db_unmapped = @db_files THEN N'REVIEW: no file remapped'
             ELSE N'REVIEW: ' + CAST(@db_unmapped AS nvarchar(10)) + N' of '
                  + CAST(@db_files AS nvarchar(10)) + N' not remapped' END,
          N'SET @path = ''' + @BackupPath + N'\' + @dbname + N'_FULL_'' + @ts + ''.bak'';' + @crlf
        + N'RESTORE DATABASE [' + @dbname + N'] FROM DISK = @path' + @crlf
        + N'    WITH' + @crlf
        + CASE WHEN @WithReplace   = 1 THEN N'         REPLACE,' + @crlf  ELSE N'' END
        + CASE WHEN @WithRecovery  = 0 THEN N'         NORECOVERY,' + @crlf ELSE N'' END
        + N'         STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + @crlf
        + @block
        + N';' + @crlf);

    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

-- The summary row. Also PREPENDED to the preamble when NOTHING matched, because a run where no
-- file was remapped is a misconfiguration, not a script with some caveats: read top-down, the
-- header would otherwise announce a root mapping that did not happen to a single file.
DECLARE @n     int = (SELECT COUNT(*) FROM @unmatched);
DECLARE @files int = (SELECT ISNULL(SUM(files), 0) FROM @out WHERE database_name IS NOT NULL);

IF @n > 0
BEGIN
    SET @cmd =
          N'-- ================================================================' + @crlf
        + N'-- REVIEW BEFORE RUNNING: ' + CAST(@n AS nvarchar(10)) + N' of '
        + CAST(@files AS nvarchar(10)) + N' file(s) were NOT remapped.' + @crlf
        + N'-- Their paths do not start with @OldDataRoot ('  + @OldDataRoot + N')' + @crlf
        + N'--                        or @OldLogRoot  ('      + @OldLogRoot  + N')' + @crlf
        + N'-- Those MOVE targets still point at the SOURCE path. Fix the roots and re-run this' + @crlf
        + N'-- generator, or edit those MOVE targets by hand.' + @crlf
        + N'-- ================================================================' + @crlf;

    SELECT @cmd = @cmd
        + N'--   [' + db + N'] ' + logical_name
        + N' (' + file_type + N') -> ' + source_path + @crlf
    FROM @unmatched
    ORDER BY db, logical_name;

    SET @cmd = @cmd + N'-- ================================================================' + @crlf;

    INSERT @out (seq, database_name, files, unmapped, status, script)
    VALUES (9999, NULL, @files, @n,
            CASE WHEN @n = @files THEN N'STOP: nothing was remapped'
                 ELSE N'REVIEW: ' + CAST(@n AS nvarchar(10)) + N' file(s)' END,
            @cmd);

    -- Nothing matched at all: say so at the TOP too, where it cannot be scrolled past.
    IF @n = @files
        UPDATE @out
        SET script = N'-- ****************************************************************' + @crlf
                   + N'-- STOP. NOT ONE FILE WAS REMAPPED, so every MOVE below points at the' + @crlf
                   + N'-- SOURCE path and this script moves nothing. @OldDataRoot / @OldLogRoot' + @crlf
                   + N'-- do not match the real paths on ' + @@SERVERNAME + N'.' + @crlf
                   + N'-- Set them from what the source actually reports, then re-run.' + @crlf
                   + N'-- ****************************************************************' + @crlf
                   + script,
            status = N'-- STOP: roots match nothing'
        WHERE seq = 0;
END
ELSE
    INSERT @out (seq, database_name, files, unmapped, status, script)
    VALUES (9999, NULL, @files, 0, N'all remapped',
            N'-- All files matched the configured path prefixes. No MOVE target was left' + @crlf
          + N'-- pointing at a source path.' + @crlf);

-- ONE COLUMN, and it is the DDL. One row per database, plus the preamble that declares @ts and
-- the summary that says what was not remapped. Copy the column, run it on the target.
-- The counts above are used to build the warnings and the summary; they are deliberately NOT
-- returned as columns, because this script's job is to emit restore DDL, not to report on itself.
SELECT script AS restore_script
FROM @out
ORDER BY seq;
