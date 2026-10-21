/*
Script Name : Get-IndexFragmentationAcrossDatabases
Category    : performance-troubleshooting
Purpose     : Check index fragmentation across all user databases in one result set, worst first, for maintenance planning.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-index-fragmentation-across-databases/)
Requires    : VIEW DATABASE STATE and VIEW DEFINITION in each user database (server-wide: CONNECT ANY DATABASE
              + VIEW SERVER STATE + VIEW ANY DEFINITION). Databases you cannot open are skipped and listed
              in the Messages tab, not errored. Without VIEW DEFINITION a database returns no rows and no error.
*/
-- SAFE:ReadOnly
-- IMPACT:Medium
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('tempdb..#Frag') IS NOT NULL DROP TABLE #Frag;

CREATE TABLE #Frag (
    database_name SYSNAME NOT NULL,
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    index_name SYSNAME NULL,
    avg_fragmentation_percent DECIMAL(5,2) NOT NULL,
    page_count BIGINT NOT NULL
);

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE frag_cur CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
    ORDER BY name;

OPEN frag_cur; FETCH NEXT FROM frag_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF HAS_DBACCESS(@db) = 1
    BEGIN
        SET @sql = N'USE ' + QUOTENAME(@db) + N';
        INSERT INTO #Frag
        SELECT
            DB_NAME(),
            s.name,
            o.name,
            i.name,
            ROUND(ips.avg_fragmentation_in_percent, 2),
            ips.page_count
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
        INNER JOIN sys.indexes AS i
            ON ips.object_id = i.object_id
           AND ips.index_id = i.index_id
        INNER JOIN sys.objects AS o
            ON i.object_id = o.object_id
        INNER JOIN sys.schemas AS s
            ON o.schema_id = s.schema_id
        WHERE o.is_ms_shipped = 0
          AND ips.page_count > 0
          AND ips.alloc_unit_type_desc <> ''INTERNAL''
          AND ips.avg_fragmentation_in_percent >= 5.0;';
        BEGIN TRY EXEC sys.sp_executesql @sql; END TRY
        BEGIN CATCH PRINT 'Skipped ' + @db + ': ' + ERROR_MESSAGE(); END CATCH;
    END
    ELSE
        PRINT 'Skipped ' + @db + ': no access.';
    FETCH NEXT FROM frag_cur INTO @db;
END;
CLOSE frag_cur; DEALLOCATE frag_cur;

SELECT
    database_name,
    schema_name,
    table_name,
    index_name,
    avg_fragmentation_percent,
    page_count
FROM #Frag
ORDER BY avg_fragmentation_percent DESC, page_count DESC;

DROP TABLE #Frag;
