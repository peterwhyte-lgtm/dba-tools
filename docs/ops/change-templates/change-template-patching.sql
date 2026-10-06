/*
================================================================================
CHANGE TEMPLATE : SQL Server Patching (CU / SP / SSMS)
================================================================================
Use this template to document a patching change request.
Fill in all sections before submitting for change board approval.
================================================================================

CHANGE DETAILS
--------------
Change #          :
Requested by      :
DBA               :
Target server(s)  :
Instance(s)       :
Scheduled date    :
Maintenance window:
Rollback window   :

PATCH DETAILS
-------------
Patch type        : [ ] Cumulative Update (CU)  [ ] Service Pack (SP)  [ ] SSMS  [ ] OS
KB article        :
From version      :
To version        :
Patch file        :
Patch file hash   :
Download source   :

SCOPE
-----
[ ] All instances on server (/allinstances)
[ ] Specific instance: _______________
[ ] SSMS only

RISK ASSESSMENT
---------------
Risk level        : [ ] Low  [ ] Medium  [ ] High
Expected downtime : ___ minutes
Affected services :
Rollback plan     : SQL Server patch rollback requires uninstall, capture pre-patch version to confirm rollback path with Microsoft

PRE-PATCH CHECKLIST
-------------------
[ ] Verified no active SQL Agent jobs will be running during window
[ ] Full backup of all databases taken and verified
[ ] Patch file checksum verified
[ ] Change approved by change board
[ ] Maintenance notification sent to application teams
[ ] SQL Server error log reviewed, no active errors

APPROVALS
---------
Requested by      :                    Date:
Approved by       :                    Date:
================================================================================
*/
-- SAFE:ReadOnly
-- IMPACT:Low

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- ============================================================
-- PRE-PATCH CAPTURE
-- Run BEFORE applying the patch, save output for comparison
-- ============================================================

-- 1. Current version and patch level
SELECT
    @@SERVERNAME                            AS server_name,
    SERVERPROPERTY('InstanceName')          AS instance_name,
    SERVERPROPERTY('ProductVersion')        AS product_version,
    SERVERPROPERTY('ProductLevel')          AS product_level,
    SERVERPROPERTY('ProductUpdateLevel')    AS update_level,
    SERVERPROPERTY('Edition')               AS edition,
    GETDATE()                               AS captured_at;

-- 2. Active sessions, confirm it is safe to patch
SELECT
    COUNT(*)                        AS active_sessions,
    SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS running_requests
FROM sys.dm_exec_sessions
WHERE is_user_process = 1;

-- 3. Any long-running queries (> 5 minutes), should be none
SELECT
    session_id,
    status,
    command,
    DATEDIFF(MINUTE, start_time, GETDATE())     AS elapsed_minutes,
    wait_type,
    DB_NAME(database_id)                        AS database_name
FROM sys.dm_exec_requests
WHERE session_id IN (SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1)
  AND DATEDIFF(MINUTE, start_time, GETDATE()) > 5
ORDER BY elapsed_minutes DESC;

-- 4. SQL Agent jobs, confirm none running
SELECT
    j.name                          AS job_name,
    ja.start_execution_date,
    DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS elapsed_minutes
FROM msdb.dbo.sysjobactivity ja
JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
WHERE ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
  AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.sysjobactivity);

-- 5. Last backup times, confirm recent backups exist
SELECT
    d.name                                                  AS database_name,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS last_full,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS last_log
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'
GROUP BY d.name
ORDER BY d.name;

-- ============================================================
-- POST-PATCH VALIDATION
-- Run AFTER the patch is applied and services have restarted
-- ============================================================

-- 1. Confirm new version
SELECT
    @@SERVERNAME                            AS server_name,
    SERVERPROPERTY('ProductVersion')        AS product_version,
    SERVERPROPERTY('ProductLevel')          AS product_level,
    SERVERPROPERTY('ProductUpdateLevel')    AS update_level,
    GETDATE()                               AS validated_at;

-- 2. Confirm all services are running
SELECT
    servicename,
    status_desc,
    startup_type_desc,
    service_account
FROM sys.dm_server_services;

-- 3. Confirm all databases are online
SELECT
    name,
    state_desc,
    recovery_model_desc
FROM sys.databases
WHERE state_desc <> 'ONLINE'
ORDER BY name;

-- 4. Check error log for issues since restart
EXEC xp_readerrorlog 0, 1, N'Error', NULL, NULL, NULL, N'desc';

-- 5. Spot-check key sp_configure settings survived the patch
SELECT
    name,
    value_in_use
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'backup compression default'
)
ORDER BY name;

-- ============================================================
-- SIGN-OFF
-- ============================================================

/*
Pre-patch version  :
Post-patch version :
Patch outcome      : [ ] Success  [ ] Partial  [ ] Failed  [ ] Rolled back

Notes:


Validated by : _______________   Date: _______________
*/
