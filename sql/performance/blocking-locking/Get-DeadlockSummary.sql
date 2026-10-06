/*
Script Name : Get-DeadlockSummary
Category    : performance-troubleshooting
Purpose     : Show recent deadlock events from the system_health XEvent ring buffer.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-deadlock-summary/)
Requires    : VIEW SERVER PERFORMANCE STATE (SQL Server 2022+) or VIEW SERVER STATE
Notes       : Reads the ring_buffer target only (4 MB / 5,000 events by default), and the
              DMV can return a truncated slice of it, so recent deadlocks may be missing.
              Event times are UTC. For history, read the system_health .xel files with
              sys.fn_xe_file_target_read_file.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH ring_buffer AS (
    SELECT
        CAST(target_data AS XML) AS ring_xml
    FROM sys.dm_xe_session_targets AS t
    INNER JOIN sys.dm_xe_sessions AS s ON t.event_session_address = s.address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
),
deadlock_nodes AS (
    SELECT
        e.x.value('@timestamp', 'datetime2') AS event_timestamp,
        e.x.query('data[@name="xml_report"]/value') AS deadlock_graph
    FROM ring_buffer
    CROSS APPLY ring_xml.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS e(x)
)
SELECT TOP 50
    event_timestamp,
    deadlock_graph
FROM deadlock_nodes
ORDER BY event_timestamp DESC;
