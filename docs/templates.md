# Script templates

Starting points for new scripts. See `docs/standards.md` for the full rules and `tools/scaffolding/New-Wrapper.ps1` to generate a wrapper automatically.

---

## SQL diagnostic script

```sql
/*
Script Name : Get-Something
Category    : performance
Purpose     : One-line description of what this returns.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    -- query here
```

`-- SAFE:` values: `ReadOnly` / `WritesData` / `CreatesObjects`  
`-- IMPACT:` values: `Low` / `Medium` / `High`

Add `HealthCheck : Yes` (after `Requires`) if this script belongs in the daily healthcheck suite.

---

## PowerShell wrapper

Wrappers sit at `powershell/wrappers/<category>/` — three levels from root.

```powershell
<#
.SYNOPSIS
One-line description matching the SQL script Purpose.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : One-line description.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\<category>\Get-Something.ps1

.EXAMPLE
.\powershell\wrappers\<category>\Get-Something.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\<category>\Get-Something.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
```

Use `.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\Get-Something.sql` to generate this automatically.

---

## PowerShell orchestrator

Orchestrators sit at `powershell/<subfolder>/` — two levels from root. Use when real logic is needed beyond "run the SQL file."

```powershell
<#
.SYNOPSIS
One-line description.

.NOTES
ScriptType   : automation
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : One-line description.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.
#>

param(
    [string]$ServerInstance = '.'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
# ... orchestration logic here
```
