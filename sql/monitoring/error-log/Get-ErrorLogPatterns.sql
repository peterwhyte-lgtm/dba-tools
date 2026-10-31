/*
Script Name : Get-ErrorLogPatterns
Category    : monitoring
Purpose     : Reads the current SQL Server error log and groups entries by category — surfaces memory pressure, login failures, IO issues, corruption warnings, and auto-growth events without scrolling through raw entries.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-error-log-patterns/)
Requires    : EXECUTE on xp_readerrorlog, which is granted to sysadmin and securityadmin.
              VIEW SERVER STATE does not grant it.
Notes       : The error log writes every error as two lines, an 'Error: 18456, Severity: 14,
              State: 38.' header and then the message. occurrences counts the message line only
              and categorises it with its header's error number attached, so 60 failed logins
              read 60, not 120. Tested on SQL Server 2025.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

/* ── How many hours back to read (default 24) ───────────────────────────── */
DECLARE @HoursBack INT = 24;
/* ─────────────────────────────────────────────────────────────────────────── */

IF OBJECT_ID('tempdb..#ErrLog') IS NOT NULL DROP TABLE #ErrLog;
CREATE TABLE #ErrLog (
    LogDate DATETIME NOT NULL,
    ProcessInfo NVARCHAR(50),
    Txt NVARCHAR(4000)
);
CREATE CLUSTERED INDEX cx_ErrLog ON #ErrLog (LogDate, ProcessInfo);

DECLARE @StartDate DATETIME = DATEADD(HOUR, -@HoursBack, GETDATE());
INSERT INTO #ErrLog
EXEC xp_readerrorlog 0, 1, NULL, NULL, @StartDate, NULL, N'desc';

/* Categorise once, in a CTE. The CASE used to be written out twice, in the SELECT and
   again in the GROUP BY, so any change to a pattern had to be made in both places or the
   two would silently disagree. */
/* Each error is a header line plus a message line with the same time and spid. The header is
   dropped from the count and its text is prefixed to the message (match_txt), so the error number
   still decides the category (Error: 823 is corruption) without the event being counted twice. */
WITH entries AS (
    SELECT
        e.LogDate,
        e.Txt,
        ISNULL(hdr.Txt + N' ', N'') + e.Txt AS match_txt
    FROM #ErrLog AS e
    OUTER APPLY (
        SELECT TOP (1) h.Txt
        FROM #ErrLog AS h
        WHERE h.LogDate = e.LogDate
          AND h.ProcessInfo = e.ProcessInfo
          AND h.Txt LIKE N'Error: %, Severity: %, State: %'
    ) AS hdr
    WHERE e.Txt NOT LIKE N'Error: %, Severity: %, State: %'
),
categorised AS (
    SELECT
        LogDate,
        Txt,
        CASE
            WHEN match_txt LIKE '%paged out%'
              OR match_txt LIKE '%virtual address space%'
              OR match_txt LIKE '%out of memory%'
              OR match_txt LIKE '%cannot allocate%' THEN 'Memory Pressure'
            WHEN match_txt LIKE '%login failed%'
              OR match_txt LIKE '%18456%'
              OR match_txt LIKE '%password%incorrect%' THEN 'Login Failure'
            /* Corruption is tested BEFORE IO and Backup, and its patterns match the way the
               error log actually writes these lines. Verified 2026-08-30, and the category was
               inverted before that: 'Error: 823, Severity: 24' matched nothing at all and fell
               through to Error / Failure, the real 824 text ('logical consistency-based I/O
               error') matched IO Issue first and never reached here, and the ONLY thing landing
               in Corruption / Integrity was 'CHECKDB ... finished without errors', a success
               message. The bucket a DBA scans first for corruption could not detect corruption. */
            WHEN match_txt LIKE '%corrupt%'
              OR match_txt LIKE '%consistency-based I/O error%'
              OR match_txt LIKE '%Error: 823%'
              OR match_txt LIKE '%Error: 824%'
              OR match_txt LIKE '%Error: 825%'
              OR match_txt LIKE '% 823 %'
              OR match_txt LIKE '% 824 %'
              OR match_txt LIKE '% 825 %'
              OR match_txt LIKE '%suspect_pages%'
              OR (match_txt LIKE '%CHECKDB%'
                  AND match_txt NOT LIKE '%without errors%'
                  AND match_txt NOT LIKE '%0 allocation errors and 0 consistency errors%')
                 THEN 'Corruption / Integrity'
            /* A clean integrity check is good news and must not be filed as a failure. Both
               wordings are excluded above and caught here, because 'finished without errors'
               and 'found 0 allocation errors' both contain the word errors and would otherwise
               be swept up by the generic Error / Failure branch further down. */
            WHEN match_txt LIKE '%without errors%'
              OR match_txt LIKE '%0 allocation errors and 0 consistency errors%'
                 THEN 'Informational'
            WHEN match_txt LIKE '%Backup%'
              OR match_txt LIKE '%BACKUP%'
              OR match_txt LIKE '%backup of database%'
              OR match_txt LIKE '%RESTORE%' THEN 'Backup / Restore'
            WHEN match_txt LIKE '%I/O%'
              OR match_txt LIKE '%stall%'
              OR match_txt LIKE '%stalled%'
              OR match_txt LIKE '%disk%' THEN 'IO Issue'
            WHEN match_txt LIKE '%suspect%'
              OR match_txt LIKE '%offline%'
              OR match_txt LIKE '%emergency%'
              OR match_txt LIKE '%recovery%' THEN 'Database State'
            WHEN match_txt LIKE '%autogrow%'
              OR match_txt LIKE '%Auto-grow%'
              OR match_txt LIKE '% grew %'
              OR match_txt LIKE '%Autogrow%' THEN 'Auto-Growth'
            WHEN match_txt LIKE '%deadlock%' THEN 'Deadlock'
            WHEN match_txt LIKE '%Error%'
              OR match_txt LIKE '%error%'
              OR match_txt LIKE '%failed%' THEN 'Error / Failure'
            WHEN match_txt LIKE '%Warning%'
              OR match_txt LIKE '%warning%' THEN 'Warning'
            ELSE 'Informational'
        END AS category
    FROM entries
),
/* latest_message must be the most RECENT entry in the category. It used to be
   LEFT(MAX(Txt), 200), which is the alphabetically greatest text, not the newest one, and
   it sat next to last_seen where a reader would naturally read the two as the same event. */
ranked AS (
    SELECT
        category,
        LogDate,
        Txt,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY LogDate DESC, Txt) AS rn
    FROM categorised
)
SELECT
    category,
    COUNT(*)                                        AS occurrences,
    MIN(LogDate)                                    AS first_seen,
    MAX(LogDate)                                    AS last_seen,
    LEFT(MAX(CASE WHEN rn = 1 THEN Txt END), 200)   AS latest_message
FROM ranked
GROUP BY category
ORDER BY occurrences DESC;

DROP TABLE #ErrLog;
