/*
Script Name : Get-AgFailoverReadiness
Category    : high-availability
Purpose     : Per-AG, per-database failover readiness with quantified RPO and RTO estimates.
              Answers "would a failover succeed RIGHT NOW and what would it cost?"
              RTO = estimated seconds to drain redo queue at current redo rate.
              RPO = log send queue size (data that would be lost if primary fails now).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/)
Requires    : VIEW SERVER STATE, VIEW ANY DATABASE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT 'This instance is not a member of an Availability Group (or AG feature is disabled).' AS info;
END
ELSE
BEGIN
    WITH ag_readiness AS (
    SELECT
        ag.name AS ag_name,
        ar.replica_server_name,
        agl.dns_name AS listener_name,
        agl.port AS listener_port,
        DB_NAME(drs.database_id) AS database_name,
        drs.is_local,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc AS replica_health,
        drs.synchronization_state_desc AS db_sync_state,
        drs.database_state_desc,
        -- RPO exposure: data that could be lost if primary fails right now
        drs.log_send_queue_size AS log_send_queue_kb,
        CAST(drs.log_send_queue_size / 1024.0 AS DECIMAL(10,2)) AS log_send_queue_mb,
        -- RTO estimate: seconds to drain the redo queue at current redo rate
        drs.redo_queue_size AS redo_queue_kb,
        CAST(drs.redo_queue_size / 1024.0 AS DECIMAL(10,2)) AS redo_queue_mb,
        drs.redo_rate AS redo_rate_kb_per_sec,
        CASE
            WHEN drs.redo_rate > 0 AND drs.redo_queue_size > 0
            THEN CAST(drs.redo_queue_size / drs.redo_rate AS INT)
            ELSE NULL
        END AS estimated_rto_seconds,
        drs.secondary_lag_seconds,
        drs.last_hardened_time,
        drs.last_received_time,
        -- Readiness: a synchronous-commit SYNCHRONIZED secondary can fail over without data loss
        -- (the cluster's own flag is is_failover_ready in sys.dm_hadr_database_replica_cluster_states;
        -- this derives readiness from sync state, availability mode and failover mode)
        -- COLLATE DATABASE_DEFAULT on catalog columns avoids collation conflicts with literals
        CASE
            WHEN ars.role_desc COLLATE DATABASE_DEFAULT = 'PRIMARY'
            THEN 'PRIMARY - this is the source'
            WHEN drs.database_state_desc COLLATE DATABASE_DEFAULT <> 'ONLINE'
            THEN 'CRITICAL - database is ' + (drs.database_state_desc COLLATE DATABASE_DEFAULT) + ' on this replica'
            -- Async first: an async replica is always SYNCHRONIZING, so it must not fall into an OK branch
            WHEN ar.availability_mode_desc COLLATE DATABASE_DEFAULT = 'ASYNCHRONOUS_COMMIT'
            THEN 'INFO - async replica; forced failover only (possible data loss: ' +
                 CAST(CAST(drs.log_send_queue_size / 1024.0 AS INT) AS VARCHAR) + ' MB of log not yet sent)'
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZED'
                 AND ar.failover_mode_desc COLLATE DATABASE_DEFAULT = 'AUTOMATIC'
            THEN 'OK - SYNCHRONIZED; automatic or manual failover without data loss'
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZED'
            THEN 'OK - SYNCHRONIZED; manual failover without data loss (failover mode is MANUAL)'
            -- A synchronous replica that is not SYNCHRONIZED is not failover ready
            ELSE 'WARN - ' + (drs.synchronization_state_desc COLLATE DATABASE_DEFAULT) +
                 '; not failover ready, forced failover only (possible data loss) until SYNCHRONIZED'
        END AS readiness_status,
        -- Numeric sort key avoids collation conflict in ORDER BY string comparison
        CASE
            WHEN ars.role_desc COLLATE DATABASE_DEFAULT = 'PRIMARY' THEN 5
            WHEN drs.database_state_desc COLLATE DATABASE_DEFAULT <> 'ONLINE' THEN 1
            WHEN drs.redo_queue_size > 1048576 THEN 2
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZED' THEN 4
            ELSE 3
        END AS sort_priority,
        ar.availability_mode_desc COLLATE DATABASE_DEFAULT AS commit_mode,
        ar.failover_mode_desc COLLATE DATABASE_DEFAULT AS failover_mode
    FROM sys.availability_groups AS ag
    JOIN sys.availability_replicas AS ar ON ar.group_id = ag.group_id
    JOIN sys.dm_hadr_availability_replica_states AS ars ON ars.replica_id = ar.replica_id
    JOIN sys.dm_hadr_database_replica_states AS drs ON drs.replica_id = ar.replica_id
    LEFT JOIN sys.availability_group_listeners AS agl ON agl.group_id = ag.group_id
    )
    SELECT * FROM ag_readiness
    ORDER BY sort_priority, ag_name, database_name, replica_server_name;
END;
