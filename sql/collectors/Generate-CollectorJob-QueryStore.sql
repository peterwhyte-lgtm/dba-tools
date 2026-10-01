/*
Script Name : Generate-CollectorJob-QueryStore
Category    : collectors
Purpose     : Generates DDL to create the DBA - Collect Query Store SQL Agent job.
              Creates the target database and collector.QueryStore table if absent,
              then outputs T-SQL to install a recurring Query Store collection job.
              The job iterates all online user databases with QS enabled and inserts
              the top 50 queries by average CPU from the most recently completed
              runtime stats interval. Databases without QS are silently skipped.
              Edit parameters, review output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-collect-health-and-configuration-baselines/)
Requires    : sysadmin (to run generated DDL); VIEW DATABASE STATE per database at job runtime
Notes       : Default interval: every 30 minutes.
              Query Store must be enabled on each target database to collect data.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase  sysname       = N'DBAMonitor';   -- created if absent
DECLARE @JobOwner        sysname       = N'sa';
DECLARE @CategoryName    nvarchar(128) = N'DBA Collectors';
DECLARE @IntervalMinutes int           = 30;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q       nchar(1)      = NCHAR(39);
DECLARE @crlf    nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl     nvarchar(max) = N'';
DECLARE @jobName sysname       = N'DBA - Collect Query Store';
DECLARE @stepCmd nvarchar(max);

-- ── Step command (| = single-quote placeholder) ────────────────────────────────
-- Builds @sql via string concatenation so @db is evaluated, not embedded literally.
-- N|...|  segments become N'...' after REPLACE; || inside them → '' (escaped quote).
-- || ||  → '' '' which within a N-string equals the space character literal ' '.
SET @stepCmd = REPLACE(
N'SET NOCOUNT ON;
DECLARE @db   sysname;
DECLARE @dbid int;
DECLARE @sql  nvarchar(max);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = |ONLINE| AND database_id > 4 AND is_read_only = 0;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @dbid = DB_ID(@db);
    SET @sql =
        N|DECLARE @iid BIGINT; |
      + N|SELECT TOP 1 @iid = runtime_stats_interval_id FROM [| + @db + N|].sys.query_store_runtime_stats_interval |
      + N|WHERE end_time < GETDATE() ORDER BY end_time DESC; |
      + N|IF @iid IS NOT NULL AND EXISTS ( |
      + N|    SELECT 1 FROM [| + @db + N|].sys.database_query_store_options |
      + N|    WHERE desired_state_desc IN (N||READ_WRITE||, N||READ_ONLY||)) |
      + N|BEGIN |
      + N|    INSERT INTO [<<DB>>].[collector].[QueryStore] |
      + N|        (server_name, collection_time, database_name, query_id, query_sql_text, |
      + N|         plan_id, query_plan_hash, interval_start, interval_end, count_executions, |
      + N|         avg_cpu_ms, avg_duration_ms, avg_logical_io_reads, avg_rowcount, |
      + N|         is_forced_plan, plan_forcing_type_desc) |
      + N|    SELECT TOP 50 @@SERVERNAME, GETDATE(), DB_NAME(| + CAST(@dbid AS nvarchar(10)) + N|), q.query_id, |
      + N|        LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), || ||), CHAR(10), || ||), 500), |
      + N|        p.plan_id, CONVERT(char(32), p.query_plan_hash, 2), |
      + N|        rsi.start_time, rsi.end_time, rs.count_executions, |
      + N|        CAST(rs.avg_cpu_time    / 1000.0 AS decimal(12,2)), |
      + N|        CAST(rs.avg_duration    / 1000.0 AS decimal(12,2)), |
      + N|        rs.avg_logical_io_reads, CAST(rs.avg_rowcount AS bigint), |
      + N|        p.is_forced_plan, p.plan_forcing_type_desc |
      + N|    FROM [| + @db + N|].sys.query_store_query         q |
      + N|    JOIN [| + @db + N|].sys.query_store_query_text    qt  ON qt.query_text_id              = q.query_text_id |
      + N|    JOIN [| + @db + N|].sys.query_store_plan          p   ON p.query_id                    = q.query_id |
      + N|    JOIN [| + @db + N|].sys.query_store_runtime_stats rs  ON rs.plan_id                    = p.plan_id |
      + N|                                                          AND rs.runtime_stats_interval_id  = @iid |
      + N|    JOIN [| + @db + N|].sys.query_store_runtime_stats_interval rsi |
      + N|        ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id |
      + N|    WHERE q.is_internal_query = 0 |
      + N|    ORDER BY rs.avg_cpu_time DESC; |
      + N|END|;

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Skip inaccessible or incompatible databases
    END CATCH;

    FETCH NEXT FROM db_cur INTO @db;
END;
CLOSE db_cur;
DEALLOCATE db_cur;'
, N'|', NCHAR(39));

SET @stepCmd = REPLACE(@stepCmd, N'<<DB>>', @TargetDatabase);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- ================================================================' + @crlf +
    N'-- Generated by Generate-CollectorJob-QueryStore.sql'                + @crlf +
    N'-- Server    : ' + @@SERVERNAME                                      + @crlf +
    N'-- Target DB : ' + @TargetDatabase                                   + @crlf +
    N'-- Generated : ' + CONVERT(nvarchar(20), GETDATE(), 120)             + @crlf +
    N'-- ================================================================' + @crlf + @crlf;

-- ── 1. Target database ────────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N' + @q + @TargetDatabase + @q + N')' + @crlf +
    N'    CREATE DATABASE [' + @TargetDatabase + N'];'                                               + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 2. Collector schema ───────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (SELECT 1 FROM [' + @TargetDatabase + N'].sys.schemas WHERE name = N' + @q + N'collector' + @q + N')' + @crlf +
    N'    EXEC [' + @TargetDatabase + N'].sys.sp_executesql N' + @q + N'CREATE SCHEMA collector' + @q + N';'              + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 3. QueryStore table ───────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (' + @crlf +
    N'    SELECT 1 FROM [' + @TargetDatabase + N'].sys.objects o'                                                        + @crlf +
    N'    JOIN [' + @TargetDatabase + N'].sys.schemas s ON s.schema_id = o.schema_id'                                    + @crlf +
    N'    WHERE o.name = N' + @q + N'QueryStore' + @q + N' AND s.name = N' + @q + N'collector' + @q + N')'             + @crlf +
    N'CREATE TABLE [' + @TargetDatabase + N'].[collector].[QueryStore] ('                                                + @crlf +
    N'    id                     bigint IDENTITY(1,1) PRIMARY KEY,'                                                       + @crlf +
    N'    server_name            nvarchar(128) NOT NULL,'                                                                  + @crlf +
    N'    collection_time        datetime2     NOT NULL,'                                                                  + @crlf +
    N'    database_name          nvarchar(128),'                                                                           + @crlf +
    N'    query_id               bigint,'                                                                                   + @crlf +
    N'    query_sql_text         nvarchar(500),'                                                                            + @crlf +
    N'    plan_id                bigint,'                                                                                   + @crlf +
    N'    query_plan_hash        char(32),'                                                                                 + @crlf +
    N'    interval_start         datetime2,'                                                                                + @crlf +
    N'    interval_end           datetime2,'                                                                                + @crlf +
    N'    count_executions       bigint,'                                                                                   + @crlf +
    N'    avg_cpu_ms             decimal(12,2),'                                                                            + @crlf +
    N'    avg_duration_ms        decimal(12,2),'                                                                            + @crlf +
    N'    avg_logical_io_reads   bigint,'                                                                                   + @crlf +
    N'    avg_rowcount           bigint,'                                                                                   + @crlf +
    N'    is_forced_plan         bit,'                                                                                      + @crlf +
    N'    plan_forcing_type_desc nvarchar(60)'                                                                              + @crlf +
    N');'                                                                                                                  + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 4. Agent category ─────────────────────────────────────────────────────────
SET @ddl +=
    N'USE msdb;' + @crlf +
    N'GO' + @crlf + @crlf +
    N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N' + @q + @CategoryName + @q + N' AND category_class = 1)' + @crlf +
    N'    EXEC msdb.dbo.sp_add_category'                                                                                             + @crlf +
    N'        @class = N' + @q + N'JOB' + @q + N', @type = N' + @q + N'LOCAL' + @q + N', @name = N' + @q + @CategoryName + @q + N';' + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 5. Job + step + schedule ──────────────────────────────────────────────────
SET @ddl +=
    N'-- Job: ' + @jobName + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + @jobName + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job @job_name = N' + @q + @jobName + @q + N', @delete_unused_schedule = 1;' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_job'                                                    + @crlf +
    N'    @job_name         = N' + @q + @jobName + @q + N','                       + @crlf +
    N'    @enabled          = 1,'                                                   + @crlf +
    N'    @owner_login_name = N' + @q + @JobOwner + @q + N','                      + @crlf +
    N'    @category_name    = N' + @q + @CategoryName + @q + N';'                  + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_jobstep'                                                + @crlf +
    N'    @job_name          = N' + @q + @jobName + @q + N','                      + @crlf +
    N'    @step_id           = 1,'                                                  + @crlf +
    N'    @step_name         = N' + @q + N'Collect QS top queries all databases' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N','                       + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N','                     + @crlf +
    N'    @command           = N' + @q + REPLACE(@stepCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 0,'                                                  + @crlf +
    N'    @on_success_action = 1,'                                                  + @crlf +
    N'    @on_fail_action    = 2;'                                                  + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_schedule'                                               + @crlf +
    N'    @schedule_name        = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N',' + @crlf +
    N'    @freq_type            = 4,'                                               + @crlf +   -- daily recurring
    N'    @freq_interval        = 1,'                                               + @crlf +
    N'    @freq_subday_type     = 4,'                                               + @crlf +   -- minutes
    N'    @freq_subday_interval = ' + CAST(@IntervalMinutes AS nvarchar(5)) + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_attach_schedule'                                            + @crlf +
    N'    @job_name      = N' + @q + @jobName + @q + N','                          + @crlf +
    N'    @schedule_name = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + @jobName + @q + N';'   + @crlf +
    N'GO' + @crlf;

SELECT @ddl AS ddl;
