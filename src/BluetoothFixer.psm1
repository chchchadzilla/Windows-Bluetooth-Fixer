#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Bluetooth Fixer - diagnostic and repair engine.
.DESCRIPTION
    Finds out WHY Bluetooth is broken on a Windows 10/11 PC and repairs it.
    Every finding carries evidence and maps to one or more fixes. Every fix is
    logged, backed up where it changes state, and verified afterwards.

    Nothing in this module ever removes a USB root hub, a host controller or
    any other protected device. That is the exact mistake it exists to undo.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Module state
# ---------------------------------------------------------------------------
$script:BFRoot     = Split-Path -Parent $PSCommandPath
$script:KB         = Import-PowerShellDataFile -Path (Join-Path $script:BFRoot 'BluetoothFixer.Data.psd1')
$script:BFVersion  = '1.0.1'
$script:BFLog      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$script:BFLogSink  = $null
$script:BFLogFile  = $null
$script:BFDataDir  = Join-Path $env:ProgramData 'BluetoothFixer'
$script:BFUserDir  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'BluetoothFixer'
$script:BFProgress = $null   # scriptblock(percent, text)

foreach ($d in @($script:BFDataDir, (Join-Path $script:BFDataDir 'Backups'), (Join-Path $script:BFDataDir 'Logs'), $script:BFUserDir, (Join-Path $script:BFUserDir 'Reports'))) {
    if (-not (Test-Path $d)) { try { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null } catch { } }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Set-BFLogSink {
    <# Attach a synchronized ArrayList that receives every log line (used by the GUI). #>
    param([System.Collections.ArrayList]$Sink, [scriptblock]$Progress)
    $script:BFLogSink = $Sink
    if ($Progress) { $script:BFProgress = $Progress }
}

function Write-BFLog {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR','OK','STEP','DEBUG')][string]$Level = 'INFO')
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    [void]$script:BFLog.Add($line)
    if ($script:BFLogSink -ne $null) { try { [void]$script:BFLogSink.Add($line) } catch { } }
    if ($script:BFLogFile) { try { Add-Content -Path $script:BFLogFile -Value $line -ErrorAction SilentlyContinue } catch { } }
    if ($Level -ne 'DEBUG') { Write-Verbose $line }
}

function Start-BFLogFile {
    $script:BFLogFile = Join-Path (Join-Path $script:BFDataDir 'Logs') ('BluetoothFixer-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try { Set-Content -Path $script:BFLogFile -Value ('Windows Bluetooth Fixer {0} - log started {1}' -f $script:BFVersion, (Get-Date)) -ErrorAction Stop } catch { $script:BFLogFile = $null }
    return $script:BFLogFile
}

function Get-BFLog { return @($script:BFLog) }

function Report-BFProgress {
    param([int]$Percent, [string]$Text)
    if ($script:BFProgress) { try { & $script:BFProgress $Percent $Text } catch { } }
    Write-BFLog -Level STEP -Message $Text
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function Test-BFAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BFKB { return $script:KB }

function Get-BFDevProp {
    <# Fetch several device properties in one call. Returns hashtable KeyName -> Data. #>
    param([Parameter(Mandatory)][string]$InstanceId, [Parameter(Mandatory)][string[]]$Keys)
    $h = @{}
    try {
        Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $Keys -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Type -ne 'Empty') { $h[$_.KeyName] = $_.Data }
        }
    } catch { }
    return $h
}

function Test-BFProtectedDevice {
    param([string]$InstanceId)
    foreach ($pat in $script:KB.ProtectedDevicePatterns) { if ($InstanceId -match $pat) { return $true } }
    return $false
}

function Invoke-BFPnpUtil {
    <# Runs pnputil and returns @{ExitCode; Output}. #>
    param([Parameter(Mandatory)][string[]]$Arguments, [int]$TimeoutSec = 120)
    $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    Write-BFLog -Level DEBUG -Message ("pnputil {0}" -f ($Arguments -join ' '))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pnputil
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch { }; return @{ ExitCode = -1; Output = 'pnputil timed out' } }
    $text = ($out + "`n" + $err).Trim()
    return @{ ExitCode = $p.ExitCode; Output = $text }
}

function Get-BFRawFileVersion {
    <# Reads the binary's fixed version block (the FileVersion string can come from a stale MUI file). #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $v = (Get-Item $Path).VersionInfo
    return ('{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart)
}

function ConvertTo-BFHtmlText { param([string]$s) if ($null -eq $s) { return '' }; return [System.Net.WebUtility]::HtmlEncode($s) }

function Get-BFProblemText {
    param([int]$Code)
    $pc = $script:KB.ProblemCodes[$Code]
    if ($pc) { return $pc.Text }
    return "Problem code $Code."
}

function Get-BFNtStatusText {
    param($Status)
    if ($null -eq $Status) { return '' }
    $hex = '0x{0:X8}' -f ([uint32]([int64]$Status -band 0xFFFFFFFF))
    $t = $script:KB.NtStatus[$hex]
    if ($t) { return "$hex ($t)" }
    return $hex
}

function Get-BFVidPid {
    param([string]$Text)
    if ($Text -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') { return @{ Vid = $Matches[1].ToUpper(); Pid = $Matches[2].ToUpper() } }
    return $null
}

function Get-BFChipName {
    param([string]$Vid, [string]$Pid, [string]$BusDesc, [string]$WifiName)
    $kb = $script:KB
    $vendor = $kb.UsbVendors[$Vid]
    $chip = $null
    if ($Vid -eq '8087' -or $Vid -eq '8086') {
        $n = $kb.IntelPids[$Pid]; if ($n) { $chip = "Intel $n Bluetooth" } else { $chip = "Intel Bluetooth (PID $Pid)" }
    } elseif ($Vid -eq '0BDA') {
        $n = $kb.RealtekPids[$Pid]; if ($n) { $chip = "Realtek $n Bluetooth" } else { $chip = "Realtek Bluetooth (PID $Pid)" }
    } elseif ($vendor) {
        $chip = "$($vendor.Name) Bluetooth (PID $Pid)"
    } else {
        $chip = "Bluetooth radio VID $Vid PID $Pid"
    }
    if ($BusDesc -and $BusDesc -notmatch '^(USB|Bluetooth|Wireless)') { $chip += " [$BusDesc]" }
    return $chip
}

function Get-BFChipVendorKey {
    <# Best chip vendor guess: from the USB VID, and if that is a module maker, from the Wi-Fi adapter name / bus description. #>
    param([string]$Vid, [string]$BusDesc, [string]$WifiName, [string]$DriverProvider)
    $v = $script:KB.UsbVendors[$Vid]
    if ($v -and $v.Chip -ne 'Module') { return $v.Chip }
    $hint = "$BusDesc $WifiName $DriverProvider"
    if ($hint -match 'Intel|AX2\d\d|AX4\d\d|BE2\d\d|Killer AX|9560|9462|8265') { return 'Intel' }
    if ($hint -match 'Realtek|RTL8') { return 'Realtek' }
    if ($hint -match 'MediaTek|MT79|MT76|Filogic') { return 'MediaTek' }
    if ($hint -match 'Qualcomm|Atheros|QCA|QCNFA|FastConnect|Killer 1535|WCN') { return 'Qualcomm' }
    if ($hint -match 'Broadcom|BCM') { return 'Broadcom' }
    if ($v) { return $v.Chip }
    return 'Unknown'
}

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
function Get-BFEnvironment {
    Report-BFProgress 3 'Reading system information'
    $cs = $null; $bios = $null; $os = $null; $bb = $null
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
    try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop } catch { }
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $chassis = $null
    try { $chassis = (Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes } catch { }
    $isLaptop = $false
    if ($chassis) { foreach ($c in $chassis) { if ($c -in 8,9,10,11,12,14,18,21,30,31,32) { $isLaptop = $true } } }

    $pending = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'Component Based Servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'Windows Update' }
    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $pending += 'Pending file renames' }

    $airplane = $null
    try { $airplane = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\RadioManagement\SystemRadioState' -ErrorAction Stop).'(default)' } catch { }
    $hiberboot = $null
    try { $hiberboot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction Stop).HiberbootEnabled } catch { }

    $oem = $null
    $mf = if ($cs) { "$($cs.Manufacturer) $($cs.Model) $($cs.SystemFamily)" } else { '' }
    foreach ($o in $script:KB.OemSupport) { if ($mf -match $o.Match) { $oem = $o; break } }

    $build = if ($os) { $os.BuildNumber } else { [Environment]::OSVersion.Version.Build }
    [pscustomobject]@{
        ComputerName   = $env:COMPUTERNAME
        UserName       = "$env:USERDOMAIN\$env:USERNAME"
        IsAdmin        = Test-BFAdmin
        OSName         = if ($os) { $os.Caption } else { 'Windows' }
        OSVersion      = if ($os) { $os.Version } else { [Environment]::OSVersion.VersionString }
        Build          = [int]$build
        UBR            = if ($cv) { $cv.UBR } else { $null }
        DisplayVersion = if ($cv) { $cv.DisplayVersion } else { $null }
        IsWindows11    = ([int]$build -ge 22000)
        InstallDate    = if ($os) { $os.InstallDate } else { $null }
        LastBoot       = if ($os) { $os.LastBootUpTime } else { $null }
        Manufacturer   = if ($cs) { $cs.Manufacturer } else { 'Unknown' }
        Model          = if ($cs) { $cs.Model } else { 'Unknown' }
        SystemFamily   = if ($cs) { $cs.SystemFamily } else { '' }
        SKU            = if ($cs) { $cs.SystemSKUNumber } else { '' }
        Serial         = if ($bios) { $bios.SerialNumber } else { '' }
        BIOSVersion    = if ($bios) { $bios.SMBIOSBIOSVersion } else { '' }
        BIOSDate       = if ($bios) { $bios.ReleaseDate } else { $null }
        BaseBoard      = if ($bb) { "$($bb.Manufacturer) $($bb.Product)" } else { '' }
        IsLaptop       = $isLaptop
        PendingReboot  = ($pending.Count -gt 0)
        PendingReasons = $pending
        AirplaneMode   = ($airplane -eq 1)
        FastStartup    = ($hiberboot -eq 1)
        Oem            = $oem
        PSVersion      = $PSVersionTable.PSVersion.ToString()
        HasPnpUtilScan = ([int]$build -ge 18362)
        HasPnpUtilEnum = ([int]$build -ge 19041)
    }
}

# ---------------------------------------------------------------------------
# Device inventory
# ---------------------------------------------------------------------------
function New-BFDeviceRecord {
    param($Pnp, [string]$Role, [string]$WifiName)
    $keys = 'DEVPKEY_Device_HardwareIds','DEVPKEY_Device_CompatibleIds','DEVPKEY_Device_BusReportedDeviceDesc','DEVPKEY_Device_Parent',
            'DEVPKEY_Device_ProblemCode','DEVPKEY_Device_ProblemStatus','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_DriverVersion',
            'DEVPKEY_Device_DriverProvider','DEVPKEY_Device_DriverDate','DEVPKEY_Device_MatchingDeviceId','DEVPKEY_Device_DriverRank',
            'DEVPKEY_Device_Service','DEVPKEY_Device_FirstInstallDate','DEVPKEY_Device_LastArrivalDate','DEVPKEY_Device_LastRemovalDate',
            'DEVPKEY_Device_Manufacturer','DEVPKEY_Device_ConfigFlags','DEVPKEY_Device_Children','DEVPKEY_Device_DriverDesc','DEVPKEY_Device_LocationPaths'
    $p = Get-BFDevProp -InstanceId $Pnp.InstanceId -Keys $keys
    $vp = Get-BFVidPid -Text $Pnp.InstanceId
    if (-not $vp) { foreach ($h in @($p['DEVPKEY_Device_HardwareIds'])) { $vp = Get-BFVidPid -Text $h; if ($vp) { break } } }
    $vid = if ($vp) { $vp.Vid } else { $null }
    $pid = if ($vp) { $vp.Pid } else { $null }
    $vendor = if ($vid) { $script:KB.UsbVendors[$vid] } else { $null }
    $busDesc = $p['DEVPKEY_Device_BusReportedDeviceDesc']
    $problem = 0
    if ($p.ContainsKey('DEVPKEY_Device_ProblemCode')) { $problem = [int]$p['DEVPKEY_Device_ProblemCode'] }
    elseif ($Pnp.ConfigManagerErrorCode -and $Pnp.ConfigManagerErrorCode -ne 'CM_PROB_NONE') { $problem = -1 }
    $compat = @($p['DEVPKEY_Device_CompatibleIds'])
    $isBtClassE0 = $false
    foreach ($c in $compat) { if ($c -match 'Class_E0&SubClass_01&Prot_01') { $isBtClassE0 = $true } }
    $matching = $p['DEVPKEY_Device_MatchingDeviceId']
    $genericMatch = ($matching -and $matching -match '^USB\\Class_')
    $name = $Pnp.FriendlyName
    if (-not $name) { $name = $p['DEVPKEY_Device_DriverDesc'] }
    if (-not $name) { $name = $busDesc }
    if (-not $name) { $name = '(unnamed device)' }
    $chipVendor = if ($vid) { Get-BFChipVendorKey -Vid $vid -BusDesc $busDesc -WifiName $WifiName -DriverProvider $p['DEVPKEY_Device_DriverProvider'] } else { 'Unknown' }
    $chipName = if ($vid) { Get-BFChipName -Vid $vid -Pid $pid -BusDesc $busDesc -WifiName $WifiName } else { $name }

    [pscustomobject]@{
        InstanceId      = $Pnp.InstanceId
        Name            = $name
        Class           = $Pnp.Class
        Status          = $Pnp.Status
        Present         = [bool]$Pnp.Present
        Role            = $Role
        ProblemCode     = $problem
        ProblemText     = if ($problem -gt 0) { Get-BFProblemText -Code $problem } elseif ($problem -eq 0 -and $Pnp.Present) { 'Working' } else { 'Not present' }
        ProblemStatus   = Get-BFNtStatusText -Status $p['DEVPKEY_Device_ProblemStatus']
        HardwareIds     = @($p['DEVPKEY_Device_HardwareIds'])
        CompatibleIds   = $compat
        IsBluetoothUsbClass = $isBtClassE0
        BusDesc         = $busDesc
        Parent          = $p['DEVPKEY_Device_Parent']
        Children        = @($p['DEVPKEY_Device_Children'])
        InfPath         = $p['DEVPKEY_Device_DriverInfPath']
        DriverVersion   = $p['DEVPKEY_Device_DriverVersion']
        DriverProvider  = $p['DEVPKEY_Device_DriverProvider']
        DriverDate      = $p['DEVPKEY_Device_DriverDate']
        MatchingId      = $matching
        GenericDriverMatch = $genericMatch
        DriverRank      = $p['DEVPKEY_Device_DriverRank']
        Service         = $p['DEVPKEY_Device_Service']
        Manufacturer    = $p['DEVPKEY_Device_Manufacturer']
        FirstInstall    = $p['DEVPKEY_Device_FirstInstallDate']
        LastArrival     = $p['DEVPKEY_Device_LastArrivalDate']
        LastRemoval     = $p['DEVPKEY_Device_LastRemovalDate']
        ConfigFlags     = $p['DEVPKEY_Device_ConfigFlags']
        Location        = @($p['DEVPKEY_Device_LocationPaths']) -join ' | '
        Vid             = $vid
        Pid             = $pid
        VendorName      = if ($vendor) { $vendor.Name } else { $null }
        NeedsVendorDriver = if ($vendor) { [bool]$vendor.NeedsVendorDriver } else { $false }
        ChipVendor      = $chipVendor
        ChipName        = $chipName
    }
}

function Get-BFDeviceInventory {
    Report-BFProgress 8 'Enumerating devices (this takes a few seconds)'
    $all = @()
    try { $all = @(Get-PnpDevice -ErrorAction Stop) } catch { Write-BFLog -Level ERROR -Message "Get-PnpDevice failed: $($_.Exception.Message)" }
    $vids = $script:KB.UsbVendors.Keys

    # Wi-Fi adapter (tells us the combo card, hence the expected Bluetooth chip)
    $wifiPnp = @($all | Where-Object { $_.Class -eq 'Net' -and $_.InstanceId -match '^(PCI|SD|USB)\\' -and $_.FriendlyName -match 'Wi-?Fi|Wireless|802\.11|WLAN|AX\d{3}|BE\d{3}|RTL8|MT79|QCA|QCNFA|Killer|Dual Band' -and $_.FriendlyName -notmatch 'Ethernet|Gigabit|GbE|2\.5G|LAN Controller|Family Controller' })
    $wifi = @(); foreach ($w in $wifiPnp) { $wifi += New-BFDeviceRecord -Pnp $w -Role 'Wifi' }
    $wifiName = ($wifi | Where-Object Present | Select-Object -First 1).Name
    if (-not $wifiName) { $wifiName = ($wifi | Select-Object -First 1).Name }

    Report-BFProgress 14 'Inspecting Bluetooth radios'
    $records = New-Object System.Collections.ArrayList
    $seen = @{}
    $add = { param($pnp, $role) if (-not $seen.ContainsKey($pnp.InstanceId)) { $seen[$pnp.InstanceId] = $true; [void]$records.Add((New-BFDeviceRecord -Pnp $pnp -Role $role -WifiName $wifiName)) } }

    # 1. Bluetooth-class devices that are radios (not children of the stack)
    foreach ($d in ($all | Where-Object { $_.Class -eq 'Bluetooth' })) {
        if ($d.InstanceId -match '^(BTH|BTHENUM|BTHLE|BTHLEDEVICE|BTHHFENUM|BTHA2DP)\\') { & $add $d 'Child' }
        else { & $add $d 'Radio' }
    }
    # 2. USB devices from Bluetooth vendors or with the Bluetooth USB class, in any state (driverless "Unknown device" included)
    foreach ($d in ($all | Where-Object { $_.InstanceId -match '^USB\\VID_' })) {
        $vp = Get-BFVidPid -Text $d.InstanceId
        $isVendor = ($vp -and ($vids -contains $vp.Vid))
        $isUnknownClass = (-not $d.Class -or $d.Class -in 'Unknown','USB','Bluetooth','')
        if ($isVendor -or $isUnknownClass) {
            $rec = New-BFDeviceRecord -Pnp $d -Role 'RadioCandidate' -WifiName $wifiName
            if (-not $seen.ContainsKey($d.InstanceId)) {
                if ($rec.IsBluetoothUsbClass -or $rec.Class -eq 'Bluetooth' -or ($isVendor -and ($rec.Vid -in '8087','8086','0BDA','0A12','0CF3','0A5C','0E8D','3574','1131') -or ($isVendor -and $rec.BusDesc -match 'Bluetooth'))) {
                    if ($rec.Class -eq 'Bluetooth') { $rec.Role = 'Radio' }
                    $seen[$d.InstanceId] = $true; [void]$records.Add($rec)
                } elseif ($isVendor -and $rec.Class -in 'Unknown','', $null) {
                    $seen[$d.InstanceId] = $true; [void]$records.Add($rec)
                }
            }
        }
    }
    # 3. Radios under ACPI/UART (Qualcomm on ARM, some MediaTek) - class Bluetooth handled above; also SWD radio management node
    foreach ($d in ($all | Where-Object { $_.InstanceId -match '^SWD\\RADIO\\BLUETOOTH' })) { & $add $d 'SoftwareRadio' }

    # 4. Bluetooth stack children (paired devices, profiles) - counts and problems only
    $children = @($all | Where-Object { $_.InstanceId -match '^(BTH|BTHENUM|BTHLE|BTHLEDEVICE)\\' })

    Report-BFProgress 20 'Inspecting the USB stack'
    # 5. USB host controllers and root hubs
    $controllers = @()
    foreach ($d in ($all | Where-Object { $_.Class -eq 'USB' -and $_.InstanceId -match '^PCI\\' -and $_.InstanceId -notmatch 'USB4_MS_CM' })) {
        $controllers += New-BFDeviceRecord -Pnp $d -Role 'Controller'
    }
    $rootHubs = @()
    foreach ($d in ($all | Where-Object { $_.InstanceId -match '^USB\\ROOT_HUB' })) { $rootHubs += New-BFDeviceRecord -Pnp $d -Role 'RootHub' }
    $usbDeviceCount = @($all | Where-Object { $_.InstanceId -match '^USB\\' -and $_.Present }).Count
    $enumUsbExists = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'

    $radios = @($records | Where-Object { $_.Role -in 'Radio','RadioCandidate' })
    [pscustomobject]@{
        All              = $all
        Radios           = $radios
        PresentRadios    = @($radios | Where-Object Present)
        PhantomRadios    = @($radios | Where-Object { -not $_.Present })
        SoftwareRadios   = @($records | Where-Object { $_.Role -eq 'SoftwareRadio' })
        Children         = $children
        PresentChildren  = @($children | Where-Object Present)
        ProblemChildren  = @($children | Where-Object { $_.Present -and $_.Status -ne 'OK' })
        Wifi             = $wifi
        WifiName         = $wifiName
        Controllers      = $controllers
        RootHubs         = $rootHubs
        UsbDeviceCount   = $usbDeviceCount
        EnumUsbKeyExists = $enumUsbExists
        AllRecords       = @($records) + $controllers + $rootHubs + $wifi
    }
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------
function Get-BFServiceState {
    Report-BFProgress 34 'Checking Bluetooth and USB services'
    $rows = @()
    foreach ($b in $script:KB.ServiceBaseline) {
        $rk = "HKLM:\SYSTEM\CurrentControlSet\Services\$($b.Name)"
        $exists = Test-Path $rk
        $start = $null; $img = $null
        if ($exists) { $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue; $start = $p.Start; $img = $p.ImagePath }
        $svc = $null
        if ($b.Kind -ne 'UserServiceTemplate') { $svc = Get-Service -Name $b.Name -ErrorAction SilentlyContinue }
        else { $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($b.Name)_*" } | Select-Object -First 1 }
        $imgOk = $true
        if ($img -and $b.Kind -eq 'Driver') {
            $path = $img -replace '^\\SystemRoot', $env:SystemRoot -replace '^\\\?\?\\', '' -replace '^system32', "$env:SystemRoot\system32" -replace '^System32', "$env:SystemRoot\System32"
            if ($path -notmatch '^[A-Za-z]:\\') { $path = Join-Path $env:SystemRoot $path }
            $imgOk = Test-Path $path
        }
        $startName = switch ($start) { 0 {'Boot'} 1 {'System'} 2 {'Automatic'} 3 {'Manual'} 4 {'Disabled'} default {'?'} }
        $rows += [pscustomobject]@{
            Name        = $b.Name
            Display     = $b.Display
            Kind        = $b.Kind
            Critical    = [bool]$b.Critical
            KeyExists   = $exists
            Start       = $start
            StartName   = $startName
            DefaultStart = $b.Start
            DefaultName = switch ($b.Start) { 2 {'Automatic'} 3 {'Manual'} default {'?'} }
            Status      = if ($svc) { $svc.Status.ToString() } else { '-' }
            InstanceName = if ($svc) { $svc.Name } else { '' }
            ImagePath   = $img
            ImageExists = $imgOk
            Deviates    = ($exists -and $start -ne $null -and [int]$start -ne [int]$b.Start)
            Disabled    = ($exists -and [int]$start -eq 4)
            Note        = $b.Note
        }
    }
    # bthserv trigger info
    $triggers = @()
    try { $triggers = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\bthserv\TriggerInfo' -ErrorAction Stop) } catch { }
    # vendor stacks
    $vendorSvcs = @()
    foreach ($v in $script:KB.VendorDriverServices) {
        $rk = "HKLM:\SYSTEM\CurrentControlSet\Services\$($v.Name)"
        if (Test-Path $rk) {
            $p = Get-ItemProperty $rk -ErrorAction SilentlyContinue
            $vendorSvcs += [pscustomobject]@{ Name = $v.Name; Vendor = $v.Vendor; Note = $v.Note; Start = $p.Start; ImagePath = $p.ImagePath }
        }
    }
    [pscustomobject]@{ Rows = $rows; BthservTriggerCount = $triggers.Count; VendorServices = $vendorSvcs }
}

# ---------------------------------------------------------------------------
# Driver store
# ---------------------------------------------------------------------------
function Get-BFDriverStore {
    Report-BFProgress 40 'Reading the driver store'
    $pk = @()
    $r = Invoke-BFPnpUtil -Arguments @('/enum-drivers')
    if ($r.ExitCode -eq 0 -or $r.Output -match 'Published Name') {
        $blocks = ($r.Output -split '(?=Published Name)') | Where-Object { $_ -match 'Published Name' }
        foreach ($b in $blocks) {
            $o = [ordered]@{ Published = ''; Original = ''; Provider = ''; Class = ''; ClassGuid = ''; Version = ''; Date = ''; Signer = ''; HardwareIds = @() }
            if ($b -match 'Published Name:\s*(\S+)') { $o.Published = $Matches[1] }
            if ($b -match 'Original Name:\s*(\S+)') { $o.Original = $Matches[1] }
            if ($b -match 'Provider Name:\s*(.+)') { $o.Provider = $Matches[1].Trim() }
            if ($b -match 'Class Name:\s*(.+)') { $o.Class = $Matches[1].Trim() }
            if ($b -match 'Class GUID:\s*(\S+)') { $o.ClassGuid = $Matches[1] }
            if ($b -match 'Driver Version:\s*(\S+)\s+(\S+)') { $o.Date = $Matches[1]; $o.Version = $Matches[2] }
            if ($b -match 'Signer Name:\s*(.+)') { $o.Signer = $Matches[1].Trim() }
            if ($o.Class -match 'Bluetooth' -or $o.Original -match 'bt|bth|blue' ) {
                $inf = Join-Path $env:SystemRoot "INF\$($o.Published)"
                if (Test-Path $inf) {
                    try {
                        $ids = Select-String -Path $inf -Pattern '(USB|PCI|ACPI|SD)\\[A-Za-z0-9_&\.\-]+' -AllMatches -ErrorAction Stop | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value.ToUpper() } | Select-Object -Unique
                        $o.HardwareIds = @($ids)
                    } catch { }
                }
                $pk += [pscustomobject]$o
            }
        }
    }
    # inbox files sanity (raw versions)
    $files = @()
    foreach ($f in 'bthport.sys','bthusb.sys','bthenum.sys','bthmini.sys','BthA2dp.sys','bthhfenum.sys','hidbth.sys','rfcomm.sys','Microsoft.Bluetooth.Legacy.LEEnumerator.sys','Microsoft.Bluetooth.AvrcpTransport.sys','UsbHub3.sys','USBXHCI.SYS','ucx01000.sys','usbccgp.sys') {
        $p = Join-Path $env:SystemRoot "System32\drivers\$f"
        $files += [pscustomobject]@{ File = $f; Exists = (Test-Path $p); Version = (Get-BFRawFileVersion -Path $p) }
    }
    $infs = @()
    foreach ($f in 'bth.inf','usbhub3.inf','usbxhci.inf','bthpan.inf','bthspp.inf','hidbth.inf','bthleenum.inf','usb.inf','usbport.inf') {
        $infs += [pscustomobject]@{ File = $f; Exists = (Test-Path (Join-Path $env:SystemRoot "INF\$f")) }
    }
    [pscustomobject]@{ BluetoothPackages = $pk; InboxFiles = $files; InboxInfs = $infs; UsbStack = (Get-BFUsbStackVersions) }
}

function Get-BFUsbStackVersions {
    <#
      The USB hub (usbhub3.sys) and controller (USBXHCI.SYS) drivers talk to the UCX class extension (ucx01000.sys).
      A cumulative update can leave the class extension newer than the drivers actually installed on the devices,
      with the matching driver package sitting unused in WinSxS. Detect that and locate the matching packages.
    #>
    $drv = Join-Path $env:SystemRoot 'System32\drivers'
    $ucx = Get-BFRawFileVersion -Path (Join-Path $drv 'ucx01000.sys')
    $hub = Get-BFRawFileVersion -Path (Join-Path $drv 'UsbHub3.sys')
    $xhci = Get-BFRawFileVersion -Path (Join-Path $drv 'USBXHCI.SYS')
    $find = {
        param($prefix, $want)
        if (-not $want) { return $null }
        try {
            foreach ($d in (Get-ChildItem (Join-Path $env:SystemRoot 'WinSxS') -Directory -Filter "amd64_dual_$prefix.inf_*" -ErrorAction Stop)) {
                if ($d.Name -match "_10\.0\.\d+\.\d+_" ) {
                    $inf = Get-ChildItem $d.FullName -Filter "$prefix.inf" -ErrorAction SilentlyContinue | Select-Object -First 1
                    $sys = Get-ChildItem $d.FullName -Filter '*.sys' -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($inf -and $sys -and (Get-BFRawFileVersion -Path $sys.FullName) -eq $want) { return $inf.FullName }
                }
            }
        } catch { }
        return $null
    }
    $mismatch = $false
    try { $mismatch = ($ucx -and $hub -and ([version]$ucx -gt [version]$hub)) } catch { }
    $xmis = $false
    try { $xmis = ($ucx -and $xhci -and ([version]$ucx -gt [version]$xhci)) } catch { }
    [pscustomobject]@{
        Ucx = $ucx; UsbHub3 = $hub; UsbXhci = $xhci
        HubOlderThanUcx = $mismatch; XhciOlderThanUcx = $xmis
        WinSxSHubInf  = if ($mismatch) { & $find 'usbhub3' $ucx } else { $null }
        WinSxSXhciInf = if ($xmis) { & $find 'usbxhci' $ucx } else { $null }
    }
}

function Find-BFStorePackagesForDevice {
    param($Device, $Store)
    $hits = @()
    foreach ($p in $Store.BluetoothPackages) {
        foreach ($h in $Device.HardwareIds) {
            $hu = $h.ToUpper()
            $short = $hu -replace '&REV_[0-9A-F]+$', ''
            if ($p.HardwareIds -contains $hu -or $p.HardwareIds -contains $short) { $hits += $p; break }
        }
    }
    return @($hits | Sort-Object Published -Unique)
}

# ---------------------------------------------------------------------------
# Timeline (event logs + setupapi)
# ---------------------------------------------------------------------------
function Get-BFTimeline {
    param([int]$Days = 30)
    Report-BFProgress 46 'Reading event logs for what happened to Bluetooth'
    $items = New-Object System.Collections.ArrayList
    $since = (Get-Date).AddDays(-$Days)
    $pat = 'USB\\|BTH|Bluetooth|ROOT_HUB|VID_8087|VID_0BDA|VID_0A12|VID_0CF3|VID_0A5C|VID_0E8D|VID_13D3|VID_0489|VID_04CA'
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; StartTime = $since } -MaxEvents 4000 -ErrorAction Stop
        foreach ($e in $ev) {
            if ($e.Message -notmatch $pat) { continue }
            $dev = ''; if ($e.Message -match 'Device (\S+) ') { $dev = $Matches[1] }
            $what = switch ($e.Id) {
                400 { 'Driver configured for' }
                410 { 'Started' }
                411 { 'FAILED to start' }
                420 { 'DELETED (uninstalled)' }
                430 { 'Needs reboot' }
                440 { 'Migrated' }
                441 { 'Migration failed' }
                default { "Event $($e.Id) for" }
            }
            $extra = ''
            if ($e.Id -eq 411 -and $e.Message -match 'Problem:\s*(0x[0-9A-Fa-f]+)') { $extra = " problem $([Convert]::ToInt32($Matches[1],16))"; if ($e.Message -match 'Problem Status:\s*(0x[0-9A-Fa-f]+)') { $extra += " status " + (Get-BFNtStatusText -Status ([Convert]::ToInt64($Matches[1],16))) } }
            if ($e.Id -eq 400 -and $e.Message -match 'Driver Name:\s*(\S+)') { $extra = " ($($Matches[1]))" }
            $sev = if ($e.Id -in 411,420,441) { 'Warning' } else { 'Info' }
            [void]$items.Add([pscustomobject]@{ Time = $e.TimeCreated; Source = 'Kernel-PnP'; Severity = $sev; Text = "$what $dev$extra"; Device = $dev; EventId = $e.Id })
        }
    } catch { Write-BFLog -Level WARN -Message "Kernel-PnP log unavailable: $($_.Exception.Message)" }
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Level = 1,2,3 } -MaxEvents 3000 -ErrorAction Stop
        foreach ($e in $ev) {
            if ($e.ProviderName -match 'BTHUSB|BthPort|Bluetooth|bthserv' -or ($e.ProviderName -match 'Kernel-PnP|UserPnp|Service Control' -and $e.Message -match $pat)) {
                $msg = ($e.Message -replace '\s+', ' ')
                if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) + '...' }
                [void]$items.Add([pscustomobject]@{ Time = $e.TimeCreated; Source = $e.ProviderName; Severity = 'Warning'; Text = "[$($e.Id)] $msg"; Device = ''; EventId = $e.Id })
            }
        }
    } catch { Write-BFLog -Level WARN -Message "System log unavailable: $($_.Exception.Message)" }
    # setupapi: who uninstalled what through Device Manager
    $log = Join-Path $env:SystemRoot 'INF\setupapi.dev.log'
    if (Test-Path $log) {
        try {
            $lines = Get-Content $log -Tail 20000 -ErrorAction Stop
            $curTime = $null
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $l = $lines[$i]
                if ($l -match '^>>>\s+\[(Device Uninstall \(Device Manager\)|Delete Device|Device Install \(Hardware initiated\)|Device Install \(DiInstallDriver\)|Device Install \(UpdateDriverForPlugAndPlayDevices\)|Device Install \(DiInstallDevice\)|Device Install \(DiShowUpdateDevice\)|Uninstall device subtree \(DiUninstallDevice\)|Setup Import Driver Package|Delete Driver Package)[^\]]*\]') {
                    $action = $Matches[1]
                    $dev = ''; if ($l -match '\]\s*-\s*(.+)$' -or $l -match '\[.+? - (.+)\]') { $dev = $Matches[1].Trim() }
                    $t = $null
                    for ($j = $i + 1; $j -lt [Math]::Min($i + 3, $lines.Count); $j++) { if ($lines[$j] -match 'Section start (\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d+)') { try { $t = [datetime]::ParseExact($Matches[1], 'yyyy/MM/dd HH:mm:ss.fff', $null) } catch { }; break } }
                    if ($t -and $t -lt $since) { continue }
                    if ("$dev $l" -match $pat -or $action -match 'Device Manager') {
                        $text = switch -Regex ($action) {
                            'Device Uninstall \(Device Manager\)' { "Uninstalled through Device Manager by a user: $dev" }
                            'DiShowUpdateDevice' { "'Update driver' clicked in Device Manager for: $dev" }
                            'DiUninstallDevice' { "Device removed (Settings > Bluetooth or Device Manager): $dev" }
                            'Delete Driver Package' { "Driver package deleted: $dev" }
                            'UpdateDriverForPlugAndPlayDevices|DiInstallDriver|DiInstallDevice' { "Driver installed manually: $dev" }
                            default { "$action : $dev" }
                        }
                        $sev = if ($action -match 'Uninstall|Delete|DiShowUpdateDevice') { 'Warning' } else { 'Info' }
                        [void]$items.Add([pscustomobject]@{ Time = $t; Source = 'setupapi.dev.log'; Severity = $sev; Text = $text; Device = $dev; EventId = 0 })
                    }
                }
            }
        } catch { Write-BFLog -Level WARN -Message "setupapi.dev.log unreadable: $($_.Exception.Message)" }
    }
    return @($items | Where-Object { $_.Time } | Sort-Object Time -Descending)
}

# ---------------------------------------------------------------------------
# Radio state (WinRT)
# ---------------------------------------------------------------------------
function Get-BFRadioState {
    Report-BFProgress 52 'Querying the radio manager'
    $res = [pscustomobject]@{ Available = $false; Access = ''; Radios = @(); BluetoothRadio = $null; Error = '' }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $null = [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $await = { param($op, $t) $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); if (-not $task.Wait(10000)) { throw 'timeout' }; $task.Result }
        $acc = & $await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
        $res.Access = $acc.ToString()
        $radios = & $await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
        $list = @()
        foreach ($r in $radios) { $list += [pscustomobject]@{ Name = $r.Name; Kind = $r.Kind.ToString(); State = $r.State.ToString() } }
        $res.Radios = $list
        $res.BluetoothRadio = $list | Where-Object { $_.Kind -eq 'Bluetooth' } | Select-Object -First 1
        $res.Available = $true
    } catch { $res.Error = $_.Exception.Message }
    return $res
}

function Set-BFBluetoothRadioOn {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $null = [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $await = { param($op, $t) $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); if (-not $task.Wait(10000)) { throw 'timeout' }; $task.Result }
        $null = & $await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
        $radios = & $await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
        foreach ($r in $radios) {
            if ($r.Kind.ToString() -eq 'Bluetooth' -and $r.State.ToString() -ne 'On') {
                $st = & $await ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::On)) ([Windows.Devices.Radios.RadioAccessStatus])
                return "Bluetooth radio '$($r.Name)' set to On: $st"
            }
        }
        return 'No Bluetooth radio was off.'
    } catch { return "Could not switch the radio: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# Policies, filters, third-party stacks, power
# ---------------------------------------------------------------------------
function Get-BFPolicyState {
    Report-BFProgress 58 'Checking policies, filter drivers and power settings'
    $hits = @()
    foreach ($k in $script:KB.BluetoothPolicyKeys) {
        if (Test-Path $k.Path) {
            $p = Get-ItemProperty $k.Path -ErrorAction SilentlyContinue
            foreach ($v in $k.Values) {
                if ($p.PSObject.Properties[$v]) { $hits += [pscustomobject]@{ Path = $k.Path; Name = $v; Value = ($p.$v | Out-String).Trim() } }
            }
        }
    }
    $filters = @()
    foreach ($g in @($script:KB.ClassGuids.Bluetooth, $script:KB.ClassGuids.USB, $script:KB.ClassGuids.HIDClass)) {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$g" -ErrorAction SilentlyContinue
        if ($p) {
            foreach ($f in @($p.UpperFilters)) { if ($f) { $filters += [pscustomobject]@{ ClassGuid = $g; Class = $p.Class; Position = 'Upper'; Filter = $f } } }
            foreach ($f in @($p.LowerFilters)) { if ($f) { $filters += [pscustomobject]@{ ClassGuid = $g; Class = $p.Class; Position = 'Lower'; Filter = $f } } }
        }
    }
    $stacks = @()
    $apps = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
    foreach ($s in $script:KB.ThirdPartyStacks) { foreach ($a in $apps) { if ($a.DisplayName -and $a.DisplayName -match $s.Match) { $stacks += [pscustomobject]@{ Name = $s.Name; Installed = $a.DisplayName; Version = $a.DisplayVersion } } } }
    $btSoftware = @($apps | Where-Object { $_.DisplayName -match 'Bluetooth' } | Select-Object DisplayName, DisplayVersion, Publisher)

    $selSuspend = $null
    try {
        $q = powercfg /q SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 2>$null
        $ac = ($q | Select-String 'Current AC Power Setting Index:\s*0x(\d+)').Matches
        if ($ac.Count) { $selSuspend = [Convert]::ToInt32($ac[0].Groups[1].Value, 16) }
    } catch { }
    [pscustomobject]@{ PolicyHits = $hits; ClassFilters = $filters; ThirdPartyStacks = $stacks; BluetoothSoftware = $btSoftware; UsbSelectiveSuspendAC = $selSuspend }
}

function Get-BFRadioPowerSettings {
    param($Device)
    if (-not $Device -or $Device.InstanceId -notmatch '^USB\\') { return $null }
    $key = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Device.InstanceId)\Device Parameters"
    if (-not (Test-Path $key)) { return $null }
    $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Key = $key
        EnhancedPowerManagementEnabled = $p.EnhancedPowerManagementEnabled
        SelectiveSuspendEnabled        = $p.SelectiveSuspendEnabled
        AllowIdleIrpInD3               = $p.AllowIdleIrpInD3
        DeviceSelectiveSuspended       = $p.DeviceSelectiveSuspended
    }
}

# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------
function New-BFFinding {
    param([string]$Id, [string]$Area, [ValidateSet('Critical','Warning','Info','OK')][string]$Severity, [string]$Title, [string]$Detail, [string[]]$Evidence = @(), [string[]]$Fixes = @())
    [pscustomobject]@{ Id = $Id; Area = $Area; Severity = $Severity; Title = $Title; Detail = $Detail; Evidence = @($Evidence); Fixes = @($Fixes) }
}

function Invoke-BFAnalysis {
    param($Env, $Inv, $Svc, $Store, $Timeline, $Radio, $Policy)
    Report-BFProgress 70 'Analysing'
    $findingList = New-Object System.Collections.ArrayList
    $add = { param($item) [void]$findingList.Add($item) }
    $kb = $script:KB

    # --- Elevation -------------------------------------------------------
    if (-not $Env.IsAdmin) {
        & $add (New-BFFinding -Id 'ENV-ADMIN' -Area 'Environment' -Severity 'Warning' -Title 'Not running as administrator' -Detail 'Diagnosis works without admin rights, but every repair needs them. Re-launch with "Run as administrator".')
    }
    if ($Env.PendingReboot) {
        & $add (New-BFFinding -Id 'ENV-REBOOT' -Area 'Environment' -Severity 'Warning' -Title 'A reboot is pending' -Detail ("Windows has unfinished changes waiting for a restart: {0}. Driver changes may not take effect until then." -f ($Env.PendingReasons -join ', ')) -Fixes @('F17'))
    }
    if ($Env.AirplaneMode) {
        & $add (New-BFFinding -Id 'ENV-AIRPLANE' -Area 'Radio' -Severity 'Critical' -Title 'Airplane mode is ON' -Detail 'All radios are switched off by airplane mode. Bluetooth cannot work until it is turned off.' -Fixes @('F10'))
    }

    # --- USB stack -------------------------------------------------------
    $brokenHubs = @()
    $ctrlWithoutHub = @()
    foreach ($c in $Inv.Controllers) {
        if (-not $c.Present) { continue }
        $hubs = @($Inv.RootHubs | Where-Object { $_.Parent -eq $c.InstanceId })
        if ($hubs.Count -eq 0) {
            # The controller thinks it has children but no root hub devnode exists
            $ctrlWithoutHub += $c
        } else {
            foreach ($h in $hubs) { if (-not $h.Present -or $h.ProblemCode -gt 0) { $brokenHubs += $h } }
        }
    }
    if ($ctrlWithoutHub.Count -gt 0) {
        $ev = @()
        foreach ($c in $ctrlWithoutHub) { $ev += "Controller '$($c.Name)' [$($c.InstanceId)] is started but has no USB Root Hub device underneath it." }
        $ev += "Present USB devices on this PC: $($Inv.UsbDeviceCount)"
        $ev += "Registry key HKLM\SYSTEM\CurrentControlSet\Enum\USB exists: $($Inv.EnumUsbKeyExists)"
        $del = @($Timeline | Where-Object { $_.Text -match 'ROOT_HUB' -and ($_.Text -match 'DELETED|Uninstalled') } | Select-Object -First 3)
        foreach ($d in $del) { $ev += ("{0:g}: {1}" -f $d.Time, $d.Text) }
        & $add (New-BFFinding -Id 'USB-NOROOTHUB' -Area 'USB stack' -Severity 'Critical' -Title 'USB Root Hub is missing - the whole USB tree is gone' -Detail 'The USB host controller is running but its Root Hub device does not exist, so NO USB device can appear, and on almost every laptop the Bluetooth radio is an internal USB device. This is what happens when "USB Root Hub" is uninstalled in Device Manager. Fix: rescan hardware, restart the controller, or reboot.' -Evidence $ev -Fixes @('F01','F02','F17'))
    }
    $us = $Store.UsbStack
    $hubBufferFault = @($brokenHubs | Where-Object { $_.ProblemStatus -match '0xC0000206' }).Count -gt 0
    # Did a root hub fail within 3 minutes of the last boot? Then the boot path is broken too, not just runtime restarts.
    $hubFailedAtBoot = $false
    if ($Env.LastBoot) {
        $bootWindowEnd = $Env.LastBoot.AddMinutes(3)
        $hubFailedAtBoot = @($Timeline | Where-Object { $_.EventId -eq 411 -and $_.Text -match 'ROOT_HUB' -and $_.Time -ge $Env.LastBoot -and $_.Time -le $bootWindowEnd }).Count -gt 0
    }
    $hasStorePkg = ($us -and ($us.WinSxSHubInf -or $us.WinSxSXhciInf))
    if ($brokenHubs.Count -gt 0) {
        $ev = @(); foreach ($h in $brokenHubs) { $ev += "$($h.Name) [$($h.InstanceId)] problem $($h.ProblemCode): $($h.ProblemText) $($h.ProblemStatus)" }
        $fx = @('F02','F01','F17')
        $detail = 'A USB Root Hub failed to start. Every device behind it, including an internal Bluetooth radio, is unreachable. Restarting the host controller re-creates the hub cleanly; a reboot is the fallback.'
        if ($hubBufferFault) {
            if ($hubFailedAtBoot) {
                $detail = 'The USB Root Hub failed with STATUS_INVALID_BUFFER_SIZE during boot, so a reboot alone will not fix it.'
                if ($hasStorePkg) { $detail += " The installed hub/controller driver ($($us.UsbHub3)) is older than the USB class extension it talks to ($($us.Ucx)); the matching Microsoft package is in the component store. Re-staging it (F21) aligns the builds."; $fx = @('F21','F17') }
                else { $detail += ' Run the component repair (F16), then reboot.'; $fx = @('F16','F17') }
            } else {
                $detail = 'The USB Root Hub fails with STATUS_INVALID_BUFFER_SIZE every time it is (re)started while Windows is running, although it started fine at boot. This happens after "Update driver" or "Uninstall" on the hub; a controller restart does not clear it, a reboot does. Reboot first.'
                if ($hasStorePkg) { $detail += " If it fails again right after the reboot, the tool will offer to re-stage the newer hub driver from the component store (the installed one is $($us.UsbHub3), the class extension is $($us.Ucx))." }
                $fx = @('F17')
            }
        }
        & $add (New-BFFinding -Id 'USB-HUBPROBLEM' -Area 'USB stack' -Severity 'Critical' -Title 'USB Root Hub has a problem' -Detail $detail -Evidence $ev -Fixes $fx)
    }
    if ($us -and ($us.HubOlderThanUcx -or $us.XhciOlderThanUcx)) {
        $ev = @("ucx01000.sys (USB class extension): $($us.Ucx)", "UsbHub3.sys (root hub driver): $($us.UsbHub3)", "USBXHCI.SYS (controller driver): $($us.UsbXhci)")
        if ($us.WinSxSHubInf) { $ev += "Matching hub package in component store: $($us.WinSxSHubInf)" }
        if ($us.WinSxSXhciInf) { $ev += "Matching xHCI package in component store: $($us.WinSxSXhciInf)" }
        $sev = 'Info'; $fx = @()
        if ($hubBufferFault -and $hubFailedAtBoot -and $hasStorePkg) { $sev = 'Critical'; $fx = @('F21') }
        elseif ($brokenHubs.Count -gt 0 -or $ctrlWithoutHub.Count -gt 0) { $sev = 'Warning' }
        & $add (New-BFFinding -Id 'USB-DRVMISMATCH' -Area 'USB stack' -Severity $sev -Title 'USB hub/controller driver is older than the USB class extension' -Detail 'A cumulative update replaced the USB class extension (ucx01000.sys) but the driver store still holds an older usbhub3/usbxhci package, so the devices run mismatched builds. Harmless while everything works. If root hubs fail with STATUS_INVALID_BUFFER_SIZE even after a reboot, re-staging the matching Microsoft package from the component store (F21, in the Fix plan tab) aligns them.' -Evidence $ev -Fixes $fx)
    }
    if ($Inv.Controllers.Count -eq 0) {
        & $add (New-BFFinding -Id 'USB-NOCTRL' -Area 'USB stack' -Severity 'Critical' -Title 'No USB host controller found' -Detail 'Windows does not see any USB controller. Check chipset drivers and BIOS (USB controller enabled).' -Fixes @('F09'))
    }
    foreach ($c in $Inv.Controllers) { if ($c.Present -and $c.ProblemCode -gt 0) {
        & $add (New-BFFinding -Id "USB-CTRL-$($c.InstanceId.GetHashCode())" -Area 'USB stack' -Severity 'Critical' -Title "USB controller problem: $($c.Name)" -Detail (Get-BFProblemText -Code $c.ProblemCode) -Evidence @("$($c.InstanceId) status $($c.ProblemStatus)") -Fixes @('F02','F17','F09')) } }

    # --- Radio discovery -------------------------------------------------
    $present = $Inv.PresentRadios
    $phantom = $Inv.PhantomRadios
    $wifiVendor = Get-BFChipVendorKey -Vid '' -BusDesc '' -WifiName $Inv.WifiName -DriverProvider ''
    $usbHealthy = ($ctrlWithoutHub.Count -eq 0 -and $brokenHubs.Count -eq 0 -and $Inv.Controllers.Count -gt 0)

    if ($present.Count -eq 0) {
        $ev = @()
        if ($Inv.WifiName) { $ev += "Wi-Fi adapter: $($Inv.WifiName) (combo cards carry Bluetooth over internal USB)" }
        foreach ($p in $phantom) { $ev += ("Ghost radio from before: {0} [{1}] last seen {2:g}, last removed {3:g}" -f $p.ChipName, $p.InstanceId, $p.LastArrival, $p.LastRemoval) }
        if ($Inv.SoftwareRadios.Count -gt 0) { foreach ($s in $Inv.SoftwareRadios) { $ev += "Radio-manager node: $($s.InstanceId) present=$($s.Present)" } }
        if (-not $usbHealthy) {
            $fxUsb = @('F01','F02','F17')
            if ($hubBufferFault) { $fxUsb = if ($hubFailedAtBoot -and $hasStorePkg) { @('F21','F17') } else { @('F17') } }
            & $add (New-BFFinding -Id 'RADIO-NONE-USB' -Area 'Radio' -Severity 'Critical' -Title 'No Bluetooth radio is present, because the USB stack is broken' -Detail 'The radio cannot appear until the USB Root Hub problem above is repaired. Fix USB first, then re-run the diagnosis.' -Evidence $ev -Fixes $fxUsb)
        } elseif ($phantom.Count -gt 0) {
            & $add (New-BFFinding -Id 'RADIO-NONE-GHOST' -Area 'Radio' -Severity 'Critical' -Title 'Bluetooth radio existed before but is not present now' -Detail 'Windows remembers a Bluetooth radio that is no longer enumerating. Causes in order of likelihood: it was uninstalled and needs a rescan/reboot; the radio was disabled in BIOS/UEFI; a driver update left it in a bad power state (full shutdown, unplug, hold power 30 s); the module is loose or failed.' -Evidence $ev -Fixes @('F01','F05','F17','F18'))
        } else {
            $sev = 'Critical'; $title = 'No Bluetooth radio detected at all'
            $detail = 'Windows has never seen a Bluetooth radio on this PC, or it was purged. If this machine should have Bluetooth: check BIOS/UEFI (Wireless / Bluetooth enabled), do a full power drain, or plug in a USB Bluetooth adapter.'
            if ($Inv.WifiName -and $wifiVendor -ne 'Unknown') { $detail = "Your Wi-Fi card ($($Inv.WifiName)) normally carries a $wifiVendor Bluetooth radio on internal USB, but nothing from $wifiVendor is enumerating. " + $detail }
            & $add (New-BFFinding -Id 'RADIO-NONE' -Area 'Radio' -Severity $sev -Title $title -Detail $detail -Evidence $ev -Fixes @('F01','F18','F09'))
        }
    }

    foreach ($r in $present) {
        $ev = @("Instance: $($r.InstanceId)", "Hardware IDs: $($r.HardwareIds -join ', ')", "Driver: $($r.InfPath) v$($r.DriverVersion) by $($r.DriverProvider) (matched on $($r.MatchingId))", "Service: $($r.Service)")
        if ($r.BusDesc) { $ev += "Bus reported description: $($r.BusDesc)" }
        # Problem codes
        if ($r.ProblemCode -eq 22) {
            & $add (New-BFFinding -Id "RADIO-DISABLED-$($r.Pid)" -Area 'Radio' -Severity 'Critical' -Title "Bluetooth radio is disabled: $($r.ChipName)" -Detail 'The radio is disabled in Device Manager (Code 22). Enabling it is a one-click fix.' -Evidence $ev -Fixes @('F03'))
        } elseif ($r.ProblemCode -eq 28 -or ($r.Class -ne 'Bluetooth' -and $r.ProblemCode -gt 0)) {
            $pk = Find-BFStorePackagesForDevice -Device $r -Store $Store
            $ev2 = $ev + @("Matching packages already in the driver store: " + $(if ($pk.Count) { ($pk | ForEach-Object { "$($_.Published) ($($_.Original) $($_.Version) by $($_.Provider))" }) -join '; ' } else { 'none' }))
            $fx = @('F08','F09'); if ($pk.Count) { $fx = @('F07') + $fx }
            & $add (New-BFFinding -Id "RADIO-NODRIVER-$($r.Pid)" -Area 'Driver' -Severity 'Critical' -Title "No driver installed for $($r.ChipName)" -Detail (Get-BFProblemText -Code $r.ProblemCode) -Evidence $ev2 -Fixes $fx)
        } elseif ($r.ProblemCode -eq 31 -or $r.ProblemCode -eq 39 -or $r.ProblemCode -eq 37 -or $r.ProblemCode -eq 52 -or $r.ProblemCode -eq 48) {
            & $add (New-BFFinding -Id "RADIO-DRVLOAD-$($r.Pid)" -Area 'Driver' -Severity 'Critical' -Title "Driver cannot load for $($r.ChipName) (Code $($r.ProblemCode))" -Detail ((Get-BFProblemText -Code $r.ProblemCode) + ' ' + $r.ProblemStatus) -Evidence $ev -Fixes @('F07','F08','F16'))
        } elseif ($r.ProblemCode -eq 32) {
            & $add (New-BFFinding -Id "RADIO-SVCDISABLED-$($r.Pid)" -Area 'Services' -Severity 'Critical' -Title "Driver service for $($r.ChipName) is disabled (Code 32)" -Detail "The kernel driver service '$($r.Service)' has Start=4 (Disabled). Restore it to Manual." -Evidence $ev -Fixes @('F06','F04'))
        } elseif ($r.ProblemCode -eq 10 -or $r.ProblemCode -eq 43) {
            & $add (New-BFFinding -Id "RADIO-FAILSTART-$($r.Pid)" -Area 'Radio' -Severity 'Critical' -Title "$($r.ChipName) cannot start (Code $($r.ProblemCode))" -Detail ((Get-BFProblemText -Code $r.ProblemCode) + ' ' + $r.ProblemStatus + ' Order of attack: restart the device, reinstall the right vendor driver, disable power management, full power drain.') -Evidence $ev -Fixes @('F04','F07','F13','F08','F18'))
        } elseif ($r.ProblemCode -eq 14) {
            & $add (New-BFFinding -Id "RADIO-REBOOT-$($r.Pid)" -Area 'Radio' -Severity 'Warning' -Title "$($r.ChipName) needs a reboot" -Detail 'A driver change is waiting for a restart.' -Evidence $ev -Fixes @('F17'))
        } elseif ($r.ProblemCode -gt 0) {
            & $add (New-BFFinding -Id "RADIO-PROBLEM-$($r.Pid)" -Area 'Radio' -Severity 'Critical' -Title "$($r.ChipName) has problem code $($r.ProblemCode)" -Detail ((Get-BFProblemText -Code $r.ProblemCode) + ' ' + $r.ProblemStatus) -Evidence $ev -Fixes @('F04','F07','F17'))
        }

        # Wrong / generic driver checks (only meaningful when a driver is installed)
        if ($r.InfPath) {
            $chip = $r.ChipVendor
            $provider = "$($r.DriverProvider)"
            $needsVendor = $r.NeedsVendorDriver -or ($chip -in 'Intel','Realtek','MediaTek','Qualcomm','Broadcom')
            if ($needsVendor -and $r.GenericDriverMatch) {
                $pk = Find-BFStorePackagesForDevice -Device $r -Store $Store
                $ev2 = $ev + @("Vendor packages in the driver store for this radio: " + $(if ($pk.Count) { ($pk | ForEach-Object { "$($_.Published) ($($_.Original) $($_.Version) by $($_.Provider))" }) -join '; ' } else { 'none' }))
                $fx = @('F08','F09'); if ($pk.Count) { $fx = @('F07') + $fx }
                & $add (New-BFFinding -Id "DRV-GENERIC-$($r.Pid)" -Area 'Driver' -Severity 'Critical' -Title "Generic Microsoft driver is installed on a $chip radio" -Detail "The radio matched only on its USB class ($($r.MatchingId)) and is using the inbox 'Generic Bluetooth Radio' driver. $chip radios need the vendor driver to load firmware; with the generic driver they appear in Device Manager but never pair or turn on. Install the $chip driver." -Evidence $ev2 -Fixes $fx)
            }
            $providerVendor = Get-BFChipVendorKey -Vid '' -BusDesc '' -WifiName '' -DriverProvider $provider
            if ($chip -ne 'Unknown' -and $chip -ne 'Module' -and $providerVendor -ne 'Unknown' -and $providerVendor -ne $chip -and $provider -notmatch 'Microsoft') {
                & $add (New-BFFinding -Id "DRV-WRONGVENDOR-$($r.Pid)" -Area 'Driver' -Severity 'Critical' -Title "A $providerVendor driver is forced onto a $chip radio" -Detail "The installed driver ($($r.InfPath) by $provider) belongs to a different chip vendor than the hardware ($($r.ChipName)). This only happens through 'Let me pick from a list' with 'Show compatible hardware' unticked. Roll it back: remove the device and let Windows re-match the correct package." -Evidence $ev -Fixes @('F07','F08'))
            }
            if ($provider -match 'Microsoft' -and $r.InfPath -match '^oem' ) {
                & $add (New-BFFinding -Id "DRV-OEMMS-$($r.Pid)" -Area 'Driver' -Severity 'Info' -Title 'Radio uses a Microsoft-signed third-party package' -Detail "Driver package $($r.InfPath) is from Windows Update rather than the inbox INF. Normal." -Evidence $ev)
            }
            # Better package available in store?
            $pk = Find-BFStorePackagesForDevice -Device $r -Store $Store | Where-Object { $_.Published -ne $r.InfPath -and $_.Provider -notmatch 'Microsoft' }
            if ($pk.Count -gt 0 -and $r.ProblemCode -eq 0 -and -not $r.GenericDriverMatch) {
                $newer = @()
                foreach ($p in $pk) { try { if ([version]$p.Version -gt [version]$r.DriverVersion) { $newer += $p } } catch { } }
                if ($newer.Count) {
                    & $add (New-BFFinding -Id "DRV-NEWER-$($r.Pid)" -Area 'Driver' -Severity 'Info' -Title 'A newer vendor driver is already in the driver store' -Detail ("Installed {0}; available: {1}. Windows normally picks the best rank automatically, so this is informational." -f $r.DriverVersion, (($newer | ForEach-Object { "$($_.Published) $($_.Version)" }) -join ', ')) -Evidence $ev -Fixes @('F07'))
                }
            }
            # Power management
            $pw = Get-BFRadioPowerSettings -Device $r
            if ($pw -and $pw.EnhancedPowerManagementEnabled -eq 1 -and $chip -eq 'Intel') {
                & $add (New-BFFinding -Id "PWR-EPM-$($r.Pid)" -Area 'Power' -Severity 'Info' -Title 'Enhanced USB power management is on for the Intel radio' -Detail 'Intel radios are known to drop connections or vanish after sleep with EnhancedPowerManagementEnabled=1. Only relevant if your symptom is "Bluetooth disappears after sleep".' -Evidence @("$($pw.Key) EnhancedPowerManagementEnabled=1") -Fixes @('F13'))
            }
        }
        if ($r.ProblemCode -eq 0 -and $r.Class -eq 'Bluetooth' -and $r.InfPath) {
            & $add (New-BFFinding -Id "RADIO-OK-$($r.Pid)" -Area 'Radio' -Severity 'OK' -Title "Radio present and started: $($r.ChipName)" -Detail "Driver $($r.InfPath) v$($r.DriverVersion) by $($r.DriverProvider)." -Evidence $ev)
        }
    }

    if ($present.Count -gt 1) {
        & $add (New-BFFinding -Id 'RADIO-MULTI' -Area 'Radio' -Severity 'Warning' -Title "$($present.Count) Bluetooth radios are present" -Detail 'Windows only uses one Bluetooth radio at a time. A USB dongle plus an internal radio will fight; disable the one you do not want (Device Manager > Disable), never uninstall.' -Evidence @($present | ForEach-Object { "$($_.ChipName) [$($_.InstanceId)]" }))
    }
    if ($phantom.Count -gt 0 -and $present.Count -gt 0) {
        & $add (New-BFFinding -Id 'RADIO-GHOSTS' -Area 'Radio' -Severity 'Info' -Title "$($phantom.Count) ghost Bluetooth radio entries" -Detail 'Old radio entries that are not connected. Harmless, but cleaning them prevents stale settings from being reused.' -Evidence @($phantom | ForEach-Object { "$($_.ChipName) [$($_.InstanceId)]" }) -Fixes @('F05'))
    }

    # --- Radio manager state --------------------------------------------
    if ($Radio.Available) {
        if ($present.Count -gt 0 -and -not $Radio.BluetoothRadio) {
            & $add (New-BFFinding -Id 'RM-NOBT' -Area 'Radio' -Severity 'Critical' -Title 'Radio Management does not see a Bluetooth radio' -Detail 'A radio device exists but the Radio Management service (the Bluetooth on/off toggle) does not list it. Usually the Bluetooth Support Service is not running or RmSvc is disabled.' -Evidence @("Radios seen: " + (($Radio.Radios | ForEach-Object { "$($_.Name)=$($_.State)" }) -join ', ')) -Fixes @('F06','F04'))
        } elseif ($Radio.BluetoothRadio) {
            $st = $Radio.BluetoothRadio.State
            if ($st -eq 'Off') { & $add (New-BFFinding -Id 'RM-OFF' -Area 'Radio' -Severity 'Critical' -Title 'Bluetooth is switched OFF' -Detail 'The radio is fine but turned off in Settings / quick settings.' -Evidence @("Radio '$($Radio.BluetoothRadio.Name)' state Off") -Fixes @('F10')) }
            elseif ($st -eq 'Disabled') { & $add (New-BFFinding -Id 'RM-DISABLED' -Area 'Radio' -Severity 'Critical' -Title 'Bluetooth radio reports Disabled' -Detail 'Radio Management says the radio is disabled (hardware switch, airplane mode, or device disabled).' -Fixes @('F10','F03')) }
            elseif ($st -eq 'Unknown') { & $add (New-BFFinding -Id 'RM-UNKNOWN' -Area 'Radio' -Severity 'Warning' -Title 'Bluetooth radio state unknown' -Detail 'The radio manager cannot read the radio state. Typical when the driver is half-loaded.' -Fixes @('F04','F06')) }
            else { & $add (New-BFFinding -Id 'RM-ON' -Area 'Radio' -Severity 'OK' -Title 'Bluetooth radio is ON' -Detail "Radio '$($Radio.BluetoothRadio.Name)' reports On.") }
        }
    } elseif ($Radio.Error) {
        & $add (New-BFFinding -Id 'RM-API' -Area 'Radio' -Severity 'Info' -Title 'Radio Management API not available in this session' -Detail $Radio.Error)
    }

    # --- Services --------------------------------------------------------
    $disabled = @($Svc.Rows | Where-Object { $_.Disabled })
    $deviating = @($Svc.Rows | Where-Object { $_.Deviates -and -not $_.Disabled })
    $missing = @($Svc.Rows | Where-Object { -not $_.KeyExists -and $_.Kind -ne 'UserServiceTemplate' })
    $badImage = @($Svc.Rows | Where-Object { $_.KeyExists -and -not $_.ImageExists })
    if ($disabled.Count) {
        & $add (New-BFFinding -Id 'SVC-DISABLED' -Area 'Services' -Severity 'Critical' -Title "$($disabled.Count) Bluetooth/USB service(s) are DISABLED" -Detail 'A disabled service or kernel driver here breaks Bluetooth outright. These will be restored to their Windows defaults.' -Evidence @($disabled | ForEach-Object { "$($_.Name) ($($_.Display)) Start=Disabled, default $($_.DefaultName). $($_.Note)" }) -Fixes @('F06'))
    }
    if ($deviating.Count) {
        & $add (New-BFFinding -Id 'SVC-DEVIATE' -Area 'Services' -Severity 'Warning' -Title "$($deviating.Count) service(s) changed from Windows defaults" -Detail 'Usually harmless (Manual changed to Automatic), but drift like this is a fingerprint of manual troubleshooting. Restoring defaults keeps the trigger-start logic Windows expects.' -Evidence @($deviating | ForEach-Object { "$($_.Name) ($($_.Display)) is $($_.StartName), default $($_.DefaultName)" }) -Fixes @('F06'))
    }
    if ($missing.Count) {
        & $add (New-BFFinding -Id 'SVC-MISSING' -Area 'Services' -Severity 'Critical' -Title "$($missing.Count) core service registry key(s) are missing" -Detail 'A service key that ships with Windows is gone. Only a component repair (DISM/SFC) or an in-place upgrade can restore it.' -Evidence @($missing | ForEach-Object { "$($_.Name) ($($_.Display))" }) -Fixes @('F16'))
    }
    if ($badImage.Count) {
        & $add (New-BFFinding -Id 'SVC-IMAGE' -Area 'Services' -Severity 'Critical' -Title 'Driver file missing for a registered service' -Detail 'The registry points to a driver file that does not exist. Component repair will restore inbox files; vendor files need the vendor package reinstalled.' -Evidence @($badImage | ForEach-Object { "$($_.Name): $($_.ImagePath)" }) -Fixes @('F16','F08'))
    }
    $bths = $Svc.Rows | Where-Object Name -eq 'bthserv'
    if ($bths -and $bths.KeyExists -and $Svc.BthservTriggerCount -eq 0) {
        & $add (New-BFFinding -Id 'SVC-TRIGGER' -Area 'Services' -Severity 'Warning' -Title 'Bluetooth Support Service lost its start triggers' -Detail 'bthserv is Manual and normally starts automatically when a radio appears. Its trigger list is empty, so it will not start by itself.' -Fixes @('F06'))
    }
    if ($present.Count -gt 0 -and $bths -and $bths.Status -ne 'Running' -and -not $bths.Disabled) {
        & $add (New-BFFinding -Id 'SVC-BTHSERV-STOPPED' -Area 'Services' -Severity 'Warning' -Title 'Bluetooth Support Service is not running' -Detail 'A radio is present but bthserv is stopped. Starting it (and repairing its triggers) usually brings the toggle back.' -Fixes @('F06'))
    }
    $das = $Svc.Rows | Where-Object Name -eq 'DeviceAssociationService'
    if ($das -and $das.Status -ne 'Running' -and $present.Count -gt 0) {
        & $add (New-BFFinding -Id 'SVC-DAS' -Area 'Services' -Severity 'Warning' -Title 'Device Association Service is not running' -Detail 'Pairing will fail without it.' -Fixes @('F06'))
    }

    # --- Driver store / inbox integrity --------------------------------
    $missingFiles = @($Store.InboxFiles | Where-Object { -not $_.Exists -and $_.File -notmatch 'Legacy.LEEnumerator|AvrcpTransport' })
    if ($missingFiles.Count) {
        & $add (New-BFFinding -Id 'STORE-FILES' -Area 'Driver' -Severity 'Critical' -Title 'Inbox Bluetooth/USB driver files are missing' -Detail 'Windows ships these in every install. Missing files mean a component-store repair is needed.' -Evidence @($missingFiles | ForEach-Object { $_.File }) -Fixes @('F16'))
    }
    $missingInfs = @($Store.InboxInfs | Where-Object { -not $_.Exists -and $_.File -in 'bth.inf','usbhub3.inf','usbxhci.inf' })
    if ($missingInfs.Count) {
        & $add (New-BFFinding -Id 'STORE-INFS' -Area 'Driver' -Severity 'Critical' -Title 'Inbox Bluetooth/USB INF files are missing' -Detail 'bth.inf / usbhub3.inf / usbxhci.inf are part of Windows. Without them no radio or hub can be installed. Run component repair.' -Evidence @($missingInfs | ForEach-Object { $_.File }) -Fixes @('F16'))
    }
    $vendorPk = @($Store.BluetoothPackages | Where-Object { $_.Provider -notmatch 'Microsoft' })
    if ($present.Count -gt 0) {
        foreach ($r in $present) {
            if ($r.NeedsVendorDriver -and $r.ChipVendor -ne 'Module') {
                $pk = Find-BFStorePackagesForDevice -Device $r -Store $Store | Where-Object { $_.Provider -notmatch 'Microsoft' }
                if ($pk.Count -eq 0 -and $vendorPk.Count -eq 0) {
                    & $add (New-BFFinding -Id "STORE-NOVENDOR-$($r.Pid)" -Area 'Driver' -Severity 'Warning' -Title "No $($r.ChipVendor) Bluetooth package in the driver store" -Detail "Windows has no vendor package that lists $($r.HardwareIds[0]). Fetching it from Windows Update (automatic) or the vendor site puts one in place." -Fixes @('F08','F09'))
                }
            }
        }
    }

    # --- Policies / filters / stacks -----------------------------------
    foreach ($h in $Policy.PolicyHits) {
        $sev = 'Warning'; $t = "Bluetooth policy set: $($h.Name) = $($h.Value)"
        if ($h.Name -eq 'AllowBluetooth' -and $h.Value -eq '0') { $sev = 'Critical'; $t = 'Policy AllowBluetooth=0 turns Bluetooth off completely' }
        if ($h.Name -match 'DenyDeviceClasses|DenyUnspecified|DenyDeviceIDs') { $sev = 'Critical'; $t = "Device installation restriction policy: $($h.Name)" }
        & $add (New-BFFinding -Id "POL-$($h.Name)" -Area 'Policy' -Severity $sev -Title $t -Detail "Set at $($h.Path). Policies come from Group Policy, Intune/MDM, or a 'privacy tweaker' tool. Clearing it is reversible (backed up first)." -Evidence @("$($h.Path)\$($h.Name) = $($h.Value)") -Fixes @('F11'))
    }
    $btFilters = @($Policy.ClassFilters | Where-Object { $_.Class -eq 'Bluetooth' })
    if ($btFilters.Count) {
        & $add (New-BFFinding -Id 'FILTER-BT' -Area 'Driver' -Severity 'Warning' -Title 'Filter drivers are attached to the Bluetooth class' -Detail 'Class-wide filter drivers come from third-party Bluetooth software. If that software is gone the filter blocks every Bluetooth device from starting (Code 39/31).' -Evidence @($btFilters | ForEach-Object { "$($_.Position)Filters: $($_.Filter)" }) -Fixes @('F12'))
    }
    $usbFilters = @($Policy.ClassFilters | Where-Object { $_.Class -eq 'USB' })
    if ($usbFilters.Count) {
        & $add (New-BFFinding -Id 'FILTER-USB' -Area 'USB stack' -Severity 'Warning' -Title 'Filter drivers are attached to the USB class' -Detail 'Third-party USB class filters (virtualisation, anti-cheat, USB-over-IP) can prevent hubs and radios from starting.' -Evidence @($usbFilters | ForEach-Object { "$($_.Position)Filters: $($_.Filter)" }))
    }
    foreach ($s in $Policy.ThirdPartyStacks) {
        & $add (New-BFFinding -Id "STACK-$($s.Name.GetHashCode())" -Area 'Software' -Severity 'Warning' -Title "Third-party Bluetooth stack installed: $($s.Name)" -Detail "'$($s.Installed)' replaces or patches the Windows Bluetooth stack. On Windows 10/11 these almost always do more harm than good. Uninstall it, then re-run." -Fixes @('F20'))
    }
    if ($Env.FastStartup -and $present.Count -gt 0 -and @($findingList | Where-Object { $_.Severity -eq 'Critical' }).Count -eq 0) {
        & $add (New-BFFinding -Id 'PWR-FASTSTARTUP' -Area 'Power' -Severity 'Info' -Title 'Fast Startup is enabled' -Detail 'Fast Startup keeps the kernel and drivers from the last session. Radios that misbehave "until I restart" are often this. Turning it off costs a few seconds at boot.' -Fixes @('F19'))
    }

    # --- Children (paired devices) ---------------------------------------
    if ($Inv.ProblemChildren.Count) {
        & $add (New-BFFinding -Id 'CHILD-PROBLEMS' -Area 'Paired devices' -Severity 'Warning' -Title "$($Inv.ProblemChildren.Count) paired device(s)/profile(s) have problems" -Detail 'Individual paired devices failing does not mean the radio is broken. Remove and re-pair the affected device, or reset all pairings.' -Evidence @($Inv.ProblemChildren | Select-Object -First 12 | ForEach-Object { "$($_.FriendlyName) [$($_.InstanceId)] $($_.Status)" }) -Fixes @('F14'))
    }

    # --- Timeline narrative ----------------------------------------------
    $userUninstalls = @($Timeline | Where-Object { $_.Source -eq 'setupapi.dev.log' -and $_.Text -match 'Uninstalled through Device Manager|Update driver. clicked' })
    if ($userUninstalls.Count) {
        & $add (New-BFFinding -Id 'HIST-UNINSTALL' -Area 'History' -Severity 'Warning' -Title "$($userUninstalls.Count) Device Manager action(s) on USB/Bluetooth devices recently" -Detail 'Uninstalling or "updating" the driver of a USB Root Hub or a Bluetooth radio by hand is the most common way Bluetooth gets broken. The list below is exactly what was done and when. Rescan/reboot brings hardware back; drivers may need re-fetching.' -Evidence @($userUninstalls | Select-Object -First 12 | ForEach-Object { ("{0:g}  {1}" -f $_.Time, $_.Text) }) -Fixes @('F01'))
    }
    $failedStarts = @($Timeline | Where-Object { $_.EventId -eq 411 -and $_.Text -match 'BTH|VID_|Bluetooth' } | Select-Object -First 5)
    if ($failedStarts.Count) {
        & $add (New-BFFinding -Id 'HIST-FAILED' -Area 'History' -Severity 'Info' -Title 'Recent Bluetooth driver start failures in the event log' -Detail 'Each line is a time the radio or a Bluetooth device failed to start, with the kernel status code decoded.' -Evidence @($failedStarts | ForEach-Object { ("{0:g}  {1}" -f $_.Time, $_.Text) }))
    }

    # --- All good? -------------------------------------------------------
    $crit = @($findingList | Where-Object { $_.Severity -eq 'Critical' })
    if ($crit.Count -eq 0 -and $present.Count -gt 0) {
        & $add (New-BFFinding -Id 'ALL-OK' -Area 'Summary' -Severity 'OK' -Title 'No critical Bluetooth problems found' -Detail 'Radio present, driver loaded, services in shape. If a specific device will not pair, remove it in Settings and pair again; if audio stutters, that is a profile/driver-version matter rather than a broken stack.')
    }
    return @($findingList)
}

# ---------------------------------------------------------------------------
# Public: Diagnose
# ---------------------------------------------------------------------------
function Invoke-BFDiagnosis {
    <# Runs the full diagnosis and returns a diagnosis object. #>
    [CmdletBinding()]
    param([int]$TimelineDays = 30)
    if (-not $script:BFLogFile) { Start-BFLogFile | Out-Null }
    Write-BFLog -Level STEP -Message "Diagnosis started (v$script:BFVersion)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $env = Get-BFEnvironment
    Write-BFLog -Message ("System: {0} {1} | {2} {3} build {4}.{5} | admin={6}" -f $env.Manufacturer, $env.Model, $env.OSName, $env.DisplayVersion, $env.Build, $env.UBR, $env.IsAdmin)
    $inv = Get-BFDeviceInventory
    Write-BFLog -Message ("Radios present: {0}, ghost radios: {1}, USB controllers: {2}, root hubs: {3}, USB devices present: {4}" -f $inv.PresentRadios.Count, $inv.PhantomRadios.Count, $inv.Controllers.Count, $inv.RootHubs.Count, $inv.UsbDeviceCount)
    foreach ($r in $inv.Radios) { Write-BFLog -Message ("Radio: {0} [{1}] present={2} problem={3} driver={4} {5}" -f $r.ChipName, $r.InstanceId, $r.Present, $r.ProblemCode, $r.InfPath, $r.DriverVersion) }
    $svc = Get-BFServiceState
    $store = Get-BFDriverStore
    Write-BFLog -Message ("Bluetooth driver packages in store: {0}" -f (($store.BluetoothPackages | ForEach-Object { "$($_.Published)=$($_.Original) $($_.Version)" }) -join ', '))
    $tl = Get-BFTimeline -Days $TimelineDays
    $radio = Get-BFRadioState
    $pol = Get-BFPolicyState
    $findings = Invoke-BFAnalysis -Env $env -Inv $inv -Svc $svc -Store $store -Timeline $tl -Radio $radio -Policy $pol
    $order = @{ Critical = 0; Warning = 1; Info = 2; OK = 3 }
    $findings = @($findings | Sort-Object { $order[$_.Severity] }, Area)
    $diag = [pscustomobject]@{
        Version     = $script:BFVersion
        Time        = Get-Date
        Environment = $env
        Inventory   = $inv
        Services    = $svc
        DriverStore = $store
        Timeline    = $tl
        Radio       = $radio
        Policy      = $pol
        Findings    = $findings
        Summary     = Get-BFSummary -Findings $findings -Inv $inv -Env $env
        Links       = $null
        DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
    $diag.Links = Get-BFVendorLinks -Diagnosis $diag
    Report-BFProgress 100 ("Diagnosis finished in {0}s: {1} critical, {2} warnings" -f $diag.DurationSec, @($findings | Where-Object Severity -eq 'Critical').Count, @($findings | Where-Object Severity -eq 'Warning').Count)
    return $diag
}

function Get-BFSummary {
    param($Findings, $Inv, $Env)
    $crit = @($Findings | Where-Object Severity -eq 'Critical')
    $warn = @($Findings | Where-Object Severity -eq 'Warning')
    $headline = ''
    if ($crit.Count -eq 0 -and $Inv.PresentRadios.Count -gt 0) { $headline = 'Bluetooth looks healthy.' }
    elseif ($crit.Count -gt 0) { $headline = $crit[0].Title }
    else { $headline = 'No critical faults, but see warnings.' }
    $verdict = if ($crit.Count -eq 0) { 'Healthy' } elseif ($Env.IsAdmin) { 'Broken - fixable now' } else { 'Broken - run as administrator to fix' }
    [pscustomobject]@{
        Headline      = $headline
        Verdict       = $verdict
        CriticalCount = $crit.Count
        WarningCount  = $warn.Count
        RadioPresent  = ($Inv.PresentRadios.Count -gt 0)
        RadioName     = ($Inv.PresentRadios | Select-Object -First 1).ChipName
        WifiName      = $Inv.WifiName
    }
}

function Get-BFVendorLinks {
    param($Diagnosis)
    $kb = $script:KB
    $links = @()
    $env = $Diagnosis.Environment
    $radios = @($Diagnosis.Inventory.Radios)
    $chipVendors = @($radios | ForEach-Object { $_.ChipVendor } | Where-Object { $_ -and $_ -ne 'Unknown' -and $_ -ne 'Module' } | Select-Object -Unique)
    if ($chipVendors.Count -eq 0 -and $Diagnosis.Inventory.WifiName) { $v = Get-BFChipVendorKey -Vid '' -BusDesc '' -WifiName $Diagnosis.Inventory.WifiName -DriverProvider ''; if ($v -ne 'Unknown') { $chipVendors = @($v) } }
    foreach ($cv in $chipVendors) {
        $d = $kb.ChipVendorDownloads[$cv]
        if ($d) {
            if ($d.Url) { $links += [pscustomobject]@{ Group = 'Chip vendor'; Label = $d.Label; Url = $d.Url; Note = $d.Note } } else { $links += [pscustomobject]@{ Group = 'Chip vendor'; Label = $d.Label; Url = ''; Note = $d.Note } }
            if ($d.Extra) { $links += [pscustomobject]@{ Group = 'Chip vendor'; Label = $d.Extra.Label; Url = $d.Extra.Url; Note = '' } }
        }
    }
    if ($env.Oem) {
        $u = $env.Oem.Url
        if ($u -match '\{serial\}') { if ($env.Serial -and $env.Serial -notmatch 'Default|To be filled|System Serial|^\s*$') { $u = $u -replace '\{serial\}', [uri]::EscapeDataString($env.Serial) } else { $u = $env.Oem.Fallback } }
        $links += [pscustomobject]@{ Group = 'PC maker'; Label = "$($env.Oem.Name) drivers for this exact machine ($($env.Model))"; Url = $u; Note = "Their updater tool: $($env.Oem.Tool)" }
    } else {
        $links += [pscustomobject]@{ Group = 'PC maker'; Label = "Search your PC maker's support site for '$($env.Manufacturer) $($env.Model)' drivers"; Url = ('https://www.bing.com/search?q=' + [uri]::EscapeDataString("$($env.Manufacturer) $($env.Model) bluetooth driver download")); Note = '' }
    }
    $hwids = @()
    foreach ($r in $radios) { if ($r.HardwareIds.Count) { $hwids += ($r.HardwareIds[0] -replace '&REV_[0-9A-F]+$', '') } }
    foreach ($h in ($hwids | Select-Object -Unique)) {
        $links += [pscustomobject]@{ Group = 'Windows Update Catalog'; Label = "Every Microsoft-signed driver ever published for $h"; Url = ($kb.WindowsUpdateCatalogSearch -f [uri]::EscapeDataString($h)); Note = 'Download the newest .cab, extract it, then point Device Manager > Update driver > Browse at the folder.' }
    }
    if ($hwids.Count -eq 0 -and $Diagnosis.Inventory.WifiName -match 'Intel') {
        $links += [pscustomobject]@{ Group = 'Windows Update Catalog'; Label = 'Intel Bluetooth drivers on the Windows Update Catalog'; Url = ($kb.WindowsUpdateCatalogSearch -f [uri]::EscapeDataString('Intel Bluetooth')); Note = '' }
    }
    $links += [pscustomobject]@{ Group = 'Microsoft'; Label = 'Microsoft: Fix Bluetooth problems in Windows'; Url = 'https://support.microsoft.com/windows/fix-bluetooth-problems-in-windows-723e092f-03fa-858b-5c80-131ec3fba75c'; Note = '' }
    return $links
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------
function New-BFBackup {
    <# Exports the registry keys and vendor Bluetooth driver packages the fixes may touch. #>
    param($Diagnosis)
    $dir = Join-Path (Join-Path $script:BFDataDir 'Backups') (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-BFLog -Level STEP -Message "Backing up to $dir"
    $n = 0
    foreach ($k in $script:KB.BackupKeys) {
        $file = Join-Path $dir (($k -replace '[\\:{}]', '_') + '.reg')
        $r = & reg.exe export $k $file /y 2>&1
        if (Test-Path $file) { $n++ }
    }
    # per-radio device parameters
    if ($Diagnosis) {
        foreach ($rd in $Diagnosis.Inventory.Radios) {
            $k = "HKLM\SYSTEM\CurrentControlSet\Enum\$($rd.InstanceId)"
            $file = Join-Path $dir ('Enum_' + ($rd.InstanceId -replace '[\\&{}]', '_') + '.reg')
            $null = & reg.exe export $k $file /y 2>&1
        }
        foreach ($p in ($Diagnosis.DriverStore.BluetoothPackages | Where-Object { $_.Provider -notmatch 'Microsoft' })) {
            $target = Join-Path $dir "Drivers\$($p.Published)"
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            $r = Invoke-BFPnpUtil -Arguments @('/export-driver', $p.Published, $target)
            Write-BFLog -Level DEBUG -Message "export-driver $($p.Published): exit $($r.ExitCode)"
        }
    }
    Set-Content -Path (Join-Path $dir 'README.txt') -Value @"
Windows Bluetooth Fixer backup - $(Get-Date)
Registry: double-click a .reg file to restore that key.
Drivers : pnputil /add-driver "<folder>\*.inf" /install   (run as administrator)
"@
    Write-BFLog -Level OK -Message "Backup complete ($n registry exports)"
    return $dir
}

# ---------------------------------------------------------------------------
# Native helpers (cfgmgr32 / newdev)
# ---------------------------------------------------------------------------
function Initialize-BFNative {
    if (-not ('BluetoothFixer.Native' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace BluetoothFixer {
  public static class Native {
    [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode)] public static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);
    [DllImport("cfgmgr32.dll")] public static extern int CM_Reenumerate_DevNode(uint dnDevInst, uint ulFlags);
    [DllImport("newdev.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr hwndParent, string HardwareId, string FullInfPath, uint InstallFlags, out bool bRebootRequired);
    public const uint INSTALLFLAG_FORCE = 0x1;
    public const uint INSTALLFLAG_NONINTERACTIVE = 0x4;
    public const uint CM_REENUMERATE_SYNCHRONOUS = 0x1;
  }
}
"@ -ErrorAction Stop
    }
}

function Invoke-BFRescan {
    <# Scan for hardware changes (same as Device Manager's action). #>
    $r = Invoke-BFPnpUtil -Arguments @('/scan-devices')
    if ($r.ExitCode -eq 0 -and $r.Output -notmatch 'Failed|denied') { return @{ Success = $true; Message = 'Hardware rescan completed.' } }
    # fallback: cfgmgr32 re-enumerate root
    try {
        Initialize-BFNative
        [uint32]$root = 0
        $rc = [BluetoothFixer.Native]::CM_Locate_DevNodeW([ref]$root, $null, 0)
        if ($rc -ne 0) { return @{ Success = $false; Message = "CM_Locate_DevNode failed ($rc). pnputil said: $($r.Output)" } }
        $rc = [BluetoothFixer.Native]::CM_Reenumerate_DevNode($root, [BluetoothFixer.Native]::CM_REENUMERATE_SYNCHRONOUS)
        if ($rc -eq 0) { return @{ Success = $true; Message = 'Hardware rescan completed (cfgmgr32).' } }
        return @{ Success = $false; Message = "CM_Reenumerate_DevNode failed ($rc). pnputil said: $($r.Output)" }
    } catch { return @{ Success = $false; Message = "Rescan failed: $($_.Exception.Message). pnputil said: $($r.Output)" } }
}

function Invoke-BFRestartDevice {
    param([Parameter(Mandatory)][string]$InstanceId)
    $r = Invoke-BFPnpUtil -Arguments @('/restart-device', $InstanceId)
    if ($r.ExitCode -eq 0 -and $r.Output -notmatch 'Failed') { return @{ Success = $true; Message = "Restarted $InstanceId"; RebootRequired = ($r.Output -match 'reboot') } }
    try {
        Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        return @{ Success = $true; Message = "Restarted $InstanceId (disable/enable)"; RebootRequired = $false }
    } catch { return @{ Success = $false; Message = "Restart failed: $($_.Exception.Message). pnputil said: $($r.Output)" } }
}

function Install-BFDriverForDevice {
    <# Installs a specific INF onto every device with the given hardware ID (UpdateDriverForPlugAndPlayDevices). #>
    param([Parameter(Mandatory)][string]$HardwareId, [Parameter(Mandatory)][string]$InfPath, [switch]$Force)
    Initialize-BFNative
    if (-not (Test-Path $InfPath)) { return @{ Success = $false; Message = "INF not found: $InfPath" } }
    $reboot = $false
    $flags = [BluetoothFixer.Native]::INSTALLFLAG_NONINTERACTIVE
    if ($Force) { $flags = $flags -bor [BluetoothFixer.Native]::INSTALLFLAG_FORCE }
    $ok = [BluetoothFixer.Native]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $HardwareId, $InfPath, $flags, [ref]$reboot)
    if ($ok) { return @{ Success = $true; Message = "Installed $InfPath on $HardwareId"; RebootRequired = $reboot } }
    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $why = switch ($err) { 0xE0000235 { 'in-use / 64-bit mismatch' } 0xE000022B { 'no compatible device found for that hardware ID' } 0xE0000203 { 'no better driver found (use Force)' } 0xE0000228 { 'no such device instance' } 0x000000E7 { 'no such device installed' } default { "Win32 error $err (0x$('{0:X}' -f $err))" } }
    return @{ Success = $false; Message = "UpdateDriverForPlugAndPlayDevices failed: $why" }
}

# ---------------------------------------------------------------------------
# Fix catalog
# ---------------------------------------------------------------------------
function Get-BFFixCatalog {
    @(
        [pscustomobject]@{ Id = 'F01'; Name = 'Rescan hardware';                          Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Same as Device Manager > Scan for hardware changes. Re-creates uninstalled devices (root hubs, radios) from the hardware that is physically there.' }
        [pscustomobject]@{ Id = 'F02'; Name = 'Restart USB host controller(s)';            Risk = 'Moderate'; NeedsAdmin = $true;  Description = 'Restarts the xHCI controller(s) whose root hub is missing or failed. USB devices blink out for 2-3 seconds; a USB keyboard/mouse comes straight back. Never removes anything.' }
        [pscustomobject]@{ Id = 'F03'; Name = 'Enable disabled Bluetooth radio';           Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Turns a Code-22 (disabled) radio back on.' }
        [pscustomobject]@{ Id = 'F04'; Name = 'Restart Bluetooth radio device';            Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Disable/enable cycle of the radio. Clears Code 10/43 firmware hangs surprisingly often.' }
        [pscustomobject]@{ Id = 'F05'; Name = 'Remove ghost Bluetooth devices';            Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Deletes not-present (phantom) radio and Bluetooth child entries so Windows enumerates fresh. Never touches present devices, hubs or controllers.' }
        [pscustomobject]@{ Id = 'F06'; Name = 'Reset Bluetooth services to Windows defaults'; Risk = 'Safe';  NeedsAdmin = $true;  Description = 'Restores Start type of every Bluetooth/USB service and kernel driver to the clean-install default, restores bthserv start triggers, and starts the services that should be running.' }
        [pscustomobject]@{ Id = 'F07'; Name = 'Reinstall the correct radio driver';        Risk = 'Moderate'; NeedsAdmin = $true;  Description = 'If a vendor package that lists this radio is already in the driver store, installs it onto the device. Otherwise removes the (wrong/broken) device entry and rescans so Windows re-matches the best package. Backs up first.' }
        [pscustomobject]@{ Id = 'F08'; Name = 'Fetch driver from Windows Update';          Risk = 'Moderate'; NeedsAdmin = $true;  Description = 'Asks Windows Update (via the official agent API) for driver updates whose hardware ID matches your radio, downloads and installs them. Needs internet. This is how you get the Intel/Realtek/MediaTek driver without hunting on vendor sites.' }
        [pscustomobject]@{ Id = 'F09'; Name = 'Open vendor download pages';                Risk = 'Safe';     NeedsAdmin = $false; Description = 'Opens the exact pages for your chip vendor, your PC maker (by serial number when possible) and the Windows Update Catalog search for your hardware ID.' }
        [pscustomobject]@{ Id = 'F10'; Name = 'Turn Bluetooth radio on / airplane mode off'; Risk = 'Safe';  NeedsAdmin = $false; Description = 'Switches the radio on through the Radio Management API and clears airplane mode.' }
        [pscustomobject]@{ Id = 'F11'; Name = 'Clear Bluetooth-blocking policies';         Risk = 'Moderate'; NeedsAdmin = $true;  Description = 'Removes AllowBluetooth=0 and device-installation restriction policies. Backed up as .reg first. If the PC is managed by a company, the policy will come back and you should ask IT instead.' }
        [pscustomobject]@{ Id = 'F12'; Name = 'Remove third-party Bluetooth class filters'; Risk = 'Moderate'; NeedsAdmin = $true; Description = 'Clears UpperFilters/LowerFilters on the Bluetooth device class (leftovers of uninstalled Bluetooth software). Backed up first. Reboot required.' }
        [pscustomobject]@{ Id = 'F13'; Name = 'Disable power management on the radio';     Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Sets EnhancedPowerManagementEnabled=0 and SelectiveSuspendEnabled=0 on the radio and turns off USB selective suspend in the active power plan. Fixes "Bluetooth gone after sleep". Radio restart applies it.' }
        [pscustomobject]@{ Id = 'F14'; Name = 'Forget all paired devices';                 Risk = 'Moderate'; NeedsAdmin = $true;  Description = 'Removes every paired Bluetooth device entry (BTHENUM/BTHLE). You will pair your devices again. Fixes corrupted pairing records that make the radio unusable.' }
        [pscustomobject]@{ Id = 'F15'; Name = 'Run the Windows Bluetooth troubleshooter';  Risk = 'Safe';     NeedsAdmin = $false; Description = 'Launches the built-in troubleshooter (msdt BluetoothDiagnostic, or Get Help on newer builds).' }
        [pscustomobject]@{ Id = 'F16'; Name = 'Repair Windows component store (DISM + SFC)'; Risk = 'Moderate'; NeedsAdmin = $true; Description = 'DISM /RestoreHealth then SFC /scannow. Restores missing inbox Bluetooth/USB driver files and INFs. Takes 10-30 minutes; needs internet for DISM.' }
        [pscustomobject]@{ Id = 'F17'; Name = 'Reboot now and verify afterwards';          Risk = 'Reboot';   NeedsAdmin = $true;  Description = 'Restarts Windows in 30 seconds and re-runs this tool once after logon to confirm the fix.' }
        [pscustomobject]@{ Id = 'F18'; Name = 'Hardware / BIOS checklist';                 Risk = 'Safe';     NeedsAdmin = $false; Description = 'Shows the exact steps for a radio that Windows cannot see at all: BIOS wireless setting, power drain, module reseat.' }
        [pscustomobject]@{ Id = 'F19'; Name = 'Turn off Fast Startup';                     Risk = 'Safe';     NeedsAdmin = $true;  Description = 'Sets HiberbootEnabled=0 so every boot is a clean driver initialisation.' }
        [pscustomobject]@{ Id = 'F20'; Name = 'Open Programs and Features';                Risk = 'Safe';     NeedsAdmin = $false; Description = 'To uninstall third-party Bluetooth stacks.' }
        [pscustomobject]@{ Id = 'F21'; Name = 'Re-stage inbox USB hub/xHCI driver from the component store'; Risk = 'Moderate'; NeedsAdmin = $true; Description = 'When Windows Update left ucx01000.sys newer than the installed usbhub3/usbxhci package, imports the matching Microsoft package from WinSxS into the driver store and installs it on the controllers/hubs. Only offered when the mismatch exists. USB devices blink for a few seconds.' }
    )
}

function Get-BFRecommendedFixes {
    <# Ordered, de-duplicated fix IDs from the findings (critical first). #>
    param($Diagnosis, [switch]$IncludeInfo)
    $ids = New-Object System.Collections.ArrayList
    $order = @('Critical','Warning','Info')
    if (-not $IncludeInfo) { $order = @('Critical','Warning') }
    foreach ($sev in $order) {
        foreach ($f in ($Diagnosis.Findings | Where-Object Severity -eq $sev)) { foreach ($x in $f.Fixes) { if (-not $ids.Contains($x)) { [void]$ids.Add($x) } } }
    }
    # Sensible execution order: rescan before restarting controllers, services before driver work, reboot last, links last
    $rank = @{ F10 = 1; F06 = 2; F11 = 3; F12 = 4; F01 = 5; F02 = 6; F21 = 7; F03 = 8; F04 = 9; F05 = 10; F13 = 11; F07 = 12; F08 = 13; F14 = 14; F19 = 15; F16 = 16; F17 = 90; F09 = 95; F18 = 96; F15 = 97; F20 = 98 }
    return @($ids | Sort-Object { if ($rank.ContainsKey($_)) { $rank[$_] } else { 50 } })
}

# ---------------------------------------------------------------------------
# Fix implementations
# ---------------------------------------------------------------------------
function Invoke-BFFix {
    <# Executes one fix. Returns @{Id; Success; Message; RebootRequired; Skipped}. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FixId, $Diagnosis, [string]$BackupDir, [switch]$Confirmed)
    $cat = Get-BFFixCatalog | Where-Object Id -eq $FixId
    if (-not $cat) { return @{ Id = $FixId; Success = $false; Message = "Unknown fix $FixId" } }
    $isAdmin = Test-BFAdmin
    if ($cat.NeedsAdmin -and -not $isAdmin) { return @{ Id = $FixId; Success = $false; Skipped = $true; Message = "'$($cat.Name)' needs administrator rights. Re-launch as administrator." } }
    Write-BFLog -Level STEP -Message "FIX $FixId - $($cat.Name)"
    $res = @{ Id = $FixId; Success = $false; Message = ''; RebootRequired = $false; Skipped = $false }
    try {
        switch ($FixId) {
            'F01' {
                $r = Invoke-BFRescan
                Start-Sleep -Seconds 4
                $res.Success = $r.Success; $res.Message = $r.Message
                if ($r.Success) {
                    $hubs = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\ROOT_HUB' })
                    $bad = @($hubs | Where-Object { $_.Status -ne 'OK' })
                    $res.Message += " Root hubs now: $($hubs.Count) (with problems: $($bad.Count))."
                    foreach ($h in $bad) {
                        $st = (Get-BFDevProp -InstanceId $h.InstanceId -Keys 'DEVPKEY_Device_ProblemStatus')['DEVPKEY_Device_ProblemStatus']
                        if ($st -and ('0x{0:X8}' -f ([uint32]([int64]$st -band 0xFFFFFFFF))) -eq '0xC0000206') { $res.RebootRequired = $true; $res.Message += ' A hub failed with STATUS_INVALID_BUFFER_SIZE, which only a reboot clears.' ; break }
                    }
                    $rad = @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -notmatch '^(BTH|BTHENUM|BTHLE)\\' })
                    $res.Message += " Bluetooth radios present: $($rad.Count)."
                }
            }
            'F02' {
                $targets = @()
                if ($Diagnosis) {
                    foreach ($c in $Diagnosis.Inventory.Controllers) {
                        if (-not $c.Present) { continue }
                        $hubs = @($Diagnosis.Inventory.RootHubs | Where-Object { $_.Parent -eq $c.InstanceId })
                        if ($hubs.Count -eq 0 -or ($hubs | Where-Object { -not $_.Present -or $_.ProblemCode -gt 0 })) { $targets += $c.InstanceId }
                    }
                }
                if ($targets.Count -eq 0) {
                    # live re-check
                    $ctrls = @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^PCI\\' -and $_.InstanceId -notmatch 'USB4_MS_CM' })
                    foreach ($c in $ctrls) {
                        $kids = @((Get-BFDevProp -InstanceId $c.InstanceId -Keys 'DEVPKEY_Device_Children')['DEVPKEY_Device_Children'])
                        $live = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\ROOT_HUB' -and $_.Present -and $_.Status -eq 'OK' })
                        $has = $false; foreach ($k in $kids) { if ($live.InstanceId -contains $k) { $has = $true } }
                        if (-not $has) { $targets += $c.InstanceId }
                    }
                }
                if ($targets.Count -eq 0) { $res.Success = $true; $res.Skipped = $true; $res.Message = 'Every USB controller already has a healthy root hub. Nothing to restart.'; break }
                $msgs = @()
                foreach ($t in $targets) {
                    Write-BFLog -Message "Restarting controller $t"
                    $r = Invoke-BFRestartDevice -InstanceId $t
                    $msgs += $r.Message
                    if ($r.RebootRequired) { $res.RebootRequired = $true }
                }
                Start-Sleep -Seconds 5
                $null = Invoke-BFRescan
                Start-Sleep -Seconds 3
                $hubs = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\ROOT_HUB' -and $_.Present })
                $bad = @($hubs | Where-Object { $_.Status -ne 'OK' })
                $res.Success = ($hubs.Count -gt 0 -and $bad.Count -eq 0)
                $res.Message = ($msgs -join ' ') + " Root hubs present: $($hubs.Count), with problems: $($bad.Count)."
                if (-not $res.Success) { $res.RebootRequired = $true; $res.Message += ' The hub did not come back cleanly; a reboot will finish the job.' }
            }
            'F03' {
                $targets = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Present -and $_.Status -eq 'Error' -and $_.InstanceId -notmatch '^(BTH|BTHENUM|BTHLE)\\' })
                $targets += @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Present -and $_.ConfigManagerErrorCode -eq 'CM_PROB_DISABLED' -and $_.InstanceId -match '^USB\\VID_(8087|0BDA|0A12|0CF3|0A5C|0E8D|13D3|0489|04CA|3574)' })
                $done = 0
                foreach ($t in ($targets | Select-Object -Unique InstanceId)) {
                    $r = Invoke-BFPnpUtil -Arguments @('/enable-device', $t.InstanceId)
                    if ($r.ExitCode -eq 0) { $done++ } else { try { Enable-PnpDevice -InstanceId $t.InstanceId -Confirm:$false -ErrorAction Stop; $done++ } catch { } }
                }
                $res.Success = $true; $res.Message = "Enabled $done device(s)."
            }
            'F04' {
                $radios = @()
                if ($Diagnosis) { $radios = @($Diagnosis.Inventory.PresentRadios | ForEach-Object { $_.InstanceId }) }
                if ($radios.Count -eq 0) { $radios = @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -notmatch '^(BTH|BTHENUM|BTHLE)\\' } | ForEach-Object { $_.InstanceId }) }
                if ($radios.Count -eq 0) { $res.Skipped = $true; $res.Message = 'No radio present to restart.'; break }
                $msgs = @(); $ok = $true
                foreach ($id in $radios) { $r = Invoke-BFRestartDevice -InstanceId $id; $msgs += $r.Message; if (-not $r.Success) { $ok = $false } }
                Start-Sleep -Seconds 3
                $res.Success = $ok; $res.Message = $msgs -join ' '
            }
            'F05' {
                $ghosts = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { -not $_.Present -and ($_.Class -eq 'Bluetooth' -or $_.InstanceId -match '^(BTH|BTHENUM|BTHLE|BTHLEDEVICE)\\' -or $_.InstanceId -match '^USB\\VID_(8087|0BDA|0A12|0CF3|0A5C|0E8D|13D3|0489|04CA|3574)') })
                $n = 0; $skipped = 0
                foreach ($g in $ghosts) {
                    if (Test-BFProtectedDevice -InstanceId $g.InstanceId) { $skipped++; continue }
                    $r = Invoke-BFPnpUtil -Arguments @('/remove-device', $g.InstanceId)
                    if ($r.ExitCode -eq 0) { $n++ } else { Write-BFLog -Level WARN -Message "Could not remove $($g.InstanceId): $($r.Output)" }
                }
                $res.Success = $true; $res.Message = "Removed $n ghost device(s) out of $($ghosts.Count) (protected skipped: $skipped)."
            }
            'F06' {
                $changed = @(); $started = @()
                foreach ($b in $script:KB.ServiceBaseline) {
                    $rk = "HKLM:\SYSTEM\CurrentControlSet\Services\$($b.Name)"
                    if (-not (Test-Path $rk)) { continue }
                    $cur = (Get-ItemProperty $rk -ErrorAction SilentlyContinue).Start
                    if ($cur -ne $null -and [int]$cur -ne [int]$b.Start) {
                        $ok = $false
                        if ($b.Kind -eq 'Service') {
                            $mode = if ($b.Start -eq 2) { 'auto' } else { 'demand' }
                            $o = & sc.exe config $b.Name start= $mode 2>&1
                            $ok = ($LASTEXITCODE -eq 0)
                        }
                        if (-not $ok) { try { Set-ItemProperty -Path $rk -Name Start -Value ([int]$b.Start) -Type DWord -ErrorAction Stop; $ok = $true } catch { Write-BFLog -Level WARN -Message "Could not set Start on $($b.Name): $($_.Exception.Message)" } }
                        if ($ok) { $changed += "$($b.Name): $cur -> $($b.Start)" }
                    }
                }
                # bthserv triggers
                $trig = @(); try { $trig = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\bthserv\TriggerInfo' -ErrorAction Stop) } catch { }
                if ($trig.Count -eq 0 -and (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bthserv')) {
                    $o = & sc.exe triggerinfo bthserv start/device/0850302a-b344-4fda-9be9-90576b8d46f0 2>&1
                    if ($LASTEXITCODE -eq 0) { $changed += 'bthserv: restored radio-arrival start trigger' } else { Write-BFLog -Level WARN -Message "sc triggerinfo failed: $o" }
                }
                # start what should run
                foreach ($n in 'SystemEventsBroker','DeviceAssociationService','RmSvc','bthserv','DeviceInstall','DsmSvc') {
                    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
                    if ($s -and $s.Status -ne 'Running') { try { Start-Service -Name $n -ErrorAction Stop; $started += $n } catch { Write-BFLog -Level WARN -Message "Could not start ${n}: $($_.Exception.Message)" } }
                }
                $u = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'BluetoothUserService_*' -and $_.Status -ne 'Running' }
                foreach ($s in $u) { try { Start-Service -Name $s.Name -ErrorAction Stop; $started += $s.Name } catch { } }
                $res.Success = $true
                $res.Message = "Start types corrected: $($changed.Count)" + $(if ($changed.Count) { ' (' + ($changed -join '; ') + ')' } else { '' }) + ". Services started: " + $(if ($started.Count) { $started -join ', ' } else { 'none needed' }) + '.'
            }
            'F07' {
                if (-not $Diagnosis) { $res.Message = 'Run a diagnosis first.'; break }
                $radios = @($Diagnosis.Inventory.PresentRadios)
                if ($radios.Count -eq 0) { $res.Skipped = $true; $res.Message = 'No radio is present; fix the USB stack / hardware first.'; break }
                $msgs = @(); $any = $false
                foreach ($r in $radios) {
                    $pk = @(Find-BFStorePackagesForDevice -Device $r -Store $Diagnosis.DriverStore | Where-Object { $_.Provider -notmatch 'Microsoft' })
                    $best = $null
                    foreach ($p in $pk) { if (-not $best) { $best = $p } else { try { if ([version]$p.Version -gt [version]$best.Version) { $best = $p } } catch { } } }
                    $hwid = ($r.HardwareIds | Select-Object -First 1)
                    if ($best -and $hwid) {
                        $inf = Join-Path $env:SystemRoot "INF\$($best.Published)"
                        Write-BFLog -Message "Installing $($best.Published) ($($best.Original) $($best.Version)) onto $hwid"
                        $ir = Install-BFDriverForDevice -HardwareId $hwid -InfPath $inf -Force
                        $msgs += "$($r.ChipName): $($ir.Message)"
                        if ($ir.Success) { $any = $true; if ($ir.RebootRequired) { $res.RebootRequired = $true } }
                    } else {
                        if (Test-BFProtectedDevice -InstanceId $r.InstanceId) { $msgs += "$($r.ChipName): protected device, not removed."; continue }
                        # Wrong-vendor forced driver: also delete that package if it does not list this HWID
                        if ($r.InfPath -match '^oem' -and $r.DriverProvider -notmatch 'Microsoft') {
                            $lists = $false
                            foreach ($p in $Diagnosis.DriverStore.BluetoothPackages) { if ($p.Published -eq $r.InfPath) { foreach ($h in $r.HardwareIds) { if ($p.HardwareIds -contains $h.ToUpper() -or $p.HardwareIds -contains ($h.ToUpper() -replace '&REV_[0-9A-F]+$','')) { $lists = $true } } } }
                            if (-not $lists) {
                                Write-BFLog -Message "Package $($r.InfPath) does not list $hwid - it was forced. Removing device and deleting the package."
                                $null = Invoke-BFPnpUtil -Arguments @('/remove-device', $r.InstanceId)
                                $d = Invoke-BFPnpUtil -Arguments @('/delete-driver', $r.InfPath, '/uninstall', '/force')
                                $msgs += "Deleted forced package $($r.InfPath): exit $($d.ExitCode)."
                            } else {
                                $null = Invoke-BFPnpUtil -Arguments @('/remove-device', $r.InstanceId)
                            }
                        } else {
                            Write-BFLog -Message "Removing device $($r.InstanceId) so Windows re-matches a driver"
                            $null = Invoke-BFPnpUtil -Arguments @('/remove-device', $r.InstanceId)
                        }
                        Start-Sleep -Seconds 2
                        $sc = Invoke-BFRescan
                        Start-Sleep -Seconds 6
                        $back = Get-PnpDevice -InstanceId $r.InstanceId -ErrorAction SilentlyContinue
                        if ($back) { $msgs += "$($r.ChipName): re-enumerated, status $($back.Status)."; $any = ($back.Status -eq 'OK') } else { $msgs += "$($r.ChipName): removed and rescanned ($($sc.Message)). If it does not return, reboot." ; $res.RebootRequired = $true }
                    }
                }
                $res.Success = $any; $res.Message = $msgs -join ' '
            }
            'F08' {
                $hwids = @()
                if ($Diagnosis) { foreach ($r in $Diagnosis.Inventory.PresentRadios) { $hwids += $r.HardwareIds } }
                $hwl = @($hwids | ForEach-Object { $_.ToLower() -replace '&rev_[0-9a-f]+$', '' } | Select-Object -Unique)
                Write-BFLog -Message 'Asking Windows Update for driver updates (this can take a minute)...'
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                try { $searcher.ServerSelection = 2 } catch { }
                $sr = $searcher.Search("IsInstalled=0 and Type='Driver'")
                $coll = New-Object -ComObject Microsoft.Update.UpdateColl
                $picked = @()
                for ($i = 0; $i -lt $sr.Updates.Count; $i++) {
                    $u = $sr.Updates.Item($i)
                    $hw = ''; $cls = ''
                    try { $hw = "$($u.DriverHardwareID)".ToLower() } catch { }
                    try { $cls = "$($u.DriverClass)" } catch { }
                    $match = $false
                    if ($cls -match 'Bluetooth') { $match = $true }
                    foreach ($h in $hwl) { if ($hw -and ($h -like "$hw*" -or $hw -like "$h*")) { $match = $true } }
                    if ($match) { $picked += $u.Title; [void]$coll.Add($u); Write-BFLog -Message "Windows Update offers: $($u.Title) [$hw]" }
                }
                if ($coll.Count -eq 0) { $res.Success = $true; $res.Skipped = $true; $res.Message = "Windows Update has no Bluetooth driver update for this PC ($($sr.Updates.Count) driver updates checked). Use the vendor links instead."; break }
                Write-BFLog -Message "Downloading $($coll.Count) driver update(s)"
                $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll
                $dr = $dl.Download()
                if ($dr.ResultCode -ne 2) { $res.Message = "Download failed (result $($dr.ResultCode), HRESULT 0x$('{0:X8}' -f $dr.HResult))."; break }
                Write-BFLog -Message 'Installing'
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
                $ir = $inst.Install()
                $res.Success = ($ir.ResultCode -eq 2 -or $ir.ResultCode -eq 3)
                $res.RebootRequired = [bool]$ir.RebootRequired
                $res.Message = "Installed from Windows Update: $($picked -join '; ') (result $($ir.ResultCode)$(if ($ir.RebootRequired) { ', reboot required' }))."
            }
            'F09' {
                $links = if ($Diagnosis) { $Diagnosis.Links } else { @() }
                $n = 0
                foreach ($l in $links) { if ($l.Url) { try { Start-Process $l.Url; $n++ } catch { } } }
                $res.Success = $true; $res.Message = "Opened $n page(s) in your browser."
            }
            'F10' {
                $m = @()
                if ((Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\RadioManagement\SystemRadioState') -and $isAdmin) {
                    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\RadioManagement\SystemRadioState' -Name '(default)' -Value 0 -ErrorAction Stop; $m += 'Airplane mode flag cleared.' } catch { }
                }
                $m += (Set-BFBluetoothRadioOn)
                $res.Success = $true; $res.Message = $m -join ' '
            }
            'F11' {
                $n = 0
                foreach ($k in $script:KB.BluetoothPolicyKeys) {
                    if (-not (Test-Path $k.Path)) { continue }
                    $p = Get-ItemProperty $k.Path -ErrorAction SilentlyContinue
                    foreach ($v in $k.Values) {
                        if ($p.PSObject.Properties[$v]) {
                            $val = $p.$v
                            $block = ($v -eq 'AllowBluetooth' -and $val -eq 0) -or ($v -match '^Deny') -or ($v -match 'Allow' -and $val -eq 0) -or ($v -eq 'ServicesAllowedList')
                            if ($block) { try { Remove-ItemProperty -Path $k.Path -Name $v -ErrorAction Stop; $n++; Write-BFLog -Message "Removed policy $($k.Path)\$v" } catch { Write-BFLog -Level WARN -Message "Could not remove $v : $($_.Exception.Message)" } }
                        }
                    }
                }
                $null = & gpupdate.exe /target:computer /force 2>&1
                $res.Success = $true; $res.Message = "Removed $n blocking policy value(s). If they return after a while, this PC is managed (Intune/Group Policy) and IT must lift the restriction."
            }
            'F12' {
                $g = $script:KB.ClassGuids.Bluetooth
                $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$g"
                $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
                $removed = @()
                foreach ($name in 'UpperFilters','LowerFilters') { if ($p.PSObject.Properties[$name]) { $removed += "$name=$($p.$name)"; Remove-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue } }
                $res.Success = $true; $res.RebootRequired = ($removed.Count -gt 0)
                $res.Message = if ($removed.Count) { "Removed Bluetooth class filters: $($removed -join '; '). Reboot required." } else { 'No Bluetooth class filters were present.' }
            }
            'F13' {
                $n = 0
                $radios = if ($Diagnosis) { @($Diagnosis.Inventory.PresentRadios) } else { @() }
                foreach ($r in $radios) {
                    if ($r.InstanceId -notmatch '^USB\\') { continue }
                    $k = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($r.InstanceId)\Device Parameters"
                    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                    Set-ItemProperty -Path $k -Name EnhancedPowerManagementEnabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $k -Name SelectiveSuspendEnabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $k -Name AllowIdleIrpInD3 -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    $n++
                    $null = Invoke-BFRestartDevice -InstanceId $r.InstanceId
                }
                $null = & powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 0 2>&1
                $null = & powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 0 2>&1
                $null = & powercfg.exe /setactive SCHEME_CURRENT 2>&1
                $res.Success = $true; $res.Message = "Power management disabled on $n radio(s); USB selective suspend turned off in the active power plan."
            }
            'F14' {
                $kids = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^(BTHENUM|BTHLE|BTHLEDEVICE)\\' })
                $n = 0
                foreach ($k in $kids) { $r = Invoke-BFPnpUtil -Arguments @('/remove-device', $k.InstanceId); if ($r.ExitCode -eq 0) { $n++ } }
                $res.Success = $true; $res.Message = "Removed $n paired-device entries. Pair your devices again from Settings > Bluetooth & devices."
            }
            'F15' {
                $msdt = Join-Path $env:SystemRoot 'System32\msdt.exe'
                if (Test-Path $msdt) { Start-Process $msdt -ArgumentList '/id BluetoothDiagnostic'; $res.Message = 'Launched the Bluetooth troubleshooter.' }
                else { Start-Process 'ms-settings:troubleshoot'; $res.Message = 'Opened Settings > Troubleshoot (pick Bluetooth).' }
                $res.Success = $true
            }
            'F16' {
                Write-BFLog -Message 'DISM /Online /Cleanup-Image /RestoreHealth (this takes a while)'
                $d = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
                Write-BFLog -Level DEBUG -Message ($d -replace '\s+', ' ')
                Write-BFLog -Message 'sfc /scannow'
                $s = & sfc.exe /scannow 2>&1 | Out-String
                $s = ($s -replace "`0", '') -replace '\s+', ' '
                Write-BFLog -Level DEBUG -Message $s
                $res.Success = ($d -match 'completed successfully' -or $s -match 'did not find any integrity violations|successfully repaired')
                $res.RebootRequired = ($s -match 'repaired' -or $d -match 'restart')
                $res.Message = 'Component repair finished. DISM: ' + $(if ($d -match 'completed successfully') { 'OK' } else { 'see log' }) + '. SFC: ' + $(if ($s -match 'did not find any integrity violations') { 'no violations' } elseif ($s -match 'successfully repaired') { 'repaired files (reboot)' } else { 'see log' }) + '.'
            }
            'F17' {
                if (-not $Confirmed) { $res.Skipped = $true; $res.Message = 'Reboot needs explicit confirmation.'; break }
                $gui = Join-Path $script:BFRoot 'BluetoothFixer.GUI.ps1'
                $cmd = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$gui`" -Verify"
                try { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'BluetoothFixerVerify' -Value $cmd -ErrorAction Stop } catch { Write-BFLog -Level WARN -Message "Could not register post-reboot verification: $($_.Exception.Message)" }
                & shutdown.exe /r /t 30 /c "Windows Bluetooth Fixer: restarting to finish the Bluetooth repair. Save your work." 2>&1 | Out-Null
                $res.Success = $true; $res.RebootRequired = $true; $res.Message = 'Reboot scheduled in 30 seconds. The tool re-runs after logon to verify. (Cancel with: shutdown /a)'
            }
            'F18' {
                $res.Success = $true
                $res.Message = @"
Radio invisible to Windows - hardware checklist:
1. Full power drain: shut down (not restart), unplug the charger, hold the power button 30 seconds, boot. Combo cards keep their Bluetooth half in a low-power state that only a cold start clears.
2. BIOS/UEFI: look under Wireless / Onboard Devices / Advanced for 'Bluetooth' or 'Wireless Device Enable' and make sure it is Enabled. Dell: Settings > Wireless > Wireless Device Enable. Lenovo: Config > Network. HP: Advanced > Built-In Device Options.
3. Load BIOS defaults if you have changed anything there, then re-enable Wireless.
4. If a Windows Update or driver update preceded the failure, roll back that driver in Device Manager (Properties > Driver > Roll Back).
5. Laptop with an M.2 Wi-Fi card: reseat the card (one screw, two antenna leads). Bluetooth on Intel/MediaTek/Realtek cards rides the USB pins, which are the ones that lose contact first.
6. Still nothing after all that: the Bluetooth half of the module is dead. A USB Bluetooth 5.x dongle (Intel or Realtek RTL8761B based) is a 15-dollar fix.
"@
            }
            'F19' {
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
                $res.Success = $true; $res.Message = 'Fast Startup disabled. Takes effect at the next shutdown.'
            }
            'F20' {
                Start-Process 'appwiz.cpl'; $res.Success = $true; $res.Message = 'Opened Programs and Features.'
            }
            'F21' {
                $us = Get-BFUsbStackVersions
                $todo = @()
                if ($us.WinSxSHubInf) { $todo += $us.WinSxSHubInf }
                if ($us.WinSxSXhciInf) { $todo += $us.WinSxSXhciInf }
                if ($todo.Count -eq 0) { $res.Success = $true; $res.Skipped = $true; $res.Message = "No mismatch to fix (ucx $($us.Ucx), hub $($us.UsbHub3), xhci $($us.UsbXhci)) or no matching package in the component store."; break }
                $msgs = @(); $ok = $true
                foreach ($inf in $todo) {
                    Write-BFLog -Message "Staging $inf"
                    $r = Invoke-BFPnpUtil -Arguments @('/add-driver', $inf) -TimeoutSec 180
                    if ($r.ExitCode -ne 0 -and $r.Output -notmatch 'added|Total attempted:\s+1\s+Number successfully imported:\s+1') { $ok = $false; $msgs += "Stage failed for $(Split-Path $inf -Leaf): $(($r.Output -replace '\s+',' ').Trim())"; continue }
                    Write-BFLog -Message "Installing $inf on matching devices"
                    $r2 = Invoke-BFPnpUtil -Arguments @('/add-driver', $inf, '/install') -TimeoutSec 300
                    $msgs += "$(Split-Path $inf -Leaf): $(($r2.Output -replace '\s+',' ').Trim())"
                    if ($r2.Output -match 'reboot|restart') { $res.RebootRequired = $true }
                }
                Start-Sleep -Seconds 5
                $null = Invoke-BFRescan
                Start-Sleep -Seconds 3
                $hubs = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\ROOT_HUB' -and $_.Present })
                $bad = @($hubs | Where-Object { $_.Status -ne 'OK' })
                $after = Get-BFUsbStackVersions
                $res.Success = $ok -and ($hubs.Count -gt 0) -and ($bad.Count -eq 0)
                $res.Message = ($msgs -join ' ') + " Versions now: ucx $($after.Ucx), hub $($after.UsbHub3), xhci $($after.UsbXhci). Root hubs present: $($hubs.Count), with problems: $($bad.Count)."
                if ($bad.Count -gt 0) { $res.RebootRequired = $true }
            }
            default { $res.Message = "Fix $FixId is not implemented." }
        }
    } catch {
        $res.Success = $false
        $res.Message = "Fix failed: $($_.Exception.Message)"
        Write-BFLog -Level ERROR -Message $res.Message
    }
    $lvl = if ($res.Success) { 'OK' } elseif ($res.Skipped) { 'WARN' } else { 'ERROR' }
    Write-BFLog -Level $lvl -Message "FIX $FixId result: $($res.Message)"
    return $res
}

function Invoke-BFFixPlan {
    <# Runs a list of fixes in order with a backup first. Returns results array. #>
    param([string[]]$FixIds, $Diagnosis, [switch]$ConfirmReboot)
    $results = @()
    $needsBackup = @($FixIds | Where-Object { $_ -in 'F06','F07','F11','F12','F13','F14','F19','F05' }).Count -gt 0
    $backup = $null
    if ($needsBackup -and (Test-BFAdmin)) { try { $backup = New-BFBackup -Diagnosis $Diagnosis } catch { Write-BFLog -Level WARN -Message "Backup failed: $($_.Exception.Message)" } }
    foreach ($id in $FixIds) {
        $r = Invoke-BFFix -FixId $id -Diagnosis $Diagnosis -BackupDir $backup -Confirmed:$ConfirmReboot
        $results += [pscustomobject]$r
        if ($id -eq 'F17' -and $r.Success) { break }
    }
    return $results
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
function Export-BFReport {
    param($Diagnosis, [string]$Path, $FixResults)
    if (-not $Path) { $Path = Join-Path (Join-Path $script:BFUserDir 'Reports') ('BluetoothFixer-Report-{0}.html' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    $e = { param($s) ConvertTo-BFHtmlText "$s" }
    $env = $Diagnosis.Environment
    $sb = New-Object System.Text.StringBuilder
    $sevColor = @{ Critical = '#d13438'; Warning = '#c19c00'; Info = '#0078d4'; OK = '#107c10' }
    [void]$sb.Append(@"
<!doctype html><html><head><meta charset="utf-8"><title>Bluetooth Fixer Report - $(& $e $env.ComputerName)</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f3f3f3;color:#1b1b1b}
.wrap{max-width:1100px;margin:0 auto;padding:24px}
h1{margin:0 0 4px 0;font-size:26px}h2{margin:28px 0 8px 0;font-size:18px;border-bottom:2px solid #ddd;padding-bottom:4px}
.card{background:#fff;border-radius:8px;padding:16px 20px;margin:12px 0;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.verdict{font-size:20px;font-weight:600}
.pill{display:inline-block;padding:2px 10px;border-radius:12px;color:#fff;font-size:12px;font-weight:600;margin-right:8px}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #eee;vertical-align:top}th{background:#fafafa}
.ev{font-family:Consolas,monospace;font-size:12px;background:#f7f7f7;padding:8px;border-radius:4px;white-space:pre-wrap;margin-top:6px}
.muted{color:#666}.small{font-size:12px}
a{color:#0078d4}
</style></head><body><div class="wrap">
<h1>Windows Bluetooth Fixer report</h1>
<div class="muted">$(& $e $env.Manufacturer) $(& $e $env.Model) (serial $(& $e $env.Serial)) &middot; $(& $e $env.OSName) $(& $e $env.DisplayVersion) build $(& $e $env.Build).$(& $e $env.UBR) &middot; $(& $e ($Diagnosis.Time.ToString('f'))) &middot; tool v$(& $e $Diagnosis.Version)</div>
<div class="card"><div class="verdict" style="color:$(if ($Diagnosis.Summary.CriticalCount) { '#d13438' } else { '#107c10' })">$(& $e $Diagnosis.Summary.Verdict): $(& $e $Diagnosis.Summary.Headline)</div>
<div class="muted">$($Diagnosis.Summary.CriticalCount) critical &middot; $($Diagnosis.Summary.WarningCount) warnings &middot; radio present: $($Diagnosis.Summary.RadioPresent) $(if ($Diagnosis.Summary.RadioName) { '(' + (& $e $Diagnosis.Summary.RadioName) + ')' }) &middot; Wi-Fi: $(& $e $Diagnosis.Summary.WifiName)</div></div>
"@)
    [void]$sb.Append('<h2>Findings</h2>')
    foreach ($f in $Diagnosis.Findings) {
        [void]$sb.Append("<div class='card'><span class='pill' style='background:$($sevColor[$f.Severity])'>$($f.Severity)</span><b>$(& $e $f.Title)</b> <span class='muted small'>[$(& $e $f.Area)]</span><div>$(& $e $f.Detail)</div>")
        if ($f.Evidence.Count) { [void]$sb.Append("<div class='ev'>$(& $e ($f.Evidence -join "`n"))</div>") }
        if ($f.Fixes.Count) { $names = @(); foreach ($x in $f.Fixes) { $c = Get-BFFixCatalog | Where-Object Id -eq $x; if ($c) { $names += "$x $($c.Name)" } }; [void]$sb.Append("<div class='small muted'>Fixes: $(& $e ($names -join ' | '))</div>") }
        [void]$sb.Append('</div>')
    }
    if ($FixResults) {
        [void]$sb.Append('<h2>Fixes applied</h2><div class="card"><table><tr><th>Fix</th><th>Result</th><th>Message</th></tr>')
        foreach ($r in $FixResults) { $c = Get-BFFixCatalog | Where-Object Id -eq $r.Id; [void]$sb.Append("<tr><td>$($r.Id) $(& $e $c.Name)</td><td>$(if ($r.Success) { 'OK' } elseif ($r.Skipped) { 'Skipped' } else { 'FAILED' })$(if ($r.RebootRequired) { ' (reboot)' })</td><td>$(& $e $r.Message)</td></tr>") }
        [void]$sb.Append('</table></div>')
    }
    [void]$sb.Append('<h2>Bluetooth radios and USB stack</h2><div class="card"><table><tr><th>Role</th><th>Device</th><th>Present</th><th>Problem</th><th>Driver</th><th>Instance</th></tr>')
    foreach ($d in ($Diagnosis.Inventory.AllRecords | Sort-Object Role, Present -Descending)) {
        [void]$sb.Append("<tr><td>$(& $e $d.Role)</td><td>$(& $e $d.ChipName)</td><td>$($d.Present)</td><td>$($d.ProblemCode) $(& $e $d.ProblemText) $(& $e $d.ProblemStatus)</td><td>$(& $e $d.InfPath) $(& $e $d.DriverVersion) $(& $e $d.DriverProvider)</td><td class='small'>$(& $e $d.InstanceId)</td></tr>")
    }
    [void]$sb.Append("</table><div class='small muted'>Paired-device entries: $($Diagnosis.Inventory.Children.Count) ($($Diagnosis.Inventory.PresentChildren.Count) present, $($Diagnosis.Inventory.ProblemChildren.Count) with problems). USB devices present: $($Diagnosis.Inventory.UsbDeviceCount).</div></div>")
    [void]$sb.Append('<h2>Services</h2><div class="card"><table><tr><th>Service</th><th>Kind</th><th>Start</th><th>Default</th><th>Status</th><th>Note</th></tr>')
    foreach ($s in $Diagnosis.Services.Rows) {
        $style = if ($s.Disabled) { " style='color:#d13438;font-weight:600'" } elseif ($s.Deviates) { " style='color:#c19c00'" } else { '' }
        [void]$sb.Append("<tr$style><td>$(& $e $s.Name)<br><span class='small muted'>$(& $e $s.Display)</span></td><td>$(& $e $s.Kind)</td><td>$(& $e $s.StartName)</td><td>$(& $e $s.DefaultName)</td><td>$(& $e $s.Status)</td><td class='small'>$(& $e $s.Note)</td></tr>")
    }
    [void]$sb.Append('</table></div>')
    [void]$sb.Append('<h2>Driver store (Bluetooth packages)</h2><div class="card"><table><tr><th>Published</th><th>Original</th><th>Provider</th><th>Version</th><th>Hardware IDs</th></tr>')
    foreach ($p in $Diagnosis.DriverStore.BluetoothPackages) { [void]$sb.Append("<tr><td>$(& $e $p.Published)</td><td>$(& $e $p.Original)</td><td>$(& $e $p.Provider)</td><td>$(& $e $p.Version) ($(& $e $p.Date))</td><td class='small'>$(& $e (($p.HardwareIds | Select-Object -First 8) -join ', '))$(if ($p.HardwareIds.Count -gt 8) { ' ...' })</td></tr>") }
    [void]$sb.Append('</table></div>')
    [void]$sb.Append('<h2>Timeline (newest first)</h2><div class="card"><table><tr><th>When</th><th>Source</th><th>What</th></tr>')
    foreach ($t in ($Diagnosis.Timeline | Select-Object -First 120)) { [void]$sb.Append("<tr><td class='small'>$(& $e ($t.Time.ToString('g')))</td><td class='small'>$(& $e $t.Source)</td><td class='small' style='color:$(if ($t.Severity -eq 'Warning') { '#a00' } else { '#333' })'>$(& $e $t.Text)</td></tr>") }
    [void]$sb.Append('</table></div>')
    [void]$sb.Append('<h2>Where to get drivers</h2><div class="card"><ul>')
    foreach ($l in $Diagnosis.Links) { if ($l.Url) { [void]$sb.Append("<li><b>$(& $e $l.Group):</b> <a href='$(& $e $l.Url)'>$(& $e $l.Label)</a> <span class='small muted'>$(& $e $l.Note)</span></li>") } else { [void]$sb.Append("<li><b>$(& $e $l.Group):</b> $(& $e $l.Label) <span class='small muted'>$(& $e $l.Note)</span></li>") } }
    [void]$sb.Append('</ul></div>')
    [void]$sb.Append('<h2>Log</h2><div class="card"><div class="ev">' + (& $e ((Get-BFLog) -join "`n")) + '</div></div>')
    [void]$sb.Append("<div class='small muted' style='margin:24px 0'>Windows Bluetooth Fixer is free software. Nothing in this report leaves your PC unless you share it.</div></div></body></html>")
    Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8
    # JSON sidecar
    try {
        $json = [pscustomobject]@{ Version = $Diagnosis.Version; Time = $Diagnosis.Time; Environment = $Diagnosis.Environment; Summary = $Diagnosis.Summary; Findings = $Diagnosis.Findings; Radios = $Diagnosis.Inventory.Radios; Controllers = $Diagnosis.Inventory.Controllers; RootHubs = $Diagnosis.Inventory.RootHubs; Services = $Diagnosis.Services.Rows; DriverStore = $Diagnosis.DriverStore.BluetoothPackages; Timeline = ($Diagnosis.Timeline | Select-Object -First 200); Links = $Diagnosis.Links; FixResults = $FixResults; Log = (Get-BFLog) }
        $json | ConvertTo-Json -Depth 6 | Set-Content -Path ($Path -replace '\.html$', '.json') -Encoding UTF8
    } catch { Write-BFLog -Level WARN -Message "JSON export failed: $($_.Exception.Message)" }
    Write-BFLog -Level OK -Message "Report saved: $Path"
    return $Path
}

Export-ModuleMember -Function Set-BFLogSink, Write-BFLog, Get-BFLog, Start-BFLogFile, Test-BFAdmin, Get-BFKB, Get-BFEnvironment, Get-BFDeviceInventory, Get-BFServiceState, Get-BFDriverStore, Get-BFTimeline, Get-BFRadioState, Get-BFPolicyState, Invoke-BFDiagnosis, Get-BFFixCatalog, Get-BFRecommendedFixes, Invoke-BFFix, Invoke-BFFixPlan, Export-BFReport, New-BFBackup, Get-BFVendorLinks, Invoke-BFRescan, Invoke-BFRestartDevice, Install-BFDriverForDevice, Set-BFBluetoothRadioOn, Find-BFStorePackagesForDevice
