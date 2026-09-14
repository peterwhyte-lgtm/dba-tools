/*
Script Name : Get-LogShippingStatus
Category    : high-availability
Purpose     : Show every log shipping pair on this instance and how far behind each secondary is.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE, and membership of msdb (the monitor tables live there)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  WHAT THIS ANSWERS, mid-incident: "is the secondary behind, and which part of the chain
  stopped - backup, copy, or restore?"

  Log shipping is three jobs, not one, and they fail independently:
     backup  on the primary    -> msdb.dbo.log_shipping_monitor_primary.last_backup_date
     copy    on the secondary  -> log_shipping_monitor_secondary.last_copied_date
     restore on the secondary  -> log_shipping_monitor_secondary.last_restored_date

  Reading only "restore latency" tells you the secondary is behind but not WHY. If the copy
  date is current and the restore date is old, the restore job is the problem. If the copy date
  is also old, look further up: the backup job or the share. That is the whole diagnostic, and
  it is why this script prints all three ages side by side rather than one lag number.

  WHERE TO RUN IT. The monitor tables are populated on whichever instance holds the monitor
  role - often the secondary, sometimes a third server. A row appears here only for the parts
  this instance monitors, so an empty result is not proof that log shipping is healthy. It may
  mean you are on the wrong instance. The status row below says so rather than returning
  nothing and letting you conclude the wrong thing.

  THRESHOLDS ARE THE CONFIGURED ONES, not invented. backup_threshold and restore_threshold are
  the values set when log shipping was configured, in minutes. This compares against those
  rather than against a number of my choosing.
*/

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_monitor_primary)
   AND NOT EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_monitor_secondary)
BEGIN
    SELECT 'No log shipping rows on this instance. Either log shipping is not configured, or '
         + 'this server does not hold the monitor role - check the primary and the secondary.'
           AS status;
END
ELSE
BEGIN

    SELECT
        'PRIMARY'                                              AS role,
        p.primary_server                                       AS server_name,
        p.primary_database                                     AS database_name,
        NULL                                                   AS partner_server,
        p.last_backup_date                                     AS last_backup,
        DATEDIFF(MINUTE, p.last_backup_date, GETDATE())        AS backup_age_min,
        p.backup_threshold                                     AS backup_threshold_min,
        NULL                                                   AS last_copied,
        NULL                                                   AS copy_age_min,
        NULL                                                   AS last_restored,
        NULL                                                   AS restore_age_min,
        NULL                                                   AS restore_threshold_min,
        CASE
            WHEN p.last_backup_date IS NULL THEN 'NO BACKUP RECORDED'
            WHEN DATEDIFF(MINUTE, p.last_backup_date, GETDATE()) > p.backup_threshold
                 THEN 'BACKUP LATE'
            ELSE 'OK'
        END                                                    AS verdict
    FROM msdb.dbo.log_shipping_monitor_primary AS p

    UNION ALL

    SELECT
        'SECONDARY',
        s.secondary_server,
        s.secondary_database,
        s.primary_server + '.' + s.primary_database,
        NULL,
        NULL,
        NULL,
        s.last_copied_date,
        DATEDIFF(MINUTE, s.last_copied_date, GETDATE()),
        s.last_restored_date,
        DATEDIFF(MINUTE, s.last_restored_date, GETDATE()),
        s.restore_threshold,
        CASE
            WHEN s.last_restored_date IS NULL THEN 'NOTHING RESTORED YET'
            -- copy current but restore stale: the restore job is the failure, not the network
            WHEN DATEDIFF(MINUTE, s.last_restored_date, GETDATE()) > s.restore_threshold
                 AND DATEDIFF(MINUTE, s.last_copied_date, GETDATE()) <= s.restore_threshold
                 THEN 'RESTORE JOB BEHIND (copy is current)'
            -- both stale: the problem is upstream of the restore
            WHEN DATEDIFF(MINUTE, s.last_restored_date, GETDATE()) > s.restore_threshold
                 THEN 'BEHIND - copy is stale too, check the backup job and the share'
            ELSE 'OK'
        END
    FROM msdb.dbo.log_shipping_monitor_secondary AS s
    ORDER BY role, database_name;

END
