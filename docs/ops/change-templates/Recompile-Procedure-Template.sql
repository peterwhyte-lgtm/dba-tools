/*
Change Order / DBA Runbook: Recompile a Procedure

Purpose:
  Refresh the execution plan for a stored procedure after schema, index, or statistics changes.
Business impact:
  Helps force a fresh plan when a prior cached plan is no longer optimal.
Pre-checks:
  1. Verify the procedure name and schema.
  2. Confirm the DBA has ALTER permissions on the procedure.
  3. Review recent plan regressions or performance incidents before executing.
Execution notes:
  - Replace placeholders before execution.
  - Use this as a targeted plan refresh, not as a general replacement for index tuning.
Validation:
  - Confirm the procedure exists and the command completes successfully.
Rollback:
  - No rollback is needed; SQL Server will recreate the plan when the proc runs again.
*/
-- SAFE:WritesData
-- IMPACT:Medium

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @TargetDatabase sysname = N'YourDatabase';
DECLARE @TargetSchema   sysname = N'dbo';
DECLARE @TargetProcedure sysname = N'YourProcedure';

DECLARE @sql nvarchar(max);

SET @sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
EXEC sp_recompile N''' + REPLACE(@TargetSchema,'''','''''') + N'.' + REPLACE(@TargetProcedure,'''','''''') + N''';';

PRINT @sql;
EXEC sys.sp_executesql @sql;

-- Validation: confirm the procedure exists in the target database.
SET @sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
SELECT
    s.name AS schema_name,
    p.name AS procedure_name
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON p.schema_id = s.schema_id
WHERE s.name = @TargetSchema
  AND p.name = @TargetProcedure;';
EXEC sys.sp_executesql @sql,
    N'@TargetSchema sysname, @TargetProcedure sysname',
    @TargetSchema    = @TargetSchema,
    @TargetProcedure = @TargetProcedure;
