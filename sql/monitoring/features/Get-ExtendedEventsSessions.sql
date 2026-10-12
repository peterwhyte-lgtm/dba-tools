/*
Script Name : Get-ExtendedEventsSessions
Category    : monitoring
Purpose     : Active Extended Events sessions — name, state, targets, and estimated disk impact.
              Surfaces unexpected or high-overhead XE sessions on inherited servers.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-active-xe-sessions/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    s.name AS session_name,
    s.create_time,
    CASE s.pending_buffers WHEN 0 THEN 'ACTIVE' ELSE 'ACTIVE (pending writes)' END AS state,
    s.total_regular_buffers AS buffer_count,
    s.regular_buffer_size AS buffer_size_bytes,
    s.total_large_buffers AS large_buffer_count,
    s.large_buffer_size AS large_buffer_size_bytes,
    s.dropped_event_count AS dropped_events,
    s.dropped_buffer_count AS dropped_buffers,
    s.blocked_event_fire_time AS blocked_fire_time_ms,
    STUFF((
        SELECT ', ' + t.target_name
        FROM sys.dm_xe_session_targets t
        WHERE t.event_session_address = s.address
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(500)'), 1, 2, '') AS targets,
    /* Reads the counters above. The old version keyed on target type and looked for
       asynchronous_file_target, the SQL Server 2008 name: since 2012 the file target is
       event_file, so file sessions always read OK. Blocked firing only happens when the
       session is set to EVENT_RETENTION_MODE = NO_EVENT_LOSS. */
    CASE
        WHEN s.blocked_event_fire_time > 0
            THEN 'Blocking the workload - events waited for buffer space (NO_EVENT_LOSS); allow event loss or capture less'
        WHEN s.dropped_event_count > 0 OR s.dropped_buffer_count > 0
            THEN 'Losing events - buffers cannot keep up; raise MAX_MEMORY or filter the events'
        ELSE 'OK'
    END AS overhead_note,
    CASE s.name
        WHEN 'system_health' THEN 'Built-in - monitors deadlocks, connectivity errors, scheduler health'
        WHEN 'AlwaysOn_health' THEN 'Built-in - AG health events (present on AG instances)'
        WHEN 'telemetry_xevents' THEN 'Built-in - SQL Server telemetry collection'
        WHEN 'hkenginexesession' THEN 'Built-in - In-Memory OLTP (Hekaton) session'
        WHEN 'sp_server_diagnostics session'
                                      THEN 'Built-in - WSFC diagnostics for AG/FCI'
        ELSE 'Custom or third-party session - verify purpose and owner'
    END AS session_note
FROM sys.dm_xe_sessions AS s
ORDER BY
    CASE WHEN s.name IN ('system_health','AlwaysOn_health','telemetry_xevents',
                          'hkenginexesession','sp_server_diagnostics session')
         THEN 1 ELSE 0 END,
    s.name;
