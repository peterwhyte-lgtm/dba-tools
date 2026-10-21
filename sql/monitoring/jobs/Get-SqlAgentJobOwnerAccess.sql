/*
Script Name : Get-SqlAgentJobOwnerAccess
Category    : configuration-and-environment
Purpose     : Check every SQL Agent job owner the way Agent does before a job starts, and list the jobs that will fail with "Unable to determine if the owner ... has server access" (error 15404) or "does not have server access".
Author      : Peter Whyte (https://sqldba.blog)
Requires    : db_datareader on msdb and VIEW ANY DEFINITION. The Windows owner check calls xp_logininfo, which needs sysadmin (or EXECUTE on xp_logininfo); without it those owners report the permission error instead of a result.
Notes       : Read-only. xp_logininfo asks Windows / Active Directory about each distinct Windows owner, the same call Agent makes at job start, so a domain account that has been deleted or cannot be looked up shows its real 15404 error here. Set @CheckWindowsOwners = 0 to skip the lookups. fix_command is generated text only; nothing is changed.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @CheckWindowsOwners bit     = 1;      -- 0 = skip the xp_logininfo lookups (no AD calls)
DECLARE @NewOwner           sysname = SUSER_SNAME(0x01);  -- the sa login by SID, whatever it is named (use a dedicated service login if you have one)

DECLARE @agent_xps_in_use int =
    (SELECT CONVERT(int, value_in_use) FROM sys.configurations WHERE name = N'Agent XPs');

-- One row per distinct job owner, named the same way Agent names it (SUSER_SNAME of the stored SID)
CREATE TABLE #owner
(
    owner_sid     varbinary(85)  NOT NULL PRIMARY KEY,
    owner_name    sysname        NULL,
    windows_check nvarchar(2048) NULL
);

INSERT INTO #owner (owner_sid, owner_name)
SELECT DISTINCT j.owner_sid, SUSER_SNAME(j.owner_sid)
FROM msdb.dbo.sysjobs AS j;

-- Windows owners: ask Windows, as Agent does. A row back means the account has a way in
-- (its own login or a group); an error here is the error the job will fail with.
IF @CheckWindowsOwners = 1
BEGIN
    CREATE TABLE #xp
    (
        account_name      sysname       NULL,
        type              nvarchar(10)  NULL,
        privilege         nvarchar(10)  NULL,
        mapped_login_name sysname       NULL,
        permission_path   sysname       NULL
    );

    DECLARE @sid varbinary(85), @name sysname;
    DECLARE owner_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT o.owner_sid, o.owner_name
        FROM #owner AS o
        WHERE o.owner_name LIKE N'%\%'
          AND o.owner_name <> N'NT AUTHORITY\SYSTEM'
          AND NOT EXISTS (SELECT 1
                          FROM sys.server_permissions AS p
                          JOIN sys.server_principals AS sp ON sp.principal_id = p.grantee_principal_id
                          WHERE sp.sid = o.owner_sid
                            AND p.permission_name = N'CONNECT SQL'
                            AND p.state = 'D');
    OPEN owner_cur;
    FETCH NEXT FROM owner_cur INTO @sid, @name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM #xp;
        BEGIN TRY
            INSERT INTO #xp EXEC master.dbo.xp_logininfo @name;
            UPDATE #owner
            SET windows_check = CASE WHEN EXISTS (SELECT 1 FROM #xp) THEN N'OK' ELSE N'NO ACCESS' END
            WHERE owner_sid = @sid;
        END TRY
        BEGIN CATCH
            UPDATE #owner
            SET windows_check = N'ERROR Msg ' + CONVERT(nvarchar(10), ERROR_NUMBER()) + N': ' + ERROR_MESSAGE()
            WHERE owner_sid = @sid;
        END CATCH;
        FETCH NEXT FROM owner_cur INTO @sid, @name;
    END;
    CLOSE owner_cur;
    DEALLOCATE owner_cur;
END;

WITH owner_state AS
(
    SELECT
        o.owner_sid,
        o.owner_name,
        o.windows_check,
        sp.type_desc,
        sp.is_disabled,
        CASE WHEN EXISTS (SELECT 1 FROM sys.server_permissions AS p
                          WHERE p.grantee_principal_id = sp.principal_id
                            AND p.permission_name = N'CONNECT SQL' AND p.state = 'D') THEN 1 ELSE 0 END AS connect_denied,
        CASE WHEN EXISTS (SELECT 1 FROM sys.server_permissions AS p
                          WHERE p.grantee_principal_id = sp.principal_id
                            AND p.permission_name = N'CONNECT SQL' AND p.state IN ('G', 'W')) THEN 1 ELSE 0 END AS connect_granted,
        CASE WHEN EXISTS (SELECT 1 FROM sys.server_role_members AS rm
                          JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id
                          WHERE rm.member_principal_id = sp.principal_id
                            AND r.name = N'sysadmin') THEN 1 ELSE 0 END AS is_sysadmin
    FROM #owner AS o
    LEFT JOIN sys.server_principals AS sp ON sp.sid = o.owner_sid
),
verdict AS
(
    SELECT
        os.owner_sid,
        os.owner_name,
        os.type_desc,
        CASE
            WHEN os.owner_name IS NULL THEN 'FAIL'
            WHEN os.connect_denied = 1 THEN 'FAIL'
            WHEN os.owner_name NOT LIKE N'%\%' AND os.type_desc IS NOT NULL
                 AND os.connect_granted = 0 AND os.is_sysadmin = 0 THEN 'FAIL'
            WHEN os.windows_check LIKE N'ERROR%' THEN 'FAIL'
            WHEN os.windows_check = N'NO ACCESS' THEN 'FAIL'
            WHEN os.owner_name LIKE N'%\%' AND os.windows_check IS NULL
                 AND os.owner_name <> N'NT AUTHORITY\SYSTEM' THEN 'AT RISK'
            WHEN os.is_disabled = 1 THEN 'REVIEW'
            WHEN os.type_desc = 'WINDOWS_LOGIN'
                 AND os.owner_name NOT LIKE N'NT SERVICE\%'
                 AND os.owner_name NOT LIKE N'NT AUTHORITY\%' THEN 'REVIEW'
            ELSE 'OK'
        END AS owner_check,
        CASE
            WHEN os.owner_name IS NULL
                THEN 'Owner SID resolves to no login and no Windows account, so Agent cannot name or check the owner'
            WHEN os.connect_denied = 1
                THEN 'Owner login is denied CONNECT SQL: "does not have server access"'
            WHEN os.owner_name NOT LIKE N'%\%' AND os.type_desc IS NOT NULL
                 AND os.connect_granted = 0 AND os.is_sysadmin = 0
                THEN 'Owner login has no CONNECT SQL grant: "does not have server access"'
            WHEN os.windows_check LIKE N'ERROR%'
                THEN 'Windows lookup failed, the job fails with the same error: ' + os.windows_check
            WHEN os.windows_check = N'NO ACCESS'
                THEN 'Windows account exists but has no login or group path into this instance'
            WHEN os.owner_name LIKE N'%\%' AND os.windows_check IS NULL
                 AND os.owner_name <> N'NT AUTHORITY\SYSTEM'
                THEN 'Windows owner, looked up in AD at every job start; not checked (@CheckWindowsOwners = 0)'
            WHEN os.is_disabled = 1
                THEN 'Owner login is disabled. Agent''s check reads CONNECT SQL, not is_disabled, so this alone does not fail the job'
            WHEN os.type_desc = 'WINDOWS_LOGIN'
                 AND os.owner_name NOT LIKE N'NT SERVICE\%'
                 AND os.owner_name NOT LIKE N'NT AUTHORITY\%'
                THEN 'Owned by an individual Windows account: the job fails once that account is removed from AD'
            ELSE 'Owner resolves and has server access'
        END AS owner_reason
    FROM owner_state AS os
)
SELECT
    j.name AS job_name,
    j.enabled AS job_enabled,
    ISNULL(v.owner_name, '(unresolved) ' + CONVERT(varchar(200), j.owner_sid, 1)) AS owner_name,
    CASE WHEN v.owner_name IS NULL THEN 'UNRESOLVED SID'
         WHEN v.type_desc IS NOT NULL THEN v.type_desc
         WHEN v.owner_name LIKE N'%\%' THEN 'WINDOWS (no own login)'
         ELSE 'NO LOGIN'
    END AS owner_type,
    v.owner_check AS access_check,
    CASE WHEN @agent_xps_in_use = 0
         THEN 'AGENT XPS OFF (value_in_use = 0): every job fails at start, sa included. Owner: ' + v.owner_reason
         ELSE v.owner_reason
    END AS reason,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Unknown'
    END AS last_run_outcome,
    CASE WHEN js.last_run_date = 0 OR js.last_run_date IS NULL THEN NULL
         ELSE CONVERT(datetime,
                  STUFF(STUFF(CAST(js.last_run_date AS char(8)), 7, 0, '-'), 5, 0, '-') + ' ' +
                  STUFF(STUFF(RIGHT('000000' + CAST(js.last_run_time AS varchar(6)), 6), 5, 0, ':'), 3, 0, ':'))
    END AS last_run_at,
    CASE WHEN v.owner_check = 'OK' THEN NULL
         ELSE N'EXEC msdb.dbo.sp_update_job @job_name = N''' + REPLACE(j.name, N'''', N'''''')
              + N''', @owner_login_name = N''' + REPLACE(@NewOwner, N'''', N'''''') + N''';'
    END AS fix_command
FROM msdb.dbo.sysjobs AS j
JOIN verdict AS v ON v.owner_sid = j.owner_sid
LEFT JOIN msdb.dbo.sysjobservers AS js ON js.job_id = j.job_id
ORDER BY
    CASE v.owner_check
        WHEN 'FAIL' THEN 1 WHEN 'AT RISK' THEN 2 WHEN 'REVIEW' THEN 3 ELSE 4 END,
    j.name;
