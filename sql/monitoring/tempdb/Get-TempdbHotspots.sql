/*
Script Name : Get-TempdbHotspots
Category    : maintenance-and-reliability
Purpose     : Identify sessions consuming the most TempDB space for contention and spill triage.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-temp-db-hotspots/)
Requires    : VIEW SERVER STATE
Notes       : Space is what each session holds in TempDB now: pages allocated minus pages
              deallocated, from completed work (sys.dm_db_session_space_usage) plus the requests
              still running (sys.dm_db_task_space_usage). The session view alone only counts
              finished tasks and never subtracts, so a pooled connection that creates and drops
              temp tables all day reads as gigabytes, and a query spilling right now reads 0.
              elapsed_sec is NULL for a session with no request running.
              Tested on SQL Server 2025.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH running_tasks AS (
    SELECT
        tsu.session_id,
        SUM(tsu.user_objects_alloc_page_count - tsu.user_objects_dealloc_page_count) AS user_pages,
        SUM(tsu.internal_objects_alloc_page_count - tsu.internal_objects_dealloc_page_count) AS internal_pages
    FROM sys.dm_db_task_space_usage AS tsu
    GROUP BY tsu.session_id
),
held AS (
    SELECT
        ssu.session_id,
        ssu.user_objects_alloc_page_count - ssu.user_objects_dealloc_page_count
            + ISNULL(rt.user_pages, 0) AS user_pages,
        ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count
            + ISNULL(rt.internal_pages, 0) AS internal_pages
    FROM sys.dm_db_session_space_usage AS ssu
    LEFT JOIN running_tasks AS rt ON rt.session_id = ssu.session_id
)
SELECT
    h.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id) AS active_database,
    CAST(h.user_pages * 8.0 / 1024 AS DECIMAL(10,2)) AS user_objects_mb,
    CAST(h.internal_pages * 8.0 / 1024 AS DECIMAL(10,2)) AS internal_objects_mb,
    CAST((h.user_pages + h.internal_pages) * 8.0 / 1024 AS DECIMAL(10,2)) AS total_tempdb_mb,
    r.wait_type,
    CAST(r.total_elapsed_time / 1000.0 AS DECIMAL(10,1)) AS elapsed_sec
FROM held AS h
JOIN sys.dm_exec_sessions AS s ON s.session_id = h.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = h.session_id
WHERE s.is_user_process = 1
  AND h.user_pages + h.internal_pages > 0
ORDER BY total_tempdb_mb DESC;
