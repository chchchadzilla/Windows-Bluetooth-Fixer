#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Bluetooth Fixer - command line.
.EXAMPLE
    .\BluetoothFixer.CLI.ps1                      # diagnose only
    .\BluetoothFixer.CLI.ps1 -Fix Recommended     # diagnose, then apply the recommended fixes (asks first)
    .\BluetoothFixer.CLI.ps1 -Fix F01,F02 -Yes    # specific fixes, no prompts
    .\BluetoothFixer.CLI.ps1 -Report              # also write the HTML/JSON report
    .\BluetoothFixer.CLI.ps1 -Json                # machine-readable findings on stdout
#>
[CmdletBinding()]
param(
    [string[]]$Fix,
    [switch]$Report,
    [switch]$Json,
    [switch]$Yes,
    [switch]$Verify,
    [int]$Days = 30,
    [switch]$ListFixes
)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'BluetoothFixer.psm1') -Force

if ($ListFixes) { Get-BFFixCatalog | Format-Table Id, Name, Risk, NeedsAdmin -AutoSize; return }

Start-BFLogFile | Out-Null
$colors = @{ Critical = 'Red'; Warning = 'Yellow'; Info = 'Cyan'; OK = 'Green' }
if (-not $Json) {
    Write-Host ''
    Write-Host '  Windows Bluetooth Fixer' -ForegroundColor White
    Write-Host '  ------------------------' -ForegroundColor DarkGray
    if (-not (Test-BFAdmin)) { Write-Host '  Not elevated: diagnosis only. Run as administrator to apply fixes.' -ForegroundColor Yellow }
    Set-BFLogSink -Sink ([System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))) -Progress { param($p, $t) Write-Host ("  [{0,3}%] {1}" -f $p, $t) -ForegroundColor DarkGray }
}

$d = Invoke-BFDiagnosis -TimelineDays $Days

if ($Json) { $d | Select-Object Version, Time, Summary, Findings, @{ n = 'Radios'; e = { $_.Inventory.Radios } }, @{ n = 'Services'; e = { $_.Services.Rows } }, Links | ConvertTo-Json -Depth 6; if (-not $Fix) { return } }
else {
    $e = $d.Environment
    Write-Host ''
    Write-Host ("  {0} {1}  |  {2} {3} build {4}.{5}  |  Wi-Fi: {6}" -f $e.Manufacturer, $e.Model, $e.OSName, $e.DisplayVersion, $e.Build, $e.UBR, $d.Inventory.WifiName) -ForegroundColor Gray
    $vc = if ($d.Summary.CriticalCount) { 'Red' } else { 'Green' }
    Write-Host ("  VERDICT: {0} - {1}" -f $d.Summary.Verdict, $d.Summary.Headline) -ForegroundColor $vc
    Write-Host ''
    foreach ($f in $d.Findings) {
        Write-Host ("  [{0,-8}] {1}" -f $f.Severity, $f.Title) -ForegroundColor $colors[$f.Severity]
        Write-Host ("             {0}" -f $f.Detail) -ForegroundColor Gray
        foreach ($ev in ($f.Evidence | Select-Object -First 6)) { Write-Host ("               - {0}" -f $ev) -ForegroundColor DarkGray }
        if ($f.Fixes.Count) { Write-Host ("             fixes: {0}" -f ($f.Fixes -join ', ')) -ForegroundColor DarkCyan }
    }
    Write-Host ''
    Write-Host '  Radios:' -ForegroundColor White
    if ($d.Inventory.Radios.Count -eq 0) { Write-Host '    (none, present or ghost)' -ForegroundColor DarkGray }
    foreach ($r in $d.Inventory.Radios) { Write-Host ("    {0,-7} present={1,-5} problem={2,-3} {3}  {4} {5} {6}" -f $r.Role, $r.Present, $r.ProblemCode, $r.ChipName, $r.InfPath, $r.DriverVersion, $r.InstanceId) -ForegroundColor $(if ($r.Present -and $r.ProblemCode -eq 0) { 'Green' } elseif ($r.Present) { 'Red' } else { 'DarkGray' }) }
    Write-Host ''
    Write-Host '  Where to get drivers:' -ForegroundColor White
    foreach ($l in $d.Links) { if ($l.Url) { Write-Host ("    {0}: {1}`n      {2}" -f $l.Group, $l.Label, $l.Url) -ForegroundColor Gray } else { Write-Host ("    {0}: {1}" -f $l.Group, $l.Label) -ForegroundColor Gray } }
    Write-Host ''
}

$results = $null
if ($Fix) {
    $ids = @()
    if ($Fix -contains 'Recommended') { $ids = @(Get-BFRecommendedFixes -Diagnosis $d | Where-Object { $_ -notin 'F17','F16','F14','F09','F18','F15','F20' }) }
    elseif ($Fix -contains 'Safe') { $ids = @(Get-BFRecommendedFixes -Diagnosis $d | Where-Object { $i = $_; (Get-BFFixCatalog | Where-Object Id -eq $i).Risk -eq 'Safe' -and $i -notin 'F09','F18','F15','F20' }) }
    else { $ids = @($Fix | ForEach-Object { $_.ToUpper() }) }
    if ($ids.Count -eq 0) { Write-Host '  Nothing to fix.' -ForegroundColor Green }
    else {
        Write-Host '  Fix plan:' -ForegroundColor White
        foreach ($i in $ids) { $c = Get-BFFixCatalog | Where-Object Id -eq $i; Write-Host ("    {0}  {1,-45} [{2}]" -f $i, $c.Name, $c.Risk) -ForegroundColor Cyan }
        $go = $Yes
        if (-not $go) { $a = Read-Host '  Apply these fixes? (y/N)'; $go = ($a -match '^y') }
        if ($go) {
            $results = Invoke-BFFixPlan -FixIds $ids -Diagnosis $d -ConfirmReboot:$Yes
            Write-Host ''
            foreach ($r in $results) { $c = Get-BFFixCatalog | Where-Object Id -eq $r.Id; $col = if ($r.Success) { 'Green' } elseif ($r.Skipped) { 'Yellow' } else { 'Red' }; Write-Host ("  {0} {1}: {2}" -f $r.Id, $c.Name, $r.Message) -ForegroundColor $col }
            if (($results | Where-Object RebootRequired) -and -not ($results | Where-Object { $_.Id -eq 'F17' })) { Write-Host "`n  A reboot is required to finish. Run with -Fix F17 -Yes to reboot and verify automatically." -ForegroundColor Yellow }
            Write-Host "`n  Re-checking..." -ForegroundColor DarkGray
            $d2 = Invoke-BFDiagnosis -TimelineDays 3
            $vc = if ($d2.Summary.CriticalCount) { 'Red' } else { 'Green' }
            Write-Host ("  AFTER FIX: {0} - {1}" -f $d2.Summary.Verdict, $d2.Summary.Headline) -ForegroundColor $vc
            $d = $d2
        }
    }
}

if ($Report -or $Verify) {
    $p = Export-BFReport -Diagnosis $d -FixResults $results
    Write-Host "  Report: $p" -ForegroundColor White
    if ($Report) { try { Start-Process $p } catch { } }
}
