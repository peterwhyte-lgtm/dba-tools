/*
Script Name : Get-FailedLoginSummary
Category    : security
Purpose     : Aggregated failed login analysis from the SQL Server error log and current
              lockout state per SQL login. Surfaces brute-force patterns and locked accounts.
              Complements Get-WeakLoginSettings (which checks policy configuration), this
              checks what is actually happening.
              Note: SQL Server 2025 does not write 18456 events to RING_BUFFER_SECURITY_ERROR;
              xp_readerrorlog is the reliable cross-version source for login failures.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-security-audit/)
Requires    : VIEW SERVER STATE, sysadmin (for LOGINPROPERTY on other logins), EXECUTE on xp_readerrorlog
HealthCheck : Yes
Notes       : The reason column is the literal text after "Reason: " in the error log entry.
              Read it before the mapped error_description: every one of these entries is logged
              as 18456 and only the reason separates a bad password from a missing default
              database, which the client sees as 4064.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- INSERT...EXEC cannot be used inside a CTE so materialise to a temp table first
DROP TABLE IF EXISTS #failed_logins;
CREATE TABLE #failed_logins (
    log_date DATETIME,
    process_info NVARCHAR(100),
    log_text NVARCHAR(MAX)
);

-- Filter to current error log (log# 0), type 1 (SQL Server log), login failure messages only
INSERT INTO #failed_logins
EXEC xp_readerrorlog 0, 1, N'Login failed';

WITH parsed AS (
    SELECT
        -- Login name sits between the first pair of single quotes. Some entries carry no
        -- name at all (18452 "untrusted domain" is logged as "Login failed. The login is
        -- from..."), so guard the SUBSTRING or one such line fails the whole run (Msg 537).
        CASE
            WHEN CHARINDEX('''', log_text) > 0
             AND CHARINDEX('''', log_text, CHARINDEX('''', log_text) + 1) > 0
            THEN SUBSTRING(
                log_text,
                CHARINDEX('''', log_text) + 1,
                CHARINDEX('''', log_text, CHARINDEX('''', log_text) + 1) - CHARINDEX('''', log_text) - 1
            )
            ELSE NULL
        END AS login_name,
        -- Client IP/host is in the trailing [CLIENT: ...] tag
        CASE
            WHEN CHARINDEX('[CLIENT: ', log_text) > 0
             AND CHARINDEX(']', log_text, CHARINDEX('[CLIENT: ', log_text)) > 0
            THEN SUBSTRING(
                log_text,
                CHARINDEX('[CLIENT: ', log_text) + 9,
                CHARINDEX(']', log_text, CHARINDEX('[CLIENT: ', log_text))
                    - CHARINDEX('[CLIENT: ', log_text) - 9
            )
            ELSE NULL
        END AS client_host,
        -- The log's own words: everything after "Reason: " up to the [CLIENT: tag
        CASE
            WHEN CHARINDEX('Reason: ', log_text) > 0
            THEN RTRIM(SUBSTRING(
                log_text,
                CHARINDEX('Reason: ', log_text) + 8,
                CASE
                    WHEN CHARINDEX('[CLIENT: ', log_text) > CHARINDEX('Reason: ', log_text)
                    THEN CHARINDEX('[CLIENT: ', log_text) - CHARINDEX('Reason: ', log_text) - 8
                    ELSE 4000
                END
            ))
            ELSE NULL
        END AS reason,
        -- Map reason text to the canonical error code
        CASE
            WHEN log_text LIKE '%untrusted domain%' THEN 18452
            WHEN log_text LIKE '%only administrators%' THEN 18451
            WHEN log_text LIKE '%account is disabled%' THEN 18470
            WHEN log_text LIKE '%password of the account has expired%' THEN 18487
            WHEN log_text LIKE '%password of the account must be changed%' THEN 18488
            WHEN log_text LIKE '%explicitly specified database%' THEN 4060
            WHEN log_text LIKE '%default database%' THEN 4064
            WHEN log_text LIKE '%specified in the login properties%' THEN 4064
            WHEN log_text LIKE '%password did not match%' THEN 18456
            WHEN log_text LIKE '%error occurred while evaluating the password%' THEN 18456
            WHEN log_text LIKE '%could not find a login%' THEN 18456
            ELSE 18456
        END AS error_code,
        log_date
    FROM #failed_logins
),
aggregated AS (
    SELECT
        login_name,
        client_host,
        error_code,
        reason,
        COUNT(*) AS failure_count,
        MIN(log_date) AS first_failure,
        MAX(log_date) AS last_failure
    FROM parsed
    GROUP BY login_name, client_host, error_code, reason
)
SELECT
    agg.login_name,
    agg.client_host,
    agg.error_code,
    CASE agg.error_code
        WHEN 18456 THEN 'Login failed (bad password or login does not exist)'
        WHEN 18452 THEN 'Login from untrusted domain or cannot use Windows auth'
        WHEN 18451 THEN 'Login failed, only admin connections are allowed'
        WHEN 18470 THEN 'Account is disabled'
        WHEN 18487 THEN 'Password has expired'
        WHEN 18488 THEN 'Password must be changed'
        WHEN 4060 THEN 'Credentials are valid, the requested database could not be opened'
        WHEN 4064 THEN 'Credentials are valid, the default database is not usable'
        ELSE 'Error ' + CAST(agg.error_code AS VARCHAR(10))
    END AS error_description,
    agg.reason,
    agg.failure_count,
    agg.first_failure AS first_failure_approx,
    agg.last_failure AS last_failure_approx,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'IsLocked') AS BIT)
        ELSE NULL
    END AS is_currently_locked,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'BadPasswordCount') AS INT)
        ELSE NULL
    END AS bad_password_count,
    CASE
        WHEN agg.error_code IN (4060, 4064)
        THEN 'CONFIG - valid credentials, database not usable (' + CAST(agg.failure_count AS VARCHAR) +
             ' in log); fix the database or the default database, not the password'
        WHEN agg.failure_count >= 10
        THEN 'WARN - ' + CAST(agg.failure_count AS VARCHAR) + ' failures for login [' +
             ISNULL(agg.login_name, '(unknown)') + '] in the current error log; baseline is under 10' +
             ', check client_host for a stale application password or brute force'
        ELSE 'INFO'
    END AS status
FROM aggregated AS agg
LEFT JOIN sys.sql_logins AS sl ON sl.name = agg.login_name
ORDER BY agg.failure_count DESC;

DROP TABLE #failed_logins;
