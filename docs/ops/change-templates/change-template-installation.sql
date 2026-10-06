/*
================================================================================
CHANGE TEMPLATE : SQL Server Installation
================================================================================
Use this template to document an installation change request.
Fill in all sections before submitting for change board approval.
Run the pre and post validation queries on the target server.
================================================================================

CHANGE DETAILS
--------------
Change #          :
Requested by      :
DBA               :
Target server     :
Instance name     :
SQL Server edition:
SQL Server version:
Scheduled date    :
Scheduled window  :
Rollback window   :

SCOPE
-----
[ ] New default instance
[ ] New named instance (name: _______________)
[ ] Additional features on existing install
[ ] Reinstall

FEATURES BEING INSTALLED
------------------------
[ ] Database Engine (SQLENGINE)
[ ] SQL Server Agent (SQLAGENT)
[ ] Full-Text Search (FULLTEXT)
[ ] Integration Services (IS)
[ ] Reporting Services (RS)
[ ] PolyBase (POLYBASE)
[ ] Other: _______________

ANSWER FILE
-----------
Template used     : (basic / developer / enterprise / polybase / reporting)
Answer file path  :

STORAGE LAYOUT
--------------
Install directory :
System DB data    :
System DB logs    :
User DB data      :
User DB logs      :
TempDB data       :
TempDB logs       :
TempDB file count :

SERVICE ACCOUNTS
----------------
SQL Engine account:
SQL Agent account :
Auth mode         : [ ] Windows only  [ ] Mixed mode

RISK ASSESSMENT
---------------
Risk level        : [ ] Low  [ ] Medium  [ ] High
Affected services :
Rollback plan     : Uninstall using uninstall-sql.ps1 and restore from backup

APPROVALS
---------
Requested by      :                    Date:
Approved by       :                    Date:
================================================================================
*/
-- SAFE:WritesData
-- IMPACT:Low

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- ============================================================
-- PRE-INSTALLATION CHECKS
-- Run on the TARGET SERVER before installation
-- ============================================================

-- 1. Confirm no existing instances with the same name
SELECT
    @@SERVERNAME                                AS current_server,
    SERVERPROPERTY('InstanceName')              AS instance_name,
    SERVERPROPERTY('ProductVersion')            AS version,
    SERVERPROPERTY('Edition')                   AS edition;

-- 2. Check current disk space on system drives
EXEC xp_fixeddrives;

-- 3. Check SQL Server services currently running
SELECT
    servicename,
    startup_type_desc,
    status_desc,
    service_account
FROM sys.dm_server_services;

-- ============================================================
-- POST-INSTALLATION VALIDATION
-- Run AFTER installation is complete
-- ============================================================

-- 1. Confirm instance version and edition
SELECT
    SERVERPROPERTY('ProductVersion')    AS product_version,
    SERVERPROPERTY('ProductLevel')      AS product_level,
    SERVERPROPERTY('Edition')           AS edition,
    SERVERPROPERTY('Collation')         AS collation,
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS windows_auth_only;

-- 2. Confirm sp_configure key settings
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;

SELECT
    name,
    value_in_use        AS configured_value
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'backup compression default',
    'optimize for ad hoc workloads',
    'remote admin connections'
)
ORDER BY name;

-- 3. Confirm TempDB layout
SELECT
    name                                AS file_name,
    type_desc,
    physical_name,
    size * 8 / 1024                     AS size_mb,
    growth * 8 / 1024                   AS growth_mb,
    is_percent_growth
FROM tempdb.sys.database_files
ORDER BY type, file_id;

-- 4. Confirm TCP is enabled and listening
SELECT
    local_net_address,
    local_tcp_port,
    auth_scheme
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;

-- 5. Confirm SQL Agent is enabled and running
SELECT
    servicename,
    status_desc,
    startup_type_desc
FROM sys.dm_server_services
WHERE servicename LIKE '%Agent%';

-- 6. Security posture
-- is_policy_checked and is_expiration_checked live on sys.sql_logins (NULL for Windows logins and groups).
SELECT
    sp.name,
    sp.type_desc,
    sp.is_disabled,
    sl.is_policy_checked,
    sl.is_expiration_checked
FROM sys.server_principals AS sp
LEFT JOIN sys.sql_logins AS sl ON sl.principal_id = sp.principal_id
WHERE sp.type IN ('S','U','G')
  AND sp.name NOT LIKE '##%'
ORDER BY sp.name;

-- ============================================================
-- SIGN-OFF
-- Add observations and confirmation below before closing
-- ============================================================

/*
Post-install notes:
-------------------


Validated by : _______________   Date: _______________
*/
