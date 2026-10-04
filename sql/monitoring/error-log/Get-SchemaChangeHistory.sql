/*
Script Name : Get-SchemaChangeHistory
Category    : monitoring
Purpose     : Recent DDL changes (CREATE, ALTER, DROP) captured by the SQL Server default trace - answers "what changed on this server recently?" after an incident or unexpected behaviour.
              Requires the default trace to be enabled (on by default). Reads every rollover file the trace still keeps, not only the current one.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-schema-change-history/)
Requires    : ALTER TRACE
Notes       : The default trace keeps 5 rollover files of 20 MB, so the window is a volume, not a period:
              days on a quiet instance, hours on a busy one. A service restart starts a new file but the
              older files are still read here.
              sp_rename writes no DDL event to the default trace, so a renamed object shows only its
              original Object:Created row under the old name.
              ALTER TABLE ADD or DROP COLUMN shows as Object:Altered on the table, with no column name.
              The default trace does not capture the statement text for these events, so there is no
              sql_text column: the who, where and when are all the trace holds.
              Database create and drop rows have no object name; object_type reads Database.
              Auto-created statistics (_WA_Sys_*) are excluded; a user CREATE STATISTICS is kept.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @tracepath NVARCHAR(260);
SELECT @tracepath = path FROM sys.traces WHERE is_default = 1;

IF @tracepath IS NULL
BEGIN
    RAISERROR('Default trace is not enabled. Enable it via sp_configure ''default trace enabled'', 1.', 16, 1);
    RETURN;
END;

/* sys.traces names the CURRENT file (log_NN.trc), and fn_trace_gettable reads from the file it is
   given forward, so passing that path skips every older rollover file. The base name log.trc in
   the same folder makes it read all the files that still exist. */
SET @tracepath = REVERSE(SUBSTRING(REVERSE(@tracepath), CHARINDEX(N'\', REVERSE(@tracepath)), 260)) + N'log.trc';

/* -- DDL event classes: 46 = Created, 47 = Deleted, 164 = Altered -------------------------------- */
SELECT
    t.StartTime AS change_time,
    te.name AS change_type,
    t.DatabaseName AS database_name,
    t.ObjectName AS object_name,
    CASE t.ObjectType
        WHEN 8277  THEN 'Table'
        WHEN 22601 THEN 'Index'
        WHEN 8272  THEN 'Stored procedure'
        WHEN 8278  THEN 'View'
        WHEN 20038 THEN 'Scalar function'
        WHEN 17993 THEN 'Inline table-valued function'
        WHEN 18004 THEN 'Table-valued function'
        WHEN 21076 THEN 'Trigger'
        WHEN 21572 THEN 'Database trigger'
        WHEN 8276  THEN 'Server trigger'
        WHEN 21587 THEN 'Statistics'
        WHEN 16964 THEN 'Database'
        WHEN 17235 THEN 'Schema'
        WHEN 20051 THEN 'Synonym'
        WHEN 22868 THEN 'Type'
        WHEN 20307 THEN 'Sequence'
        WHEN 8259  THEN 'Check constraint'
        WHEN 8260  THEN 'Default constraint'
        WHEN 8262  THEN 'Foreign key'
        WHEN 19280 THEN 'Primary key'
        WHEN 20821 THEN 'Unique constraint'
        WHEN 17747 THEN 'Event session' /* MS Docs lists 17747 as Security Event; CREATE/DROP EVENT SESSION writes it */
        ELSE 'Other (' + CAST(t.ObjectType AS VARCHAR(10)) + ')'
    END AS object_type,
    t.LoginName AS changed_by,
    t.HostName AS host_name,
    t.ApplicationName AS application_name
FROM sys.fn_trace_gettable(@tracepath, DEFAULT) t
JOIN sys.trace_events te ON te.trace_event_id = t.EventClass
WHERE t.EventClass IN (46, 47, 164) /* Object:Created, Object:Deleted, Object:Altered */
  AND t.EventSubClass = 1 /* Commit only - each DDL event is logged as Begin (0) then Commit (1), or
                             Rollback (2) when it never happened; without this every change doubles */
  AND ISNULL(t.DatabaseName, '') NOT IN ('', 'mssqlsystemresource')
  AND ISNULL(t.ObjectName, N'') NOT LIKE N'[_]WA[_]Sys[_]%' /* auto-created statistics are not schema
                             changes; ISNULL keeps database create and drop rows, which have no name */
ORDER BY t.StartTime DESC, t.EventSequence DESC;
