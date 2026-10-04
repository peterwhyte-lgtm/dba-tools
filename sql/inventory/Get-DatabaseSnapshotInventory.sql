/*
Script Name : Get-DatabaseSnapshotInventory
Category    : monitoring
Purpose     : Lists all database snapshots with source database, age, and the real size of each sparse file on disk, so forgotten snapshots are visible before they fill a volume.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-snapshot-inventory/)
Requires    : VIEW ANY DEFINITION, VIEW SERVER PERFORMANCE STATE (VIEW SERVER STATE before SQL Server 2022)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
--
-- DESIGN: allocated_mb comes from sys.master_files and is the snapshot's maximum size, fixed at the
-- size of the source data files when the snapshot was created. It never grows. size_on_disk_mb is
-- the sparse file's real footprint from sys.dm_io_virtual_file_stats, and it grows as pages change
-- in the source. Without VIEW ANY DEFINITION, sys.master_files returns no rows for snapshots you do
-- not own and the script returns 0 rows without an error.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    s.name AS snapshot_name,
    src.name AS source_database,
    s.create_date,
    DATEDIFF(DAY, s.create_date, GETDATE()) AS age_days,
    s.state_desc,
    src.recovery_model_desc,
    CAST(SUM(CAST(f.size AS BIGINT) * 8.0 / 1024) AS DECIMAL(20,2)) AS allocated_mb,
    CAST(SUM(vfs.size_on_disk_bytes) / 1048576.0 AS DECIMAL(20,2)) AS size_on_disk_mb
FROM sys.databases s
JOIN sys.databases src ON src.database_id = s.source_database_id
JOIN sys.master_files f ON f.database_id = s.database_id
CROSS APPLY sys.dm_io_virtual_file_stats(s.database_id, f.file_id) vfs
GROUP BY s.name, src.name, s.create_date, s.state_desc, src.recovery_model_desc
ORDER BY s.create_date ASC;
