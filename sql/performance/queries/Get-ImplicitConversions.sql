/*
Script Name : Get-ImplicitConversions
Category    : performance
Purpose     : Scans the plan cache for implicit conversion warnings (PlanAffectingConvert), one row
              per cached statement. ConvertIssue "Seek Plan" means the conversion stopped an index
              seek; "Cardinality Estimate" means it may have skewed the row estimate. Most common
              cause: VARCHAR column compared to an NVARCHAR parameter under a SQL collation.
              Covers stored procedures and the parameterised statements applications send through
              sp_executesql. Reads every cached statement, so cost grows with the plan cache.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-implicit-conversions/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Medium
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @top INT = 50; -- rows returned; every cached statement is still read

SELECT TOP (@top)
    w.convert_issue,
    qs.total_logical_reads AS total_logical_reads,
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    CAST(qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000.0 AS DECIMAL(10,2)) AS avg_cpu_ms,
    DB_NAME(CONVERT(INT, pa.value)) AS database_name,
    OBJECT_NAME(qt.objectid, qt.dbid) AS object_name,
    LEFT(SUBSTRING(qt.text, qs.statement_start_offset / 2 + 1,
        (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
              ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2 + 1), 500) AS query_text,
    w.convert_expression,
    qs.creation_time AS plan_cached_at,
    w.statement_plan AS query_plan_xml
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
CROSS APPLY sys.dm_exec_text_query_plan(qs.plan_handle, qs.statement_start_offset, qs.statement_end_offset) AS tqp
CROSS APPLY (
    SELECT CONVERT(INT, value) AS value
    FROM sys.dm_exec_plan_attributes(qs.plan_handle)
    WHERE attribute = N'dbid'
) AS pa
CROSS APPLY (SELECT TRY_CONVERT(XML, tqp.query_plan) AS statement_plan) AS x
CROSS APPLY (
    SELECT
        x.statement_plan.value('(//*:PlanAffectingConvert/@ConvertIssue)[1]', 'NVARCHAR(60)') AS convert_issue,
        x.statement_plan.value('(//*:PlanAffectingConvert/@Expression)[1]', 'NVARCHAR(400)') AS convert_expression,
        x.statement_plan
) AS w
WHERE tqp.query_plan LIKE N'%PlanAffectingConvert%'
  AND pa.value > 4
ORDER BY CASE WHEN w.convert_issue = N'Seek Plan' THEN 0 ELSE 1 END,
         qs.total_logical_reads DESC;
