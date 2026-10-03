/*
Script Name : Get-WeakLoginSettings
Category    : security-and-permissions
Purpose     : Identify SQL logins with weak security settings: a blank password, a password equal
              to the login name, sa enabled, password policy off, or expiration off.
              risk_flag is the highest-severity finding for the login; all_risks lists every
              finding it has, because a login is usually weak in more than one way at once.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-security-audit/)
Requires    : VIEW ANY DEFINITION; CONTROL SERVER or sysadmin (password_hash and LOGINPROPERTY)
HealthCheck : Yes
Notes       : PWDCOMPARE reads sys.sql_logins.password_hash, which is visible only to a login
              with CONTROL SERVER. Without it the blank/equals-name tests silently return 0.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

WITH flags AS (
    SELECT
        sl.name,
        sl.is_disabled,
        sl.is_policy_checked,
        sl.is_expiration_checked,
        sl.default_database_name,
        sl.create_date,
        sl.modify_date,
        CAST(LOGINPROPERTY(sl.name, 'PasswordLastSetTime') AS DATETIME) AS password_last_set,
        CAST(LOGINPROPERTY(sl.name, 'IsLocked') AS BIT)                 AS is_locked,
        CAST(LOGINPROPERTY(sl.name, 'IsMustChange') AS BIT)             AS must_change_password,
        /* No password literal appears in this script: PWDCOMPARE hashes the candidate itself. */
        CASE WHEN sl.password_hash IS NOT NULL AND PWDCOMPARE(N'', sl.password_hash) = 1
             THEN 1 ELSE 0 END AS pw_blank,
        CASE WHEN sl.password_hash IS NOT NULL AND PWDCOMPARE(sl.name, sl.password_hash) = 1
             THEN 1 ELSE 0 END AS pw_equals_name,
        CASE WHEN sl.name = 'sa' AND sl.is_disabled = 0 THEN 1 ELSE 0 END AS sa_enabled
    FROM sys.sql_logins AS sl
    WHERE sl.name NOT LIKE '##%'
)
SELECT
    f.name AS login_name,
    f.is_disabled,
    f.is_policy_checked,
    f.is_expiration_checked,
    f.password_last_set,
    f.is_locked,
    f.must_change_password,
    f.default_database_name,
    f.create_date,
    f.modify_date,
    CASE
        WHEN f.pw_blank = 1                 THEN 'BLANK_PASSWORD'
        WHEN f.pw_equals_name = 1           THEN 'PASSWORD_EQUALS_NAME'
        WHEN f.sa_enabled = 1               THEN 'SA_ENABLED'
        WHEN f.is_policy_checked = 0        THEN 'PASSWORD_POLICY_OFF'
        WHEN f.is_expiration_checked = 0    THEN 'EXPIRATION_OFF'
        ELSE 'OK'
    END AS risk_flag,
    STUFF(
          CASE WHEN f.pw_blank = 1              THEN ',BLANK_PASSWORD'       ELSE '' END
        + CASE WHEN f.pw_equals_name = 1        THEN ',PASSWORD_EQUALS_NAME' ELSE '' END
        + CASE WHEN f.sa_enabled = 1            THEN ',SA_ENABLED'           ELSE '' END
        + CASE WHEN f.is_policy_checked = 0     THEN ',PASSWORD_POLICY_OFF'  ELSE '' END
        + CASE WHEN f.is_expiration_checked = 0 THEN ',EXPIRATION_OFF'       ELSE '' END
        , 1, 1, '') AS all_risks
FROM flags AS f
ORDER BY
    CASE
        WHEN f.pw_blank = 1              THEN 0
        WHEN f.pw_equals_name = 1        THEN 1
        WHEN f.sa_enabled = 1            THEN 2
        WHEN f.is_policy_checked = 0     THEN 3
        WHEN f.is_expiration_checked = 0 THEN 4
        ELSE 5
    END,
    f.name;
