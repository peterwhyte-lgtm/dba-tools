/*
Script Name : Get-QueryVariance
Category    : performance
Purpose     : Queries from the plan cache where max execution time is at least 5x the minimum — the primary signal for parameter sniffing and plan instability. High execution count with high variance means the same query performs very differently depending on the parameter values in the cached plan.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/)
Requires    : VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE is enough on SQL Server 2022 and later)
Notes       : Ad-hoc and sp_executesql statements carry no dbid in sys.dm_exec_sql_text, so
              database_name falls back to the database the plan was compiled in.
              object_name needs VIEW ANY DEFINITION (or VIEW DEFINITION in that database), else NULL.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT TOP 30
    qs.execution_count,
    qs.min_elapsed_time / 1000 AS min_ms,
    qs.max_elapsed_time / 1000 AS max_ms,
    qs.total_elapsed_time / 1000 / qs.execution_count AS avg_ms,
    qs.last_elapsed_time / 1000 AS last_ms,
    qs.max_elapsed_time / NULLIF(qs.min_elapsed_time, 0) AS max_to_min_ratio,
    (qs.max_elapsed_time - qs.min_elapsed_time) / 1000 AS variance_ms,
    /* Worker time (CPU) variance */
    qs.max_worker_time / 1000 AS max_cpu_ms,
    qs.min_worker_time / 1000 AS min_cpu_ms,
    DB_NAME(COALESCE(qt.dbid, pa.dbid)) AS database_name,
    OBJECT_NAME(qt.objectid, qt.dbid) AS object_name,
    qs.query_hash,
    LEFT(LTRIM(qt.text), 200) AS query_snippet,
    qs.creation_time AS plan_cached_at
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
OUTER APPLY (SELECT CONVERT(int, a.value) AS dbid
             FROM sys.dm_exec_plan_attributes(qs.plan_handle) a
             WHERE a.attribute = N'dbid') pa
WHERE qs.execution_count >= 5
  AND qs.min_elapsed_time > 0
  AND qs.max_elapsed_time / NULLIF(qs.min_elapsed_time, 0) >= 5
ORDER BY max_to_min_ratio DESC, variance_ms DESC;
