/*
Script Name : Get-WaitStatistics
Category    : performance-troubleshooting
Purpose     : Top wait types since last SQL Server restart, filtered to actionable waits only.
Author      : Peter Whyte (https://sqldba.blog/sql-server-wait-statistics/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH filtered_waits AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
      AND wait_type NOT IN (
          -- Idle / background scheduler waits, not indicative of workload pressure
          'SLEEP_TASK',                     'SLEEP_SYSTEMTASK',
          'SLEEP_TEMPDBSTARTUP',            'SLEEP_DBSTARTUP',
          'SLEEP_DCOMSTARTUP',              'SLEEP_MASTERDBREADY',
          'SLEEP_MASTERMDREADY',            'SLEEP_MASTERUPGRADED',
          'SLEEP_MSDBSTARTUP',              'SLEEP_PHYSMASTERDBREADY',
          'SLEEP_SAFEMODE',                 'SLEEP_SETUP',
          'SLEEP_RBPEXSHRINKTASK',          'SLEEP_RETRY_VIRTUALALLOC',
          'SLEEP_BPOOL_FLUSH',              'SLEEP_BPOOL_STEAL',
          'SLEEP_BUFFERPOOL_HELPLW',        'SLEEP_MEMORYPOOL_ALLOCATEPAGES',
          'SLEEP_WORKSPACE_ALLOCATEPAGE',
          'DISPATCHER_QUEUE_SEMAPHORE',     'CHECKPOINT_QUEUE',
          'DBMIRROR_EVENTS_QUEUE',          'DBMIRROR_WORKER_QUEUE',
          'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_WAIT_ENTRIES',
          'WAITFOR',                        'LAZYWRITER_SLEEP',
          'LOGMGR_QUEUE',                   'ONDEMAND_TASK_QUEUE',
          'REQUEST_FOR_DEADLOCK_SEARCH',    'RESOURCE_QUEUE',
          'SERVER_IDLE_CHECK',              'SP_SERVER_DIAGNOSTICS_SLEEP',
          'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',  'XE_TIMER_EVENT',
          'HADR_WORK_QUEUE',                'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
          'HADR_CLUSAPI_CALL',              'HADR_NOTIFICATION_DEQUEUE',
          'FT_IFTS_SCHEDULER_IDLE_WAIT',    'FT_IFTSHC_MUTEX',
          'CLR_AUTO_EVENT',                 'CLR_MANUAL_EVENT',
          'WAIT_XTP_COMPILE_WAIT',
          -- Service Broker threads parked waiting for a message. MS Docs on
          -- BROKER_TRANSMITTER: high waiting_tasks_count "aren't indications of any
          -- performance problem". The transmission queue/table waits are NOT listed
          -- here: those move real messages and can stall for real.
          'BROKER_TO_FLUSH',                'BROKER_TASK_STOP',
          'BROKER_EVENTHANDLER',            'BROKER_RECEIVE_WAITFOR',
          'BROKER_TRANSMITTER',             'BROKER_INIT',
          'BROKER_START',                   'BROKER_SHUTDOWN',
          'BROKER_MASTERSTART',             'BROKER_DISPATCHER',
          'BROKER_SERVICE',                 'BROKER_FORWARDER',
          'BROKER_REGISTERALLENDPOINTS',    'BROKER_TASK_SUBMIT',
          'BROKER_TASK_SHUTDOWN',           'BROKER_PRIORITIZED_TASK_STOP',
          -- Extended Events plumbing: dispatcher, session and buffer bookkeeping.
          -- These rank by call count, not by stall. Measured on an idle instance:
          -- PREEMPTIVE_XE_CALLBACKEXECUTE 132,833,917 waits for 3,828,650 ms, an
          -- average of 0.00003 ms each. XE_FILE_TARGET_TVF is deliberately NOT here,
          -- because reading an event file target is a query and can stall on I/O.
          'XE_DISPATCHER_WAIT',             'XE_DISPATCHER_JOIN',
          'XE_LIVE_TARGET_TVF',             'XE_CALLBACK_LIST',
          'XE_MODULEMGR_SYNC',              'XE_SESSION_CREATE_SYNC',
          'XE_SESSION_FLUSH',               'XE_SESSION_SYNC',
          'XE_BUFFERMGR_ALLPROCESSED_EVENT','XE_BUFFERMGR_FREEBUF_EVENT',
          'XE_SQL_TEXT_HEAP_ALLOC',         'XE_SQL_TEXT_HEAP_FREE',
          'PREEMPTIVE_XE_DISPATCHER',       'PREEMPTIVE_XE_GETTARGETSTATE',
          'PREEMPTIVE_XE_CALLBACKEXECUTE',  'PREEMPTIVE_XE_ENGINEINIT',
          'PREEMPTIVE_XE_SESSIONCOMMIT',    'PREEMPTIVE_XE_TARGETINIT',
          'PREEMPTIVE_XE_TARGETFINALIZE',   'PREEMPTIVE_XE_TIMERRUN',
          -- Idle / background waits introduced SQL Server 2016 to 2022
          'SOS_WORK_DISPATCHER',            'DIRTY_PAGE_POLL',
          'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE',
          'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
          'QDS_SHUTDOWN_QUEUE',             'QDS_TASK_START',
          'QDS_ASYNC_PERSIST_TASK_START',   'PWAIT_EXTENSIBILITY_CLEANUP_TASK',
          'PARALLEL_REDO_WORKER_WAIT_WORK', 'HADR_TIMER_TASK',
          'PVS_PREALLOCATE',                'WAIT_XTP_HOST_WAIT',
          -- Older builds only. Absent from sys.dm_os_wait_stats on 2025 (17.0.4075.5),
          -- so they exclude nothing there; kept because they are still returned on the
          -- builds that have them. Excluding a name that does not exist costs nothing.
          'REPL_WORK_QUEUE',                'SNI_HTTP_ACCEPT',
          'SQLTRACE_BUFFER_FLUSH'
      )
)
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5,2)) AS pct_total_wait,
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(10,0))              AS avg_wait_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    resource_wait_time_ms
FROM filtered_waits
ORDER BY wait_time_ms DESC;
