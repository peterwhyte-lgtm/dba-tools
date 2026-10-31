<#
.SYNOPSIS
Show patch status for all SQL Server instances and SSMS on this machine.

.DESCRIPTION
Detects all installed SQL Server instances, queries their version, maps the build
number to a known CU level, and displays SSMS version alongside patch log history.

.EXAMPLE
.\admin\patching\patch-summary.ps1

.NOTES
RiskLevel   : SAFE - reports installed versions and patch state; changes nothing
#>

$ErrorActionPreference = 'SilentlyContinue'

# -- Known build -> CU mapping (update as new CUs release) --------------------
# Source: https://support.microsoft.com/en-us/help/321185
$cuMap = @{
    # SQL Server 2025 (17.x)
    '17.0.1000.7'  = 'SQL 2025 RTM'
    '17.0.4006.2'  = 'SQL 2025 CU1'
    '17.0.4015.4'  = 'SQL 2025 CU2'
    '17.0.4020.2'  = 'SQL 2025 CU2 + GDR'
    '17.0.4025.3'  = 'SQL 2025 CU3'
    '17.0.4030.1'  = 'SQL 2025 CU3 + GDR'
    '17.0.4035.5'  = 'SQL 2025 CU4'
    '17.0.4040.1'  = 'SQL 2025 CU4 + GDR'
    '17.0.4045.5'  = 'SQL 2025 CU5'
    '17.0.4055.5'  = 'SQL 2025 CU6'
    '17.0.4060.2'  = 'SQL 2025 CU6 + GDR'
    '17.0.4065.4'  = 'SQL 2025 CU7'
    '17.0.4075.5'  = 'SQL 2025 CU8'
    '17.0.4085.5'  = 'SQL 2025 CU8 + GDR'
    '17.0.5005.3'  = 'SQL 2025 CU9'
    '17.0.5015.4'  = 'SQL 2025 CU9 + GDR'
    '17.0.5035.5'  = 'SQL 2025 CU10'
    '17.0.1125.2'  = 'SQL 2025 GDR (Jul 2026)'
    '17.0.1135.8'  = 'SQL 2025 GDR (Sep 2026)'
    '17.0.1145.4'  = 'SQL 2025 GDR (Oct 2026)'
    # SQL Server 2022 (16.x)
    '16.0.1000.6'  = 'SQL 2022 RTM'
    '16.0.4003.1'  = 'SQL 2022 CU1'
    '16.0.4015.1'  = 'SQL 2022 CU2'
    '16.0.4025.1'  = 'SQL 2022 CU3'
    '16.0.4035.4'  = 'SQL 2022 CU4'
    '16.0.4045.3'  = 'SQL 2022 CU5'
    '16.0.4055.4'  = 'SQL 2022 CU6'
    '16.0.4065.3'  = 'SQL 2022 CU7'
    '16.0.4075.1'  = 'SQL 2022 CU8'
    '16.0.4085.2'  = 'SQL 2022 CU9'
    '16.0.4095.4'  = 'SQL 2022 CU10'
    '16.0.4105.2'  = 'SQL 2022 CU11'
    '16.0.4115.5'  = 'SQL 2022 CU12'
    '16.0.4125.3'  = 'SQL 2022 CU13'
    '16.0.4135.4'  = 'SQL 2022 CU14'
    '16.0.4145.4'  = 'SQL 2022 CU15'
    '16.0.4165.4'  = 'SQL 2022 CU16'
    '16.0.4175.1'  = 'SQL 2022 CU17'
    '16.0.4185.3'  = 'SQL 2022 CU18'
    '16.0.4195.2'  = 'SQL 2022 CU19'
    '16.0.4205.1'  = 'SQL 2022 CU20'
    '16.0.4215.2'  = 'SQL 2022 CU21'
    '16.0.4225.2'  = 'SQL 2022 CU22'
    '16.0.4236.2'  = 'SQL 2022 CU23'
    '16.0.4245.2'  = 'SQL 2022 CU24'
    '16.0.4255.1'  = 'SQL 2022 CU25'
    '16.0.4265.3'  = 'SQL 2022 CU26'
    '16.0.4275.2'  = 'SQL 2022 CU26 + GDR'
    '16.0.4295.3'  = 'SQL 2022 CU27'
    '16.0.4305.5'  = 'SQL 2022 CU27 + GDR'
    '16.0.1200.5'  = 'SQL 2022 GDR (Sep 2026)'
    '16.0.1210.3'  = 'SQL 2022 GDR (Oct 2026)'
    # SQL Server 2019 (15.x)
    '15.0.2000.5'  = 'SQL 2019 RTM'
    '15.0.4003.23' = 'SQL 2019 CU1'
    '15.0.4013.40' = 'SQL 2019 CU2'
    '15.0.4023.6'  = 'SQL 2019 CU3'
    '15.0.4033.1'  = 'SQL 2019 CU4'
    '15.0.4043.16' = 'SQL 2019 CU5'
    '15.0.4053.23' = 'SQL 2019 CU6'
    '15.0.4063.15' = 'SQL 2019 CU7'
    '15.0.4073.23' = 'SQL 2019 CU8'
    '15.0.4083.2'  = 'SQL 2019 CU8 + GDR'
    '15.0.4102.2'  = 'SQL 2019 CU9'
    '15.0.4123.1'  = 'SQL 2019 CU10'
    '15.0.4138.2'  = 'SQL 2019 CU11'
    '15.0.4153.1'  = 'SQL 2019 CU12'
    '15.0.4178.1'  = 'SQL 2019 CU13'
    '15.0.4188.2'  = 'SQL 2019 CU14'
    '15.0.4198.2'  = 'SQL 2019 CU15'
    '15.0.4223.1'  = 'SQL 2019 CU16'
    '15.0.4249.2'  = 'SQL 2019 CU17'
    '15.0.4261.1'  = 'SQL 2019 CU18'
    '15.0.4298.1'  = 'SQL 2019 CU19'
    '15.0.4312.2'  = 'SQL 2019 CU20'
    '15.0.4316.3'  = 'SQL 2019 CU21'
    '15.0.4322.2'  = 'SQL 2019 CU22'
    '15.0.4335.1'  = 'SQL 2019 CU23'
    '15.0.4345.5'  = 'SQL 2019 CU24'
    '15.0.4355.3'  = 'SQL 2019 CU25'
    '15.0.4365.2'  = 'SQL 2019 CU26'
    '15.0.4375.4'  = 'SQL 2019 CU27'
    '15.0.4385.2'  = 'SQL 2019 CU28'
    '15.0.4405.4'  = 'SQL 2019 CU29'
    '15.0.4415.2'  = 'SQL 2019 CU30'
    '15.0.4420.2'  = 'SQL 2019 CU31'
    '15.0.4430.1'  = 'SQL 2019 CU32'
    '15.0.4490.9'  = 'SQL 2019 CU32 + GDR'
    '15.0.4500.2'  = 'SQL 2019 CU32 + GDR'
    '15.0.2190.7'  = 'SQL 2019 GDR (Sep 2026)'
    '15.0.2200.2'  = 'SQL 2019 GDR (Oct 2026)'
    # SQL Server 2017 (14.x)
    '14.0.1000.169'= 'SQL 2017 RTM'
    '14.0.3006.16' = 'SQL 2017 CU1'
    '14.0.3257.3'  = 'SQL 2017 CU18'
    '14.0.3356.20' = 'SQL 2017 CU22'
    '14.0.3456.2'  = 'SQL 2017 CU31'
    '14.0.3460.9'  = 'SQL 2017 CU31 + GDR'
    '14.0.3490.10' = 'SQL 2017 Azure Connect Pack'
    '14.0.3550.4'  = 'SQL 2017 CU31 + GDR'
    '14.0.3560.2'  = 'SQL 2017 CU31 + GDR'
    '14.0.2130.4'  = 'SQL 2017 GDR (Sep 2026)'
    '14.0.2140.2'  = 'SQL 2017 GDR (Oct 2026)'
    # SQL Server 2016 (13.x)
    '13.0.6300.2'  = 'SQL 2016 SP3'
    '13.0.6419.1'  = 'SQL 2016 SP3 + GDR'
}

# Latest build on the CU train per major version: the newest CU, or the newest
# CU + GDR on top of it where that is the higher build. An instance at or above this
# build reports 'current'. Update alongside the CU map each patch cycle.
# Source: https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2025/build-versions
# (and the 2022/2019/2017 equivalents), checked 2026-10-31.
$latestBuild = @{
    17 = '17.0.5035.5'   # SQL 2025 CU10 (KB5125471)
    16 = '16.0.4305.5'   # SQL 2022 CU27 + GDR (KB5126934)
    15 = '15.0.4500.2'   # SQL 2019 CU32 + GDR (KB5128494)
    14 = '14.0.3560.2'   # SQL 2017 CU31 + GDR (KB5128496)
}

function Get-CuLabel([string]$version) {
    if ($cuMap.ContainsKey($version)) { return $cuMap[$version] }
    # Nearest known build at or below this one on the same major.minor, so an
    # unlisted build is never labelled with a newer update than it has.
    $parts = $version -split '\.'
    if ($parts.Count -ge 2) {
        $prefix = "$($parts[0]).$($parts[1])"
        $match  = $cuMap.Keys | Where-Object { $_ -like "$prefix.*" -and [version]$_ -le [version]$version } |
                  Sort-Object { [version]$_ } -Descending | Select-Object -First 1
        if ($match) { return "$($cuMap[$match]) (near)" }
    }
    return 'Unknown build'
}

Write-Host ""
Write-Host "  SQL Server Patch Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-', 70)) -ForegroundColor DarkCyan

# -- SQL Server instances -----------------------------------------------------
Write-Host ""
Write-Host "  SQL Server Instances" -ForegroundColor Cyan

$regPath   = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
$instances = @()
if (Test-Path $regPath) {
    $instances = Get-ItemProperty $regPath |
        Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name
}

if ($instances.Count -eq 0) {
    Write-Host "  No SQL Server instances found." -ForegroundColor Yellow
} else {
    foreach ($inst in ($instances | Sort-Object)) {
        $srv = if ($inst -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$inst" }
        try {
            $row = Invoke-Sqlcmd -ServerInstance $srv `
                       -Query "SELECT SERVERPROPERTY('ProductVersion') AS pv, SERVERPROPERTY('Edition') AS ed" `
                       -QueryTimeout 8 -TrustServerCertificate -ErrorAction Stop
            $ver   = $row.pv
            $ed    = $row.ed
            $label = Get-CuLabel $ver
            Write-Host ("  {0,-25} {1,-16} {2,-22} {3}  " -f $inst, $ver, $label, $ed) -ForegroundColor White -NoNewline
            $major = [int]($ver -split '\.')[0]
            if ($latestBuild.ContainsKey($major)) {
                if ([version]$ver -ge [version]$latestBuild[$major]) {
                    Write-Host 'current' -ForegroundColor Green
                } else {
                    Write-Host 'BEHIND' -ForegroundColor Red -NoNewline
                    Write-Host (" -> $($latestBuild[$major])") -ForegroundColor Yellow
                }
            } else { Write-Host '' }
        } catch {
            Write-Host ("  {0,-25} {1}" -f $inst, "(could not connect)") -ForegroundColor Yellow
        }
    }
}

# -- SSMS ---------------------------------------------------------------------
Write-Host ""
Write-Host "  SSMS" -ForegroundColor Cyan

$ssmsFound = $false
# Latest released SSMS - update alongside the CU map each patch cycle.
# Source: https://learn.microsoft.com/en-us/ssms/release-notes-22 (22.11.3, released 2026-10-29; checked 2026-10-31)
$ssmsLatest = '22.11.3'
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($p in $paths) {
    $ssms = Get-ItemProperty $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' } |
        Select-Object -First 1
    if ($ssms) {
        $behind = $false
        Write-Host ("  {0,-35} v{1,-10} " -f $ssms.DisplayName, $ssms.DisplayVersion) -ForegroundColor White -NoNewline
        try {
            if ([version]$ssms.DisplayVersion -ge [version]$ssmsLatest) {
                Write-Host 'current' -ForegroundColor Green
            } else {
                Write-Host 'BEHIND' -ForegroundColor Red -NoNewline
                Write-Host " -> $ssmsLatest" -ForegroundColor Yellow
                $behind = $true
            }
        } catch { Write-Host '' }
        if ($behind) {
            Write-Host "    Scripted update: .\powershell\patching\ssms\install-ssms.ps1" -ForegroundColor DarkCyan
            Write-Host "    Guide: https://sqldba.blog/dba-scripts-install-and-update-ssms-via-powershell/" -ForegroundColor DarkCyan
        }
        $ssmsFound = $true; break
    }
}
if (-not $ssmsFound) {
    Write-Host "  SSMS not detected on this machine." -ForegroundColor Yellow
}

# -- Recent patch log activity ------------------------------------------------
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$patchLogs = Get-ChildItem (Join-Path $repoRoot 'output-files\patches') `
                 -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '*.stdout' -and $_.Name -notlike '*.stderr' } |
             Sort-Object LastWriteTime -Descending | Select-Object -First 5

if ($patchLogs) {
    Write-Host ""
    Write-Host "  Recent patch activity (last 5 logs):" -ForegroundColor Cyan
    foreach ($log in $patchLogs) {
        $outcome = 'Unknown'
        $whatIf  = $false
        foreach ($line in (Get-Content $log.FullName -ErrorAction SilentlyContinue)) {
            # Check failed/cancelled first so a trailing 'Done.' line cannot override them
            if ($line -match 'FAILED|ERROR:')            { $outcome = 'Failed';    break }
            if ($line -match 'cancelled')                { $outcome = 'Cancelled'; break }
            if ($line -match '\[WhatIf')                 { $whatIf  = $true }
            if ($line -match '\bWouldPatch\b')           { $outcome = 'Preview - patch needed' }
            if ($line -match '\bUpToDate\b')             { $outcome = 'Preview - up to date' }
            if ($line -match 'succeeded|complete|Done')  { $outcome = 'Success' }
        }
        if ($outcome -eq 'Unknown' -and $whatIf) { $outcome = 'Preview (WhatIf)' }
        $color = switch -Wildcard ($outcome) { 'Success'{'Green'} 'Failed'{'Red'} 'Preview*'{'Cyan'} default{'Yellow'} }
        Write-Host ("  {0}  {1,-40} {2}" -f $log.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $log.Name, $outcome) -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "  CU download catalog: https://support.microsoft.com/en-us/help/321185" -ForegroundColor DarkGray
Write-Host "  Note: Build-to-CU map in this script requires manual updates as new CUs release." -ForegroundColor DarkGray
Write-Host ""