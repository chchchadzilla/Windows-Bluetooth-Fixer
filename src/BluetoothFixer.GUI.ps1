#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Bluetooth Fixer - graphical front end.
.PARAMETER Verify
    Started automatically after a scheduled reboot: runs a diagnosis immediately and shows the result.
.PARAMETER AutoDiagnose
    Run a diagnosis as soon as the window opens.
#>
param([switch]$Verify, [switch]$AutoDiagnose)

$ErrorActionPreference = 'Continue'
$script:GuiErrorLog = Join-Path $env:TEMP 'BluetoothFixer-GUI-errors.log'
trap {
    $msg = "GUI error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    try { Add-Content -Path $script:GuiErrorLog -Value ("{0} {1}" -f (Get-Date), $msg) } catch { }
    if ($msg.Length -gt 900) { $msg = $msg.Substring(0, 900) + ' ...' }
    try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show($msg + "`n`nFull details: $script:GuiErrorLog", 'Windows Bluetooth Fixer', 'OK', 'Error') | Out-Null } catch { }
    continue
}

function Show-Msg([string]$Text, [string]$Title = 'Windows Bluetooth Fixer', [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    # Owner-less overload on purpose: robust regardless of what is in scope.
    if ($Text.Length -gt 3000) { $Text = $Text.Substring(0, 3000) + ' ...' }
    return [System.Windows.MessageBox]::Show($Text, $Title, [System.Windows.MessageBoxButton]$Buttons, [System.Windows.MessageBoxImage]$Icon)
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $here 'BluetoothFixer.psm1'
Import-Module $modulePath -Force

# --- item classes for two-way binding ---------------------------------------
if (-not ('BluetoothFixer.UI.FixItem' -as [type])) {
Add-Type -TypeDefinition @"
using System.ComponentModel;
namespace BluetoothFixer.UI {
  public class FixItem : INotifyPropertyChanged {
    bool _sel; string _status = "";
    public bool IsSelected { get { return _sel; } set { _sel = value; Raise("IsSelected"); } }
    public string Id { get; set; } public string Name { get; set; } public string Risk { get; set; } public string Description { get; set; }
    public bool Recommended { get; set; } public bool NeedsAdmin { get; set; }
    public string Status { get { return _status; } set { _status = value; Raise("Status"); } }
    public string RecommendedText { get { return Recommended ? "Recommended" : ""; } }
    public event PropertyChangedEventHandler PropertyChanged;
    void Raise(string n) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(n)); }
  }
}
"@
}

# --- XAML --------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Bluetooth Fixer" Width="1180" Height="800" MinWidth="960" MinHeight="620" WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,7"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#CCCCCC"/><Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0067C0"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#0067C0"/><Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="ListView"><Setter Property="BorderBrush" Value="#DDDDDD"/><Setter Property="Background" Value="White"/></Style>
    <Style TargetType="TabItem"><Setter Property="Padding" Value="14,6"/><Setter Property="FontSize" Value="13"/></Style>
    <Style TargetType="GridViewColumnHeader"><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Padding" Value="6,4"/></Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <!-- header -->
    <Grid Grid.Row="0" Margin="0,0,0,10">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="Windows Bluetooth Fixer" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock x:Name="SubTitle" Text="Finds out why Bluetooth is broken and repairs it." Foreground="#555"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="BtnDiagnose" Style="{StaticResource Primary}" Content="Diagnose"/>
        <Button x:Name="BtnFixRecommended" Content="Fix recommended" IsEnabled="False"/>
        <Button x:Name="BtnReport" Content="Save report" IsEnabled="False"/>
        <Button x:Name="BtnElevate" Content="Relaunch as administrator" Background="#FFF4CE" BorderBrush="#E0B000"/>
      </StackPanel>
    </Grid>
    <!-- verdict -->
    <Border Grid.Row="1" x:Name="Verdict" Background="#E5E5E5" CornerRadius="8" Padding="14,10" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock x:Name="VerdictTitle" Text="Click Diagnose to inspect this PC." FontSize="16" FontWeight="SemiBold"/>
        <TextBlock x:Name="VerdictDetail" Text="Nothing is changed until you choose a fix. Every fix is logged and reversible where it changes settings." Foreground="#333" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <!-- tabs -->
    <TabControl Grid.Row="2" x:Name="Tabs" Background="White" BorderBrush="#DDDDDD">
      <TabItem Header="Findings">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="6"/><ColumnDefinition Width="1.2*"/></Grid.ColumnDefinitions>
          <ListView x:Name="LvFindings">
            <ListView.View><GridView>
              <GridViewColumn Header="Severity" Width="80" DisplayMemberBinding="{Binding Severity}"/>
              <GridViewColumn Header="Area" Width="100" DisplayMemberBinding="{Binding Area}"/>
              <GridViewColumn Header="Finding" Width="380" DisplayMemberBinding="{Binding Title}"/>
            </GridView></ListView.View>
            <ListView.ItemContainerStyle>
              <Style TargetType="ListViewItem">
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Severity}" Value="Critical"><Setter Property="Foreground" Value="#C50F1F"/><Setter Property="FontWeight" Value="SemiBold"/></DataTrigger>
                  <DataTrigger Binding="{Binding Severity}" Value="Warning"><Setter Property="Foreground" Value="#9D5D00"/></DataTrigger>
                  <DataTrigger Binding="{Binding Severity}" Value="OK"><Setter Property="Foreground" Value="#0F7B0F"/></DataTrigger>
                  <DataTrigger Binding="{Binding Severity}" Value="Info"><Setter Property="Foreground" Value="#005FB8"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </ListView.ItemContainerStyle>
          </ListView>
          <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" Background="Transparent"/>
          <Border Grid.Column="2" BorderBrush="#DDDDDD" BorderThickness="1" Background="#FAFAFA" Padding="10">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <TextBlock x:Name="FTitle" FontSize="16" FontWeight="SemiBold" TextWrapping="Wrap" Text="Select a finding"/>
                <TextBlock x:Name="FDetail" Margin="0,8,0,0" TextWrapping="Wrap"/>
                <TextBlock Text="Evidence" FontWeight="SemiBold" Margin="0,12,0,2"/>
                <TextBox x:Name="FEvidence" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12" Background="#F0F0F0" BorderThickness="0" Padding="6"/>
                <TextBlock Text="Fixes that address this" FontWeight="SemiBold" Margin="0,12,0,2"/>
                <TextBlock x:Name="FFixes" TextWrapping="Wrap"/>
                <Button x:Name="BtnFixThis" Content="Apply these fixes" Margin="0,10,0,0" HorizontalAlignment="Left" IsEnabled="False"/>
              </StackPanel>
            </ScrollViewer>
          </Border>
        </Grid>
      </TabItem>
      <TabItem Header="Fix plan">
        <Grid Margin="8">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="BtnRunSelected" Style="{StaticResource Primary}" Content="Run selected fixes" IsEnabled="False"/>
            <Button x:Name="BtnSelRecommended" Content="Select recommended"/>
            <Button x:Name="BtnSelSafe" Content="Select all safe"/>
            <Button x:Name="BtnSelNone" Content="Clear"/>
            <CheckBox x:Name="ChkRediag" Content="Re-diagnose after fixing" IsChecked="True" VerticalAlignment="Center" Margin="12,0,0,0"/>
            <CheckBox x:Name="ChkBackup" Content="Back up registry and drivers first" IsChecked="True" VerticalAlignment="Center" Margin="12,0,0,0"/>
          </StackPanel>
          <ListView Grid.Row="1" x:Name="LvFixes">
            <ListView.View><GridView>
              <GridViewColumn Header="" Width="30"><GridViewColumn.CellTemplate><DataTemplate><CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}"/></DataTemplate></GridViewColumn.CellTemplate></GridViewColumn>
              <GridViewColumn Header="Id" Width="44" DisplayMemberBinding="{Binding Id}"/>
              <GridViewColumn Header="Fix" Width="260" DisplayMemberBinding="{Binding Name}"/>
              <GridViewColumn Header="Risk" Width="70" DisplayMemberBinding="{Binding Risk}"/>
              <GridViewColumn Header="" Width="100" DisplayMemberBinding="{Binding RecommendedText}"/>
              <GridViewColumn Header="Result" Width="160" DisplayMemberBinding="{Binding Status}"/>
              <GridViewColumn Header="What it does" Width="520"><GridViewColumn.CellTemplate><DataTemplate><TextBlock Text="{Binding Description}" TextWrapping="Wrap"/></DataTemplate></GridViewColumn.CellTemplate></GridViewColumn>
            </GridView></ListView.View>
          </ListView>
        </Grid>
      </TabItem>
      <TabItem Header="Devices">
        <ListView x:Name="LvDevices" Margin="8">
          <ListView.View><GridView>
            <GridViewColumn Header="Role" Width="90" DisplayMemberBinding="{Binding Role}"/>
            <GridViewColumn Header="Device" Width="280" DisplayMemberBinding="{Binding ChipName}"/>
            <GridViewColumn Header="Present" Width="60" DisplayMemberBinding="{Binding Present}"/>
            <GridViewColumn Header="Problem" Width="260" DisplayMemberBinding="{Binding ProblemText}"/>
            <GridViewColumn Header="Driver" Width="120" DisplayMemberBinding="{Binding InfPath}"/>
            <GridViewColumn Header="Version" Width="110" DisplayMemberBinding="{Binding DriverVersion}"/>
            <GridViewColumn Header="Provider" Width="100" DisplayMemberBinding="{Binding DriverProvider}"/>
            <GridViewColumn Header="Instance ID" Width="420" DisplayMemberBinding="{Binding InstanceId}"/>
          </GridView></ListView.View>
        </ListView>
      </TabItem>
      <TabItem Header="Services">
        <ListView x:Name="LvServices" Margin="8">
          <ListView.View><GridView>
            <GridViewColumn Header="Service" Width="220" DisplayMemberBinding="{Binding Name}"/>
            <GridViewColumn Header="Description" Width="300" DisplayMemberBinding="{Binding Display}"/>
            <GridViewColumn Header="Kind" Width="130" DisplayMemberBinding="{Binding Kind}"/>
            <GridViewColumn Header="Start" Width="80" DisplayMemberBinding="{Binding StartName}"/>
            <GridViewColumn Header="Default" Width="80" DisplayMemberBinding="{Binding DefaultName}"/>
            <GridViewColumn Header="Status" Width="80" DisplayMemberBinding="{Binding Status}"/>
            <GridViewColumn Header="Note" Width="420" DisplayMemberBinding="{Binding Note}"/>
          </GridView></ListView.View>
          <ListView.ItemContainerStyle>
            <Style TargetType="ListViewItem">
              <Style.Triggers>
                <DataTrigger Binding="{Binding Disabled}" Value="True"><Setter Property="Foreground" Value="#C50F1F"/><Setter Property="FontWeight" Value="SemiBold"/></DataTrigger>
                <DataTrigger Binding="{Binding Deviates}" Value="True"><Setter Property="Foreground" Value="#9D5D00"/></DataTrigger>
              </Style.Triggers>
            </Style>
          </ListView.ItemContainerStyle>
        </ListView>
      </TabItem>
      <TabItem Header="Timeline">
        <ListView x:Name="LvTimeline" Margin="8">
          <ListView.View><GridView>
            <GridViewColumn Header="When" Width="150" DisplayMemberBinding="{Binding TimeText}"/>
            <GridViewColumn Header="Source" Width="130" DisplayMemberBinding="{Binding Source}"/>
            <GridViewColumn Header="What happened" Width="900" DisplayMemberBinding="{Binding Text}"/>
          </GridView></ListView.View>
          <ListView.ItemContainerStyle>
            <Style TargetType="ListViewItem"><Style.Triggers><DataTrigger Binding="{Binding Severity}" Value="Warning"><Setter Property="Foreground" Value="#9D1D1D"/></DataTrigger></Style.Triggers></Style>
          </ListView.ItemContainerStyle>
        </ListView>
      </TabItem>
      <TabItem Header="Drivers and links">
        <Grid Margin="8">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock Text="Where to get the right driver for this PC (double-click to open)" FontWeight="SemiBold" Margin="0,0,0,4"/>
          <ListView Grid.Row="1" x:Name="LvLinks">
            <ListView.View><GridView>
              <GridViewColumn Header="Source" Width="150" DisplayMemberBinding="{Binding Group}"/>
              <GridViewColumn Header="Link" Width="520" DisplayMemberBinding="{Binding Label}"/>
              <GridViewColumn Header="Note" Width="480" DisplayMemberBinding="{Binding Note}"/>
            </GridView></ListView.View>
          </ListView>
          <TextBlock Grid.Row="2" Text="Bluetooth driver packages in the Windows driver store" FontWeight="SemiBold" Margin="0,10,0,4"/>
          <ListView Grid.Row="3" x:Name="LvStore">
            <ListView.View><GridView>
              <GridViewColumn Header="Published" Width="100" DisplayMemberBinding="{Binding Published}"/>
              <GridViewColumn Header="Original INF" Width="200" DisplayMemberBinding="{Binding Original}"/>
              <GridViewColumn Header="Provider" Width="160" DisplayMemberBinding="{Binding Provider}"/>
              <GridViewColumn Header="Version" Width="120" DisplayMemberBinding="{Binding Version}"/>
              <GridViewColumn Header="Date" Width="100" DisplayMemberBinding="{Binding Date}"/>
              <GridViewColumn Header="Hardware IDs" Width="600" DisplayMemberBinding="{Binding HwText}"/>
            </GridView></ListView.View>
          </ListView>
        </Grid>
      </TabItem>
      <TabItem Header="Log">
        <Grid Margin="8">
          <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <TextBox x:Name="TxtLog" IsReadOnly="True" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap" HorizontalScrollBarVisibility="Auto" Background="#1E1E1E" Foreground="#DDDDDD"/>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,0">
            <Button x:Name="BtnOpenLogs" Content="Open log folder"/>
            <Button x:Name="BtnOpenBackups" Content="Open backup folder"/>
            <Button x:Name="BtnOpenReports" Content="Open reports folder"/>
          </StackPanel>
        </Grid>
      </TabItem>
    </TabControl>
    <!-- status -->
    <Grid Grid.Row="3" Margin="0,10,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ProgressBar x:Name="Progress" Height="18" Minimum="0" Maximum="100"/>
      <TextBlock Grid.Column="1" x:Name="Status" Margin="10,0,0,0" VerticalAlignment="Center" Foreground="#444" Text="Ready."/>
    </Grid>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$W = [Windows.Markup.XamlReader]::Load($reader)
# Fit the window to the available desktop (high-DPI laptops report small logical work areas)
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $W.Width = [Math]::Min($W.Width, [Math]::Max(900, $wa.Width - 40))
    $W.Height = [Math]::Min($W.Height, [Math]::Max(600, $wa.Height - 40))
} catch { }
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@*[local-name()="Name"]]')) { $name = $n.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'); if ($name) { $ui[$name] = $W.FindName($name) } }

# --- shared state + worker runspace -----------------------------------------
$sync = [hashtable]::Synchronized(@{})
$sync.Log = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$sync.Progress = 0; $sync.Status = 'Ready.'; $sync.Diagnosis = $null; $sync.FixResults = $null; $sync.Done = $false; $sync.Error = $null; $sync.ReportPath = $null
$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $sync)
$rs.SessionStateProxy.SetVariable('ModulePath', $modulePath)
$init = [powershell]::Create(); $init.Runspace = $rs
[void]$init.AddScript({
    Import-Module $ModulePath -Force
    Start-BFLogFile | Out-Null
    Set-BFLogSink -Sink $sync.Log -Progress { param($p, $t) $sync.Progress = $p; $sync.Status = $t }
})
[void]$init.Invoke(); $init.Dispose()

$script:worker = $null
$script:logIndex = 0
$script:isAdmin = Test-BFAdmin
$script:fixItems = New-Object System.Collections.ObjectModel.ObservableCollection[BluetoothFixer.UI.FixItem]
foreach ($c in (Get-BFFixCatalog)) { $fi = New-Object BluetoothFixer.UI.FixItem; $fi.Id = $c.Id; $fi.Name = $c.Name; $fi.Risk = $c.Risk; $fi.Description = $c.Description; $fi.NeedsAdmin = $c.NeedsAdmin; $script:fixItems.Add($fi) }
$ui.LvFixes.ItemsSource = $script:fixItems
$ui.BtnElevate.Visibility = if ($script:isAdmin) { 'Collapsed' } else { 'Visible' }
if (-not $script:isAdmin) { $ui.SubTitle.Text = 'Running WITHOUT administrator rights: diagnosis works, repairs need the yellow button.' }

function Set-Busy([bool]$b) {
    foreach ($n in 'BtnDiagnose','BtnFixRecommended','BtnRunSelected','BtnFixThis') { $ui[$n].IsEnabled = (-not $b) -and ($n -eq 'BtnDiagnose' -or $sync.Diagnosis -ne $null) }
    $ui.BtnReport.IsEnabled = (-not $b) -and ($sync.Diagnosis -ne $null)
    if ($b) { $W.Cursor = [System.Windows.Input.Cursors]::AppStarting } else { $W.Cursor = $null }
}

function Start-Work([scriptblock]$Script, $Params) {
    if ($script:worker) { return }
    $sync.Done = $false; $sync.Error = $null
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Script)
    if ($Params -is [hashtable]) { foreach ($k in $Params.Keys) { [void]$ps.AddParameter($k, $Params[$k]) } }
    $script:worker = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    Set-Busy $true
}

$diagScript = {
    try { $sync.Diagnosis = Invoke-BFDiagnosis } catch { $sync.Error = "Diagnosis failed: $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
    $sync.Done = $true
}
$fixScript = {
    param([string[]]$Ids, [bool]$Rediag, [bool]$Backup, [bool]$ConfirmReboot)
    try {
        if (-not $Backup) { $sync.FixResults = @(); foreach ($id in $Ids) { $sync.FixResults += [pscustomobject](Invoke-BFFix -FixId $id -Diagnosis $sync.Diagnosis -Confirmed:$ConfirmReboot) } }
        else { $sync.FixResults = @(Invoke-BFFixPlan -FixIds $Ids -Diagnosis $sync.Diagnosis -ConfirmReboot:$ConfirmReboot) }
        if ($Rediag) { Write-BFLog -Level STEP -Message 'Re-running diagnosis to verify'; $sync.Diagnosis = Invoke-BFDiagnosis }
    } catch { $sync.Error = "Fix run failed: $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
    $sync.Done = $true
}
$reportScript = { try { $sync.ReportPath = Export-BFReport -Diagnosis $sync.Diagnosis -FixResults $sync.FixResults } catch { $sync.Error = "Report failed: $($_.Exception.Message)" }; $sync.Done = $true }

function Render-Diagnosis {
    $d = $sync.Diagnosis
    if (-not $d) { return }
    $ui.LvFindings.ItemsSource = @($d.Findings)
    $ui.LvDevices.ItemsSource = @($d.Inventory.AllRecords | Sort-Object Role, @{ Expression = 'Present'; Descending = $true })
    $ui.LvServices.ItemsSource = @($d.Services.Rows)
    $ui.LvTimeline.ItemsSource = @($d.Timeline | Select-Object -First 300 | ForEach-Object { [pscustomobject]@{ TimeText = $_.Time.ToString('yyyy-MM-dd HH:mm:ss'); Source = $_.Source; Text = $_.Text; Severity = $_.Severity } })
    $ui.LvLinks.ItemsSource = @($d.Links)
    $ui.LvStore.ItemsSource = @($d.DriverStore.BluetoothPackages | ForEach-Object { [pscustomobject]@{ Published = $_.Published; Original = $_.Original; Provider = $_.Provider; Version = $_.Version; Date = $_.Date; HwText = (($_.HardwareIds | Select-Object -First 6) -join ', ') } })
    $rec = @(Get-BFRecommendedFixes -Diagnosis $d)
    foreach ($fi in $script:fixItems) { $fi.Recommended = ($rec -contains $fi.Id); $fi.IsSelected = $fi.Recommended -and $fi.Id -ne 'F17' -and $fi.Id -ne 'F16' -and $fi.Id -ne 'F14' }
    $ui.LvFixes.Items.Refresh()
    $s = $d.Summary
    $ui.VerdictTitle.Text = "$($s.Verdict): $($s.Headline)"
    $env = $d.Environment
    $ui.VerdictDetail.Text = ("{0} {1} | {2} {3} (build {4}.{5}) | {6} critical, {7} warnings | radio present: {8}{9} | Wi-Fi: {10} | scan took {11}s" -f $env.Manufacturer, $env.Model, $env.OSName, $env.DisplayVersion, $env.Build, $env.UBR, $s.CriticalCount, $s.WarningCount, $s.RadioPresent, $(if ($s.RadioName) { " ($($s.RadioName))" } else { '' }), $s.WifiName, $d.DurationSec)
    $ui.Verdict.Background = if ($s.CriticalCount -gt 0) { '#FDE7E9' } elseif ($s.WarningCount -gt 0) { '#FFF4CE' } else { '#DFF6DD' }
    $ui.BtnFixRecommended.Content = if ($rec.Count) { "Fix recommended ($(@($rec | Where-Object { $_ -notin 'F17','F16','F14','F09','F18','F15','F20' }).Count))" } else { 'Nothing to fix' }
    if ($ui.LvFindings.Items.Count -gt 0) { $ui.LvFindings.SelectedIndex = 0 }
}

function Show-FixResults {
    $res = $sync.FixResults
    if (-not $res) { return }
    foreach ($r in $res) { $fi = $script:fixItems | Where-Object Id -eq $r.Id; if ($fi) { $fi.Status = if ($r.Success) { 'OK' + $(if ($r.RebootRequired) { ' (reboot needed)' } else { '' }) } elseif ($r.Skipped) { 'Skipped' } else { 'FAILED' } } }
    $ui.LvFixes.Items.Refresh()
    $reboot = @($res | Where-Object RebootRequired).Count -gt 0
    $lines = @($res | ForEach-Object { $c = Get-BFFixCatalog | Where-Object Id -eq $_.Id; "{0} {1}: {2}" -f $_.Id, $c.Name, $_.Message })
    $msg = ($lines -join "`n`n")
    if ($reboot -and -not ($res | Where-Object { $_.Id -eq 'F17' -and $_.Success })) { $msg += "`n`nA reboot is needed to finish. Reboot now? (Windows restarts in 30 seconds; the tool re-checks after logon.)"
        $a = Show-Msg -Text $msg -Title 'Fix results' -Buttons 'YesNo' -Icon 'Question'
        if ($a -eq 'Yes') { Start-Work $fixScript @{ Ids = @('F17'); Rediag = $false; Backup = $false; ConfirmReboot = $true } }
    } else { Show-Msg -Text $msg -Title 'Fix results' | Out-Null }
}

# --- timer: pump log + progress, detect completion --------------------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    while ($script:logIndex -lt $sync.Log.Count) { $ui.TxtLog.AppendText($sync.Log[$script:logIndex] + "`r`n"); $script:logIndex++; $ui.TxtLog.ScrollToEnd() }
    $ui.Progress.Value = [double]$sync.Progress
    $ui.Status.Text = $sync.Status
    if ($script:worker -and $script:worker.Handle.IsCompleted) {
        # NOTE: never name a local "$w" here - PowerShell variables are case-insensitive and it would shadow the $W window
        $finishedWorker = $script:worker; $script:worker = $null
        try { $finishedWorker.PS.EndInvoke($finishedWorker.Handle) | Out-Null } catch { $sync.Error = "Worker error: $($_.Exception.Message)" }
        $finishedWorker.PS.Dispose()
        Set-Busy $false
        if ($sync.Error) { Show-Msg -Text $sync.Error -Icon 'Error' | Out-Null; $sync.Error = $null }
        if ($sync.Diagnosis) { Render-Diagnosis }
        if ($sync.FixResults) { Show-FixResults; $sync.FixResults = $null }
        if ($sync.ReportPath) { $p = $sync.ReportPath; $sync.ReportPath = $null; $ui.Status.Text = "Report saved: $p"; try { Start-Process $p } catch { } }
        if ($script:pendingAfter) { $a = $script:pendingAfter; $script:pendingAfter = $null; & $a }
    }
})
$timer.Start()

# --- events -----------------------------------------------------------------
$ui.BtnDiagnose.Add_Click({ $ui.TxtLog.Clear(); $script:logIndex = $sync.Log.Count; Start-Work $diagScript $null })
$ui.BtnReport.Add_Click({ Start-Work $reportScript $null })
$ui.BtnElevate.Add_Click({
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`" -AutoDiagnose" -ErrorAction Stop
        $W.Close()
    } catch { Show-Msg -Text "Could not elevate: $($_.Exception.Message)" -Icon 'Warning' | Out-Null }
})
$ui.LvFindings.Add_SelectionChanged({
    $f = $ui.LvFindings.SelectedItem
    if (-not $f) { return }
    $ui.FTitle.Text = "[$($f.Severity)] $($f.Title)"
    $ui.FDetail.Text = $f.Detail
    $ui.FEvidence.Text = if ($f.Evidence.Count) { $f.Evidence -join "`r`n" } else { '(none)' }
    $names = @(); foreach ($x in $f.Fixes) { $c = Get-BFFixCatalog | Where-Object Id -eq $x; if ($c) { $names += "$x  $($c.Name)  [$($c.Risk)]" } }
    $ui.FFixes.Text = if ($names.Count) { $names -join "`r`n" } else { 'No automatic fix applies; see detail.' }
    $ui.BtnFixThis.IsEnabled = ($f.Fixes.Count -gt 0) -and -not $script:worker
})
function Confirm-And-Run([string[]]$ids) {
    if (-not $ids -or $ids.Count -eq 0) { Show-Msg -Text 'No fixes selected.' | Out-Null; return }
    $needAdmin = @($ids | ForEach-Object { $i = $_; (Get-BFFixCatalog | Where-Object Id -eq $i).NeedsAdmin } | Where-Object { $_ }).Count -gt 0
    if ($needAdmin -and -not $script:isAdmin) { Show-Msg -Text 'These fixes need administrator rights. Use "Relaunch as administrator" first.' -Icon 'Warning' | Out-Null; return }
    $confirmReboot = $false
    if ($ids -contains 'F17') { $a = Show-Msg -Text 'This will restart Windows in 30 seconds after the other fixes. Save your work. Continue?' -Title 'Reboot' -Buttons 'YesNo' -Icon 'Warning'; if ($a -ne 'Yes') { return }; $confirmReboot = $true }
    if ($ids -contains 'F02') { $a = Show-Msg -Text 'Restarting the USB controller makes every USB device disconnect for a few seconds (keyboard, mouse, drives all come back). Continue?' -Title 'USB controller restart' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    if ($ids -contains 'F21') { $a = Show-Msg -Text 'This installs the newer Microsoft USB hub / xHCI driver that Windows Update left in the component store onto your USB controllers. USB devices disconnect for a few seconds. Continue?' -Title 'Re-stage USB drivers' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    if ($ids -contains 'F14') { $a = Show-Msg -Text 'Forgetting all paired devices means pairing them again afterwards. Continue?' -Title 'Forget pairings' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    foreach ($fi in $script:fixItems) { if ($ids -contains $fi.Id) { $fi.Status = 'Running...' } }
    $ui.Tabs.SelectedIndex = 1
    Start-Work $fixScript @{ Ids = $ids; Rediag = [bool]$ui.ChkRediag.IsChecked; Backup = [bool]$ui.ChkBackup.IsChecked; ConfirmReboot = $confirmReboot }
}
$ui.BtnFixThis.Add_Click({ $f = $ui.LvFindings.SelectedItem; if ($f) { Confirm-And-Run @($f.Fixes) } })
$ui.BtnFixRecommended.Add_Click({ if ($sync.Diagnosis) { $ids = @(Get-BFRecommendedFixes -Diagnosis $sync.Diagnosis | Where-Object { $_ -notin 'F17','F16','F14','F09','F18','F15','F20' }); Confirm-And-Run $ids } })
$ui.BtnRunSelected.Add_Click({ Confirm-And-Run @($script:fixItems | Where-Object IsSelected | ForEach-Object Id) })
$ui.BtnSelRecommended.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = $fi.Recommended } })
$ui.BtnSelSafe.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = ($fi.Risk -eq 'Safe' -and $fi.Id -notin 'F09','F15','F18','F20') } })
$ui.BtnSelNone.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = $false } })
$ui.LvLinks.Add_MouseDoubleClick({ $l = $ui.LvLinks.SelectedItem; if ($l -and $l.Url) { try { Start-Process $l.Url } catch { } } })
$ui.BtnOpenLogs.Add_Click({ Start-Process (Join-Path $env:ProgramData 'BluetoothFixer\Logs') })
$ui.BtnOpenBackups.Add_Click({ Start-Process (Join-Path $env:ProgramData 'BluetoothFixer\Backups') })
$ui.BtnOpenReports.Add_Click({ $p = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'BluetoothFixer\Reports'; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }; Start-Process $p })
$W.Add_Closed({ $timer.Stop(); try { if ($script:worker) { $script:worker.PS.Stop() } } catch { }; try { $rs.Close(); $rs.Dispose() } catch { } })

if ($Verify) {
    $ui.SubTitle.Text = 'Post-reboot verification: checking whether the repair held.'
    $script:pendingAfter = {
        $s = $sync.Diagnosis.Summary
        $txt = if ($s.CriticalCount -eq 0 -and $s.RadioPresent) { "Bluetooth is working again. Radio: $($s.RadioName)" } else { "Still not right: $($s.Headline). Open the Findings tab for the next step." }
        Show-Msg -Text $txt -Title 'Post-reboot verification' -Icon $(if ($s.CriticalCount -eq 0) { 'Information' } else { 'Warning' }) | Out-Null
    }
    $W.Add_ContentRendered({ Start-Work $diagScript $null })
} elseif ($AutoDiagnose) {
    $W.Add_ContentRendered({ Start-Work $diagScript $null })
}

[void]$W.ShowDialog()
