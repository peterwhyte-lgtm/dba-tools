<#
.SYNOPSIS
Runs the database free space summary query against every online database the caller can enter.

.NOTES
ScriptType   : runner
TargetScope  : single server, every online database the caller can enter
RiskLevel    : SAFE
Purpose      : Show allocated, used, and free space per database, split into data and log, ordered
               by lowest total free percentage first. Needs VIEW SERVER STATE for DBCC SQLPERF
               and fails without it; databases it cannot enter are skipped with no row.
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\monitoring\disk-space\Get-DatabaseFreeSpaceSummary.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running database free space summary...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
