#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Bluetooth Fixer - command line.
.EXAMPLE
    .\BluetoothFixer.CLI.ps1                           # diagnose only (works without admin)
    .\BluetoothFixer.CLI.ps1 -Scan                     # diagnose, then run the discovery test (can the radio hear anything?)
    .\BluetoothFixer.CLI.ps1 -Fix Recommended          # diagnose, then apply the recommended fixes (asks first)
    .\BluetoothFixer.CLI.ps1 -DriverPackage .\bt.zip   # install the vendor Bluetooth driver you downloaded, then scan
    .\BluetoothFixer.CLI.ps1 -Fix F01,F02 -Yes         # specific fixes, no prompts
    .\BluetoothFixer.CLI.ps1 -Report                   # also write the HTML/JSON report
    .\BluetoothFixer.CLI.ps1 -Json                     # machine-readable findings on stdout
#>
[CmdletBinding()]
param(
    [string[]]$Fix,
    [string]$DriverPackage,
    [switch]$Scan,
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

function Show-Scan($r) {
    Write-Host ''
    Write-Host '  DISCOVERY TEST (can the radio hear anything?)' -ForegroundColor White
    if ($r.Error) { Write-Host "    Could not run: $($r.Error)" -ForegroundColor Yellow }
    elseif ($r.TimedOut) { Write-Host '    The radio did not finish a scan in time. A healthy radio answers within 10-30 s; this usually means the driver cannot talk to the radio (firmware not loaded).' -ForegroundColor Red }
    elseif ($r.Count -eq 0) { Write-Host '    Heard nothing. Make a phone discoverable next to the PC and try again; if still nothing, the radio is deaf (wrong driver or hardware).' -ForegroundColor Red }
    else {
        Write-Host ("    Heard {0} device(s) in {1}s: the radio works." -f $r.Count, $r.DurationSec) -ForegroundColor Green
        foreach ($dv in ($r.Devices | Select-Object -First 15)) { Write-Host ("      {0,-32} {1,-8} rssi {2,-5} {3}{4}" -f $dv.Name, $dv.Kind, $dv.Rssi, $dv.Address, $(if ($dv.Paired) { '  (paired)' } else { '' })) -ForegroundColor Gray }
    }
}

if ($Json) { $d | Select-Object Version, Time, Summary, FirstStep, Findings, @{ n = 'Radios'; e = { $_.Inventory.Radios } }, @{ n = 'Services'; e = { $_.Services.Rows } }, Links | ConvertTo-Json -Depth 6; if (-not ($Fix -or $DriverPackage -or $Scan)) { return } }
else {
    $e = $d.Environment
    Write-Host ''
    Write-Host ("  {0} {1}  |  {2} {3} build {4}.{5}  |  Wi-Fi: {6}" -f $e.Manufacturer, $e.Model, $e.OSName, $e.DisplayVersion, $e.Build, $e.UBR, $d.Inventory.WifiName) -ForegroundColor Gray
    $vc = if ($d.Summary.CriticalCount) { 'Red' } else { 'Green' }
    Write-Host ("  VERDICT: {0} - {1}" -f $d.Summary.Verdict, $d.Summary.Headline) -ForegroundColor $vc
    Write-Host ''
    # The guided "first thing to try"
    $fs = $d.FirstStep
    if ($fs) {
        $fc = switch ($fs.Situation) { 'Generic' { 'Red' } 'NoDriver' { 'Red' } 'WrongVendor' { 'Red' } 'NoRadio' { 'Yellow' } default { 'Green' } }
        Write-Host '  FIRST THING TO TRY: the right driver on the radio' -ForegroundColor White
        Write-Host ("    {0}" -f $fs.Headline) -ForegroundColor $fc
        Write-Host ("    {0}" -f $fs.Explanation) -ForegroundColor Gray
        if ($fs.Radio) { Write-Host ("    Radio: {0}  |  driver now: {1}  |  hardware ID: {2}" -f $fs.ChipName, $fs.DriverText, $fs.HardwareId) -ForegroundColor DarkGray }
        if ($fs.Situation -in 'Generic', 'NoDriver', 'WrongVendor') {
            if ($fs.StorePackages.Count) { Write-Host ("    A) A vendor package is already in the driver store ({0}): -Fix F07 installs it on the radio." -f (($fs.StorePackages | ForEach-Object Published) -join ', ')) -ForegroundColor Cyan }
            Write-Host '    B) Windows Update (needs internet):  -Fix F08' -ForegroundColor Cyan
            if ($fs.DownloadLink) { Write-Host ("    C) Download the Bluetooth package from your PC/motherboard maker, then:  -DriverPackage <file.zip|.exe|folder>`n       {0}`n       {1}" -f $fs.DownloadLink.Label, $fs.DownloadLink.Url) -ForegroundColor Cyan }
            if ($fs.CatalogLink) { Write-Host ("       Windows Update Catalog: {0}" -f $fs.CatalogLink.Url) -ForegroundColor DarkCyan }
            Write-Host '    Then run with -Scan: hearing any device proves the firmware loaded.' -ForegroundColor Cyan
        }
        Write-Host ''
    }
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
$ids = @()
if ($DriverPackage) { $ids += 'F22' }
if ($Fix) {
    if ($Fix -contains 'Recommended') { $ids += @(Get-BFRecommendedFixes -Diagnosis $d | Where-Object { $_ -notin 'F17', 'F16', 'F14', 'F09', 'F18', 'F15', 'F20', 'F22' }) }
    elseif ($Fix -contains 'Safe') { $ids += @(Get-BFRecommendedFixes -Diagnosis $d | Where-Object { $i = $_; (Get-BFFixCatalog | Where-Object Id -eq $i).Risk -eq 'Safe' -and $i -notin 'F09', 'F18', 'F15', 'F20', 'F22' }) }
    else { $ids += @($Fix | ForEach-Object { $_.ToUpper() }) }
}
$ids = @($ids | Select-Object -Unique)
if ($Fix -or $DriverPackage) {
    if ($ids.Count -eq 0) { Write-Host '  Nothing to fix.' -ForegroundColor Green }
    else {
        if (($ids -contains 'F22') -and -not $DriverPackage) { Write-Host '  F22 needs -DriverPackage <path to the downloaded .zip/.exe/.cab/.inf or folder>.' -ForegroundColor Yellow; $ids = @($ids | Where-Object { $_ -ne 'F22' }) }
        Write-Host '  Fix plan:' -ForegroundColor White
        foreach ($i in $ids) { $c = Get-BFFixCatalog | Where-Object Id -eq $i; Write-Host ("    {0}  {1,-45} [{2}]{3}" -f $i, $c.Name, $c.Risk, $(if ($i -eq 'F22') { "  <- $DriverPackage" } else { '' })) -ForegroundColor Cyan }
        $go = $Yes
        if (-not $go) { $a = Read-Host '  Apply these fixes? (y/N)'; $go = ($a -match '^y') }
        if ($go -and $ids.Count) {
            $results = Invoke-BFFixPlan -FixIds $ids -Diagnosis $d -ConfirmReboot:$Yes -PackagePath $DriverPackage
            Write-Host ''
            foreach ($r in $results) { $c = Get-BFFixCatalog | Where-Object Id -eq $r.Id; $col = if ($r.Success) { 'Green' } elseif ($r.Skipped) { 'Yellow' } else { 'Red' }; Write-Host ("  {0} {1}: {2}" -f $r.Id, $c.Name, $r.Message) -ForegroundColor $col }
            if (($results | Where-Object RebootRequired) -and -not ($results | Where-Object { $_.Id -eq 'F17' })) { Write-Host "`n  A reboot is required to finish. Run with -Fix F17 -Yes to reboot and verify automatically." -ForegroundColor Yellow }
            Write-Host "`n  Re-checking..." -ForegroundColor DarkGray
            $d2 = Invoke-BFDiagnosis -TimelineDays 3
            $vc = if ($d2.Summary.CriticalCount) { 'Red' } else { 'Green' }
            Write-Host ("  AFTER FIX: {0} - {1}" -f $d2.Summary.Verdict, $d2.Summary.Headline) -ForegroundColor $vc
            if ($d2.FirstStep) { Write-Host ("  Driver now: {0}" -f $d2.FirstStep.Headline) -ForegroundColor $(if ($d2.FirstStep.Verified) { 'Green' } else { 'Yellow' }) }
            $d = $d2
            if ($d.Summary.RadioPresent) { $Scan = $true }   # prove it
        }
    }
}

if ($Scan -and $d.Summary.RadioPresent) {
    $d.Scan = Test-BFDiscovery -TimeoutSec 45
    if ($Json) { $d.Scan | ConvertTo-Json -Depth 4 } else { Show-Scan $d.Scan }
} elseif ($Scan -and -not $Json) {
    Write-Host '  No radio is present, so there is nothing to scan with.' -ForegroundColor Yellow
}

if ($Report -or $Verify) {
    $p = Export-BFReport -Diagnosis $d -FixResults $results
    Write-Host "  Report: $p" -ForegroundColor White
    if ($Report) { try { Start-Process $p } catch { } }
}
