# Script Index

All scripts with one-line descriptions, organised by layer and category.
Re-generate with `.\tools\Generate-ScriptIndex.ps1` after adding scripts.

## SQL Scripts

Run directly in SSMS / Azure Data Studio, or via `.\run.ps1 <ScriptName>`.

### backups  (14 scripts)

| Script | Purpose |
|--------|---------|
| `Generate-DiffBackupScript` | Generate a DIFFERENTIAL backup script for all online user databases. |
| `Generate-FullBackupScript` | Generate a FULL backup script for all online user databases. |
| `Generate-RestoreScript` | Generate a RESTORE DATABASE script for all online user databases. |
| `Generate-TLogBackupScript` | Generate a transaction log backup script for all online user databases |
| `Get-BackupChainIntegrity` | LSN continuity analysis for each user database. Verifies the log backup chain |
| `Get-BackupCoverage` | Review backup coverage per database with a status flag for quick health assessment. |
| `Get-BackupEncryptionStatus` | Shows TDE status and backup encryption coverage per database. Identifies |
| `Get-BackupRestoreCompletionTime` | Monitor active backup and restore operations with estimated completion time. |
| `Get-BackupRestoreDurationEstimate` | Analyze backup duration and throughput metrics from msdb for performance baseline. |
| `Get-BackupSizeTrend` | Monthly backup size trend per database over the last 12 months — an indirect proxy for data growth rate. Shrinking backups can indicate unexpected data loss; growing backups inform storage planning. |
| `Get-DatabaseBackupHistory` | Review detailed backup history for all databases over the last 2 months. |
| `Get-LastDatabaseBackupTimes` | Display the latest backup timestamp per type (Full, Differential, Log) per database. |
| `Get-LastRestoreHistory` | Full restore history from msdb — when each database was last restored, from which backup, and by whom. Use to verify DR restore tests have actually been run. |
| `Get-RecoveryModelAudit` | Audits each database's recovery model against its actual backup posture and |

### collectors  (16 scripts)

| Script | Purpose |
|--------|---------|
| `Generate-CollectorAlertJob` | Generates DDL to create the DBA - Collector Alert SQL Agent job. |
| `Generate-CollectorJob-AgHealth` | Generates DDL to create the DBA - Collect AG Health SQL Agent job. |
| `Generate-CollectorJob-Blocking` | Generates DDL to create the DBA - Collect Blocking SQL Agent job. |
| `Generate-CollectorJob-DatabaseGrowth` | Generates DDL to create the DBA - Collect Database Growth SQL Agent job. |
| `Generate-CollectorJob-Deadlocks` | Generates DDL to create the DBA - Collect Deadlocks SQL Agent job. |
| `Generate-CollectorJob-ErrorLog` | Generates DDL to create the DBA - Collect Error Log SQL Agent job. |
| `Generate-CollectorJob-IndexFragmentation` | Generates DDL to create the DBA - Collect Index Fragmentation SQL Agent job. |
| `Generate-CollectorJob-Perfmon` | Generates DDL to create the DBA - Collect Perfmon SQL Agent job. |
| `Generate-CollectorJob-QueryStore` | Generates DDL to create the DBA - Collect Query Store SQL Agent job. |
| `Generate-CollectorJob-StorageIO` | Generates DDL to create the DBA - Collect Storage IO SQL Agent job. |
| `Generate-CollectorJob-Tempdb` | Generates DDL to create the DBA - Collect TempDB SQL Agent job. |
| `Generate-CollectorJob-VlfCount` | Generates DDL to create the DBA - Collect VLF Count SQL Agent job. |
| `Generate-CollectorJob-WaitStats` | Generates DDL to create the DBA - Collect Wait Stats SQL Agent job. |
| `Get-PerfmonDelta` | Computes interval deltas for cumulative performance counters |
| `Get-StorageIODelta` | Computes interval I/O deltas between the two most recent snapshots |
| `Get-WaitStatsDelta` | Computes interval wait deltas between the two most recent snapshots |

### high-availability  (12 scripts)

#### high-availability/always-on  (4 scripts)

| Script | Purpose |
|--------|---------|
| `Get-AgFailoverReadiness` | Per-AG, per-database failover readiness with quantified RPO and RTO estimates. |
| `Get-AvailabilityGroupLatency` | Display AG replica synchronization timing, queue health, and replication rates. |
| `Get-AvailabilityGroupReplicaState` | Show AG replica health, connection state, and synchronization status for failover readiness. |
| `Get-ReadableSecondaryUsage` | Shows Availability Group replica connection modes and read-only routing |

#### high-availability/fci  (1 scripts)

| Script | Purpose |
|--------|---------|
| `Get-LastNodeBlip` | Returns SQL Server error log entries that mention failover, alongside the current |

#### high-availability/logshipping  (1 scripts)

| Script | Purpose |
|--------|---------|
| `Get-LogShippingStatus` | Show every log shipping pair on this instance and how far behind each secondary is. |

#### high-availability/mirroring  (2 scripts)

| Script | Purpose |
|--------|---------|
| `Get-MirroringEndpointHealth` | Returns the state, port, role, and authentication configuration of the database |
| `Get-MirroringStatus` | Shows health, state, and point-in-time latency for all mirrored databases on this |

#### high-availability/replication  (4 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DistributionAgentStatus` | Monitors Distribution Agent activity — status, delivery latency (current and overall), |
| `Get-LogReaderAgentStatus` | Monitors Log Reader Agent activity — status, delivery latency, transaction and command |
| `Get-ReplicationStatus` | Lists all publications and subscriptions from the distribution database, including |
| `Get-UndistributedCommands` | Shows how many commands have been written to the distribution database but not yet |

### inventory  (12 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DatabaseInventory` | Inventory user databases for migration readiness — compatibility level, recovery model, state. |
| `Get-Databases` | Lists all databases with key properties and allocated file sizes. |
| `Get-DatabaseSnapshotInventory` | Lists all database snapshots with source database, age, and allocated size — snapshots silently consume filegroup space if forgotten. |
| `Get-DatabaseSummary` | One-row-per-database view of every database on the instance: state, |
| `Get-JobInventory` | Inventory SQL Agent jobs with owner for migration dependency checks. |
| `Get-LinkedServerAndJobInventory` | Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews. |
| `Get-LinkedServerInventory` | Inventory linked servers for migration and connectivity dependency mapping. |
| `Get-LoginInventory` | Inventory server logins by type and status for migration and access review. |
| `Get-OsAndHardwareInfo` | Show OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row. |
| `Get-PatchLevel` | Reports SQL Server version, Cumulative Update level, edition, and build |
| `Get-ServicesInformation` | SQL Server services — startup type, running status, and service account with |
| `Get-VersionAndEdition` | Display core instance version, edition, cluster status, and patch level. |

### maintenance  (6 scripts)

| Script | Purpose |
|--------|---------|
| `Generate-BackupJobs` | Generates SQL Agent DDL to create three scheduled maintenance jobs: |
| `Generate-IndexMaintenanceJobs` | Generates SQL Agent DDL for: |
| `Generate-IndexMaintenanceScript` | Generates ALTER INDEX REBUILD / REORGANIZE statements for fragmented indexes |
| `Generate-MaintenanceJobs` | Generates SQL Agent DDL for routine housekeeping jobs: |
| `Get-MaintenanceJobStatus` | Reports last run outcome, duration, and next scheduled run for all |
| `Set-AgentJobState` | Save, disable and restore SQL Agent job state as one operation, so a maintenance |

### migration  (14 scripts)

| Script | Purpose |
|--------|---------|
| `Fix-OrphanedUsers` | Generate ALTER USER statements to re-map orphaned database users to their |
| `Generate-AgentJobScript` | Generate sp_add_job DDL to recreate all SQL Agent jobs on the target server. |
| `Generate-LinkedServerScript` | Generate sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers. |
| `Generate-LoginScript` | Generate CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved. |
| `Generate-RestoreWithMoveScript` | Generate RESTORE DATABASE ... WITH MOVE statements from each database's latest |
| `Generate-UserMappingScript` | Generate CREATE USER and role membership DDL for all user databases. |
| `Get-CompatibilityLevelAudit` | Lists all user databases with current compatibility level, equivalent SQL version name, and the instance's native compatibility level. Use to plan compat level upgrades before or after migration. |
| `Get-DeprecatedFeaturesInUse` | Lists deprecated SQL Server features used since the last service restart, ranked by usage count. Zero rows means no deprecated features have been called. |
| `Get-EditionFeatureUsage` | Audits Enterprise-only features in active use on this instance. |
| `Get-LoginMigrationParity` | Compare logins between two servers to verify a migration. Returns one comparable |
| `Get-MigrationLoginAudit` | Audits all server-level principals that need to be migrated — SQL logins, Windows logins, and server roles — with migration risk and action per login type. |
| `Get-MigrationRiskAssessment` | Pre-migration risk scan — returns categorised HIGH/MEDIUM/INFO findings for compatibility, database settings, linked server dependencies, and sizing. |
| `Get-PostMigrationValidation` | Run on both SOURCE and TARGET and compare the CSV outputs to confirm the |
| `Get-VersionUpgradeReadiness` | Pre-upgrade readiness summary for SQL Server version upgrades. |

### monitoring  (47 scripts)

| Script | Purpose |
|--------|---------|
| `Get-ActiveConnectionsByDatabase` | Session count, active requests, open transactions, and blocked sessions grouped by database — essential check before taking any database offline or starting a decommission. |
| `Get-LinkedServerConnectivity` | Inventories all linked servers and tests each one for connectivity using sp_testlinkedserver. |

#### monitoring/databases  (4 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DatabaseHealth` | Review the health and sizing posture of user databases. |
| `Get-DatabaseIntegrityChecks` | Pre-check database readiness and configuration for integrity validation runs. |
| `Get-LastDbccCheckdb` | Show when each user database last had a successful DBCC CHECKDB run. |
| `Get-SuspectPages` | Show any pages recorded in msdb.dbo.suspect_pages — evidence of I/O or corruption errors. |

#### monitoring/disk-space  (12 scripts)

| Script | Purpose |
|--------|---------|
| `Get-AutogrowthHistory` | Reads autogrowth events from the SQL Server default trace. |
| `Get-DatabaseFilesDetail` | Show per-file details for all user databases: path, size, max size, growth settings. |
| `Get-DatabaseFreeSpaceSummary` | Allocated, used, and free space for all online databases, ordered by total free space descending. |
| `Get-DatabaseGrowthEvents` | Show recent autogrowth events from the default trace for capacity planning. |
| `Get-DatabaseGrowthForecast` | Project when database files will exhaust their configured size limits, |
| `Get-DatabaseGrowthRisk` | Flag databases approaching their configured file size limits. |
| `Get-DatabaseSizesAndFreeSpace` | Data and log file sizes with used and free space for all online user databases. |
| `Get-DiskSpace` | Show free and used space per volume that hosts SQL Server database files. |
| `Get-FilegroupSpace` | Allocated, used, and free space per filegroup across all online databases — ordered by lowest free percentage first. |
| `Get-LogReuseWaits` | Reports why each database's transaction log cannot truncate and reuse |
| `Get-TransactionLogSizeAndUsage` | Show transaction log size, used space, free space, and percent used per database. |
| `Get-VlfCount` | Reports virtual log file (VLF) count per database transaction log, |

#### monitoring/error-log  (3 scripts)

| Script | Purpose |
|--------|---------|
| `Get-ErrorLogPatterns` | Reads the current SQL Server error log and groups entries by category — surfaces memory pressure, login failures, IO issues, corruption warnings, and auto-growth events without scrolling through raw entries. |
| `Get-RecentErrorLogEntries` | Show SQL Server error log entries from the last 24 hours, filtering routine noise. |
| `Get-SchemaChangeHistory` | Recent DDL changes (CREATE, ALTER, DROP) captured by the SQL Server default trace — answers "what changed on this server recently?" after an incident or unexpected behaviour. |

#### monitoring/features  (8 scripts)

| Script | Purpose |
|--------|---------|
| `Get-CdcAndChangeTracking` | CDC (Change Data Capture) and Change Tracking enabled databases with retention, |
| `Get-CollationConflicts` | Databases whose collation differs from the server collation — a common source of implicit conversion errors and failed JOIN operations. |
| `Get-CompressionCandidates` | Largest uncompressed tables and heaps in the current database, ordered by reserved space — identifies the best candidates for row or page compression. |
| `Get-CrossDatabaseDependencies` | Objects in the current database that reference other databases via 3-part names or linked servers — critical to find before a migration, rename, or decommission. |
| `Get-DatabaseMailQueue` | Database Mail items that are failed, retrying, or unsent — plus last 24 hours of sent mail for context. Shows error detail for failed items. |
| `Get-ExtendedEventsSessions` | Active Extended Events sessions — name, state, targets, and estimated disk impact. |
| `Get-QueryStoreStatus` | Query Store enablement, fill ratio, capture mode, and health across all user databases. |
| `Get-ServiceBrokerHealth` | Service Broker health across all user databases. Orphaned/disconnected |

#### monitoring/instance  (9 scripts)

| Script | Purpose |
|--------|---------|
| `Get-InstanceConfigurationScore` | Scores the SQL Server instance across ~20 key configuration checks. Returns PASS/WARN/FAIL per item with finding and recommended action. Run this first when taking ownership of a new instance. |
| `Get-InstanceConfigurationSnapshot` | Capture all sp_configure settings for baseline review and change tracking. |
| `Get-MaxdopConfiguration` | Show MAXDOP and cost threshold settings alongside current CPU topology. |
| `Get-MemoryConfigurationAndUsage` | Show configured memory limits alongside current SQL Server memory consumption. |
| `Get-OsConfigurationChecks` | DMV-accessible OS and hardware configuration checks: Lock Pages in Memory, |
| `Get-ResourceGovernorConfig` | Resource Governor configuration, enabled state, resource pools, workload groups, |
| `Get-SilentFailureAudit` | Find the SQL Server problems that never raise an error. One row per finding across |
| `Get-SqlServerCpuTopologyAndSchedulerDetails` | CPU topology, NUMA layout, scheduler summary, and parallelism configuration in one row. |
| `Get-TraceFlags` | Active global and session trace flags, what each one does, and whether it still |

#### monitoring/jobs  (5 scripts)

| Script | Purpose |
|--------|---------|
| `Get-AgentAlertsAndOperators` | SQL Agent alerts and operators with severity gap analysis, plus the notification |
| `Get-JobDurationTrends` | SQL Agent job duration over the last 30 days — flags jobs that are running significantly longer than their average. |
| `Get-JobScheduleSummary` | Show enabled SQL Agent jobs with their schedules and next scheduled run time. |
| `Get-SqlAgentJobFailureSummary` | Show SQL Agent job failures from the last 7 days with readable timestamps and error messages. |
| `Get-SqlAgentJobOverview` | Show all SQL Agent jobs with enabled state, owner, and last run outcome. |

#### monitoring/tempdb  (4 scripts)

| Script | Purpose |
|--------|---------|
| `Get-TempDbConfiguration` | Reviews TempDB file configuration — file count, sizing parity, autogrowth |
| `Get-TempDbFileBalance` | TempDB data file configuration — checks for size imbalance, growth mismatches, percent-based growth, and file count vs CPU count. |
| `Get-TempdbHotspots` | Identify sessions consuming the most TempDB space for contention and spill triage. |
| `Get-TempdbUsage` | Show TempDB file sizes, free space, and allocation breakdown per file. |

### performance  (37 scripts)

| Script | Purpose |
|--------|---------|
| `Get-BackupRestoreProgress` | Show active backup/restore progress and estimated completion for long-running operations. |
| `Get-DatabaseIoUsage` | Database I/O totals with percentage share, MB read/written, and latency breakdown. |
| `Get-TableSizes` | Largest tables across all online user databases by total size (data + index). |
| `Get-WaitStatistics` | Top wait types since last SQL Server restart, filtered to actionable waits only. |

#### performance/active-sessions  (5 scripts)

| Script | Purpose |
|--------|---------|
| `Get-ActiveRequests` | Point-in-time snapshot of all active requests — sessions with a |
| `Get-ActiveRequestsWithPlan` | Point-in-time snapshot of all active requests with XML execution |
| `Get-ActiveSessions` | Show all active user sessions with current wait type, blocking, elapsed time, and statement. |
| `Get-LongRunningQueries` | Active requests with elapsed and wait details — ordered by elapsed time descending. |
| `Get-WorkerThreadsAndActiveSessions` | Active user sessions with CPU, elapsed time, and current worker thread pool usage. |

#### performance/blocking-locking  (8 scripts)

| Script | Purpose |
|--------|---------|
| `Get-BlockingChains` | Traces all active blocking chains using a recursive CTE. Returns |
| `Get-BlockingChainsWithPlan` | Same as Get-BlockingChains.sql with the addition of query_plan for |
| `Get-BlockingSessions` | Show sessions involved in blocking chains with wait type, timing, and current statement. |
| `Get-BlockingSummary` | Head blockers with context — who is blocking, how many sessions, and what they are running. |
| `Get-ContentionAnalysis` | Unified contention summary across lock waits, latch waits, TempDB allocation |
| `Get-DeadlockSummary` | Show recent deadlock events from the system_health XEvent ring buffer. |
| `Get-LockEscalationStats` | Shows tables with the most lock escalations since last restart. |
| `Get-OpenTransactions` | Active transactions with age, session details, and the SQL currently running or last executed — long-running open transactions cause log growth and block readers in READ_COMMITTED isolation. |

#### performance/indexes  (8 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DuplicateIndexes` | Exact duplicate and overlapping (prefix) indexes across all user databases. |
| `Get-Heaps` | Lists tables with no clustered index (heaps) across all online user databases. |
| `Get-IndexDesignIssues` | Tables with index design problems: excessive index count (write amplification), |
| `Get-IndexFragmentation` | Top fragmented indexes across all user databases, ranked by fragmentation pct. |
| `Get-IndexFragmentationAcrossDatabases` | Check index fragmentation details across all user databases for maintenance planning. |
| `Get-IndexUsageStats` | Show how indexes across all user databases are being used — seeks, scans, lookups, updates. |
| `Get-MissingIndexes` | Missing index candidates from DMVs, ranked by impact score (seeks x cost x impact). |
| `Get-UnusedIndexes` | Identifies indexes with zero read activity but non-zero write overhead |

#### performance/queries  (9 scripts)

| Script | Purpose |
|--------|---------|
| `Get-ImplicitConversions` | Scans the plan cache for implicit conversion warnings. These cause index range |
| `Get-MemoryGrantSpills` | Top queries by memory grant spills to TempDB. Spills occur when SQL grants |
| `Get-PlanCacheHealth` | Summarises plan cache composition by object type — highlights single-use |
| `Get-QueryVariance` | Queries from the plan cache where max execution time is at least 5x the minimum — the primary signal for parameter sniffing and plan instability. High execution count with high variance means the same query performs very differently depending on the parameter values in the cached plan. |
| `Get-SlowQueriesFromCache` | Top 20 queries by average elapsed time from the plan cache — identifies habitually slow queries. |
| `Get-StatisticsHealth` | Identifies stale, low-sample, and never-updated statistics in the current database. |
| `Get-StoredProcedurePerformance` | Stored procedures from the plan cache ranked by total elapsed time — shows execution count, average and max duration, CPU, and logical reads. Resets on SQL Server restart or plan eviction. |
| `Get-TopCpuQueries` | List top 20 CPU-consuming queries with execution counts and timing metrics. |
| `Get-TopIoQueries` | Top 20 queries by total logical reads since last restart — primary I/O pressure source. |

#### performance/query-store  (3 scripts)

| Script | Purpose |
|--------|---------|
| `Get-QueryStoreForcedPlans` | Forced plans in Query Store with failure counts, plan age, forcing reason, |
| `Get-QueryStoreRegressions` | Queries that regressed in the last 24 hours vs their 7-day average CPU/duration. |
| `Get-QueryStoreTopQueries` | Top queries from Query Store by CPU, duration, execution count, or plan regressions. |

### security  (18 scripts)

| Script | Purpose |
|--------|---------|
| `Get-AuditSpecifications` | SQL Server Audit objects and specifications with compliance gap analysis. |
| `Get-DatabaseMailAndXpCmdShell` | Security surface area audit — xp_cmdshell, CLR, Database Mail, force encryption, and active NTLM connections. |
| `Get-DdlTriggers` | Server-level DDL triggers. These fire on schema changes (CREATE/ALTER/DROP) |
| `Get-LinkedServerSecurity` | Lists linked servers with their security context — how local logins are |
| `Get-ProxyAndCredentials` | Lists SQL Agent proxies and server-level credentials with their identity |

#### security/access  (10 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DatabasePermissions` | Returns all explicit object- and schema-level GRANT/DENY permissions in the |
| `Get-DatabaseRoleMembers` | List database role memberships across all online user databases. |
| `Get-FailedLoginSummary` | Aggregated failed login analysis from the SQL Server error log and current |
| `Get-LoginLastActivity` | All SQL and Windows logins with current session status, connection details, and disabled/locked state. |
| `Get-LoginPermissions` | Show explicit server-level permissions granted or denied to logins. |
| `Get-OrphanedUsers` | Find database users with no matching server login — common after migrations or login drops. |
| `Get-ServerRoleMembers` | List members of every fixed and user-defined server role — the comprehensive server-privilege audit. |
| `Get-SysadminMembers` | List members of the sysadmin fixed server role — the focused privileged-access check (sysadmin only). |
| `Get-UserPermissionsAudit` | Audit one login's effective access across the whole instance in a single pass: |
| `Get-WeakLoginSettings` | Identify SQL logins with weak security settings: policy off, expiration off, or sa enabled. |

#### security/encryption  (3 scripts)

| Script | Purpose |
|--------|---------|
| `Get-CertificateExpiryWarnings` | All user-managed certificates across server and user databases with days until expiry. |
| `Get-CertificatesAndKeys` | Server-level certificates and asymmetric keys with expiry, usage detection, |
| `Get-TdeStatus` | Transparent Data Encryption (TDE) status across all databases. Includes |

### traces  (6 scripts)

| Script | Purpose |
|--------|---------|
| `Create-DecommissionAuditSession` | Creates an Extended Events session that captures all T-SQL batch, RPC, successful login, and failed login activity |
| `Create-LoginActivitySession` | Creates a lightweight Extended Events session that captures every successful and failed login to the server — who, from where, and using which application. |
| `Create-SpExecutionSession` | Creates an Extended Events session capturing stored procedure and RPC execution — procedure name, duration, login, and hostname. |
| `Get-ActiveXeSessions` | Shows all currently running Extended Events sessions with their targets and file output paths. |
| `Get-XeSessionActivity` | Reads and summarises Extended Events file target data for a named session. |
| `Remove-XeSession` | Lists all DBA-created Extended Events sessions (running and stopped) and generates the DDL to stop and drop each one. |

## PowerShell Scripts

Wrappers and orchestrators. Run via `.\run.ps1 <ScriptName>` or directly.

### diagnostics  (2 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-ActiveRequests` | Captures a point-in-time snapshot of all active SQL Server requests with optional execution plan export. |
| `Get-BlockingChains` | Traces active SQL Server blocking chains with full chain structure, wait details, and optional execution plans. |

### disk-space  (4 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-BackupAge` | Reports the age of the latest backup for each user database. |
| `Get-DiskSpaceSummary` | Shows a friendly local disk space summary for the current machine. |
| `Get-LargestFolders` | Shows the largest folders on a drive, sorted by size. |
| `Get-OldestBackupFolderFiles` | Lists the oldest file in each backup subfolder and flags folders older than a threshold. |

### installation  (6 scripts)

| Script | Synopsis |
|--------|---------|
| `configure-sql` | Apply sp_configure settings to an existing SQL Server instance. |
| `generate-install-report` | Generate a summary report from SQL Server installation and configuration logs. |
| `install-sql` | Install SQL Server from setup.exe with validated parameters and post-install configuration. |
| `post-install-validation` | Validate a SQL Server installation is configured correctly. |
| `pre-install-check` | Run pre-installation checks before deploying SQL Server. |
| `uninstall-sql` | Uninstall a SQL Server instance with optional data directory cleanup. |

### inventory  (3 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-InstanceHealthSummary` | Returns a brief server identity and key configuration settings snapshot. |
| `Get-InstanceSnapshot` | Captures a quick SQL Server instance configuration snapshot. |
| `Test-OsConfiguration` | OS-level configuration checks not visible via SQL DMVs: power plan, page file, pending reboot. |

### migration  (9 scripts)

| Script | Synopsis |
|--------|---------|
| `Export-MigrationBaseline` | Captures a performance and configuration baseline snapshot for pre/post migration comparison. |
| `Generate-AgentJobScript` | Generates sp_add_job DDL to recreate all SQL Agent jobs on the target server. |
| `Generate-LinkedServerScript` | Generates sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers on the instance. |
| `Generate-LoginScript` | Generates CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved. |
| `Generate-RestoreWithMoveScript` | Generates RESTORE DATABASE scripts with WITH MOVE for all online user databases on the instance. |
| `Generate-UserMappingScript` | Generates CREATE USER and role membership DDL for all user databases. |
| `Invoke-MigrationExport` | Generates all migration artifacts for a single source SQL Server instance — ready for execution on the target. |
| `Invoke-MigrationPreFlightCheck` | Runs a pre-migration checklist covering network connectivity, SQL Server version/edition/collation |
| `Invoke-PreMigrationAssessment` | Runs the full pre-migration assessment suite and saves each result as a named CSV in a timestamped folder. |

### patching  (5 scripts)

| Script | Synopsis |
|--------|---------|
| `install-ssms` | — |
| `Invoke-SqlPatch` | Download and apply SQL Server Cumulative Updates to local or remote servers. |
| `Patch-SqlServer` | Patch this machine's SQL Server to the latest Cumulative Update. One file, no config. |
| `patch-summary` | Show patch status for all SQL Server instances and SSMS on this machine. |
| `uninstall-ssms` | — |

### reporting  (20 scripts)

| Script | Synopsis |
|--------|---------|
| `Compare-ConfigurationBaseline` | Compare current sp_configure and key database settings against a saved baseline. |
| `Get-CapacityProjection` | Projects days-to-full for databases and drives from collector historical data. |
| `Invoke-AiAssessment` | Sends a healthcheck collection to the Claude API and writes an AI-generated assessment report. |
| `Invoke-AssessmentReport` | Runs a full instance assessment and generates a structured markdown report. |
| `Invoke-HealthCheckCollection` | Runs a full DBA health-check collection and saves each result as a named CSV in a timestamped folder. |
| `Invoke-MultiServerHealthCheck` | Runs the health check collection across multiple SQL Server instances and surfaces |
| `MultiServer-Compare-Configuration` | Cross-server sp_configure drift detection — finds settings where any server differs from the majority. |
| `MultiServer-GetBackupStatus` | — |
| `MultiServer-GetBlockingSessions` | — |
| `MultiServer-GetDatabaseSizes` | — |
| `MultiServer-GetDiskSpace` | — |
| `MultiServer-GetFirewallRules` | — |
| `MultiServer-GetMaintenanceJobStatus` | — |
| `MultiServer-GetPatchLevel` | — |
| `MultiServer-GetRecentEventLogs` | — |
| `MultiServer-GetServiceStatus` | — |
| `MultiServer-GetWaitStats` | — |
| `MultiServer-RestartService` | — |
| `MultiServer-TestSqlPort` | — |
| `Review-HealthCheckOutput` | Reads a health-check output folder and surfaces flagged findings with severity ratings. |

### wrappers/backups  (14 wrappers)

| Script | Synopsis |
|--------|---------|
| `Generate-DiffBackupScript` | Generates a DIFFERENTIAL backup T-SQL script for all online user databases. |
| `Generate-FullBackupScript` | Generates a FULL backup T-SQL script for all online user databases. |
| `Generate-RestoreScript` | Generates a RESTORE DATABASE T-SQL script for all online user databases. |
| `Generate-TLogBackupScript` | Generates a transaction log BACKUP T-SQL script for all eligible online user databases. |
| `Get-BackupChainIntegrity` | LSN continuity analysis for all user databases — detects log chain gaps that break point-in-time restore. |
| `Get-BackupCoverage` | Runs the backup coverage review query for the current SQL Server instance. |
| `Get-BackupEncryptionStatus` | Shows TDE status and backup encryption coverage per database. Identifies |
| `Get-BackupRestoreCompletionTime` | Monitors active backup and restore operations with estimated completion time. |
| `Get-BackupRestoreDurationEstimate` | Shows backup duration and throughput metrics from msdb for baseline planning. |
| `Get-BackupSizeTrend` | Running backup size trend analysis. |
| `Get-DatabaseBackupHistory` | Shows detailed backup history for all databases over the last 2 months. |
| `Get-LastDatabaseBackupTimes` | Shows the latest full, diff, and log backup timestamp and age per database. |
| `Get-LastRestoreHistory` | Checking last restore history. |
| `Get-RecoveryModelAudit` | Audits each database's recovery model against its actual backup posture and flags the |

### wrappers/high-availability  (12 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-AgFailoverReadiness` | AG per-database failover readiness with RPO/RTO estimates, listener health, and quorum state. |
| `Get-AvailabilityGroupLatency` | Shows AG replica synchronisation timing, queue sizes, and replication rates. |
| `Get-AvailabilityGroupReplicaState` | Shows AG replica health, connection state, and synchronisation status. |
| `Get-DistributionAgentStatus` | Monitors Distribution Agent activity — status, delivery latency, command counts, and errors (last 24 hours). |
| `Get-LastNodeBlip` | Returns SQL Server error log entries related to cluster failovers and the instance last-started time. |
| `Get-LogReaderAgentStatus` | Monitors Log Reader Agent activity — status, delivery latency, and errors (last 24 hours). |
| `Get-LogShippingStatus` | Log shipping status for every pair on this instance, with backup, copy and restore ages side by side. |
| `Get-MirroringEndpointHealth` | Returns the state, port, and authentication config of the database mirroring endpoint. Run on both principal and mirror during troubleshooting. |
| `Get-MirroringStatus` | Shows health, state, and latency metrics for all mirrored databases on the principal server. |
| `Get-ReadableSecondaryUsage` | Shows AG replica connection modes and read-only routing configuration. |
| `Get-ReplicationStatus` | Lists all publications and subscriptions from the distribution database. |
| `Get-UndistributedCommands` | Shows count of commands pending delivery to each subscriber — a high number signals Distribution Agent lag or failure. |

### wrappers/inventory  (12 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-DatabaseInventory` | Inventories user databases for migration readiness — compatibility, recovery model, state. |
| `Get-Databases` | Lists all databases with key properties and allocated file sizes. |
| `Get-DatabaseSnapshotInventory` | Lists all database snapshots with source database, age, and allocated size. |
| `Get-DatabaseSummary` | Runs the database summary query for the current SQL Server instance. |
| `Get-JobInventory` | Inventories SQL Agent jobs with owner for migration dependency checks. |
| `Get-LinkedServerAndJobInventory` | Inventories logins, linked servers, and SQL Agent jobs for pre-migration review. |
| `Get-LinkedServerInventory` | Inventories linked servers for migration and connectivity dependency mapping. |
| `Get-LoginInventory` | Inventories server logins by type and status for migration and access review. |
| `Get-OsAndHardwareInfo` | Returns OS version, hardware specs, and SQL Server uptime for the target instance. |
| `Get-PatchLevel` | Reports SQL Server version, Cumulative Update level, edition, and build number |
| `Get-ServicesInformation` | Shows SQL Server service state, startup type, and service accounts. |
| `Get-VersionAndEdition` | Shows SQL Server version, edition, patch level, and instance details. |

### wrappers/maintenance  (6 wrappers)

| Script | Synopsis |
|--------|---------|
| `Generate-BackupJobs` | Generates SQL Agent job DDL for scheduled database backups: full daily, log every 15 minutes, |
| `Generate-IndexMaintenanceJobs` | Generates SQL Agent job DDL for index maintenance (rebuild/reorganize) and statistics update |
| `Generate-IndexMaintenanceScript` | Generates ALTER INDEX REBUILD / REORGANIZE statements for fragmented indexes |
| `Generate-MaintenanceJobs` | Generates SQL Agent job DDL for routine housekeeping: integrity check (DBCC CHECKDB), |
| `Get-MaintenanceJobStatus` | Reports last run outcome, duration, last message, and next scheduled run for all |
| `Set-AgentJobState` | Save, disable and restore SQL Agent job state as one operation, so a maintenance window can |

### wrappers/migration  (9 wrappers)

| Script | Synopsis |
|--------|---------|
| `Fix-OrphanedUsers` | Generates ALTER USER statements to re-map orphaned database users to their |
| `Get-CompatibilityLevelAudit` | Lists all user databases with current compatibility level and compares to the instance native level. |
| `Get-DeprecatedFeaturesInUse` | Reports deprecated SQL Server features with active usage since last restart. |
| `Get-EditionFeatureUsage` | Audits Enterprise-only features in use on this SQL Server instance. Run before any edition downgrade. |
| `Get-LoginMigrationParity` | Produces one comparable fingerprint row per login, for diffing a source server against a target after a migration. |
| `Get-MigrationLoginAudit` | Audits all server-level principals that need to be migrated, with risk level and action per login type. |
| `Get-MigrationRiskAssessment` | Runs the migration risk assessment to surface databases, logins, and configuration |
| `Get-PostMigrationValidation` | Runs post-migration validation checks and produces a summary result set for comparison between source and target. |
| `Get-VersionUpgradeReadiness` | Pre-upgrade readiness summary for SQL Server version upgrades — version info, compat level matrix, |

### wrappers/monitoring  (47 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-ActiveConnectionsByDatabase` | Checking active connections by database. |
| `Get-LinkedServerConnectivity` | Inventories linked servers and tests each one for connectivity. |

#### wrappers/monitoring/databases  (4 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-DatabaseHealth` | Runs the database health review query for the current SQL Server instance. |
| `Get-DatabaseIntegrityChecks` | Pre-CHECKDB readiness: database states, recovery models, and last backup times. |
| `Get-LastDbccCheckdb` | Shows when each user database last had a successful DBCC CHECKDB. |
| `Get-SuspectPages` | Shows any pages in msdb.dbo.suspect_pages -- evidence of corruption or I/O errors. |

#### wrappers/monitoring/disk-space  (12 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-AutogrowthHistory` | Reads autogrowth events from the SQL Server default trace. |
| `Get-DatabaseFilesDetail` | Returns per-file details for all user databases: path, size, max size, and growth settings. |
| `Get-DatabaseFreeSpaceSummary` | Runs the database free space summary query against all online databases. |
| `Get-DatabaseGrowthEvents` | Shows recent autogrowth events from the default trace for capacity planning. |
| `Get-DatabaseGrowthForecast` | Project when database files will hit their configured size limits based on historical growth data. |
| `Get-DatabaseGrowthRisk` | Runs the database growth risk review query. |
| `Get-DatabaseSizesAndFreeSpace` | Runs the database sizes and free space review query. |
| `Get-DiskSpace` | Shows free and used space per volume that hosts SQL Server database files. |
| `Get-FilegroupSpace` | Reports allocated, used, and free space per filegroup across all online databases. |
| `Get-LogReuseWaits` | Reports why each database's transaction log cannot truncate and reuse space |
| `Get-TransactionLogSizeAndUsage` | Runs the transaction log size and usage review query. |
| `Get-VlfCount` | Reports virtual log file (VLF) count per database transaction log, ranked by severity. |

#### wrappers/monitoring/error-log  (3 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-ErrorLogPatterns` | Analysing SQL Server error log patterns. |
| `Get-RecentErrorLogEntries` | Shows SQL Server error log entries from the last 24 hours, with routine noise filtered out. |
| `Get-SchemaChangeHistory` | Reading schema change history from default trace. |

#### wrappers/monitoring/features  (8 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-CdcAndChangeTracking` | Reports CDC and Change Tracking enabled databases with retention and cleanup settings. |
| `Get-CollationConflicts` | Identifies databases whose collation differs from the server collation. |
| `Get-CompressionCandidates` | Identifies the largest uncompressed tables in the current database. |
| `Get-CrossDatabaseDependencies` | Scanning for cross-database dependencies. |
| `Get-DatabaseMailQueue` | Shows failed, retrying, and unsent database mail items with error detail. |
| `Get-ExtendedEventsSessions` | Lists active Extended Events sessions with target types and overhead notes. |
| `Get-QueryStoreStatus` | Checks Query Store status across all user databases on the target SQL Server instance. |
| `Get-ServiceBrokerHealth` | Service Broker health across all user databases — conversation endpoints, queue state, transmission errors. |

#### wrappers/monitoring/instance  (9 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-InstanceConfigurationScore` | Scores the SQL Server instance across key configuration checks — returns PASS/WARN/FAIL per item. |
| `Get-InstanceConfigurationSnapshot` | Runs the instance configuration snapshot review query. |
| `Get-MaxdopConfiguration` | Shows MAXDOP and cost threshold for parallelism alongside current CPU topology. |
| `Get-MemoryConfigurationAndUsage` | Runs the memory configuration and usage review query. |
| `Get-OsConfigurationChecks` | DMV-accessible OS and hardware configuration checks: LPIM, NUMA, IFI, scheduler affinity. |
| `Get-ResourceGovernorConfig` | Returns Resource Governor configuration — pools, workload groups, and classifier function. |
| `Get-SilentFailureAudit` | Finds the SQL Server problems that never raise an error, in one pass across the whole instance. |
| `Get-SqlServerCpuTopologyAndSchedulerDetails` | CPU topology, NUMA, scheduler summary, and parallelism config in one row. |
| `Get-TraceFlags` | Returns active global and session trace flags on the target SQL Server instance. |

#### wrappers/monitoring/jobs  (5 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-AgentAlertsAndOperators` | Reviews SQL Agent alerts and operators with severity gap analysis on the target instance. |
| `Get-JobDurationTrends` | Shows SQL Agent job duration trends over the last 30 days, flagging jobs running longer than their average. |
| `Get-JobScheduleSummary` | Shows enabled SQL Agent jobs with their schedules and next scheduled run time. |
| `Get-SqlAgentJobFailureSummary` | Runs the SQL Agent failure summary review query. |
| `Get-SqlAgentJobOverview` | Runs the SQL Agent job overview review query. |

#### wrappers/monitoring/tempdb  (4 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-TempDbConfiguration` | Reviews TempDB file configuration — file count, sizing parity, autogrowth |
| `Get-TempDbFileBalance` | Reviews TempDB data file configuration for size imbalance, growth mismatches, and file count vs CPU count. |
| `Get-TempdbHotspots` | Shows sessions consuming the most TempDB space right now. |
| `Get-TempdbUsage` | Runs the TempDB usage review query. |

### wrappers/performance  (33 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-BackupRestoreProgress` | Shows active backup/restore progress and estimated completion times. |
| `Get-DatabaseIoUsage` | Shows I/O read and write activity per database file since the last SQL Server restart. |
| `Get-TableSizes` | Reports largest tables across all user databases by total size (data + indexes). |
| `Get-WaitStatistics` | Runs the top wait-statistics review script for the current SQL Server instance. |

#### wrappers/performance/active-sessions  (3 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-ActiveSessions` | Shows all active user sessions with wait type, blocking chain, elapsed time, and current statement. |
| `Get-LongRunningQueries` | Runs the long-running query review script for the current SQL Server instance. |
| `Get-WorkerThreadsAndActiveSessions` | Active user sessions with CPU/elapsed time and current worker thread pool utilisation. |

#### wrappers/performance/blocking-locking  (6 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-BlockingSessions` | Returns sessions involved in blocking chains with wait type, timing, and current statement. |
| `Get-BlockingSummary` | Shows a summary of current blocking chains — head blockers and all waiting sessions. |
| `Get-ContentionAnalysis` | Unified contention summary — lock waits, latch waits, TempDB allocation pressure, and spinlocks. |
| `Get-DeadlockSummary` | Shows recent deadlock events from the system_health XEvent ring buffer. |
| `Get-LockEscalationStats` | Shows tables with the highest lock escalation counts since the last SQL Server restart. |
| `Get-OpenTransactions` | Checking open transactions. |

#### wrappers/performance/indexes  (8 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-DuplicateIndexes` | Exact duplicate and overlapping (prefix) indexes across all user databases with usage stats. |
| `Get-Heaps` | Lists all tables with no clustered index (heaps) across all online user databases. |
| `Get-IndexDesignIssues` | Tables with excessive index counts, wide key columns, or high missing-index recommendation counts. |
| `Get-IndexFragmentation` | Reports top fragmented indexes across all user databases on the instance. |
| `Get-IndexFragmentationAcrossDatabases` | Checks index fragmentation across all user databases — run off-peak on busy instances. |
| `Get-IndexUsageStats` | Shows index usage statistics across all user databases — seeks, scans, lookups, and updates. |
| `Get-MissingIndexes` | Lists missing index candidates from DMVs, ranked by impact score. |
| `Get-UnusedIndexes` | Identifies non-clustered indexes with zero reads but non-zero write overhead since the last SQL Server restart. |

#### wrappers/performance/queries  (9 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-ImplicitConversions` | Scans the plan cache for implicit conversion warnings causing index scans and CPU waste. |
| `Get-MemoryGrantSpills` | Top queries by memory grant spills to TempDB — identifies under-granted sorts and hash joins. |
| `Get-PlanCacheHealth` | Summarises plan cache composition by object type — highlights single-use |
| `Get-QueryVariance` | Analysing query variance (parameter sniffing suspects). |
| `Get-SlowQueriesFromCache` | Top 20 queries by average elapsed time from the plan cache — habitually slow queries. |
| `Get-StatisticsHealth` | Identifies stale, low-sample, and never-updated statistics in a user database. |
| `Get-StoredProcedurePerformance` | Running stored procedure performance analysis. |
| `Get-TopCpuQueries` | Lists the top 20 CPU-consuming queries since the last SQL Server restart. |
| `Get-TopIoQueries` | Lists the top 20 queries by total logical reads since the last SQL Server restart. |

#### wrappers/performance/query-store  (3 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-QueryStoreForcedPlans` | Query Store forced plans with failure counts, plan age, and whether a cheaper plan now exists. |
| `Get-QueryStoreRegressions` | Queries that regressed in the last 24h vs their 7-day baseline CPU and duration in Query Store. |
| `Get-QueryStoreTopQueries` | Top queries from Query Store by CPU, duration, execution count, or plan regressions. |

### wrappers/security  (18 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-AuditSpecifications` | SQL Server Audit objects and specifications with compliance gap analysis (FAILED_LOGIN_GROUP, privilege changes). |
| `Get-DatabaseMailAndXpCmdShell` | Shows whether Database Mail, xp_cmdshell, and CLR are enabled on the instance. |
| `Get-DdlTriggers` | Lists server-level DDL triggers — hidden dependencies that can block or audit schema changes. |
| `Get-LinkedServerSecurity` | Lists linked servers with their login mappings and risk level. |
| `Get-ProxyAndCredentials` | Lists SQL Agent proxies and server-level credentials with security context. |

#### wrappers/security/access  (10 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-DatabasePermissions` | Lists all explicit object- and schema-level permissions in the target database. |
| `Get-DatabaseRoleMembers` | Lists database role memberships across all online user databases. |
| `Get-FailedLoginSummary` | Aggregated failed login summary from security ring buffer — brute-force detection and locked accounts. |
| `Get-LoginLastActivity` | Checking login activity. |
| `Get-LoginPermissions` | Shows explicit server-level permissions granted or denied directly to logins. |
| `Get-OrphanedUsers` | Finds database users with no matching server login across all user databases. |
| `Get-ServerRoleMembers` | Lists all members of every fixed and user-defined server role. |
| `Get-SysadminMembers` | Lists all members of the sysadmin fixed server role. |
| `Get-UserPermissionsAudit` | Lists all SQL Server logins by type and disabled state for a permissions review. |
| `Get-WeakLoginSettings` | Identifies SQL logins with weak security settings — policy off, expiration off, or sa enabled. |

#### wrappers/security/encryption  (3 wrappers)

| Script | Synopsis |
|--------|---------|
| `Get-CertificateExpiryWarnings` | Checks all user-managed certificates across the server and user databases for expiry. |
| `Get-CertificatesAndKeys` | Server-level certificates and keys with expiry dates, usage (TDE/endpoint/EKM), and lifecycle risk flags. |
| `Get-TdeStatus` | Reports TDE (Transparent Data Encryption) status across all databases on the target instance. |

### wrappers/traces  (6 wrappers)

| Script | Synopsis |
|--------|---------|
| `Create-DecommissionAuditSession` | Creates an XE session capturing all activity on a database — use before decommissioning. |
| `Create-LoginActivitySession` | Creates an XE session capturing all logins to the server. |
| `Create-SpExecutionSession` | Creates an XE session capturing stored procedure execution. |
| `Get-ActiveXeSessions` | Shows all running Extended Events sessions and their file targets. |
| `Get-XeSessionActivity` | Reads and summarises collected XE file target data for a named session. |
| `Remove-XeSession` | Lists all DBA-created Extended Events sessions and generates the DDL to stop and drop each one. |
