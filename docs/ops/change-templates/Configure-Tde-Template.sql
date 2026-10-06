/*
Change Order / DBA Runbook: Configure TDE

Purpose:
  Enable Transparent Data Encryption for a target database using a documented, repeatable process.
Business impact:
  Protects database files at rest and supports compliance and security requirements.
Pre-checks:
  1. Confirm the SQL Server service account and backup plan for the certificate/private key.
  2. Confirm the DBA has CONTROL SERVER and CREATE ANY DATABASE permissions.
  3. Verify storage paths for the certificate and private key backups.
Execution notes:
  - Replace placeholder values before execution (find and replace each one, every occurrence):
      YourDatabase, TDE_Certificate_YourDatabase, StrongMasterKeyPassword!,
      C:\SQLBackups\TDE\YourDatabase_Cert.cer, C:\SQLBackups\TDE\YourDatabase_Cert_PrivateKey.pvk
    CREATE MASTER KEY, BACKUP CERTIFICATE and ENCRYPTION BY PASSWORD accept literals only, not variables.
  - Run the master database section first, then the target database section.
Validation:
  - Confirm the database encryption state and encryption progress after the change.
Rollback:
  - Revert encryption only after confirming a valid backup and approved security procedure.
*/
-- SAFE:CreatesObjects
-- IMPACT:High

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Run the following section in master.
USE [master];
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'StrongMasterKeyPassword!';
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'TDE_Certificate_YourDatabase')
BEGIN
    CREATE CERTIFICATE [TDE_Certificate_YourDatabase]
        WITH SUBJECT = N'TDE Certificate for YourDatabase';
END;
GO

BACKUP CERTIFICATE [TDE_Certificate_YourDatabase]
TO FILE = N'C:\SQLBackups\TDE\YourDatabase_Cert.cer'
WITH PRIVATE KEY (
    FILE = N'C:\SQLBackups\TDE\YourDatabase_Cert_PrivateKey.pvk',
    ENCRYPTION BY PASSWORD = N'StrongMasterKeyPassword!'
);
GO

-- Run the following section in the target database.
USE [YourDatabase];
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
BEGIN
    CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE [TDE_Certificate_YourDatabase];
END;
GO

ALTER DATABASE [YourDatabase] SET ENCRYPTION ON;
GO

SELECT
    d.name AS database_name,
    d.is_encrypted,
    dek.encryption_state_desc,
    dek.percent_complete,
    dek.encryptor_type
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON dek.database_id = d.database_id
WHERE d.database_id = DB_ID();
