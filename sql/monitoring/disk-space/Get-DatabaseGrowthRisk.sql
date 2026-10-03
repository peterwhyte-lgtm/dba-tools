/*
Script Name : Get-DatabaseGrowthRisk
Category    : storage-capacity-management
Purpose     : Flag databases approaching their configured file size limits.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-growth-risk-and-forecast/)
Requires    : VIEW ANY DATABASE
HealthCheck : Yes
Notes       : max_size of -1 and of 268435456 both mean "no configured ceiling": MS Docs
              documents 268435456 as the 2 TB default cap SQL Server gives a log file, so a
              default install would otherwise report a fake 2097152 MB limit and a false OK.
              Same convention as Generate-CollectorJob-DatabaseGrowth.sql. A file deliberately
              capped at exactly 2 TB is indistinguishable from the default and reads as unlimited.
              growth_limit_mb sums only the files that have a real ceiling, so read
              unlimited_files first: any value above 0 means the limit is partial.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH db_sizes AS (
    SELECT
        d.name AS database_name,
        CAST(SUM(CASE WHEN mf.type_desc = 'ROWS'
            THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS data_mb,
        CAST(SUM(CASE WHEN mf.type_desc = 'LOG'
            THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS log_mb,
        CAST(SUM(CASE WHEN mf.max_size IN (-1, 268435456) THEN 0
            ELSE mf.max_size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS growth_limit_mb,
        SUM(CASE WHEN mf.max_size IN (-1, 268435456) THEN 1 ELSE 0 END) AS unlimited_files
    FROM sys.databases AS d
    LEFT JOIN sys.master_files AS mf ON d.database_id = mf.database_id
    WHERE d.database_id > 4
    GROUP BY d.name
)
SELECT
    database_name,
    data_mb,
    log_mb,
    CAST(data_mb + log_mb AS DECIMAL(18,2)) AS total_mb,
    growth_limit_mb,
    unlimited_files,
    CASE
        WHEN growth_limit_mb = 0 THEN 'UNLIMITED'
        WHEN data_mb + log_mb >= growth_limit_mb THEN 'AT_LIMIT'
        WHEN data_mb + log_mb >= growth_limit_mb * 0.85 THEN 'NEAR_LIMIT'
        ELSE 'OK'
    END AS growth_status
FROM db_sizes
ORDER BY total_mb DESC;
