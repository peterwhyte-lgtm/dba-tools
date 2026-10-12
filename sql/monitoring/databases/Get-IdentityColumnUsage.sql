/*
Script Name : Get-IdentityColumnUsage
Category    : monitoring
Purpose     : Show how close every identity column on the instance is to the maximum value its
              data type can hold, so an int key is found at 85% rather than when inserts start
              failing with Msg 8115 (arithmetic overflow converting IDENTITY to data type int).
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW ANY DATABASE, plus access to each online database it inspects (it opens every database)
Notes       : percent_used is the share of the range between the column's seed and the limit of its
              data type (the maximum for a positive increment, the minimum for a negative one) that
              last_value has already consumed. values_remaining is how many more inserts fit at the
              current increment (NULL for decimal/numeric identities wider than 30 digits).
              last_value is NULL until the first row is ever inserted.
              A reseed (DBCC CHECKIDENT ... RESEED) moves last_value but not seed_value. When a reseed
              has put last_value behind the seed, such as an exhausted int reseeded into its negative
              range, percent_used is measured from the far end of the data type instead.
              Sequences (sys.sequences) are not identity columns and are not covered here.
              Set @MinPercentUsed to filter out columns below a threshold (0 returns every column).
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @MinPercentUsed DECIMAL(5,2) = 0;

IF OBJECT_ID('tempdb..#identity') IS NOT NULL DROP TABLE #identity;

CREATE TABLE #identity (
    database_name NVARCHAR(128),
    schema_name NVARCHAR(128),
    table_name NVARCHAR(128),
    column_name NVARCHAR(128),
    data_type NVARCHAR(40),
    seed_value DECIMAL(38,0),
    increment_value DECIMAL(38,0),
    last_value DECIMAL(38,0) NULL,
    type_max DECIMAL(38,0),
    type_min DECIMAL(38,0),
    row_count BIGINT
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #identity
SELECT
    DB_NAME(),
    s.name,
    t.name,
    ic.name,
    CASE WHEN ty.name IN (''decimal'', ''numeric'')
         THEN ty.name + ''('' + CAST(ic.precision AS VARCHAR(2)) + '',0)''
         ELSE ty.name END,
    CAST(ic.seed_value AS DECIMAL(38,0)),
    CAST(ic.increment_value AS DECIMAL(38,0)),
    CAST(ic.last_value AS DECIMAL(38,0)),
    CASE ty.name
        WHEN ''tinyint''  THEN CAST(255 AS DECIMAL(38,0))
        WHEN ''smallint'' THEN CAST(32767 AS DECIMAL(38,0))
        WHEN ''int''      THEN CAST(2147483647 AS DECIMAL(38,0))
        WHEN ''bigint''   THEN CAST(9223372036854775807 AS DECIMAL(38,0))
        ELSE CAST(REPLICATE(''9'', ic.precision) AS DECIMAL(38,0))
    END,
    CASE ty.name
        WHEN ''tinyint''  THEN CAST(0 AS DECIMAL(38,0))
        WHEN ''smallint'' THEN CAST(-32768 AS DECIMAL(38,0))
        WHEN ''int''      THEN CAST(-2147483648 AS DECIMAL(38,0))
        WHEN ''bigint''   THEN CAST(-9223372036854775808 AS DECIMAL(38,0))
        ELSE -CAST(REPLICATE(''9'', ic.precision) AS DECIMAL(38,0))
    END,
    (SELECT SUM(p.rows)
     FROM sys.partitions AS p
     WHERE p.object_id = t.object_id
       AND p.index_id IN (0, 1))
FROM sys.identity_columns AS ic
JOIN sys.tables AS t
    ON t.object_id = ic.object_id
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
JOIN sys.types AS ty
    ON ty.user_type_id = ic.system_type_id
WHERE t.is_ms_shipped = 0;
'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id <> 2            /* tempdb is rebuilt at every startup */
  AND HAS_DBACCESS(name) = 1;     /* skip what this account cannot open, rather than failing the whole run */

EXEC sys.sp_executesql @sql;

;WITH dir AS (
    /* the limit is the end of the range the increment walks towards; the start is the far end */
    SELECT
        *,
        CASE WHEN increment_value > 0 THEN type_max ELSE type_min END AS type_limit,
        CASE WHEN increment_value > 0 THEN type_min ELSE type_max END AS type_start
    FROM #identity
), base AS (
    /* measure from the seed, unless a reseed has moved last_value behind the seed (the usual
       fix of reseeding an exhausted int into its negative range), then from the far end */
    SELECT
        *,
        CASE WHEN last_value IS NOT NULL
              AND SIGN(last_value - seed_value) = -SIGN(increment_value)
             THEN type_start ELSE seed_value END AS range_base
    FROM dir
), calc AS (
    SELECT
        database_name,
        schema_name,
        table_name,
        column_name,
        data_type,
        seed_value,
        increment_value,
        last_value,
        type_limit,
        row_count,
        /* worked in FLOAT so a numeric(38,0) column cannot overflow the subtraction */
        CAST(
            CASE WHEN last_value IS NULL OR type_limit = range_base THEN 0
                 ELSE (CAST(last_value AS FLOAT) - CAST(range_base AS FLOAT))
                    / (CAST(type_limit AS FLOAT) - CAST(range_base AS FLOAT)) * 100
            END AS DECIMAL(6,2)) AS percent_used,
        /* exact for tinyint to bigint and narrower decimals; NULL for decimal/numeric wider than
           30 digits, where the exact count does not fit and percent_used is the figure to read */
        CASE WHEN ABS(type_limit) < 1e30
             THEN FLOOR(ABS(type_limit - COALESCE(last_value, seed_value - increment_value)) / ABS(increment_value))
        END AS values_remaining
    FROM base
)
SELECT
    database_name,
    schema_name,
    table_name,
    column_name,
    data_type,
    seed_value,
    increment_value,
    last_value,
    type_limit,
    values_remaining,
    percent_used,
    row_count
FROM calc
WHERE percent_used >= @MinPercentUsed
ORDER BY percent_used DESC, database_name, schema_name, table_name;

DROP TABLE #identity;
