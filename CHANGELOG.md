# Changelog

## 1.1.0 - 2026-10-24
- New: **guided view**. The window now opens on a six-step walk-through (check, what we found, the right driver, test the radio, other fixes, wrap up) with the plan on the left and plain-English verdicts; the old console is one click away as **Advanced view**.
- New: **"first thing to try"** (`Get-BFDriverSituation`, `Diagnosis.FirstStep`): is the radio running the chip maker's driver or Windows' generic one? Generic Microsoft driver on an Intel/Realtek/MediaTek/Qualcomm/Broadcom radio ("working" in Device Manager, hears nothing) is now called out first, with the exact download page and three ways to fix it.
- New: **discovery test** (`Test-BFDiscovery`, step 4, CLI `-Scan`): a real Bluetooth classic + LE discovery through the Windows device-enumeration API, listing what the radio hears. The only proof the firmware loaded. Result goes into the report.
- New: **F22 install vendor driver from a downloaded package** (`Install-BFDriverPackage`, CLI `-DriverPackage`): unpacks `.zip`/`.exe`(7-Zip SFX)/`.cab`/folders (nested too), picks the INF that lists the radio's hardware ID (Bluetooth class, x64, signed, newest), `pnputil /add-driver /install`, forces the device over if needed, verifies the switch. `-DryRun` for testing.
- New: motherboard download pages for desktops built on retail boards (exact Gigabyte and MSI model pages; search fallback for others; ASRock added to the PC-maker table). The board model is shown in step 2.
- New: `SOFT-WRONGVENDOR-*` finding when Bluetooth software from a different chip vendor is installed (the Intel package on a Realtek PC).
- Fixed: Realtek and Intel USB devices that are not radios (USB NVMe bridges, card readers, webcams) no longer appear as "radio candidates" or pollute the driver links. A vendor ID alone is not a radio.
- Fixed: generic-driver detection also triggers on `bth.inf` by provider, not only on the matching-ID shape.
- Knowledge base: Realtek RTL8922AE Bluetooth PID 8922; `RtkBtFilter2` / `RtkBtManServ` vendor services; Realtek notes updated.
- Report: "First thing to try" card and the discovery-test table; JSON carries `FirstStep` and `Scan`.


## 1.0.1 - 2026-09-01
- Fixed: GUI crashed after applying fixes (a local `$w` shadowed the `$W` window; PowerShell variable names are case-insensitive). All message boxes now go through an owner-less helper.
- New: detects a USB hub/xHCI driver older than the UCX class extension (cumulative update left the driver store behind) and locates the matching package in WinSxS; new fix F21 re-stages it, recommended only when the hub also fails at boot.
- New: STATUS_INVALID_BUFFER_SIZE hub failures now route straight to "reboot first" instead of a pointless controller restart.
- New: timeline shows "Update driver clicked in Device Manager" and "Device removed in Settings" actions.

## 1.0.0 - 2026-09-01
First release.
- Diagnosis engine: radio discovery (present, driverless, ghost), USB stack health (controllers, root hubs, Enum\USB), driver correctness (generic vs vendor, forced wrong vendor, store matches by hardware ID), service baseline (31 services/drivers), Radio Management state, policies, class filters, third-party stacks, power settings, timeline from Kernel-PnP log and setupapi.dev.log.
- 20 fixes with backup, logging and post-fix re-diagnosis; Windows Update driver fetch by hardware ID; reboot-and-verify.
- WPF GUI, CLI with JSON output, HTML + JSON report.
- Elevating launcher exe built with the in-box C# compiler.
- Knowledge base: USB vendor IDs, Intel and Realtek PIDs, OEM support URL patterns, problem codes, NTSTATUS decoder.
