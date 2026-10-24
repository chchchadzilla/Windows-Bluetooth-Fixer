#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Bluetooth Fixer - graphical front end: a guided, step-by-step view plus the full Advanced view.
.DESCRIPTION
    Guided view (default): 1 Check -> 2 What we found -> 3 The right driver (first thing to try) -> 4 Test the radio
    (real discovery scan) -> 5 Other fixes -> 6 Wrap up. Advanced view: every finding, device, service, timeline,
    driver link and log line, with the full fix plan.
.PARAMETER Verify
    Started automatically after a scheduled reboot: runs a diagnosis immediately and shows the result.
.PARAMETER AutoDiagnose
    Run a diagnosis as soon as the window opens (the launchers pass this).
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
  public class StepItem : INotifyPropertyChanged {
    string _state = "Pending"; string _hint = "";
    public int Number { get; set; } public string Title { get; set; }
    public string Hint { get { return _hint; } set { _hint = value; Raise("Hint"); } }
    public string State { get { return _state; } set { _state = value; Raise("State"); } }
    public event PropertyChangedEventHandler PropertyChanged;
    void Raise(string n) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(n)); }
  }
}
"@
}

# --- XAML --------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Bluetooth Fixer" Width="1180" Height="800" MinWidth="980" MinHeight="660" WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,7"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#CCCCCC"/><Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0067C0"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#0067C0"/><Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#E0E0E0"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="8"/><Setter Property="Padding" Value="16"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="22"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="Body" TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Foreground" Value="#333333"/><Setter Property="LineHeight" Value="20"/></Style>
    <Style x:Key="Muted" TargetType="TextBlock" BasedOn="{StaticResource Body}"><Setter Property="Foreground" Value="#666666"/><Setter Property="FontSize" Value="12"/><Setter Property="LineHeight" Value="17"/></Style>
    <Style x:Key="Label" TargetType="TextBlock"><Setter Property="Foreground" Value="#666666"/><Setter Property="Width" Value="130"/><Setter Property="VerticalAlignment" Value="Top"/></Style>
    <Style TargetType="ListView"><Setter Property="BorderBrush" Value="#DDDDDD"/><Setter Property="Background" Value="White"/></Style>
    <Style TargetType="TabItem"><Setter Property="Padding" Value="14,6"/><Setter Property="FontSize" Value="13"/></Style>
    <Style TargetType="GridViewColumnHeader"><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Padding" Value="6,4"/></Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <!-- header -->
    <Grid Grid.Row="0" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="Windows Bluetooth Fixer" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock x:Name="SubTitle" Text="Finds out why Bluetooth is broken, then walks you through the fix." Foreground="#555555"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="BtnAdvanced" Content="Advanced view"/>
        <Button x:Name="BtnElevate" Content="Relaunch as administrator" Background="#FFF4CE" BorderBrush="#E0B000"/>
      </StackPanel>
    </Grid>

    <!-- ===================== GUIDED VIEW ===================== -->
    <Grid Grid.Row="1" x:Name="Wizard">
      <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Style="{StaticResource Card}" Padding="8" Margin="0">
        <ItemsControl x:Name="StepList">
          <ItemsControl.ItemTemplate>
            <DataTemplate>
              <Border x:Name="Row" Padding="10,9" Margin="0,0,0,4" CornerRadius="6" Background="Transparent" Cursor="Hand">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Border x:Name="Dot" Width="26" Height="26" CornerRadius="13" Background="#C8C8C8" VerticalAlignment="Top">
                    <TextBlock x:Name="Num" Text="{Binding Number}" Foreground="White" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="8,2,0,0">
                    <TextBlock Text="{Binding Title}" FontWeight="SemiBold" TextWrapping="Wrap"/>
                    <TextBlock Text="{Binding Hint}" Foreground="#666666" FontSize="11" TextWrapping="Wrap"/>
                  </StackPanel>
                </Grid>
              </Border>
              <DataTemplate.Triggers>
                <DataTrigger Binding="{Binding State}" Value="Current"><Setter TargetName="Row" Property="Background" Value="#E6F0FA"/><Setter TargetName="Dot" Property="Background" Value="#0067C0"/></DataTrigger>
                <DataTrigger Binding="{Binding State}" Value="Done"><Setter TargetName="Dot" Property="Background" Value="#0F7B0F"/><Setter TargetName="Num" Property="Text" Value="&#x2713;"/></DataTrigger>
                <DataTrigger Binding="{Binding State}" Value="Attention"><Setter TargetName="Dot" Property="Background" Value="#C50F1F"/><Setter TargetName="Num" Property="Text" Value="!"/></DataTrigger>
                <DataTrigger Binding="{Binding State}" Value="Skipped"><Setter TargetName="Dot" Property="Background" Value="#9D9D9D"/><Setter TargetName="Num" Property="Text" Value="&#x2013;"/></DataTrigger>
              </DataTemplate.Triggers>
            </DataTemplate>
          </ItemsControl.ItemTemplate>
        </ItemsControl>
      </Border>

      <Grid Grid.Column="2">
        <!-- Step 1: check -->
        <ScrollViewer x:Name="Step1" VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="Let's find out why Bluetooth isn't working"/>
            <TextBlock Style="{StaticResource Body}" Text="This takes about ten seconds and changes nothing. It reads the device tree, the driver store, the Bluetooth services, the radio switch, policies and Windows' own Plug-and-Play log, then tells you in plain English what is wrong and what to try first."/>
            <Border Style="{StaticResource Card}" Margin="0,16,0,12">
              <StackPanel>
                <TextBlock x:Name="CheckTitle" Style="{StaticResource H2}" Text="Ready to check this PC"/>
                <TextBlock x:Name="CheckStatus" Style="{StaticResource Body}" Text="Click Start check. Nothing is changed until you choose a fix, and every fix is logged and backed up where it changes settings."/>
                <ProgressBar x:Name="CheckBar" Height="10" Minimum="0" Maximum="100" Margin="0,12,0,12"/>
                <Button x:Name="BtnStartCheck" Style="{StaticResource Primary}" Content="Start check" HorizontalAlignment="Left"/>
              </StackPanel>
            </Border>
            <TextBlock Style="{StaticResource Muted}" Text="Prefer the full picture? The Advanced view (top right) shows every finding with its evidence, every device, service, timeline entry and log line."/>
          </StackPanel>
        </ScrollViewer>

        <!-- Step 2: what we found -->
        <ScrollViewer x:Name="Step2" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="What we found"/>
            <Border x:Name="Verdict" Background="#E5E5E5" CornerRadius="8" Padding="16,12" Margin="0,0,0,12">
              <StackPanel>
                <TextBlock x:Name="VerdictTitle" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap" Text="Run the check first."/>
                <TextBlock x:Name="VerdictDetail" Style="{StaticResource Body}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="Your Bluetooth hardware"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="Radio chip"/><TextBlock x:Name="HwChip" Style="{StaticResource Body}"/></StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="Driver in use"/><TextBlock x:Name="HwDriver" Style="{StaticResource Body}"/></StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="Radio switch"/><TextBlock x:Name="HwRadio" Style="{StaticResource Body}"/></StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="Wi-Fi card"/><TextBlock x:Name="HwWifi" Style="{StaticResource Body}"/></StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="This PC"/><TextBlock x:Name="HwPc" Style="{StaticResource Body}"/></StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0"><TextBlock Style="{StaticResource Label}" Text="Windows"/><TextBlock x:Name="HwOs" Style="{StaticResource Body}"/></StackPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="Problems found, worst first"/>
                <ItemsControl x:Name="LvProblems">
                  <ItemsControl.ItemTemplate>
                    <DataTemplate>
                      <Grid Margin="0,0,0,6">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="84"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <Border x:Name="Pill" CornerRadius="10" Padding="8,2" Background="#9D9D9D" HorizontalAlignment="Left" VerticalAlignment="Top"><TextBlock Text="{Binding Severity}" Foreground="White" FontSize="11" FontWeight="SemiBold"/></Border>
                        <TextBlock Grid.Column="1" Text="{Binding Title}" TextWrapping="Wrap" Margin="8,1,0,0"/>
                      </Grid>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding Severity}" Value="Critical"><Setter TargetName="Pill" Property="Background" Value="#C50F1F"/></DataTrigger>
                        <DataTrigger Binding="{Binding Severity}" Value="Warning"><Setter TargetName="Pill" Property="Background" Value="#B58A00"/></DataTrigger>
                        <DataTrigger Binding="{Binding Severity}" Value="Info"><Setter TargetName="Pill" Property="Background" Value="#0067C0"/></DataTrigger>
                        <DataTrigger Binding="{Binding Severity}" Value="OK"><Setter TargetName="Pill" Property="Background" Value="#0F7B0F"/></DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </ItemsControl.ItemTemplate>
                </ItemsControl>
                <TextBlock Style="{StaticResource Muted}" Margin="0,8,0,0" Text="Each finding is explained with its evidence in Advanced view > Findings. The next steps walk through the fixes in the right order: driver first, then a real test, then everything else."/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- Step 3: the right driver -->
        <ScrollViewer x:Name="Step3" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="First thing to try: the right driver on the radio"/>
            <TextBlock Style="{StaticResource Body}" Text="A radio that 'looks fine but finds nothing' is, more often than anything else, running Windows' generic Bluetooth driver instead of the chip maker's. Intel, Realtek, MediaTek, Qualcomm and Broadcom radios load their firmware through the vendor driver; without it they are deaf while Device Manager says 'working'. Check this before anything else."/>
            <Border x:Name="DrvBadge" Background="#E5E5E5" CornerRadius="8" Padding="16,12" Margin="0,14,0,12">
              <StackPanel>
                <TextBlock x:Name="DrvBadgeText" FontSize="12" FontWeight="SemiBold" Foreground="#555555" Text="RUN THE CHECK FIRST"/>
                <TextBlock x:Name="DrvHeadline" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,2,0,4"/>
                <TextBlock x:Name="DrvExplain" Style="{StaticResource Body}"/>
                <TextBlock x:Name="DrvCurrent" Style="{StaticResource Muted}" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
            <Border x:Name="DrvAdminNote" Visibility="Collapsed" Background="#FFF4CE" CornerRadius="6" Padding="12,8" Margin="0,0,0,12"><TextBlock Style="{StaticResource Body}" Text="Installing a driver needs administrator rights. Click 'Relaunch as administrator' (top right) first; the check runs again on its own and brings you back here."/></Border>
            <Button x:Name="BtnDrvShowAnyway" Content="Show the driver options anyway" HorizontalAlignment="Left" Margin="0,0,0,12" Visibility="Collapsed"/>
            <StackPanel x:Name="DrvOptions" Visibility="Collapsed">
              <Border Style="{StaticResource Card}" x:Name="DrvCardStore" Visibility="Collapsed">
                <StackPanel>
                  <TextBlock Style="{StaticResource H2}" Text="Option A: use the vendor package that is already on this PC"/>
                  <TextBlock x:Name="DrvStoreText" Style="{StaticResource Body}"/>
                  <Button x:Name="BtnDrvStore" Style="{StaticResource Primary}" Content="Install it on the radio now" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" x:Name="DrvCardWU">
                <StackPanel>
                  <TextBlock x:Name="DrvWUTitle" Style="{StaticResource H2}" Text="Option B: let Windows Update fetch it (easiest; needs internet)"/>
                  <TextBlock Style="{StaticResource Body}" Text="Asks Windows Update, through its official API, for driver updates that list your radio's hardware ID, then downloads and installs them. One to three minutes. If Windows Update has nothing for your chip it says so, and you use Option C."/>
                  <Button x:Name="BtnDrvWU" Content="Fetch from Windows Update" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" x:Name="DrvCardPkg">
                <StackPanel>
                  <TextBlock x:Name="DrvPkgTitle" Style="{StaticResource H2}" Text="Option C: install the package from your PC or motherboard maker (the reliable one)"/>
                  <TextBlock x:Name="DrvPkgText" Style="{StaticResource Body}" Text="Download the Bluetooth driver for this exact machine from the page below, then come back and click 'Install the file I downloaded'. The tool unpacks the .zip or .exe, finds the INF that lists your radio, checks that it is signed, installs it and verifies that the radio switched over. You do not need to run the maker's installer."/>
                  <TextBlock x:Name="DrvLinkLabel" Style="{StaticResource Body}" FontWeight="SemiBold" Margin="0,10,0,0"/>
                  <TextBlock x:Name="DrvLinkNote" Style="{StaticResource Muted}"/>
                  <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                    <Button x:Name="BtnDrvOpenPage" Content="1. Open the download page"/>
                    <Button x:Name="BtnDrvPick" Style="{StaticResource Primary}" Content="2. Install the file I downloaded..."/>
                    <Button x:Name="BtnDrvPickFolder" Content="...or pick a folder"/>
                  </StackPanel>
                  <TextBlock x:Name="DrvHwid" Style="{StaticResource Muted}" Margin="0,10,0,0"/>
                </StackPanel>
              </Border>
            </StackPanel>
            <Border Style="{StaticResource Card}" x:Name="DrvResultCard" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="Result"/>
                <TextBlock x:Name="DrvResult" Style="{StaticResource Body}"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- Step 4: test -->
        <ScrollViewer x:Name="Step4" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="Test it: can the radio hear anything?"/>
            <TextBlock Style="{StaticResource Body}" Text="Device Manager saying 'working' proves nothing. This asks the radio to run a real discovery scan, the same one Settings > Add device runs, and lists what it hears. Hearing anything at all (your phone, a TV, a neighbour's speaker) proves the firmware loaded and the stack is alive."/>
            <Border x:Name="ScanBadge" Background="#E5E5E5" CornerRadius="8" Padding="16,12" Margin="0,14,0,12">
              <StackPanel>
                <TextBlock x:Name="ScanHeadline" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap" Text="Not tested yet"/>
                <TextBlock x:Name="ScanExplain" Style="{StaticResource Body}" Margin="0,4,0,0" Text="Click Scan. It listens for up to 45 seconds."/>
              </StackPanel>
            </Border>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <Button x:Name="BtnScan" Style="{StaticResource Primary}" Content="Scan for nearby devices (about 30 s)"/>
              <TextBlock Style="{StaticResource Muted}" VerticalAlignment="Center" Text="Tip: open Bluetooth settings on your phone, or put headphones in pairing mode, so there is something to hear."/>
            </StackPanel>
            <ListView x:Name="LvScan" Height="280">
              <ListView.View><GridView>
                <GridViewColumn Header="Device heard" Width="320" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Type" Width="80" DisplayMemberBinding="{Binding Kind}"/>
                <GridViewColumn Header="Paired" Width="70" DisplayMemberBinding="{Binding Paired}"/>
                <GridViewColumn Header="Signal" Width="80" DisplayMemberBinding="{Binding Rssi}"/>
                <GridViewColumn Header="Address" Width="170" DisplayMemberBinding="{Binding Address}"/>
              </GridView></ListView.View>
            </ListView>
          </StackPanel>
        </ScrollViewer>

        <!-- Step 5: other fixes -->
        <ScrollViewer x:Name="Step5" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="Other fixes the check recommends"/>
            <TextBlock x:Name="FixIntro" Style="{StaticResource Body}" Text="Run the check first."/>
            <ListView x:Name="LvGuidedFixes" Margin="0,12,0,10" MinHeight="120" MaxHeight="360">
              <ListView.View><GridView>
                <GridViewColumn Header="" Width="30"><GridViewColumn.CellTemplate><DataTemplate><CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}"/></DataTemplate></GridViewColumn.CellTemplate></GridViewColumn>
                <GridViewColumn Header="Fix" Width="250" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Risk" Width="70" DisplayMemberBinding="{Binding Risk}"/>
                <GridViewColumn Header="What it does" Width="430"><GridViewColumn.CellTemplate><DataTemplate><TextBlock Text="{Binding Description}" TextWrapping="Wrap"/></DataTemplate></GridViewColumn.CellTemplate></GridViewColumn>
                <GridViewColumn Header="Result" Width="150" DisplayMemberBinding="{Binding Status}"/>
              </GridView></ListView.View>
            </ListView>
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnGuidedApply" Style="{StaticResource Primary}" Content="Apply the ticked fixes"/>
              <CheckBox x:Name="ChkBackupG" Content="Back up registry and drivers first" IsChecked="True" VerticalAlignment="Center" Margin="8,0,0,0"/>
            </StackPanel>
            <TextBlock Style="{StaticResource Muted}" Margin="0,10,0,0" Text="Fixes with a side effect (USB controller restart, forgetting pairings, reboot) ask before they run. Afterwards the check runs again so you can see the difference. Everything else, including the fixes the check did not recommend, is in Advanced view > Fix plan."/>
          </StackPanel>
        </ScrollViewer>

        <!-- Step 6: wrap up -->
        <ScrollViewer x:Name="Step6" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Style="{StaticResource H1}" Text="Where things stand"/>
            <Border x:Name="FinalBadge" Background="#E5E5E5" CornerRadius="8" Padding="16,12" Margin="0,0,0,12">
              <StackPanel>
                <TextBlock x:Name="FinalHeadline" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap"/>
                <TextBlock x:Name="FinalText" Style="{StaticResource Body}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <WrapPanel Margin="0,0,0,12">
              <Button x:Name="BtnBtSettings" Style="{StaticResource Primary}" Content="Open Bluetooth settings to pair" Margin="0,0,8,8"/>
              <Button x:Name="BtnRecheck" Content="Run the check again" Margin="0,0,8,8"/>
              <Button x:Name="BtnReport2" Content="Save report (HTML + JSON)" Margin="0,0,8,8"/>
              <Button x:Name="BtnLinks2" Content="Open the driver download pages" Margin="0,0,8,8"/>
              <Button x:Name="BtnChecklist" Content="Hardware / BIOS checklist" Margin="0,0,8,8"/>
            </WrapPanel>
            <Border Style="{StaticResource Card}" x:Name="ChecklistCard" Visibility="Collapsed"><TextBox x:Name="TxtChecklist" IsReadOnly="True" TextWrapping="Wrap" BorderThickness="0" Background="Transparent"/></Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource H2}" Text="Still stuck?"/>
                <TextBlock Style="{StaticResource Body}" Text="Save the report and open an issue on GitHub with the .json attached (blank the serial number and computer name if you like). The timeline and device inventory in it are what make a fix possible. Everything the tool did, with the exact commands, is in Advanced view > Log."/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </Grid>
    </Grid>

    <!-- ===================== ADVANCED VIEW ===================== -->
    <Grid Grid.Row="1" x:Name="Advanced" Visibility="Collapsed">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
        <Button x:Name="BtnDiagnose" Style="{StaticResource Primary}" Content="Diagnose"/>
        <Button x:Name="BtnFixRecommended" Content="Fix recommended" IsEnabled="False"/>
        <Button x:Name="BtnReport" Content="Save report" IsEnabled="False"/>
        <TextBlock x:Name="AdvVerdict" VerticalAlignment="Center" Margin="8,0,0,0" FontWeight="SemiBold" TextWrapping="Wrap"/>
      </StackPanel>
      <TabControl Grid.Row="1" x:Name="Tabs" Background="White" BorderBrush="#DDDDDD">
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
    </Grid>

    <!-- footer -->
    <Grid Grid.Row="2" Margin="0,12,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <ProgressBar x:Name="Progress" Height="18" Minimum="0" Maximum="100"/>
      <TextBlock Grid.Column="1" x:Name="Status" Margin="10,0,10,0" VerticalAlignment="Center" Foreground="#444444" Text="Ready." TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal" x:Name="NavButtons">
        <Button x:Name="BtnBack" Content="Back" IsEnabled="False" MinWidth="90"/>
        <Button x:Name="BtnNext" Style="{StaticResource Primary}" Content="Next" IsEnabled="False" MinWidth="110" Margin="0"/>
      </StackPanel>
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
$sync.Progress = 0; $sync.Status = 'Ready.'; $sync.Diagnosis = $null; $sync.DiagFresh = $false; $sync.FixResults = $null; $sync.Scan = $null; $sync.Done = $false; $sync.Error = $null; $sync.ReportPath = $null
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
$script:step = 1
$script:maxStep = 1
$script:scanAuto = $false
$script:afterFixGoTo = 0
$script:pendingAfter = $null
$script:fixItems = New-Object System.Collections.ObjectModel.ObservableCollection[BluetoothFixer.UI.FixItem]
foreach ($c in (Get-BFFixCatalog)) { $fi = New-Object BluetoothFixer.UI.FixItem; $fi.Id = $c.Id; $fi.Name = $c.Name; $fi.Risk = $c.Risk; $fi.Description = $c.Description; $fi.NeedsAdmin = $c.NeedsAdmin; $script:fixItems.Add($fi) }
$script:guidedFixItems = New-Object System.Collections.ObjectModel.ObservableCollection[BluetoothFixer.UI.FixItem]
$ui.LvFixes.ItemsSource = $script:fixItems
$ui.LvGuidedFixes.ItemsSource = $script:guidedFixItems
$script:steps = New-Object System.Collections.ObjectModel.ObservableCollection[BluetoothFixer.UI.StepItem]
foreach ($def in @(@(1, 'Check this PC', 'Read-only, about ten seconds'), @(2, 'What we found', 'The verdict in plain English'), @(3, 'The right driver', 'First thing to try'), @(4, 'Test the radio', 'A real discovery scan'), @(5, 'Other fixes', 'In the right order'), @(6, 'Wrap up', 'Pair, report, more help'))) {
    $si = New-Object BluetoothFixer.UI.StepItem; $si.Number = $def[0]; $si.Title = $def[1]; $si.Hint = $def[2]; $script:steps.Add($si)
}
$script:steps[0].State = 'Current'
$ui.StepList.ItemsSource = $script:steps
$ui.BtnElevate.Visibility = if ($script:isAdmin) { 'Collapsed' } else { 'Visible' }
if (-not $script:isAdmin) { $ui.SubTitle.Text = 'Running WITHOUT administrator rights: the check works, repairs need the yellow button.' }
# These fix ids never run from a one-click "recommended" list: they reboot, take ages, forget pairings, open pages, or need a file.
$script:manualOnly = @('F17', 'F16', 'F14', 'F09', 'F18', 'F15', 'F20', 'F22')

function Set-Busy([bool]$b) {
    $hasDiag = ($sync.Diagnosis -ne $null)
    foreach ($n in 'BtnStartCheck', 'BtnDiagnose', 'BtnRecheck') { $ui[$n].IsEnabled = -not $b }
    foreach ($n in 'BtnFixRecommended', 'BtnRunSelected', 'BtnFixThis', 'BtnDrvWU', 'BtnDrvStore', 'BtnDrvPick', 'BtnDrvPickFolder', 'BtnScan', 'BtnGuidedApply', 'BtnReport', 'BtnReport2') { $ui[$n].IsEnabled = (-not $b) -and $hasDiag }
    $ui.BtnNext.IsEnabled = (-not $b) -and ($hasDiag -or $script:step -ge 6)
    $ui.BtnBack.IsEnabled = (-not $b) -and ($script:step -gt 1)
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
    try { $sync.Diagnosis = Invoke-BFDiagnosis; $sync.DiagFresh = $true } catch { $sync.Error = "Diagnosis failed: $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
    $sync.Done = $true
}
$fixScript = {
    param([string[]]$Ids, [bool]$Rediag, [bool]$Backup, [bool]$ConfirmReboot, [string]$PackagePath)
    try {
        if (-not $Backup) { $sync.FixResults = @(); foreach ($id in $Ids) { $sync.FixResults += [pscustomobject](Invoke-BFFix -FixId $id -Diagnosis $sync.Diagnosis -Confirmed:$ConfirmReboot -PackagePath $PackagePath) } }
        else { $sync.FixResults = @(Invoke-BFFixPlan -FixIds $Ids -Diagnosis $sync.Diagnosis -ConfirmReboot:$ConfirmReboot -PackagePath $PackagePath) }
        if ($Rediag) { Write-BFLog -Level STEP -Message 'Re-running the check to verify'; $sync.Diagnosis = Invoke-BFDiagnosis; $sync.DiagFresh = $true }
    } catch { $sync.Error = "Fix run failed: $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
    $sync.Done = $true
}
$scanScript = {
    param([int]$Timeout)
    try { $sync.Scan = Test-BFDiscovery -TimeoutSec $Timeout; if ($sync.Diagnosis) { $sync.Diagnosis.Scan = $sync.Scan } } catch { $sync.Error = "Discovery test failed: $($_.Exception.Message)" }
    $sync.Done = $true
}
$reportScript = { try { $sync.ReportPath = Export-BFReport -Diagnosis $sync.Diagnosis -FixResults $sync.FixResults } catch { $sync.Error = "Report failed: $($_.Exception.Message)" }; $sync.Done = $true }

# --- wizard navigation --------------------------------------------------------
function Show-Step([int]$n) {
    if ($n -lt 1) { $n = 1 }; if ($n -gt 6) { $n = 6 }
    $script:step = $n
    if ($n -gt $script:maxStep) { $script:maxStep = $n }
    for ($i = 1; $i -le 6; $i++) { $ui["Step$i"].Visibility = if ($i -eq $n) { 'Visible' } else { 'Collapsed' } }
    foreach ($st in $script:steps) {
        if ($st.Number -eq $n) { $st.State = 'Current' }
        elseif ($st.Number -lt $n) { if ($st.State -in 'Current', 'Pending') { $st.State = 'Done' } }
        elseif ($st.State -eq 'Current') { $st.State = 'Pending' }
    }
    $ui.BtnBack.IsEnabled = ($n -gt 1) -and -not $script:worker
    $ui.BtnNext.Content = if ($n -eq 6) { 'Finish' } else { 'Next' }
    $ui.BtnNext.IsEnabled = (-not $script:worker) -and (($sync.Diagnosis -ne $null) -or $n -eq 6)
    if ($n -eq 4 -and -not $script:scanAuto -and $sync.Diagnosis -and $sync.Diagnosis.Summary.RadioPresent -and -not $script:worker) { $script:scanAuto = $true; Start-Scan }
    if ($n -eq 6) { Render-Final }
}

function Set-StepOutcome([int]$n, [string]$state, [string]$hint) {
    $st = $script:steps[$n - 1]
    if ($st.Number -ne $script:step) { $st.State = $state }
    if ($hint) { $st.Hint = $hint }
}

function Start-Diagnosis {
    $ui.TxtLog.Clear(); $script:logIndex = $sync.Log.Count
    $ui.CheckTitle.Text = 'Checking this PC...'
    $ui.CheckStatus.Text = 'Reading devices, drivers, services and logs. Nothing is being changed.'
    Start-Work $diagScript $null
}

function Start-Scan {
    $ui.LvScan.ItemsSource = $null
    $ui.ScanBadge.Background = '#E5E5E5'
    $ui.ScanHeadline.Text = 'Scanning...'
    $ui.ScanExplain.Text = 'Listening for nearby Bluetooth devices. A healthy radio answers within 10 to 30 seconds; the test gives up after 45.'
    Start-Work $scanScript @{ Timeout = 45 }
}

# --- rendering ----------------------------------------------------------------
function Render-DriverStep {
    $d = $sync.Diagnosis
    $fs = $d.FirstStep
    if (-not $fs) { return }
    $needs = ($fs.Situation -in 'Generic', 'NoDriver', 'WrongVendor')
    switch ($fs.Situation) {
        'NoRadio'   { $ui.DrvBadge.Background = '#E5E5E5'; $ui.DrvBadgeText.Text = 'NO RADIO TO CHECK'; $ui.DrvBadgeText.Foreground = '#555555' }
        'Vendor'    { $ui.DrvBadge.Background = '#DFF6DD'; $ui.DrvBadgeText.Text = 'LOOKS RIGHT'; $ui.DrvBadgeText.Foreground = '#0F7B0F' }
        'GenericOk' { $ui.DrvBadge.Background = '#DFF6DD'; $ui.DrvBadgeText.Text = 'LOOKS RIGHT'; $ui.DrvBadgeText.Foreground = '#0F7B0F' }
        default     { $ui.DrvBadge.Background = '#FDE7E9'; $ui.DrvBadgeText.Text = 'NEEDS FIXING - START HERE'; $ui.DrvBadgeText.Foreground = '#C50F1F' }
    }
    $ui.DrvHeadline.Text = $fs.Headline
    $ui.DrvExplain.Text = $fs.Explanation
    $ui.DrvCurrent.Text = if ($fs.Radio) { "Radio: $($fs.ChipName)   |   Driver now: $($fs.DriverText)   |   Hardware ID: $($fs.HardwareId)" } else { '' }
    $ui.DrvOptions.Visibility = if ($needs) { 'Visible' } else { 'Collapsed' }
    $ui.BtnDrvShowAnyway.Visibility = if (-not $needs -and $fs.Radio) { 'Visible' } else { 'Collapsed' }
    $ui.DrvAdminNote.Visibility = if ($needs -and -not $script:isAdmin) { 'Visible' } else { 'Collapsed' }
    if ($fs.StorePackages.Count) {
        $ui.DrvCardStore.Visibility = 'Visible'
        $ui.DrvStoreText.Text = 'The driver store already holds a vendor package that lists your radio: ' + (($fs.StorePackages | ForEach-Object { "$($_.Published) ($($_.Original) $($_.Version) by $($_.Provider))" }) -join '; ') + '. Windows did not apply it; this installs it onto the radio.'
    } else { $ui.DrvCardStore.Visibility = 'Collapsed' }
    $vendor = if ($fs.ChipVendor -in 'Unknown', 'Module', '') { 'your chip vendor' } else { $fs.ChipVendor }
    if ($fs.DownloadLink) {
        $ui.DrvLinkLabel.Text = "Where to get it: $($fs.DownloadLink.Label)"
        $ui.DrvLinkNote.Text = $fs.DownloadLink.Note
    } else { $ui.DrvLinkLabel.Text = 'Where to get it: your PC maker''s support page for this exact model.'; $ui.DrvLinkNote.Text = '' }
    $cat = if ($fs.CatalogLink) { ' The Windows Update Catalog also lists every Microsoft-signed driver for it (Advanced view > Drivers and links).' } else { '' }
    $ui.DrvHwid.Text = "On that page look for the Bluetooth entry (often under 'WLAN+BT' or 'Wireless') from $vendor. Your radio's hardware ID is $($fs.HardwareId); the right package lists it.$cat"
    Set-StepOutcome 3 $(if ($fs.Situation -eq 'NoRadio') { 'Skipped' } elseif ($needs) { 'Attention' } else { 'Done' }) $(switch ($fs.Situation) { 'Generic' { 'Generic driver: fix this first' } 'NoDriver' { 'No driver installed' } 'WrongVendor' { 'Wrong vendor driver' } 'NoRadio' { 'No radio present' } default { 'Vendor driver in place' } })
}

function Render-Diagnosis {
    $d = $sync.Diagnosis
    if (-not $d) { return }
    # Advanced tabs
    $ui.LvFindings.ItemsSource = @($d.Findings)
    $ui.LvDevices.ItemsSource = @($d.Inventory.AllRecords | Sort-Object Role, @{ Expression = 'Present'; Descending = $true })
    $ui.LvServices.ItemsSource = @($d.Services.Rows)
    $ui.LvTimeline.ItemsSource = @($d.Timeline | Select-Object -First 300 | ForEach-Object { [pscustomobject]@{ TimeText = $_.Time.ToString('yyyy-MM-dd HH:mm:ss'); Source = $_.Source; Text = $_.Text; Severity = $_.Severity } })
    $ui.LvLinks.ItemsSource = @($d.Links)
    $ui.LvStore.ItemsSource = @($d.DriverStore.BluetoothPackages | ForEach-Object { [pscustomobject]@{ Published = $_.Published; Original = $_.Original; Provider = $_.Provider; Version = $_.Version; Date = $_.Date; HwText = (($_.HardwareIds | Select-Object -First 6) -join ', ') } })
    $rec = @(Get-BFRecommendedFixes -Diagnosis $d)
    foreach ($fi in $script:fixItems) { $fi.Recommended = ($rec -contains $fi.Id); $fi.IsSelected = $fi.Recommended -and $fi.Id -notin $script:manualOnly }
    $ui.LvFixes.Items.Refresh()
    $s = $d.Summary
    $env = $d.Environment
    $ui.AdvVerdict.Text = "$($s.Verdict): $($s.Headline)"
    $ui.BtnFixRecommended.Content = if ($rec.Count) { "Fix recommended ($(@($rec | Where-Object { $_ -notin $script:manualOnly }).Count))" } else { 'Nothing to fix' }
    if ($ui.LvFindings.Items.Count -gt 0) { $ui.LvFindings.SelectedIndex = 0 }

    # Guided: step 2
    $ui.VerdictTitle.Text = "$($s.Verdict): $($s.Headline)"
    $ui.VerdictDetail.Text = ("{0} critical, {1} warnings | radio present: {2} | check took {3}s" -f $s.CriticalCount, $s.WarningCount, $(if ($s.RadioPresent) { 'yes' } else { 'NO' }), $d.DurationSec)
    $ui.Verdict.Background = if ($s.CriticalCount -gt 0) { '#FDE7E9' } elseif ($s.WarningCount -gt 0) { '#FFF4CE' } else { '#DFF6DD' }
    $fs = $d.FirstStep
    $ui.HwChip.Text = if ($fs -and $fs.Radio) { "$($fs.ChipName)   ($($fs.HardwareId))" } else { 'No Bluetooth radio is present' }
    $ui.HwDriver.Text = if ($fs -and $fs.Radio) { $fs.DriverText } else { '-' }
    $ui.HwRadio.Text = if ($d.Radio.Available -and $d.Radio.BluetoothRadio) { "$($d.Radio.BluetoothRadio.State)" + $(if ($env.AirplaneMode) { ' (airplane mode is ON)' } else { '' }) } elseif ($d.Radio.Available) { 'Radio Management lists no Bluetooth radio' } else { 'not readable in this session' }
    $ui.HwWifi.Text = if ($s.WifiName) { "$($s.WifiName)  (combo cards carry the Bluetooth radio, so this tells us which chip to expect)" } else { 'none found' }
    $board = ''
    if (-not $env.IsLaptop -and $env.BaseBoardProduct -and $env.BaseBoardProduct -notmatch 'Default|To be filled|Base Board' -and "$($env.Model)" -ne "$($env.BaseBoardProduct)") { $board = "  |  motherboard: $($env.BaseBoardMaker) $($env.BaseBoardProduct)" }
    $ui.HwPc.Text = "$($env.Manufacturer) $($env.Model)$board" + $(if ($env.IsLaptop) { '  (laptop)' } else { '  (desktop)' })
    $ui.HwOs.Text = "$($env.OSName) $($env.DisplayVersion) (build $($env.Build).$($env.UBR))" + $(if (-not $env.IsAdmin) { '  |  not running as administrator' } else { '' })
    $problems = @($d.Findings | Where-Object { $_.Severity -in 'Critical', 'Warning' } | ForEach-Object { [pscustomobject]@{ Severity = $_.Severity; Title = $_.Title } })
    if ($problems.Count -eq 0) { $problems = @([pscustomobject]@{ Severity = 'OK'; Title = 'No critical problems or warnings. If a specific gadget will not pair, that is a pairing problem, not a broken stack (step 6 has the fix).' }) }
    $ui.LvProblems.ItemsSource = $problems
    Set-StepOutcome 2 $(if ($s.CriticalCount -gt 0) { 'Attention' } else { 'Done' }) $(if ($s.CriticalCount -gt 0) { "$($s.CriticalCount) critical problem(s)" } elseif ($s.WarningCount -gt 0) { "$($s.WarningCount) warning(s), nothing critical" } else { 'Looks healthy' })

    # Guided: step 3
    Render-DriverStep

    # Guided: step 5
    $script:guidedFixItems.Clear()
    foreach ($fi in $script:fixItems) { if ($fi.Recommended -and $fi.Id -notin 'F17', 'F09', 'F18', 'F15', 'F20', 'F22', 'F07', 'F08') { $fi.IsSelected = ($fi.Id -notin 'F16', 'F14'); $script:guidedFixItems.Add($fi) } }
    $n = $script:guidedFixItems.Count
    $ui.FixIntro.Text = if ($n -gt 0) { "The check recommends $n more fix(es) besides the driver, listed in the order they should run: radio switch and services first, then the USB stack, then power and cleanup. Each one is reversible where it changes settings (backed up first)." } else { 'The check does not recommend any other fix right now. If the radio still hears nothing after the driver step, step 6 has the hardware checklist and the report for asking for help.' }
    Set-StepOutcome 5 $(if ($n -gt 0) { 'Attention' } else { 'Done' }) $(if ($n -gt 0) { "$n recommended" } else { 'Nothing else to fix' })
    $ui.CheckTitle.Text = 'Check complete'
    $ui.CheckStatus.Text = "$($s.Verdict): $($s.Headline)  (click Next, or run the check again)"
}

function Render-Scan($r) {
    if (-not $r) { return }
    $fs = $sync.Diagnosis.FirstStep
    $ui.LvScan.ItemsSource = @($r.Devices)
    if ($r.Error) {
        $ui.ScanBadge.Background = '#E5E5E5'
        $ui.ScanHeadline.Text = 'The scan could not run'
        $ui.ScanExplain.Text = "$($r.Error). The manual version of this test is Settings > Bluetooth & devices > Add device: if nothing ever appears there, the radio is deaf."
        Set-StepOutcome 4 'Attention' 'Scan could not run'
    } elseif ($r.TimedOut) {
        $ui.ScanBadge.Background = '#FFF4CE'
        $ui.ScanHeadline.Text = 'The radio did not finish a scan in 45 seconds'
        $ui.ScanExplain.Text = 'A healthy radio answers within 10 to 30 seconds. Taking longer usually means the driver cannot talk to the radio at all: the firmware did not load (step 3), or the Bluetooth Support Service is stuck (step 5 restarts it).'
        Set-StepOutcome 4 'Attention' 'Scan timed out'
    } elseif ($r.Count -eq 0) {
        $ui.ScanBadge.Background = '#FDE7E9'
        $ui.ScanHeadline.Text = 'The radio heard nothing'
        $ui.ScanExplain.Text = if ($fs -and $fs.Situation -in 'Generic', 'NoDriver', 'WrongVendor') { "That matches the driver finding: with the generic driver the radio cannot hear anything. Go back to step 3 and install the $($fs.ChipVendor) package, then scan again." } else { 'Either nothing nearby is discoverable right now, or the radio is deaf. Open Bluetooth settings on a phone (that makes it discoverable) or put headphones in pairing mode, then scan again. If it still hears nothing, carry on to the other fixes and the hardware checklist.' }
        Set-StepOutcome 4 'Attention' 'Heard nothing'
    } else {
        $ui.ScanBadge.Background = '#DFF6DD'
        $ui.ScanHeadline.Text = "The radio works: it heard $($r.Count) device(s)" + $(if ($r.Named -lt $r.Count) { " ($($r.Named) with a name)" } else { '' })
        $ui.ScanExplain.Text = 'Firmware loaded, stack alive, radio listening. If one particular gadget still refuses to pair, that is a pairing problem rather than a broken stack: remove it in Settings > Bluetooth & devices, put it in pairing mode and pair again.'
        Set-StepOutcome 4 'Done' "Heard $($r.Count) device(s)"
    }
    $ui.Status.Text = "Scan finished in $($r.DurationSec)s."
}

function Render-Final {
    $d = $sync.Diagnosis
    if (-not $d) { $ui.FinalHeadline.Text = 'Run the check first'; $ui.FinalText.Text = ''; return }
    $s = $d.Summary; $sc = $d.Scan
    $heard = ($sc -and -not $sc.Error -and -not $sc.TimedOut -and $sc.Count -gt 0)
    $deaf = ($sc -and -not $sc.Error -and ($sc.TimedOut -or $sc.Count -eq 0))
    if ($s.CriticalCount -eq 0 -and $s.RadioPresent -and -not $deaf) {
        $ui.FinalBadge.Background = '#DFF6DD'
        $ui.FinalHeadline.Text = if ($heard) { "Bluetooth is working: the $($s.RadioName) heard $($sc.Count) nearby device(s)" } else { 'Bluetooth looks healthy' }
        $ui.FinalText.Text = 'Pair your devices from Bluetooth settings. If one gadget will not pair: remove it there, put it in pairing mode (hold its power button until the light flashes), pair again. If every device fails to pair, Advanced view > Fix plan > "Forget all paired devices" resets the pairing store.'
    } else {
        $ui.FinalBadge.Background = if ($s.CriticalCount -gt 0 -or $deaf) { '#FDE7E9' } else { '#FFF4CE' }
        $ui.FinalHeadline.Text = if ($deaf -and $s.CriticalCount -eq 0) { 'Everything checks out on paper, but the radio heard nothing' } else { $s.Headline }
        $ui.FinalText.Text = if ($deaf -and $s.CriticalCount -eq 0) { 'Try the scan again with a phone made discoverable next to the PC. If it still hears nothing, work through the hardware / BIOS checklist (a full power drain and reseating the card fix more of these than anyone expects), then save the report and ask for help with it.' } else { 'Step 3 and step 5 hold the fixes for this. If you applied them and the problem remains, save the report: the findings, evidence and timeline in it are what make the next step possible.' }
    }
}

function Show-FixResults {
    $res = $sync.FixResults
    if (-not $res) { return }
    foreach ($r in $res) { $fi = $script:fixItems | Where-Object Id -eq $r.Id; if ($fi) { $fi.Status = if ($r.Success) { 'OK' + $(if ($r.RebootRequired) { ' (reboot needed)' } else { '' }) } elseif ($r.Skipped) { 'Skipped' } else { 'FAILED' } } }
    $ui.LvFixes.Items.Refresh(); $ui.LvGuidedFixes.Items.Refresh()
    $reboot = @($res | Where-Object RebootRequired).Count -gt 0
    $lines = @($res | ForEach-Object { $c = Get-BFFixCatalog | Where-Object Id -eq $_.Id; "{0} {1}: {2}" -f $_.Id, $c.Name, $_.Message })
    $drv = @($res | Where-Object { $_.Id -in 'F07', 'F08', 'F22' })
    if ($drv.Count) {
        $ui.DrvResultCard.Visibility = 'Visible'
        $ui.DrvResult.Text = (($drv | ForEach-Object { $c = Get-BFFixCatalog | Where-Object Id -eq $_.Id; "$($c.Name): $(if ($_.Success) { 'OK. ' } elseif ($_.Skipped) { 'Skipped. ' } else { 'FAILED. ' })$($_.Message)" }) -join "`n`n")
        $ui.DrvResultCard.Background = if (@($drv | Where-Object Success).Count) { '#F3FBF3' } else { '#FFF8F8' }
    }
    $msg = ($lines -join "`n`n")
    if ($reboot -and -not ($res | Where-Object { $_.Id -eq 'F17' -and $_.Success })) {
        $msg += "`n`nA reboot is needed to finish. Reboot now? (Windows restarts in 30 seconds; the tool re-checks after logon.)"
        $a = Show-Msg -Text $msg -Title 'Fix results' -Buttons 'YesNo' -Icon 'Question'
        if ($a -eq 'Yes') { Start-Work $fixScript @{ Ids = @('F17'); Rediag = $false; Backup = $false; ConfirmReboot = $true; PackagePath = '' } }
    } else { Show-Msg -Text $msg -Title 'Fix results' | Out-Null }
}

# --- timer: pump log + progress, detect completion --------------------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    while ($script:logIndex -lt $sync.Log.Count) { $ui.TxtLog.AppendText($sync.Log[$script:logIndex] + "`r`n"); $script:logIndex++; $ui.TxtLog.ScrollToEnd() }
    $ui.Progress.Value = [double]$sync.Progress
    $ui.CheckBar.Value = [double]$sync.Progress
    $ui.Status.Text = $sync.Status
    if ($script:worker -and $script:step -eq 1) { $ui.CheckStatus.Text = $sync.Status }
    if ($script:worker -and $script:worker.Handle.IsCompleted) {
        # NOTE: never name a local "$w" here - PowerShell variables are case-insensitive and it would shadow the $W window
        $finishedWorker = $script:worker; $script:worker = $null
        try { $finishedWorker.PS.EndInvoke($finishedWorker.Handle) | Out-Null } catch { $sync.Error = "Worker error: $($_.Exception.Message)" }
        $finishedWorker.PS.Dispose()
        Set-Busy $false
        if ($sync.Error) { Show-Msg -Text $sync.Error -Icon 'Error' | Out-Null; $sync.Error = $null }
        if ($sync.Diagnosis -and $sync.DiagFresh) {
            $sync.DiagFresh = $false
            Render-Diagnosis
            if ($script:step -eq 1) { Show-Step 2 }
        }
        if ($sync.FixResults) {
            Show-FixResults; $sync.FixResults = $null
            if ($script:afterFixGoTo) { $g = $script:afterFixGoTo; $script:afterFixGoTo = 0; $script:scanAuto = $false; Show-Step $g }
        }
        if ($sync.Scan) { Render-Scan $sync.Scan; $sync.Scan = $null }
        if ($sync.ReportPath) { $p = $sync.ReportPath; $sync.ReportPath = $null; $ui.Status.Text = "Report saved: $p"; try { Start-Process $p } catch { } }
        if ($script:pendingAfter) { $a = $script:pendingAfter; $script:pendingAfter = $null; & $a }
    }
})
$timer.Start()

# --- running fixes --------------------------------------------------------------
function Select-DriverPackage([switch]$Folder) {
    if ($Folder) {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Pick the folder you unpacked the Bluetooth driver into (the one with the .inf files, or any folder above it).'
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
        return $null
    }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Pick the Bluetooth driver you downloaded'
    $dlg.Filter = 'Driver packages (*.zip;*.exe;*.cab;*.7z;*.inf)|*.zip;*.exe;*.cab;*.7z;*.inf|All files (*.*)|*.*'
    $dl = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path $dl) { $dlg.InitialDirectory = $dl }
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.FileName }
    return $null
}

function Confirm-And-Run([string[]]$ids, [string]$PackagePath = '', [int]$GoTo = 0, [bool]$Backup = $true) {
    if (-not $ids -or $ids.Count -eq 0) { Show-Msg -Text 'No fixes selected.' | Out-Null; return }
    $needAdmin = @($ids | ForEach-Object { $i = $_; (Get-BFFixCatalog | Where-Object Id -eq $i).NeedsAdmin } | Where-Object { $_ }).Count -gt 0
    if ($needAdmin -and -not $script:isAdmin) { Show-Msg -Text 'These fixes need administrator rights. Use "Relaunch as administrator" (top right) first; the check re-runs on its own.' -Icon 'Warning' | Out-Null; return }
    $confirmReboot = $false
    if ($ids -contains 'F17') { $a = Show-Msg -Text 'This will restart Windows in 30 seconds after the other fixes. Save your work. Continue?' -Title 'Reboot' -Buttons 'YesNo' -Icon 'Warning'; if ($a -ne 'Yes') { return }; $confirmReboot = $true }
    if ($ids -contains 'F02') { $a = Show-Msg -Text 'Restarting the USB controller makes every USB device disconnect for a few seconds (keyboard, mouse, drives all come back). Continue?' -Title 'USB controller restart' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    if ($ids -contains 'F21') { $a = Show-Msg -Text 'This installs the newer Microsoft USB hub / xHCI driver that Windows Update left in the component store onto your USB controllers. USB devices disconnect for a few seconds. Continue?' -Title 'Re-stage USB drivers' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    if ($ids -contains 'F14') { $a = Show-Msg -Text 'Forgetting all paired devices means pairing them again afterwards. Continue?' -Title 'Forget pairings' -Buttons 'YesNo' -Icon 'Question'; if ($a -ne 'Yes') { return } }
    if ($ids -contains 'F22' -and -not $PackagePath) { $PackagePath = Select-DriverPackage; if (-not $PackagePath) { return } }
    foreach ($fi in $script:fixItems) { if ($ids -contains $fi.Id) { $fi.Status = 'Running...' } }
    $script:afterFixGoTo = $GoTo
    if ($ui.Advanced.Visibility -eq 'Visible') { $ui.Tabs.SelectedIndex = 1 }
    Start-Work $fixScript @{ Ids = $ids; Rediag = $true; Backup = $Backup; ConfirmReboot = $confirmReboot; PackagePath = $PackagePath }
}

function Open-DriverPages {
    $d = $sync.Diagnosis
    if (-not $d) { return }
    $n = 0
    foreach ($l in @($d.Links | Where-Object { $_.Url -and $_.Group -in 'Motherboard', 'PC maker', 'Chip vendor', 'Windows Update Catalog' })) { try { Start-Process $l.Url; $n++ } catch { } }
    $ui.Status.Text = "Opened $n page(s) in your browser."
}

# --- events -----------------------------------------------------------------
$ui.BtnStartCheck.Add_Click({ Start-Diagnosis })
$ui.BtnDiagnose.Add_Click({ Start-Diagnosis })
$ui.BtnRecheck.Add_Click({ Start-Diagnosis; Show-Step 1 })
$ui.BtnReport.Add_Click({ Start-Work $reportScript $null })
$ui.BtnReport2.Add_Click({ Start-Work $reportScript $null })
$ui.BtnNext.Add_Click({ if ($script:step -ge 6) { $W.Close() } else { Show-Step ($script:step + 1) } })
$ui.BtnBack.Add_Click({ Show-Step ($script:step - 1) })
$ui.BtnAdvanced.Add_Click({
    if ($ui.Advanced.Visibility -eq 'Visible') { $ui.Advanced.Visibility = 'Collapsed'; $ui.Wizard.Visibility = 'Visible'; $ui.NavButtons.Visibility = 'Visible'; $ui.BtnAdvanced.Content = 'Advanced view' }
    else { $ui.Advanced.Visibility = 'Visible'; $ui.Wizard.Visibility = 'Collapsed'; $ui.NavButtons.Visibility = 'Collapsed'; $ui.BtnAdvanced.Content = 'Guided view' }
})
$ui.BtnElevate.Add_Click({
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`" -AutoDiagnose" -ErrorAction Stop
        $W.Close()
    } catch { Show-Msg -Text "Could not elevate: $($_.Exception.Message)" -Icon 'Warning' | Out-Null }
})
$ui.StepList.Add_PreviewMouseLeftButtonUp({
    param($s, $e)
    try {
        $o = $e.OriginalSource
        while ($o -and -not ($o.DataContext -is [BluetoothFixer.UI.StepItem])) { $o = [System.Windows.Media.VisualTreeHelper]::GetParent($o) }
        if ($o -and -not $script:worker) { $n = $o.DataContext.Number; if ($sync.Diagnosis -or $n -eq 1) { Show-Step $n } }
    } catch { }
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
$ui.BtnFixThis.Add_Click({ $f = $ui.LvFindings.SelectedItem; if ($f) { Confirm-And-Run @($f.Fixes | Where-Object { $_ -notin 'F09', 'F18', 'F15', 'F20' }) -Backup ([bool]$ui.ChkBackup.IsChecked) } })
$ui.BtnFixRecommended.Add_Click({ if ($sync.Diagnosis) { $ids = @(Get-BFRecommendedFixes -Diagnosis $sync.Diagnosis | Where-Object { $_ -notin $script:manualOnly }); Confirm-And-Run $ids -Backup ([bool]$ui.ChkBackup.IsChecked) } })
$ui.BtnRunSelected.Add_Click({ Confirm-And-Run @($script:fixItems | Where-Object IsSelected | ForEach-Object Id) -Backup ([bool]$ui.ChkBackup.IsChecked) })
$ui.BtnSelRecommended.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = $fi.Recommended } })
$ui.BtnSelSafe.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = ($fi.Risk -eq 'Safe' -and $fi.Id -notin 'F09', 'F15', 'F18', 'F20') } })
$ui.BtnSelNone.Add_Click({ foreach ($fi in $script:fixItems) { $fi.IsSelected = $false } })
$ui.LvLinks.Add_MouseDoubleClick({ $l = $ui.LvLinks.SelectedItem; if ($l -and $l.Url) { try { Start-Process $l.Url } catch { } } })
$ui.BtnOpenLogs.Add_Click({ Start-Process (Join-Path $env:ProgramData 'BluetoothFixer\Logs') })
$ui.BtnOpenBackups.Add_Click({ Start-Process (Join-Path $env:ProgramData 'BluetoothFixer\Backups') })
$ui.BtnOpenReports.Add_Click({ $p = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'BluetoothFixer\Reports'; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }; Start-Process $p })
# step 3: driver
$ui.BtnDrvShowAnyway.Add_Click({ $ui.DrvOptions.Visibility = 'Visible'; $ui.BtnDrvShowAnyway.Visibility = 'Collapsed'; if (-not $script:isAdmin) { $ui.DrvAdminNote.Visibility = 'Visible' } })
$ui.BtnDrvStore.Add_Click({ Confirm-And-Run @('F07') -GoTo 4 })
$ui.BtnDrvWU.Add_Click({ Confirm-And-Run @('F08') -GoTo 4 })
$ui.BtnDrvOpenPage.Add_Click({ $fs = $sync.Diagnosis.FirstStep; if ($fs -and $fs.DownloadLink -and $fs.DownloadLink.Url) { try { Start-Process $fs.DownloadLink.Url } catch { } } else { Open-DriverPages } })
$ui.BtnDrvPick.Add_Click({ if (-not $script:isAdmin) { Show-Msg -Text 'Installing a driver needs administrator rights. Use "Relaunch as administrator" (top right) first.' -Icon 'Warning' | Out-Null; return }; $p = Select-DriverPackage; if ($p) { Confirm-And-Run @('F22') -PackagePath $p -GoTo 4 } })
$ui.BtnDrvPickFolder.Add_Click({ if (-not $script:isAdmin) { Show-Msg -Text 'Installing a driver needs administrator rights. Use "Relaunch as administrator" (top right) first.' -Icon 'Warning' | Out-Null; return }; $p = Select-DriverPackage -Folder; if ($p) { Confirm-And-Run @('F22') -PackagePath $p -GoTo 4 } })
# step 4: scan
$ui.BtnScan.Add_Click({ Start-Scan })
# step 5: other fixes
$ui.BtnGuidedApply.Add_Click({ Confirm-And-Run @($script:guidedFixItems | Where-Object IsSelected | ForEach-Object Id) -GoTo 5 -Backup ([bool]$ui.ChkBackupG.IsChecked) })
# step 6: wrap up
$ui.BtnBtSettings.Add_Click({ try { Start-Process 'ms-settings:bluetooth' } catch { } })
$ui.BtnLinks2.Add_Click({ Open-DriverPages })
$ui.BtnChecklist.Add_Click({ if ($ui.ChecklistCard.Visibility -eq 'Visible') { $ui.ChecklistCard.Visibility = 'Collapsed' } else { $ui.TxtChecklist.Text = (Invoke-BFFix -FixId 'F18').Message; $ui.ChecklistCard.Visibility = 'Visible' } })
$W.Add_Closed({ $timer.Stop(); try { if ($script:worker) { $script:worker.PS.Stop() } } catch { }; try { $rs.Close(); $rs.Dispose() } catch { } })

if ($Verify) {
    $ui.SubTitle.Text = 'Post-reboot verification: checking whether the repair held.'
    $script:pendingAfter = {
        $s = $sync.Diagnosis.Summary
        $txt = if ($s.CriticalCount -eq 0 -and $s.RadioPresent) { "Bluetooth is working again. Radio: $($s.RadioName). Step 4 runs a discovery scan to prove it." } else { "Still not right: $($s.Headline). Step 3 and the Advanced view have the next move." }
        Show-Msg -Text $txt -Title 'Post-reboot verification' -Icon $(if ($s.CriticalCount -eq 0) { 'Information' } else { 'Warning' }) | Out-Null
    }
    $W.Add_ContentRendered({ Start-Diagnosis })
} elseif ($AutoDiagnose) {
    $W.Add_ContentRendered({ Start-Diagnosis })
}

[void]$W.ShowDialog()
