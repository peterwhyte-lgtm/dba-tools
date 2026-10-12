/*
Script Name : Get-MemoryGrantFeedback
Category    : performance
Purpose     : Queries in the current database that memory grant feedback has had to correct,
              read from Query Store (sys.query_store_plan_feedback). A row means the engine saw
              a grant that was wrong for this query, usually too small and spilling a sort or
              hash to TempDB, and stored an adjustment. Unlike sys.dm_exec_query_stats this
              survives a restart and a plan cache flush, because feedback persistence keeps it
              in Query Store. Shows the stored adjustment with the query's Query Store memory
              and TempDB figures.
              Run in the context of the target database (-Database <dbname>).
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW DATABASE PERFORMANCE STATE (SQL Server 2022+) or VIEW DATABASE STATE.
              SQL Server 2022 or later with Query Store on; earlier builds have no
              sys.query_store_plan_feedback.
Notes       : feedback_data is the engine's own JSON, shown as stored (AdditionalMemoryKB per
              plan node). It is not parsed here because OPENJSON fails on databases below
              compatibility level 130. Memory and TempDB columns are Query Store averages
              across the plan's retained intervals, converted from 8 KB pages to MB; TempDB
              space includes temp tables as well as spills.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('sys.query_store_plan_feedback') IS NULL
BEGIN
    SELECT 'Memory grant feedback persistence (sys.query_store_plan_feedback) needs SQL Server 2022 or later. '
         + 'This instance is ' + CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')) + '.' AS info;
END
ELSE IF ISNULL((SELECT actual_state_desc FROM sys.database_query_store_options), 'OFF')
        NOT IN ('READ_WRITE', 'READ_ONLY')
BEGIN
    SELECT
        DB_NAME() AS current_database,
        ISNULL((SELECT actual_state_desc FROM sys.database_query_store_options), 'OFF') AS query_store_status,
        'Feedback is only persisted with Query Store on: ALTER DATABASE [' + DB_NAME()
        + '] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE)' AS action;
END
ELSE
BEGIN
    -- Dynamic SQL so the batch still compiles on builds without the view.
    DECLARE @sql nvarchar(max) = N'
    SELECT
        DB_NAME() AS database_name,
        p.query_id,
        f.plan_id,
        OBJECT_NAME(q.object_id) AS object_name,
        f.state_desc AS feedback_state,
        f.feedback_data,
        f.last_updated_time AS feedback_updated,
        rs.executions,
        CAST(rs.avg_used_memory_pages * 8 / 1024.0 AS DECIMAL(10,2)) AS avg_used_memory_mb,
        CAST(rs.max_used_memory_pages * 8 / 1024.0 AS DECIMAL(10,2)) AS max_used_memory_mb,
        CAST(rs.avg_tempdb_pages * 8 / 1024.0 AS DECIMAL(10,2)) AS avg_tempdb_mb,
        CAST(rs.max_tempdb_pages * 8 / 1024.0 AS DECIMAL(10,2)) AS max_tempdb_mb,
        p.last_execution_time,
        LEFT(qt.query_sql_text, 400) AS query_text
    FROM sys.query_store_plan_feedback AS f
    JOIN sys.query_store_plan AS p ON p.plan_id = f.plan_id
    JOIN sys.query_store_query AS q ON q.query_id = p.query_id
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    OUTER APPLY (
        SELECT
            SUM(r.count_executions) AS executions,
            SUM(r.avg_query_max_used_memory * r.count_executions)
                / NULLIF(SUM(r.count_executions), 0) AS avg_used_memory_pages,
            MAX(r.max_query_max_used_memory) AS max_used_memory_pages,
            SUM(r.avg_tempdb_space_used * r.count_executions)
                / NULLIF(SUM(r.count_executions), 0) AS avg_tempdb_pages,
            MAX(r.max_tempdb_space_used) AS max_tempdb_pages
        FROM sys.query_store_runtime_stats AS r
        WHERE r.plan_id = f.plan_id
    ) AS rs
    WHERE f.feature_desc LIKE N''Memory Grant%''
    ORDER BY f.last_updated_time DESC;';

    EXEC sys.sp_executesql @sql;
END;
