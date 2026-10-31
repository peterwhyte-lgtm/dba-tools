/*
Script Name : Get-QueryStoreStatus
Category    : monitoring
Purpose     : Query Store enablement, fill ratio, capture mode, and health across all user databases.
              Surfaces databases where QS is off, full, or auto-switched to READ_ONLY.
Notes       : readonly_reason is a bitmap. 1/2/4/8 mean the DATABASE is read-only, single-user,
              in emergency mode or a readable secondary: Query Store follows it, so INFO, not a
              fault. 65536 = max_storage_size_mb reached, 131072/262144 = internal memory limit,
              524288 = database out of disk space: those are the WARNs. Size-based cleanup (AUTO)
              starts at 90% of max_storage_size_mb. Query Store works at any compatibility level
              (tested on a compat 100 database on SQL Server 2025); it needs SQL Server 2016+.
              ERROR state: run sp_query_store_consistency_check (2017+), or SET QUERY_STORE CLEAR ALL.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-store-status/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #qs_status (
    database_name SYSNAME,
    db_state NVARCHAR(60),
    qs_state NVARCHAR(60),
    qs_desired_state NVARCHAR(60),
    capture_mode NVARCHAR(60),
    cleanup_mode NVARCHAR(60),
    current_storage_mb DECIMAL(10,2),
    max_storage_mb DECIMAL(10,2),
    fill_pct DECIMAL(5,1),
    stale_query_threshold_days INT,
    flush_interval_seconds INT,
    readonly_reason INT,
    status NVARCHAR(200)
);

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #qs_status
        SELECT
            N' + QUOTENAME(@db, N'''') + N',
            N''' + (SELECT state_desc FROM sys.databases WHERE name = @db) + N''',
            actual_state_desc,
            desired_state_desc,
            query_capture_mode_desc,
            size_based_cleanup_mode_desc,
            CAST(current_storage_size_mb AS DECIMAL(10,2)),
            CAST(max_storage_size_mb AS DECIMAL(10,2)),
            CAST(100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5,1)),
            stale_query_threshold_days,
            flush_interval_seconds,
            readonly_reason,
            CASE
                WHEN actual_state_desc = ''OFF''
                    THEN ''WARN - Query Store not enabled''
                WHEN actual_state_desc = ''ERROR''
                    THEN ''WARN - Query Store in ERROR state; run sp_query_store_consistency_check''
                WHEN actual_state_desc = ''READ_ONLY'' AND readonly_reason & 65536 <> 0
                    THEN ''WARN - READ_ONLY: max_storage_size_mb reached''
                WHEN actual_state_desc = ''READ_ONLY'' AND readonly_reason & 524288 <> 0
                    THEN ''WARN - READ_ONLY: database is out of disk space''
                WHEN actual_state_desc = ''READ_ONLY'' AND readonly_reason & (131072 | 262144) <> 0
                    THEN ''WARN - READ_ONLY: Query Store internal memory limit''
                WHEN actual_state_desc = ''READ_ONLY'' AND readonly_reason & 15 <> 0
                    THEN ''INFO - READ_ONLY because the database is read-only, single-user, emergency or a secondary''
                WHEN 100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) > 80
                    THEN ''WARN - fill > 80%; READ_ONLY at 100% (size-based cleanup starts at 90% if AUTO)''
                WHEN desired_state_desc <> actual_state_desc
                    THEN ''WARN - desired/actual state mismatch''
                ELSE ''OK''
            END
        FROM ' + QUOTENAME(@db) + N'.sys.database_query_store_options;';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- QS catalog may not be visible if DB is inaccessible; skip silently
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    database_name,
    db_state,
    qs_state,
    qs_desired_state,
    capture_mode,
    cleanup_mode,
    current_storage_mb,
    max_storage_mb,
    fill_pct,
    stale_query_threshold_days,
    flush_interval_seconds,
    readonly_reason,
    status
FROM #qs_status
ORDER BY
    CASE WHEN status LIKE 'WARN%' THEN 1 WHEN status LIKE 'INFO%' THEN 2 ELSE 3 END,
    database_name;

DROP TABLE #qs_status;
