/*
Script Name : Get-OsAndHardwareInfo
Category    : configuration-and-environment
Purpose     : Show OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-os-and-hardware-info/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
Notes       : socket_count and cores_per_socket come straight from sys.dm_os_sys_info (SQL Server
              2016 SP2 and later). cpu_count / hyperthread_ratio is the socket count, not the
              physical cores, since hyperthread_ratio is logical CPUs per socket.
              Uptime is counted in whole minutes. DATEDIFF(DAY) counts midnights, so an instance
              started at 23:00 read as 1 day up an hour later.
              Tested on SQL Server 2025.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    SERVERPROPERTY('MachineName') AS machine_name,
    SERVERPROPERTY('ServerName') AS server_name,
    SERVERPROPERTY('Edition') AS sql_edition,
    SERVERPROPERTY('ProductVersion') AS sql_version,
    SERVERPROPERTY('ProductLevel') AS sql_product_level,
    SERVERPROPERTY('ProductUpdateLevel') AS sql_cu_level,
    SERVERPROPERTY('IsClustered') AS is_clustered,
    wni.windows_release AS os_release,
    wni.windows_service_pack_level AS os_service_pack,
    wni.windows_sku AS os_sku,
    osi.cpu_count AS logical_cpu_count,
    osi.socket_count,
    osi.cores_per_socket,
    CAST(osi.physical_memory_kb / 1024.0 / 1024 AS DECIMAL(10,2)) AS physical_memory_gb,
    CAST(osi.committed_kb / 1024.0 AS DECIMAL(12,2)) AS sql_committed_mb,
    osi.sqlserver_start_time AS sql_start_time,
    DATEDIFF(MINUTE, osi.sqlserver_start_time, GETDATE()) / 1440 AS uptime_days,
    DATEDIFF(MINUTE, osi.sqlserver_start_time, GETDATE()) / 60 % 24 AS uptime_hours_remainder
FROM sys.dm_os_sys_info AS osi
CROSS JOIN sys.dm_os_windows_info AS wni;
