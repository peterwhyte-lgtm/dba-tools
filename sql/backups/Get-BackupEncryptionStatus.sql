/*
Script Name : Get-BackupEncryptionStatus
Category    : backups
Purpose     : Shows TDE status and backup encryption coverage per database. Identifies
              databases with no recent full backup, and databases where neither TDE
              nor backup encryption protects the backup files.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-encryption-status/)
Requires    : VIEW DATABASE STATE; VIEW SERVER STATE for sys.dm_database_encryption_keys
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Joins sys.databases → sys.dm_database_encryption_keys (TDE state) →
  msdb.dbo.backupset (last 30 days). The key_algorithm and encryptor_thumbprint columns
  in backupset are populated when backup encryption was used (SQL 2014+).
  A database can have TDE without encrypted backups, or encrypted backups without TDE.
  Neither is automatically wrong — the report surfaces the combination so you can assess.
*/

SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    CASE d.is_encrypted WHEN 1 THEN 'Yes' ELSE 'No' END AS tde_enabled,
    dek.encryption_state_desc AS tde_state,
    dek.encryptor_type AS tde_encryptor_type,
    -- Most recent full backup (last 30 days)
    MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END) AS last_full_backup,
    -- Was the most recent full backup encrypted?
    MAX(CASE bs.type WHEN 'D' THEN bs.key_algorithm END) AS backup_encryption_algorithm,
    MAX(CASE bs.type WHEN 'D'
         THEN SUBSTRING(CONVERT(varchar(max), bs.encryptor_thumbprint, 2), 1, 16)
         ELSE NULL END) AS backup_encryptor_thumbprint_prefix,
    -- Assessment. A TDE database's backup files are encrypted by its TDE key, so TDE without backup encryption is
    -- covered, not a gap; the risk is losing the TDE certificate. The missing-backup check comes first so a TDE
    -- database with no recent backup is reported as that.
    CASE
        WHEN MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END) IS NULL
            THEN 'WARN - no full backup in last 30 days'
        WHEN d.is_encrypted = 1
             AND MAX(CASE bs.type WHEN 'D' THEN bs.key_algorithm END) IS NOT NULL
            THEN 'OK - TDE and backup encryption'
        WHEN d.is_encrypted = 1
            THEN 'OK - TDE (backup file encrypted by the TDE key)'
        WHEN MAX(CASE bs.type WHEN 'D' THEN bs.key_algorithm END) IS NOT NULL
            THEN 'OK - backup encryption (data files not TDE)'
        ELSE 'INFO - no TDE or backup encryption'
    END AS encryption_status
FROM sys.databases d
LEFT JOIN sys.dm_database_encryption_keys dek
    ON dek.database_id = d.database_id
LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name
   AND bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE())
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'
GROUP BY
    d.name,
    d.recovery_model_desc,
    d.is_encrypted,
    dek.encryption_state_desc,
    dek.encryptor_type
ORDER BY
    CASE
        WHEN d.is_encrypted = 1
             AND MAX(CASE bs.type WHEN 'D' THEN bs.key_algorithm END) IS NULL THEN 1
        ELSE 2
    END,
    d.name;
