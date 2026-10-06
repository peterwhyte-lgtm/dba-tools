/*
Script Name : Generate-AgentJobScript
Category    : migration
Purpose     : Generate sp_add_job DDL to recreate all SQL Agent jobs on the target server.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-agent-job-script/)
Requires    : db_datareader on msdb (or sysadmin); the Agent roles alone cannot SELECT sysoperators.
              Without it the script stops with an error instead of returning an empty script.
Notes       : Steps and schedules are built with STRING_AGG, not SELECT @var = @var + ... ORDER BY,
              which MS Docs calls nondeterministic. Needs SQL Server 2017 or later.
              Custom job categories are created on the target if missing. A missing operator or
              owner login still stops sp_add_job, and the rest of that job's block is then
              skipped rather than leaving an unattached schedule behind.
              A schedule is reused only when its name AND definition match, so two schedules
              that share a name on the source stay two schedules on the target.
              NOT scripted: operators, proxies, alerts, job history. Create operators and
              proxies on the target first; a step that ran under a proxy needs @proxy_name added.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- Without SELECT on these msdb tables the cursor never opens and the result is a header with no jobs,
-- while the errors sit in the Messages pane. Fail loudly instead.
IF ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.sysjobs',         N'OBJECT', N'SELECT'), 0) <> 1
   OR ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.sysjobsteps',     N'OBJECT', N'SELECT'), 0) <> 1
   OR ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.sysjobschedules', N'OBJECT', N'SELECT'), 0) <> 1
   OR ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.sysschedules',    N'OBJECT', N'SELECT'), 0) <> 1
   OR ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.syscategories',   N'OBJECT', N'SELECT'), 0) <> 1
   OR ISNULL(HAS_PERMS_BY_NAME(N'msdb.dbo.sysoperators',    N'OBJECT', N'SELECT'), 0) <> 1
BEGIN
    RAISERROR(N'Generate-AgentJobScript needs SELECT on the msdb job tables (db_datareader on msdb, or sysadmin). SQLAgentReaderRole and SQLAgentOperatorRole are not enough, and the generated script would contain no jobs.', 16, 1);
    RETURN;
END;

DECLARE @ddl  NVARCHAR(MAX) = N'';
DECLARE @crlf NCHAR(2)      = CHAR(13) + CHAR(10);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- SQL Agent Job Migration Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Review owner_login_name values - map to valid logins on target.' + @crlf
    + N'-- NOT included: operators, proxies, alerts. Create them on the target first.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf
    + N'USE msdb;' + @crlf + N'GO' + @crlf + @crlf;

-- ── Per job ───────────────────────────────────────────────────────────────────

DECLARE @job_id    UNIQUEIDENTIFIER;
DECLARE @job_name  NVARCHAR(128);
DECLARE @enabled   TINYINT;
DECLARE @desc      NVARCHAR(512);
DECLARE @category  NVARCHAR(128);
DECLARE @cat_id    INT;
DECLARE @cat_type  INT;
DECLARE @owner     NVARCHAR(128);
DECLARE @owner_sid NVARCHAR(200);
DECLARE @start_step INT;
DECLARE @nl_email  INT; DECLARE @nl_netsend INT; DECLARE @nl_page INT; DECLARE @nl_eventlog INT;
DECLARE @op_email  NVARCHAR(128); DECLARE @op_netsend NVARCHAR(128); DECLARE @op_page NVARCHAR(128);
DECLARE @q_job     NVARCHAR(300);

DECLARE job_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        j.job_id,
        j.name,
        j.enabled,
        ISNULL(j.description, N''),
        ISNULL(c.name, N'[Uncategorized (Local)]'),
        ISNULL(c.category_id, 0),
        ISNULL(c.category_type, 1),
        SUSER_SNAME(j.owner_sid),
        CONVERT(NVARCHAR(200), j.owner_sid, 1),
        j.start_step_id,
        j.notify_level_email,
        j.notify_level_netsend,
        j.notify_level_page,
        j.notify_level_eventlog,
        ISNULL(CAST(n_email.name  AS NVARCHAR(128)), N''),
        ISNULL(CAST(n_ns.name     AS NVARCHAR(128)), N''),
        ISNULL(CAST(n_page.name   AS NVARCHAR(128)), N'')
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id
    LEFT JOIN msdb.dbo.sysoperators n_email ON j.notify_email_operator_id   = n_email.id
    LEFT JOIN msdb.dbo.sysoperators n_ns    ON j.notify_netsend_operator_id = n_ns.id
    LEFT JOIN msdb.dbo.sysoperators n_page  ON j.notify_page_operator_id    = n_page.id
    ORDER BY j.name;

OPEN job_cur;
FETCH NEXT FROM job_cur INTO
    @job_id, @job_name, @enabled, @desc, @category, @cat_id, @cat_type, @owner, @owner_sid, @start_step,
    @nl_email, @nl_netsend, @nl_page, @nl_eventlog,
    @op_email, @op_netsend, @op_page;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @q_job = N'N''' + REPLACE(@job_name, N'''', N'''''') + N'''';

    -- ── Job header ────────────────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'-- Job: ' + @job_name + @crlf
        + CASE WHEN @owner IS NULL
               THEN N'-- MANUAL: the owner SID ' + @owner_sid + N' matches no login on the source, so @owner_login_name is sa. Change it if sa should not own this job.' + @crlf
               ELSE N'' END
        + N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = ' + @q_job + N')' + @crlf
        + N'BEGIN' + @crlf
        + N'    DECLARE @job_id UNIQUEIDENTIFIER, @schedule_id INT;' + @crlf
        + CASE WHEN @cat_id >= 100
               THEN N'    IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE category_class = 1 AND name = N''' + REPLACE(@category, N'''', N'''''') + N''')' + @crlf
                  + N'        EXEC msdb.dbo.sp_add_category @class = N''JOB'', @type = N''' + CASE WHEN @cat_type = 2 THEN N'MULTI-SERVER' ELSE N'LOCAL' END + N''', @name = N''' + REPLACE(@category, N'''', N'''''') + N''';' + @crlf
               ELSE N'' END
        + N'    EXEC msdb.dbo.sp_add_job' + @crlf
        + N'        @job_name              = ' + @q_job + N',' + @crlf
        + N'        @enabled               = '    + CAST(@enabled AS NVARCHAR(1)) + N',' + @crlf
        + N'        @description           = N''' + REPLACE(@desc,     N'''', N'''''') + N''',' + @crlf
        + N'        @category_name         = N''' + REPLACE(@category, N'''', N'''''') + N''',' + @crlf
        + N'        @owner_login_name      = N''' + REPLACE(ISNULL(@owner, N'sa'), N'''', N'''''') + N''',' + @crlf
        + N'        @notify_level_eventlog = '    + CAST(@nl_eventlog  AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_email    = '    + CAST(@nl_email     AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_netsend  = '    + CAST(@nl_netsend   AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_page     = '    + CAST(@nl_page      AS NVARCHAR(1)) + @crlf
        + CASE WHEN @op_email   <> N'' THEN N'       ,@notify_email_operator_name   = N''' + REPLACE(@op_email,   N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + CASE WHEN @op_netsend <> N'' THEN N'       ,@notify_netsend_operator_name = N''' + REPLACE(@op_netsend, N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + CASE WHEN @op_page    <> N'' THEN N'       ,@notify_page_operator_name    = N''' + REPLACE(@op_page,    N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + N'        ,@job_id = @job_id OUTPUT;' + @crlf
        + N'    IF @job_id IS NULL RETURN;  -- sp_add_job failed (see the error above), so skip the rest of this job' + @crlf + @crlf;

    -- ── Job steps (STRING_AGG keeps every step, in step_id order) ────────────
    SELECT @ddl = @ddl + ISNULL(STRING_AGG(CAST(
          N'    EXEC msdb.dbo.sp_add_jobstep' + @crlf
        + N'        @job_id          = @job_id,' + @crlf
        + N'        @step_id         = '    + CAST(s.step_id          AS NVARCHAR(5))   + N',' + @crlf
        + N'        @step_name       = N''' + REPLACE(s.step_name,    N'''', N'''''') + N''',' + @crlf
        + N'        @subsystem       = N''' + s.subsystem                               + N''',' + @crlf
        + N'        @command         = N''' + REPLACE(ISNULL(s.command, N''), N'''', N'''''') + N''',' + @crlf
        + N'        @database_name   = N''' + REPLACE(ISNULL(s.database_name, N'master'), N'''', N'''''') + N''',' + @crlf
        + CASE WHEN s.database_user_name IS NOT NULL
               THEN N'        @database_user_name = N''' + REPLACE(s.database_user_name, N'''', N'''''') + N''',' + @crlf ELSE N'' END
        + CASE WHEN s.subsystem = N'CmdExec'
               THEN N'        @cmdexec_success_code = ' + CAST(s.cmdexec_success_code AS NVARCHAR(11)) + N',' + @crlf ELSE N'' END
        + CASE WHEN s.output_file_name IS NOT NULL
               THEN N'        @output_file_name = N''' + REPLACE(s.output_file_name, N'''', N'''''') + N''',' + @crlf ELSE N'' END
        + N'        @flags           = '    + CAST(s.flags             AS NVARCHAR(11)) + N',' + @crlf
        + N'        @on_success_action = '  + CAST(s.on_success_action AS NVARCHAR(1))  + N',' + @crlf
        + N'        @on_success_step_id= '  + CAST(s.on_success_step_id AS NVARCHAR(5)) + N',' + @crlf
        + N'        @on_fail_action  = '    + CAST(s.on_fail_action    AS NVARCHAR(1))  + N',' + @crlf
        + N'        @on_fail_step_id = '    + CAST(s.on_fail_step_id   AS NVARCHAR(5))  + N',' + @crlf
        + N'        @retry_attempts  = '    + CAST(s.retry_attempts    AS NVARCHAR(5))  + N',' + @crlf
        + N'        @retry_interval  = '    + CAST(s.retry_interval    AS NVARCHAR(5))  + N';' + @crlf + @crlf
        AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY s.step_id), N'')
    FROM msdb.dbo.sysjobsteps s
    WHERE s.job_id = @job_id;

    -- ── Set start step ────────────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'    EXEC msdb.dbo.sp_update_job @job_id = @job_id, @start_step_id = ' + CAST(@start_step AS NVARCHAR(5)) + N';' + @crlf + @crlf;

    -- ── Schedules: reuse one only when name AND definition match, attach by id ─
    SELECT @ddl = @ddl + ISNULL(STRING_AGG(CAST(
          N'    SET @schedule_id = NULL;' + @crlf
        + N'    SELECT TOP (1) @schedule_id = schedule_id FROM msdb.dbo.sysschedules' + @crlf
        + N'     WHERE name = N''' + REPLACE(sc.name, N'''', N'''''') + N''' AND enabled = ' + CAST(sc.enabled AS NVARCHAR(1))
        + N' AND freq_type = ' + CAST(sc.freq_type AS NVARCHAR(10)) + N' AND freq_interval = ' + CAST(sc.freq_interval AS NVARCHAR(10)) + @crlf
        + N'       AND freq_subday_type = ' + CAST(sc.freq_subday_type AS NVARCHAR(10)) + N' AND freq_subday_interval = ' + CAST(sc.freq_subday_interval AS NVARCHAR(10))
        + N' AND freq_relative_interval = ' + CAST(sc.freq_relative_interval AS NVARCHAR(10)) + N' AND freq_recurrence_factor = ' + CAST(sc.freq_recurrence_factor AS NVARCHAR(10)) + @crlf
        + N'       AND active_start_date = ' + CAST(sc.active_start_date AS NVARCHAR(10)) + N' AND active_end_date = ' + CAST(sc.active_end_date AS NVARCHAR(10))
        + N' AND active_start_time = ' + CAST(sc.active_start_time AS NVARCHAR(10)) + N' AND active_end_time = ' + CAST(sc.active_end_time AS NVARCHAR(10)) + @crlf
        + N'     ORDER BY schedule_id;' + @crlf
        + N'    IF @schedule_id IS NULL' + @crlf
        + N'        EXEC msdb.dbo.sp_add_schedule' + @crlf
        + N'            @schedule_name       = N''' + REPLACE(sc.name, N'''', N'''''')     + N''',' + @crlf
        + N'            @enabled             = '    + CAST(sc.enabled            AS NVARCHAR(1))  + N',' + @crlf
        + N'            @freq_type           = '    + CAST(sc.freq_type          AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_interval       = '    + CAST(sc.freq_interval      AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_subday_type    = '    + CAST(sc.freq_subday_type   AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_subday_interval= '    + CAST(sc.freq_subday_interval AS NVARCHAR(10))+ N',' + @crlf
        + N'            @freq_relative_interval='   + CAST(sc.freq_relative_interval AS NVARCHAR(10))+N',' + @crlf
        + N'            @freq_recurrence_factor='   + CAST(sc.freq_recurrence_factor AS NVARCHAR(10))+N',' + @crlf
        + N'            @active_start_date   = '    + CAST(sc.active_start_date  AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_end_date     = '    + CAST(sc.active_end_date    AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_start_time   = '    + CAST(sc.active_start_time  AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_end_time     = '    + CAST(sc.active_end_time    AS NVARCHAR(10)) + N',' + @crlf
        + N'            @schedule_id         = @schedule_id OUTPUT;' + @crlf
        + N'    EXEC msdb.dbo.sp_attach_schedule @job_id = @job_id, @schedule_id = @schedule_id;' + @crlf + @crlf
        AS NVARCHAR(MAX)), N'') WITHIN GROUP (ORDER BY sc.name, sc.schedule_id), N'')
    FROM msdb.dbo.sysjobschedules js
    INNER JOIN msdb.dbo.sysschedules sc ON js.schedule_id = sc.schedule_id
    WHERE js.job_id = @job_id;

    -- ── Add to local server ───────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'    EXEC msdb.dbo.sp_add_jobserver @job_id = @job_id, @server_name = N''(local)'';' + @crlf
        + N'END' + @crlf + N'GO' + @crlf + @crlf;

    FETCH NEXT FROM job_cur INTO
        @job_id, @job_name, @enabled, @desc, @category, @cat_id, @cat_type, @owner, @owner_sid, @start_step,
        @nl_email, @nl_netsend, @nl_page, @nl_eventlog,
        @op_email, @op_netsend, @op_page;
END

CLOSE job_cur;
DEALLOCATE job_cur;

SELECT @ddl AS ddl;
