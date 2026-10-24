# Field guide: what each finding means and what the fix does

Finding IDs appear in the report and the JSON. Fix IDs are in the README table.

## The first thing to try (guided view, step 3)
`Get-BFDriverSituation` looks at the primary present radio and returns one of:
- **Generic** - Microsoft's inbox `bth.inf` ("Generic Bluetooth Adapter") on an Intel / Realtek / MediaTek / Qualcomm / Broadcom radio. The radio is "working" in Device Manager, Radio Management may even list it as On, and it hears nothing because the firmware never loaded. Fix order: F07 if a vendor package is already in the store, F08 Windows Update, F22 the download from the PC/motherboard maker, F09 to open the pages.
- **NoDriver** - Code 28. Same fixes.
- **WrongVendor** - a driver whose provider is a different chip vendor than the hardware. F07 removes it, then as above.
- **GenericOk** - CSR and similar radios carry their own firmware; the inbox driver is right.
- **Vendor** - the vendor driver is on it; look elsewhere (step 4 proves it, step 5 does the rest).
- **NoRadio** - nothing to check; the USB / ghost / BIOS findings say why.

Detection: `MatchingDeviceId` starts with `USB\Class_` (matched on the Bluetooth USB class only) **or** the INF is `bth.inf` with provider Microsoft, on a radio whose vendor needs its own driver (`UsbVendors[].NeedsVendorDriver`, or the chip vendor inferred from the Wi-Fi adapter name / bus description for module makers).

## The discovery test (guided view, step 4; CLI `-Scan`)
`Test-BFDiscovery` runs `DeviceInformation.FindAllAsync` with the Bluetooth classic and LE association-endpoint selectors, the same enumeration Settings > Add device performs, and lists every device heard with name, type, signal and address. 10-30 s on a healthy radio; 45 s cap.
- **Heard N** - firmware loaded, stack alive. Pairing trouble is a pairing problem.
- **Heard nothing** - either nothing discoverable nearby (make a phone discoverable and retry) or the radio is deaf. With a Generic driver situation this is the confirmation.
- **Timed out** - the driver cannot talk to the radio at all, or `bthserv` is stuck. Step 3 / F06.

## Environment
- **ENV-ADMIN** Not elevated. Diagnosis is complete; repairs are blocked. Use the yellow button.
- **ENV-REBOOT** Windows has pending servicing/driver changes. Anything you fix may not show until a restart.
- **ENV-AIRPLANE** `RadioManagement\SystemRadioState = 1`. Airplane mode kills every radio. F10 clears it.

## USB stack (the part nobody checks)
On laptops the Bluetooth half of an Intel/Realtek/MediaTek/Qualcomm combo card is an **internal USB device**.
If the USB tree is broken, Bluetooth is gone even though the Wi-Fi half (PCIe) still works.
- **USB-NOROOTHUB** A host controller is started but has no `USB\ROOT_HUB30` child. Classic cause: "USB Root Hub (USB 3.0)" uninstalled in Device Manager. F01 rescan recreates it; if it comes back with a problem, F02 restarts the controller; F17 reboot is the fallback that always works.
- **USB-HUBPROBLEM** Root hub exists but failed. `0xC0000206 STATUS_INVALID_BUFFER_SIZE` = the hub fails every runtime (re)start after someone clicked Update driver / Uninstall on it, while it starts fine at boot; a controller restart does not clear it, a reboot does (F17). If it also fails at boot, see USB-DRVMISMATCH.
- **USB-DRVMISMATCH** `ucx01000.sys` (USB class extension) is a newer build than the installed `usbhub3`/`usbxhci` package, and the matching package is in WinSxS. A cumulative update left the driver store behind. Informational while USB works; F21 imports the matching Microsoft package from the component store and installs it when hubs keep failing.
- **USB-NOCTRL / USB-CTRL-*** Controller missing or failed: chipset driver or BIOS.

## Radio
- **RADIO-NONE-USB** No radio because USB is broken. Fix USB first.
- **RADIO-NONE-GHOST** Windows remembers a radio (`LastArrival`/`LastRemoval` shown) but it is not enumerating now. Rescan (F01), clean ghosts (F05), reboot (F17), then hardware checklist (F18).
- **RADIO-NONE** Never seen a radio. BIOS setting, power drain, dead module, or the PC simply has none. F18 walks through it.
- **RADIO-DISABLED-*** Code 22. F03.
- **RADIO-NODRIVER-*** Code 28. If a matching package is in the store F07 installs it; otherwise F08 pulls it from Windows Update by hardware ID; F09 opens the vendor page.
- **RADIO-DRVLOAD-*** Code 31/37/39/48/52: driver file cannot load (corrupt, unsigned, blocked). F07 then F08; F16 if inbox files are damaged.
- **RADIO-SVCDISABLED-*** Code 32: the driver's service is Disabled. F06.
- **RADIO-FAILSTART-*** Code 10/43: radio firmware did not come up. F04 restart, F07 correct driver, F13 power management, F18 power drain.
- **RADIO-MULTI** Two radios (dongle + internal). Disable one; never uninstall.
- **RM-OFF / RM-DISABLED / RM-UNKNOWN / RM-NOBT** What the Radio Management service thinks. Off -> F10. NOBT (device exists but no radio listed) -> bthserv/RmSvc problem -> F06.

## Driver
- **DRV-GENERIC-*** The radio matched only on `USB\Class_E0&SubClass_01&Prot_01` (or runs `bth.inf` by provider Microsoft) and so uses the inbox "Generic Bluetooth Adapter" driver. Fine for CSR dongles; fatal for Intel/Realtek/MediaTek/Qualcomm/Broadcom, which need vendor firmware. F07 / F08 / **F22** (install the maker's download) / F09. Confirm with the discovery test afterwards.
- **DRV-WRONGVENDOR-*** A driver whose provider is a different chip vendor than the hardware. Only possible via "Let me pick from a list" with "Show compatible hardware" unticked. F07 removes the device, deletes the forced package if it does not list your hardware ID, rescans.
- **DRV-NEWER-*** Informational: a newer vendor package is in the store.
- **STORE-FILES / STORE-INFS** Inbox `bthport.sys`, `bthusb.sys`, `bth.inf`, `usbhub3.inf` ... missing. Only F16 (DISM/SFC) can restore those.
- **STORE-NOVENDOR-*** No vendor package for your radio in the store. F08 first, then F22 with the maker's download, F09 to find it.
- **FILTER-BT / FILTER-USB** Class-wide UpperFilters/LowerFilters. F12 clears the Bluetooth ones (reboot).

## Services
- **SVC-DISABLED** Anything in the baseline set to Start=4. F06 restores defaults.
- **SVC-DEVIATE** Manual<->Automatic drift. Usually harmless; F06 restores.
- **SVC-MISSING / SVC-IMAGE** Service key or driver file gone. F16.
- **SVC-TRIGGER** `bthserv` lost its device-interface-arrival trigger. F06 re-adds `start/device/0850302a-b344-4fda-9be9-90576b8d46f0`.
- **SVC-BTHSERV-STOPPED / SVC-DAS** Should be running when a radio is present. F06 starts them.

## Policy / software / power / history
- **POL-*** Bluetooth or device-install policies. F11 removes blocking values (backed up). Managed PCs will re-apply them.
- **STACK-*** Third-party Bluetooth stack detected. Uninstall via F20.
- **SOFT-WRONGVENDOR-*** Bluetooth software from another chip vendor is installed (Intel's package on a Realtek radio). It installs fine and drives nothing. Informational; F20 to remove it; step 3 names the vendor you need.
- **PWR-EPM-*** Intel radio with EnhancedPowerManagementEnabled=1 -> disappears after sleep. F13.
- **PWR-FASTSTARTUP** F19.
- **CHILD-PROBLEMS** Paired devices failing, radio fine. Re-pair, or F14 to reset all.
- **HIST-UNINSTALL** Devices uninstalled, or "Update driver" clicked, by hand in Device Manager (from setupapi.dev.log) with timestamps. Removing a paired device in Settings shows as "Device removed".
- **HIST-FAILED** Recent 411 events decoded.

## F22: install vendor driver from a downloaded package
`Install-BFDriverPackage -Path <zip|exe|cab|inf|folder> [-Device <radio record>] [-DryRun]`
1. Unpacks into `C:\ProgramData\BluetoothFixer\Packages\<stamp>\` (`%TEMP%` when not elevated): `.zip` via Expand-Archive, `.cab` via `expand.exe`, `.exe`/`.7z`/`.msi` via 7-Zip when installed (motherboard makers ship 7-Zip self-extractors). Nested containers are unpacked up to three levels until an INF for the radio shows up.
2. `Find-BFInfMatches` reads every INF, keeps the ones that list the radio's `VID_xxxx&PID_yyyy`, and ranks: Bluetooth class +100, x64 folder +30 (unspecified +20), valid catalog signature +10, Extension-class INFs -50, then newest `DriverVer`.
3. `pnputil /add-driver <inf> /install`. If the package is staged but Windows keeps the current driver (it outranks the new one), `UpdateDriverForPlugAndPlayDevices` with `INSTALLFLAG_FORCE` applies it.
4. Re-reads the device's `DriverInfPath` / provider; success = pnputil said "installed on device" or the INF/provider changed. The message shows before and after. A non-zero problem code or any pnputil "reboot" hint sets `RebootRequired`.
No INF for the radio: the message lists the INFs it did find (wrong package: Wi-Fi, audio, another vendor). No INF at all and the file is an `.exe`: run the installer yourself and re-check.

## Reading the timeline
`Kernel-PnP` 400 = driver configured, 410 = started, 411 = failed (problem + NTSTATUS decoded), 420 = deleted.
`setupapi.dev.log` lines starting "Uninstalled through Device Manager" are human actions.
