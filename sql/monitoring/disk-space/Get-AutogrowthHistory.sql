/*
Script Name : Get-AutogrowthHistory
Category    : monitoring
Purpose     : Reads autogrowth events from the SQL Server default trace.
              Autogrowth events during business hours indicate undersized files;
              frequent events indicate the growth increment is too small.
              Use this to right-size initial file sizes and growth increments.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-autogrowth-history/)
Requires    : VIEW SERVER STATE, ALTER TRACE (to read trace files)
HealthCheck : Yes
Notes       : Default trace rolls over: 5 files, 20 MB each, oldest discarded.
              History depth is therefore a function of how chatty the instance is,
              not of elapsed time. Measured on a quiet lab instance 2026-10-02:
              20 days and 83,931 events across the 5 files.
              sys.traces.path returns the CURRENT rollover file only, so the script
              strips the _nn suffix and reads the whole set (2 days vs 20 days here).
              EventClass 92 = Data File Autogrow, 93 = Log File Autogrow.
              DatabaseName comes from the trace, not DB_NAME(DatabaseID): database ids
              are reused, so DB_NAME was NULL on 96 and plainly wrong on 37 of 176
              user-database events on the lab instance (2026-10-02).
              DatabaseID > 4 excludes master, model, msdb and tempdb. Drop that
              predicate when you are chasing tempdb growth.
              Fix: pre-size files to expected peak size and set a fixed MB growth
              increment (not percent) via ALTER DATABASE ... MODIFY FILE.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @tracepath NVARCHAR(256);

SELECT @tracepath = path
FROM   sys.traces
WHERE  is_default = 1;

IF @tracepath IS NULL
BEGIN
    SELECT 'Default trace is not running or has been disabled.' AS note;
    RETURN;
END

/* sys.traces.path names the current rollover file (log_64.trc). Stripping the
   _nn suffix reads every file still on disk, which is the whole retained window. */
IF CHARINDEX('_', REVERSE(@tracepath)) > 0
    SET @tracepath = LEFT(@tracepath, LEN(@tracepath) - CHARINDEX('_', REVERSE(@tracepath))) + N'.trc';

SELECT
    e.DatabaseName                                  AS database_name,
    e.FileName                                      AS file_name,
    CASE e.EventClass
        WHEN 92 THEN 'Data File Autogrow'
        WHEN 93 THEN 'Log File Autogrow'
    END                                             AS event_type,
    e.StartTime                                     AS grew_at,
    CAST(e.IntegerData * 8.0 / 1024 AS DECIMAL(10,2)) AS growth_mb,
    CAST(e.Duration / 1000.0 AS DECIMAL(10,1))      AS duration_ms,
    DATENAME(WEEKDAY, e.StartTime)                  AS day_of_week,
    DATEPART(HOUR,    e.StartTime)                  AS hour_of_day
FROM   sys.fn_trace_gettable(@tracepath, DEFAULT) AS e
WHERE  e.EventClass IN (92, 93)
  AND  e.DatabaseID  > 4
ORDER BY e.StartTime DESC;
