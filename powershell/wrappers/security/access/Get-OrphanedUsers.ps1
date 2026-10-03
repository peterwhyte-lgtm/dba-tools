<#
.SYNOPSIS
Finds database users whose SID matches no server login, across every online database.

.NOTES
ScriptType   : hybrid
TargetScope  : single server (iterates every online database, tempdb excluded)
RiskLevel    : SAFE
Purpose      : Detect orphaned accounts that cause silent login failures, common after migrations.

.DESCRIPTION
Wrapper for the Get-OrphanedUsers SQL query. Iterates every online database the account can
open (tempdb excluded) and returns accounts where the SID has no matching entry in
sys.server_principals. Users created WITHOUT LOGIN and contained database users are excluded,
they have no server login by design and are not orphans.

Fix orphans with: ALTER USER [username] WITH LOGIN = [login_name];

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\security\Get-OrphanedUsers.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\security\Get-OrphanedUsers.ps1 -OutputFormat Csv -OutputPath .\output-files\orphaned-users.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\security\access\Get-OrphanedUsers.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running orphaned users review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
