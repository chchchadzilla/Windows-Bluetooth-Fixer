# Field guide: what each finding means and what the fix does

Finding IDs appear in the report and the JSON. Fix IDs are in the README table.

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
- **DRV-GENERIC-*** The radio matched only on `USB\Class_E0&SubClass_01&Prot_01` and runs the inbox "Generic Bluetooth Radio" driver. Fine for CSR dongles; fatal for Intel/Realtek/MediaTek/Qualcomm/Broadcom, which need vendor firmware. F07/F08.
- **DRV-WRONGVENDOR-*** A driver whose provider is a different chip vendor than the hardware. Only possible via "Let me pick from a list" with "Show compatible hardware" unticked. F07 removes the device, deletes the forced package if it does not list your hardware ID, rescans.
- **DRV-NEWER-*** Informational: a newer vendor package is in the store.
- **STORE-FILES / STORE-INFS** Inbox `bthport.sys`, `bthusb.sys`, `bth.inf`, `usbhub3.inf` ... missing. Only F16 (DISM/SFC) can restore those.
- **STORE-NOVENDOR-*** No vendor package for your radio in the store. F08 first, then F09.
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
- **PWR-EPM-*** Intel radio with EnhancedPowerManagementEnabled=1 -> disappears after sleep. F13.
- **PWR-FASTSTARTUP** F19.
- **CHILD-PROBLEMS** Paired devices failing, radio fine. Re-pair, or F14 to reset all.
- **HIST-UNINSTALL** Devices uninstalled, or "Update driver" clicked, by hand in Device Manager (from setupapi.dev.log) with timestamps. Removing a paired device in Settings shows as "Device removed".
- **HIST-FAILED** Recent 411 events decoded.

## Reading the timeline
`Kernel-PnP` 400 = driver configured, 410 = started, 411 = failed (problem + NTSTATUS decoded), 420 = deleted.
`setupapi.dev.log` lines starting "Uninstalled through Device Manager" are human actions.
