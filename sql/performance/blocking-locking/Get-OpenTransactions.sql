/*
Script Name : Get-OpenTransactions
Category    : performance
Purpose     : Active transactions with age, session details, and the SQL currently running or last executed — long-running open transactions cause log growth and block readers in READ_COMMITTED isolation.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-open-transactions/)
Requires    : VIEW SERVER STATE
Notes       : sql_text is the running statement, or for a sleeping session the last batch it sent.
              Tested on SQL Server 2025.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status AS session_status,
    s.open_transaction_count,
    t.transaction_begin_time,
    DATEDIFF(SECOND, t.transaction_begin_time, GETDATE()) AS tran_age_sec,
    CASE t.transaction_type
        WHEN 1 THEN 'Read/Write'
        WHEN 2 THEN 'Read-Only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
        ELSE CAST(t.transaction_type AS VARCHAR(10))
    END AS transaction_type,
    CASE t.transaction_state
        WHEN 0 THEN 'Not initialised'
        WHEN 1 THEN 'Not started'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended'
        WHEN 4 THEN 'Commit initiated'
        WHEN 5 THEN 'Prepared'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling back'
        WHEN 8 THEN 'Rolled back'
        ELSE CAST(t.transaction_state AS VARCHAR(10))
    END AS transaction_state,
    DB_NAME(dt.database_id) AS database_name,
    CAST(dt.database_transaction_log_bytes_used / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS log_used_mb,
    r.blocking_session_id,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS request_age_sec,
    LEFT(CAST(current_sql.text AS NVARCHAR(MAX)), 300) AS sql_text
FROM sys.dm_exec_sessions s
JOIN sys.dm_tran_session_transactions st ON st.session_id = s.session_id
JOIN sys.dm_tran_active_transactions t ON t.transaction_id = st.transaction_id
LEFT JOIN sys.dm_tran_database_transactions dt ON dt.transaction_id = t.transaction_id
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
/* The parent connection only: a MARS session has one extra connection row per logical session. */
OUTER APPLY (
    SELECT TOP (1) c.most_recent_sql_handle
    FROM sys.dm_exec_connections AS c
    WHERE c.session_id = s.session_id
      AND c.parent_connection_id IS NULL
) AS conn
OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle, conn.most_recent_sql_handle)) AS current_sql
WHERE s.is_user_process = 1
ORDER BY tran_age_sec DESC;
