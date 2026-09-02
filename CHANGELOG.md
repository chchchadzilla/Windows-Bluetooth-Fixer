# Changelog

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
