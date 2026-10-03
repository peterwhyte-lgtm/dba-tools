/*
Script Name : Get-DatabaseGrowthForecast
Category    : storage-capacity-management
Purpose     : Project when database files will exhaust their configured size limits,
              using historical file size changes recorded by the DatabaseGrowth temporal collector.
              Calculates MB/day growth rate from the first and last observed size within the
              window, then projects forward to the configured file limit.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-growth-risk-and-forecast/)
Requires    : SELECT on DBAMonitor.collector.DatabaseGrowthCurrent (and its history table)
Depends On  : sql\collectors\Generate-CollectorJob-DatabaseGrowth.sql
              (temporal collector must be installed and have recorded at least 2 size changes
              for a file, 1 hour or more apart, before that file gets a growth rate)
Notes       : Projects file-limit exhaustion only, not physical disk exhaustion.
              snapshot_count counts temporal row VERSIONS, not collection runs: the collector
              writes a version only when a file's size, limit or state changes, so a file that
              has not moved reads snapshot_count = 1, days_observed = 0.0 and STABLE however
              long the job has been running.
              growth_limit_mb is NULL for any file the collector saw as uncapped, which includes
              a log file on its 2 TB default (max_size 268435456), so those read UNLIMITED with
              no projected date.
              mb_per_day spans the first to the LAST recorded change, not to now, so it does not
              decay: a file that grew hard then stopped keeps its old rate. Read last_change
              (SysStartTime, UTC) with it.
              days_observed and mb_per_day both use DATEDIFF(hour, ...), which counts HOUR
              BOUNDARIES CROSSED, not elapsed time. Two versions 59 minutes apart inside one
              clock hour give 0 and read STABLE; two versions 2 minutes apart either side of
              the hour give 1, and the day rate is then that 2 minutes multiplied by 24.
              So a short-lived series can produce a confident CRITICAL beside
              days_observed = 0.0. Read snapshot_count and days_observed before the projection.
              days_observed can also exceed @WindowDays, because FOR SYSTEM_TIME BETWEEN
              returns the version already open at @WindowStart.
              The collector keeps history for databases that no longer exist, which is the
              point of history: its MERGE has no WHEN NOT MATCHED BY SOURCE branch, so a
              dropped database keeps its last row for good. This script filters those rows
              out against sys.databases, because a dropped database is not a capacity risk.
              60 of the 101 file rows on the lab instance belonged to dropped databases
              (2026-10-03), and one of them was reporting STABLE at 2176 MB. Query the
              collector table
              directly when you want the history of something that is gone.
              The filter only applies to rows whose server_name is this instance. Rows
              collected by another instance into the same DBAMonitor are kept, because
              sys.databases here cannot say whether they still exist there.
              Both comparisons are COLLATE DATABASE_DEFAULT, the same convention as
              Generate-CollectorJob-DatabaseGrowth.sql: sys.databases carries the server
              collation and the collector columns carry DBAMonitor's, so an instance where
              those differ would otherwise fail with a collation conflict rather than a row.
              The collector records master, model, msdb and tempdb; Get-DatabaseGrowthRisk
              excludes them with database_id > 4, so the two do not cover the same set.
              Every time on the result set is UTC: the window, last_change and
              projected_limit_date, which is a date so it carries no time at all.
              One-off bulk loads within @WindowDays inflate the growth rate.
              Reduce @WindowDays to 7 to focus on recent steady-state growth only.
              Requires SQL Server 2016 or later.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @WindowDays int = 30;
DECLARE @WindowStart DATETIME2 = DATEADD(DAY, -@WindowDays, SYSUTCDATETIME());
DECLARE @WindowEnd DATETIME2 = SYSUTCDATETIME();

-- Existence checks
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'DBAMonitor')
BEGIN
    RAISERROR('DBAMonitor database not found. Run sql\collectors\Generate-CollectorJob-DatabaseGrowth.sql to set up the growth collector.', 16, 1);
    RETURN;
END

IF NOT EXISTS (
    SELECT 1 FROM DBAMonitor.sys.objects o
    JOIN DBAMonitor.sys.schemas s ON s.schema_id = o.schema_id
    WHERE o.name = N'DatabaseGrowthCurrent' AND s.name = N'collector')
BEGIN
    RAISERROR('collector.DatabaseGrowthCurrent not found in DBAMonitor. Run the collector generator and allow at least one job run.', 16, 1);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM DBAMonitor.collector.DatabaseGrowthCurrent)
BEGIN
    RAISERROR('collector.DatabaseGrowthCurrent has no data yet. Allow the collection job to run at least once before forecasting.', 16, 1);
    RETURN;
END

-- Forecast
;WITH history AS (
    SELECT
        server_name,
        database_name,
        logical_name,
        file_type,
        file_size_mb,
        growth_limit_mb,
        SysStartTime AS snapshot_time
    FROM DBAMonitor.collector.DatabaseGrowthCurrent
    FOR SYSTEM_TIME BETWEEN @WindowStart AND @WindowEnd AS g
    /* The collector never deletes, so a dropped database keeps its last row forever.
       A database that no longer exists is not a capacity risk. Rows written by another
       instance are left alone: local sys.databases cannot speak for them. */
    WHERE  g.server_name COLLATE DATABASE_DEFAULT <> @@SERVERNAME COLLATE DATABASE_DEFAULT
       OR  EXISTS (SELECT 1 FROM sys.databases AS d
                   WHERE  d.name COLLATE DATABASE_DEFAULT
                        = g.database_name COLLATE DATABASE_DEFAULT)
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY server_name, database_name, logical_name
                           ORDER BY snapshot_time ASC) AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY server_name, database_name, logical_name
                           ORDER BY snapshot_time DESC) AS rn_desc,
        COUNT(*) OVER (PARTITION BY server_name, database_name, logical_name) AS snapshot_count
    FROM history
),
first_last AS (
    SELECT
        server_name,
        database_name,
        logical_name,
        file_type,
        MAX(growth_limit_mb) AS growth_limit_mb,
        MAX(snapshot_count) AS snapshot_count,
        MIN(snapshot_time) AS first_time,
        MIN(CASE WHEN rn_asc = 1 THEN file_size_mb END) AS first_size_mb,
        MAX(snapshot_time) AS last_time,
        MIN(CASE WHEN rn_desc = 1 THEN file_size_mb END) AS current_size_mb
    FROM ranked
    GROUP BY server_name, database_name, logical_name, file_type
),
projections AS (
    SELECT
        server_name,
        database_name,
        logical_name,
        file_type,
        snapshot_count,
        growth_limit_mb,
        current_size_mb,
        last_time,
        CAST(DATEDIFF(hour, first_time, last_time) / 24.0 AS decimal(6,1)) AS days_observed,
        CASE
            WHEN DATEDIFF(hour, first_time, last_time) > 0
            THEN (current_size_mb - first_size_mb) /
                 (DATEDIFF(hour, first_time, last_time) / 24.0)
            ELSE 0
        END AS mb_per_day
    FROM first_last
)
SELECT
    server_name,
    database_name,
    logical_name,
    file_type,
    snapshot_count,
    days_observed,
    last_time AS last_change,
    CAST(current_size_mb AS decimal(10,1)) AS current_size_mb,
    CAST(mb_per_day AS decimal(10,2)) AS mb_per_day,
    growth_limit_mb,
    CASE
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
        THEN CAST((growth_limit_mb - current_size_mb) / mb_per_day AS int)
        ELSE NULL
    END AS days_to_limit,
    CASE
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
        THEN CAST(DATEADD(day,
                 CAST((growth_limit_mb - current_size_mb) / mb_per_day AS int),
                 SYSUTCDATETIME()) AS date)
        ELSE NULL
    END AS projected_limit_date,
    CASE
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
             AND (growth_limit_mb - current_size_mb) / mb_per_day < 30 THEN 'CRITICAL'
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
             AND (growth_limit_mb - current_size_mb) / mb_per_day < 90 THEN 'WARNING'
        WHEN mb_per_day > 0 AND growth_limit_mb IS NULL THEN 'UNLIMITED'
        WHEN mb_per_day <= 0 THEN 'STABLE'
        ELSE 'OK'
    END AS forecast_status
FROM projections
ORDER BY
    CASE
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
             AND (growth_limit_mb - current_size_mb) / mb_per_day < 30 THEN 1
        WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
             AND (growth_limit_mb - current_size_mb) / mb_per_day < 90 THEN 2
        WHEN mb_per_day > 0 AND growth_limit_mb IS NULL THEN 3
        WHEN mb_per_day <= 0 THEN 5
        ELSE 4
    END,
    CASE WHEN mb_per_day > 0 AND growth_limit_mb IS NOT NULL
         THEN (growth_limit_mb - current_size_mb) / mb_per_day
         ELSE NULL END,
    current_size_mb DESC;
