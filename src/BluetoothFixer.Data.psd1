@{
    # ------------------------------------------------------------------
    # Windows Bluetooth Fixer - Knowledge Base
    # Everything the engine "knows" about Bluetooth hardware on Windows.
    # PID/chip names marked BestEffort come from public device databases
    # and Linux btusb tables; VIDs are authoritative (USB-IF assigned).
    # ------------------------------------------------------------------

    Version = '1.1.0'

    ClassGuids = @{
        Bluetooth = '{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}'
        USB       = '{36fc9e60-c465-11cf-8056-444553540000}'
        HIDClass  = '{745a17a0-74d3-11d0-b6fe-00a0c90f57da}'
        Net       = '{4d36e972-e325-11ce-bfc1-08002be10318}'
        Media     = '{4d36e96c-e325-11ce-bfc1-08002be10318}'
    }

    # USB Vendor IDs that ship Bluetooth radios / combo modules.
    # NeedsVendorDriver = the inbox Microsoft "Generic Bluetooth Radio" driver is NOT enough
    # (the radio needs vendor firmware patching at load time).
    UsbVendors = @{
        '8087' = @{ Name = 'Intel';                       Chip = 'Intel';     NeedsVendorDriver = $true;  Download = 'Intel' }
        '8086' = @{ Name = 'Intel';                       Chip = 'Intel';     NeedsVendorDriver = $true;  Download = 'Intel' }
        '0BDA' = @{ Name = 'Realtek';                     Chip = 'Realtek';   NeedsVendorDriver = $true;  Download = 'OEM' }
        '0A12' = @{ Name = 'Cambridge Silicon Radio (CSR / Qualcomm)'; Chip = 'CSR'; NeedsVendorDriver = $false; Download = 'Inbox' }
        '0CF3' = @{ Name = 'Qualcomm Atheros';            Chip = 'Qualcomm';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '0489' = @{ Name = 'Foxconn / Hon Hai (module maker; chip usually Qualcomm, Broadcom or MediaTek)'; Chip = 'Module'; NeedsVendorDriver = $true; Download = 'OEM' }
        '13D3' = @{ Name = 'IMC Networks / AzureWave (module maker; chip usually Intel, Realtek or MediaTek)'; Chip = 'Module'; NeedsVendorDriver = $true; Download = 'OEM' }
        '04CA' = @{ Name = 'Lite-On (module maker; chip usually Qualcomm or Realtek)'; Chip = 'Module'; NeedsVendorDriver = $true; Download = 'OEM' }
        '0A5C' = @{ Name = 'Broadcom';                    Chip = 'Broadcom';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '0E8D' = @{ Name = 'MediaTek';                    Chip = 'MediaTek';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '3574' = @{ Name = 'MediaTek Inc.';               Chip = 'MediaTek';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '0B05' = @{ Name = 'ASUSTek (dongle/module; chip varies)'; Chip = 'Module'; NeedsVendorDriver = $true; Download = 'OEM' }
        '2357' = @{ Name = 'TP-Link (dongle; chip usually Realtek or CSR)'; Chip = 'Module'; NeedsVendorDriver = $true; Download = 'OEM' }
        '413C' = @{ Name = 'Dell (rebranded module)';     Chip = 'Module';    NeedsVendorDriver = $true;  Download = 'OEM' }
        '0930' = @{ Name = 'Toshiba';                     Chip = 'Module';    NeedsVendorDriver = $true;  Download = 'OEM' }
        '044E' = @{ Name = 'Alps Electric (module maker)'; Chip = 'Module';   NeedsVendorDriver = $true;  Download = 'OEM' }
        '05AC' = @{ Name = 'Apple (Broadcom chip)';       Chip = 'Broadcom';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '0DB0' = @{ Name = 'Micro-Star International (MSI)'; Chip = 'Module'; NeedsVendorDriver = $true;  Download = 'OEM' }
        '1286' = @{ Name = 'Marvell';                     Chip = 'Marvell';   NeedsVendorDriver = $true;  Download = 'OEM' }
        '03F0' = @{ Name = 'HP (rebranded module)';       Chip = 'Module';    NeedsVendorDriver = $true;  Download = 'OEM' }
        '17EF' = @{ Name = 'Lenovo (rebranded module)';   Chip = 'Module';    NeedsVendorDriver = $true;  Download = 'OEM' }
        '1131' = @{ Name = 'Integrated System Solution (ISSC)'; Chip = 'ISSC'; NeedsVendorDriver = $false; Download = 'Inbox' }
        '0C10' = @{ Name = 'Broadcom';                    Chip = 'Broadcom';  NeedsVendorDriver = $true;  Download = 'OEM' }
        '1310' = @{ Name = 'Roper / CSR-based dongle';    Chip = 'CSR';       NeedsVendorDriver = $false; Download = 'Inbox' }
        '0400' = @{ Name = 'National Semiconductor / dongle'; Chip = 'Other'; NeedsVendorDriver = $false; Download = 'Inbox' }
        '07B8' = @{ Name = 'AboCom (dongle)';             Chip = 'Other';     NeedsVendorDriver = $false; Download = 'Inbox' }
        '1D5C' = @{ Name = 'Fresco Logic';                Chip = 'Other';     NeedsVendorDriver = $true;  Download = 'OEM' }
    }

    # Intel Bluetooth PIDs (VID 8087). BestEffort names.
    IntelPids = @{
        '0025' = 'Wireless-AC 9560 / 9462 / 9461 (CNVi)'
        '0026' = 'Wi-Fi 6 AX201 (CNVi)'
        '0029' = 'Wi-Fi 6 AX200'
        '0032' = 'Wi-Fi 6E AX210'
        '0033' = 'Wi-Fi 6E AX211 (CNVi)'
        '0035' = 'Wi-Fi 6E AX211 / AX411 (CNVi)'
        '0036' = 'Wi-Fi 7 BE200'
        '0037' = 'Wi-Fi 7 BE201 / BE202 (CNVi)'
        '0038' = 'Wi-Fi 7 BE211 (CNVi)'
        '0039' = 'Wi-Fi 7 (newer CNVi)'
        '0040' = 'Wi-Fi 7 (newer)'
        '0A2A' = 'Wireless-AC 8260'
        '0A2B' = 'Wireless-AC 8265'
        '0AA7' = 'Wireless-AC 3168'
        '0AAA' = 'Wireless-AC 9260'
        '07DC' = 'Wireless 7260'
        '07DA' = 'Centrino Wireless-N 6235 / 7260'
        '0A0A' = 'Wireless-AC 7265 / 3165'
        '0A0B' = 'Wireless-AC 7265 / 3165'
    }

    # Realtek Bluetooth PIDs (VID 0BDA). BestEffort names from Linux btusb / rtk_btusb tables.
    RealtekPids = @{
        '8771' = 'RTL8761B / RTL8761BU (USB dongle)'
        'B00C' = 'RTL8822CE'
        'C822' = 'RTL8822CE'
        'C82F' = 'RTL8822CE'
        'B00B' = 'RTL8822BE'
        'C821' = 'RTL8821CE'
        'B821' = 'RTL8821CE'
        'C123' = 'RTL8723DE'
        'B023' = 'RTL8723DE'
        'D723' = 'RTL8723DU'
        '4852' = 'RTL8852AE'
        '885A' = 'RTL8852AE'
        '887B' = 'RTL8852BE'
        'B85B' = 'RTL8852BE'
        'B85C' = 'RTL8852BE'
        '0852' = 'RTL8852CE'
        'C852' = 'RTL8852CE'
        '8851' = 'RTL8851BE'
        'B851' = 'RTL8851BE'
        '8922' = 'RTL8922AE (Wi-Fi 7)'
        '4922' = 'RTL8922AE'
    }

    # Where to get drivers, keyed by chip vendor.
    ChipVendorDownloads = @{
        Intel    = @{
            Label = 'Intel Wireless Bluetooth driver (official, works for every Intel radio: 7260 through BE200)'
            Url   = 'https://www.intel.com/content/www/us/en/download/18649/intel-wireless-bluetooth-drivers-for-windows-10-and-windows-11.html'
            Extra = @{
                Label = 'Intel Driver & Support Assistant (auto-detects your Intel hardware)'
                Url   = 'https://www.intel.com/content/www/us/en/support/detect.html'
            }
            Note  = 'Intel radios need the Intel driver (ibtusb.inf). With only the generic Microsoft driver they usually show up but never work.'
        }
        Realtek  = @{
            Label = 'Realtek does not publish Bluetooth drivers to the public. Your PC or motherboard maker ships it (Gigabyte, MSI and ASUS list it under WLAN+BT / Bluetooth), or use the Windows Update Catalog link.'
            Url   = 'https://www.realtek.com/Download'
            Note  = 'Realtek radios need Realtek firmware via the vendor filter driver (rtkbtfilter.inf; shows as "Realtek Bluetooth LEAI Driver" or "Realtek Bluetooth 4.x/5.x Adapter" once installed). Generic driver = radio present but deaf.'
        }
        Qualcomm = @{
            Label = 'Qualcomm / Atheros supplies drivers only to PC makers. Use your PC maker page or the Windows Update Catalog link.'
            Url   = ''
            Note  = 'Qualcomm radios (QCA61x4, QCNFA765, FastConnect 6900/7800) require the OEM driver package.'
        }
        MediaTek = @{
            Label = 'MediaTek supplies drivers only to PC makers. Use your PC maker page or the Windows Update Catalog link.'
            Url   = ''
            Note  = 'MediaTek MT7921/MT7922/MT7925 radios require the OEM driver package (MTKBTFilter).'
        }
        Broadcom = @{
            Label = 'Broadcom supplies drivers only to PC makers. Use your PC maker page or the Windows Update Catalog link.'
            Url   = ''
            Note  = 'Broadcom radios need bcbtums.sys with matching firmware from the OEM package.'
        }
        CSR      = @{
            Label = 'CSR radios use the Windows inbox driver. No download needed. If broken, reinstall the inbox driver.'
            Url   = ''
            Note  = ''
        }
        Module   = @{
            Label = 'This USB ID belongs to a module maker; the chip inside is identified from the Wi-Fi adapter or bus description.'
            Url   = ''
            Note  = ''
        }
    }

    WindowsUpdateCatalogSearch = 'https://www.catalog.update.microsoft.com/Search.aspx?q={0}'

    # PC maker support pages. {serial} and {model} are substituted when known.
    # BoardUrl: the board maker's page for one motherboard model (desktops built on a retail board). {model} = board
    # product name with spaces turned into hyphens, e.g. "B850 EAGLE WIFI7 ICE" -> B850-EAGLE-WIFI7-ICE.
    OemSupport = @(
        @{ Match = 'Dell|Alienware';          Name = 'Dell';       Url = 'https://www.dell.com/support/home/en-us/product-support/servicetag/{serial}/drivers'; Fallback = 'https://www.dell.com/support/home/en-us?app=drivers'; Tool = 'Dell SupportAssist / Dell Command Update' }
        @{ Match = 'HP|Hewlett';              Name = 'HP';         Url = 'https://support.hp.com/us-en/drivers';                                                Fallback = 'https://support.hp.com/us-en/drivers';               Tool = 'HP Support Assistant' }
        @{ Match = 'LENOVO';                  Name = 'Lenovo';     Url = 'https://pcsupport.lenovo.com/us/en/';                                                 Fallback = 'https://pcsupport.lenovo.com/us/en/';                Tool = 'Lenovo Vantage / System Update' }
        @{ Match = 'ASUS';                    Name = 'ASUS';       Url = 'https://www.asus.com/support/download-center/';                                       Fallback = 'https://www.asus.com/support/';                      Tool = 'MyASUS' }
        @{ Match = 'Acer';                    Name = 'Acer';       Url = 'https://www.acer.com/us-en/support/drivers-and-manuals';                              Fallback = 'https://www.acer.com/us-en/support';                 Tool = 'Acer Care Center' }
        @{ Match = 'Micro-Star|MSI';          Name = 'MSI';        Url = 'https://www.msi.com/support/download';                                                Fallback = 'https://www.msi.com/support';                        Tool = 'MSI Center'; BoardUrl = 'https://www.msi.com/Motherboard/{model}/support' }
        @{ Match = 'ASRock';                  Name = 'ASRock';     Url = 'https://www.asrock.com/support/index.asp';                                           Fallback = 'https://www.asrock.com/support/index.asp';           Tool = 'ASRock Live Update & APP Shop' }
        @{ Match = 'Microsoft';               Name = 'Microsoft Surface'; Url = 'https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120'; Fallback = 'https://support.microsoft.com/surface'; Tool = 'Windows Update (Surface drivers ship there)' }
        @{ Match = 'Samsung';                 Name = 'Samsung';    Url = 'https://www.samsung.com/us/support/downloads/';                                       Fallback = 'https://www.samsung.com/us/support/';                Tool = 'Samsung Update' }
        @{ Match = 'Razer';                   Name = 'Razer';      Url = 'https://mysupport.razer.com/';                                                        Fallback = 'https://mysupport.razer.com/';                       Tool = 'Razer Synapse' }
        @{ Match = 'Gigabyte|AORUS';          Name = 'Gigabyte';   Url = 'https://www.gigabyte.com/Support';                                                    Fallback = 'https://www.gigabyte.com/Support';                   Tool = 'Gigabyte Control Center'; BoardUrl = 'https://www.gigabyte.com/Motherboard/{model}/support#support-dl-driver-bluetooth' }
        @{ Match = 'TOSHIBA|Dynabook';        Name = 'Dynabook (Toshiba)'; Url = 'https://support.dynabook.com/drivers';                                        Fallback = 'https://support.dynabook.com/';                      Tool = 'Dynabook Service Station' }
        @{ Match = 'LG';                      Name = 'LG';         Url = 'https://www.lg.com/us/support/software-firmware';                                     Fallback = 'https://www.lg.com/us/support';                      Tool = 'LG Update Center' }
        @{ Match = 'HUAWEI';                  Name = 'Huawei';     Url = 'https://consumer.huawei.com/en/support/laptops/';                                     Fallback = 'https://consumer.huawei.com/en/support/';            Tool = 'Huawei PC Manager' }
        @{ Match = 'Framework';               Name = 'Framework';  Url = 'https://knowledgebase.frame.work/en_us/bios-and-drivers-downloads-rJ3PaCexh';         Fallback = 'https://knowledgebase.frame.work/';                  Tool = 'Framework driver bundle' }
        @{ Match = 'Panasonic';               Name = 'Panasonic';  Url = 'https://pc-dl.panasonic.co.jp/dl/';                                                   Fallback = 'https://pc-dl.panasonic.co.jp/dl/';                  Tool = 'Panasonic PC Settings Utility' }
        @{ Match = 'Fujitsu';                 Name = 'Fujitsu';    Url = 'https://support.ts.fujitsu.com/';                                                     Fallback = 'https://support.ts.fujitsu.com/';                    Tool = 'Fujitsu DeskUpdate' }
        @{ Match = 'Google';                  Name = 'Google';     Url = 'https://support.google.com/pixelbook/';                                               Fallback = 'https://support.google.com/';                        Tool = '' }
    )

    # Windows 11 (and 10) default service start values on a clean install.
    # 2 = Automatic, 3 = Manual (many are trigger-started), 4 = Disabled.
    # Verified against a fresh Windows 11 25H2 install (build 26200).
    ServiceBaseline = @(
        @{ Name = 'bthserv';                          Display = 'Bluetooth Support Service';                  Start = 3; Kind = 'Service'; Critical = $true;  Note = 'Trigger-started when a radio appears. Must not be Disabled.' }
        @{ Name = 'BTAGService';                      Display = 'Bluetooth Audio Gateway Service';            Start = 3; Kind = 'Service'; Critical = $false; Note = 'Needed for headset (HFP) audio.' }
        @{ Name = 'BthAvctpSvc';                      Display = 'AVCTP service';                              Start = 3; Kind = 'Service'; Critical = $false; Note = 'Needed for A2DP/AVRCP audio remote control.' }
        @{ Name = 'BluetoothUserService';             Display = 'Bluetooth User Support Service (template)';  Start = 3; Kind = 'UserServiceTemplate'; Critical = $true; Note = 'Per-user instance is BluetoothUserService_xxxxx. Powers Settings > Bluetooth UI and pairing.' }
        @{ Name = 'DeviceAssociationService';         Display = 'Device Association Service';                 Start = 2; Kind = 'Service'; Critical = $true;  Note = 'Pairing. Must be Automatic and running.' }
        @{ Name = 'DevicesFlowUserSvc';               Display = 'DevicesFlow (template)';                     Start = 3; Kind = 'UserServiceTemplate'; Critical = $false; Note = 'Connect / Add-device UI flows.' }
        @{ Name = 'DevQueryBroker';                   Display = 'DevQuery Background Discovery Broker';       Start = 3; Kind = 'Service'; Critical = $false; Note = 'Device discovery for apps.' }
        @{ Name = 'DsmSvc';                           Display = 'Device Setup Manager';                       Start = 3; Kind = 'Service'; Critical = $true;  Note = 'Installs drivers/metadata for new devices. Disabled = "driver not found" forever.' }
        @{ Name = 'DeviceInstall';                    Display = 'Device Install Service';                     Start = 3; Kind = 'Service'; Critical = $true;  Note = 'Installs drivers for new devices.' }
        @{ Name = 'PlugPlay';                         Display = 'Plug and Play';                              Start = 3; Kind = 'Service'; Critical = $true;  Note = 'Core PnP. Never disable.' }
        @{ Name = 'hidserv';                          Display = 'Human Interface Device Service';             Start = 3; Kind = 'Service'; Critical = $false; Note = 'Bluetooth keyboards/mice hot buttons.' }
        @{ Name = 'RmSvc';                            Display = 'Radio Management Service';                   Start = 3; Kind = 'Service'; Critical = $true;  Note = 'Airplane mode + radio on/off toggles. Disabled = Bluetooth toggle vanishes.' }
        @{ Name = 'SystemEventsBroker';               Display = 'System Events Broker';                       Start = 2; Kind = 'Service'; Critical = $true;  Note = 'Fires the triggers that start bthserv.' }
        @{ Name = 'Audiosrv';                         Display = 'Windows Audio';                              Start = 2; Kind = 'Service'; Critical = $false; Note = 'Bluetooth audio.' }
        @{ Name = 'AudioEndpointBuilder';             Display = 'Windows Audio Endpoint Builder';             Start = 2; Kind = 'Service'; Critical = $false; Note = 'Bluetooth audio endpoints.' }
        @{ Name = 'BTHUSB';                           Display = 'Bluetooth USB miniport driver';              Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Kernel driver for USB radios (generic path).' }
        @{ Name = 'BthPort';                          Display = 'Bluetooth port driver';                      Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'The Bluetooth stack core (bthport.sys).' }
        @{ Name = 'BthEnum';                          Display = 'Bluetooth enumerator';                       Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Enumerates paired devices (BTHENUM).' }
        @{ Name = 'BthMini';                          Display = 'Bluetooth radio miniport';                   Start = 3; Kind = 'Driver';  Critical = $true;  Note = '' }
        @{ Name = 'BthA2dp';                          Display = 'Bluetooth A2DP audio driver';                Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Stereo audio.' }
        @{ Name = 'BthHFEnum';                        Display = 'Bluetooth hands-free enumerator';            Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Headset audio.' }
        @{ Name = 'BthLEEnum';                        Display = 'Bluetooth LE enumerator';                    Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Bluetooth Low Energy devices.' }
        @{ Name = 'HidBth';                           Display = 'Bluetooth HID driver';                       Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Bluetooth keyboards / mice / controllers.' }
        @{ Name = 'BTHMODEM';                         Display = 'Bluetooth modem driver';                     Start = 3; Kind = 'Driver';  Critical = $false; Note = '' }
        @{ Name = 'RFCOMM';                           Display = 'Bluetooth RFCOMM driver';                    Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Serial-over-Bluetooth, used by many profiles.' }
        @{ Name = 'Microsoft_Bluetooth_AvrcpTransport'; Display = 'Bluetooth AVRCP transport';               Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Media buttons on headsets.' }
        @{ Name = 'usbhub3';                          Display = 'USB 3 hub driver';                           Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Root hubs. If disabled, no USB device (including internal Bluetooth) can exist.' }
        @{ Name = 'USBXHCI';                          Display = 'USB xHCI controller driver';                 Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'USB 3 host controller.' }
        @{ Name = 'UCX01000';                         Display = 'USB controller class extension';             Start = 3; Kind = 'Driver';  Critical = $true;  Note = '' }
        @{ Name = 'usbccgp';                          Display = 'USB composite device driver';                Start = 3; Kind = 'Driver';  Critical = $true;  Note = 'Many BT dongles are composite devices.' }
        @{ Name = 'USBHUB';                           Display = 'USB 2 hub driver';                           Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Older EHCI controllers.' }
        @{ Name = 'WUDFRd';                           Display = 'User-mode driver framework reflector';       Start = 3; Kind = 'Driver';  Critical = $false; Note = 'Some vendor BT filter drivers are UMDF.' }
    )

    # Vendor Bluetooth driver services (kernel). Presence tells us which stack is installed.
    VendorDriverServices = @(
        @{ Name = 'ibtusb';       Vendor = 'Intel';    Note = 'Intel Wireless Bluetooth (ibtusb.sys)' }
        @{ Name = 'RtkBtfilter';  Vendor = 'Realtek';  Note = 'Realtek Bluetooth filter (RtkBtfilter.sys)' }
        @{ Name = 'RtkBtFilter2'; Vendor = 'Realtek';  Note = 'Realtek Bluetooth filter, 2024+ packages (RtkBtFilter2.sys; RTL8852/8922)' }
        @{ Name = 'RtkBtManServ'; Vendor = 'Realtek';  Note = 'Realtek Bluetooth Device Manager Service (ships with the filter driver)' }
        @{ Name = 'rtbth';        Vendor = 'Realtek';  Note = 'Realtek Bluetooth (rtbth.sys)' }
        @{ Name = 'BCM43XX';      Vendor = 'Broadcom'; Note = 'Broadcom Bluetooth' }
        @{ Name = 'bcbtums';      Vendor = 'Broadcom'; Note = 'Broadcom Bluetooth USB (bcbtums.sys)' }
        @{ Name = 'QcBtFilter';   Vendor = 'Qualcomm'; Note = 'Qualcomm Bluetooth filter' }
        @{ Name = 'qcbtuart';     Vendor = 'Qualcomm'; Note = 'Qualcomm Bluetooth UART' }
        @{ Name = 'athbtfilt';    Vendor = 'Qualcomm'; Note = 'Atheros Bluetooth filter' }
        @{ Name = 'MTKBTFilter';  Vendor = 'MediaTek'; Note = 'MediaTek Bluetooth filter' }
        @{ Name = 'mtkbtfilterx'; Vendor = 'MediaTek'; Note = 'MediaTek Bluetooth filter' }
    )

    # Third-party Bluetooth stacks that fight with the Microsoft stack.
    ThirdPartyStacks = @(
        @{ Match = 'Toshiba Bluetooth Stack';   Name = 'Toshiba Bluetooth Stack' }
        @{ Match = 'BlueSoleil';                Name = 'IVT BlueSoleil' }
        @{ Match = 'WIDCOMM';                   Name = 'WIDCOMM / Broadcom legacy stack' }
        @{ Match = 'Broadcom Bluetooth Software'; Name = 'Broadcom legacy stack' }
        @{ Match = 'Motorola Bluetooth';        Name = 'Motorola legacy stack' }
        @{ Match = 'CSR Harmony';               Name = 'CSR Harmony stack' }
        @{ Match = 'Bluetooth Driver Installer'; Name = 'Bluetooth Driver Installer (patches bth.inf; known to break the stack)' }
    )

    # Device Manager problem codes (CM_PROB_*). Plain English + what it usually means for Bluetooth.
    ProblemCodes = @{
        0  = @{ Name = 'OK';                        Text = 'Working.'; }
        1  = @{ Name = 'NOT_CONFIGURED';            Text = 'Device is not configured correctly (Code 1). Driver install never completed.' }
        3  = @{ Name = 'OUT_OF_MEMORY';             Text = 'Driver may be corrupted or system low on memory (Code 3).' }
        9  = @{ Name = 'INVALID_DATA';              Text = 'Windows cannot identify this hardware; firmware returned bad IDs (Code 9).' }
        10 = @{ Name = 'FAILED_START';              Text = 'Device cannot start (Code 10). Driver loaded but the radio failed to initialise: usually wrong/old driver, firmware load failure, or power state issue.' }
        12 = @{ Name = 'NORMAL_CONFLICT';           Text = 'Resource conflict (Code 12).' }
        14 = @{ Name = 'NEED_RESTART';              Text = 'Restart required to finish the driver change (Code 14).' }
        16 = @{ Name = 'PARTIAL_LOG_CONF';          Text = 'Windows cannot identify all resources (Code 16).' }
        18 = @{ Name = 'REINSTALL';                 Text = 'Reinstall the drivers for this device (Code 18).' }
        19 = @{ Name = 'REGISTRY';                  Text = 'Registry configuration for this device is corrupt or incomplete (Code 19).' }
        21 = @{ Name = 'WILL_BE_REMOVED';           Text = 'Windows is removing this device (Code 21).' }
        22 = @{ Name = 'DISABLED';                  Text = 'Device is disabled in Device Manager (Code 22).' }
        24 = @{ Name = 'DEVICE_NOT_THERE';          Text = 'Device is not present, not working properly, or has no drivers (Code 24).' }
        28 = @{ Name = 'FAILED_INSTALL';            Text = 'No driver is installed for this device (Code 28). Windows did not find a matching INF.' }
        29 = @{ Name = 'HARDWARE_DISABLED';         Text = 'Device disabled by firmware/BIOS (Code 29).' }
        31 = @{ Name = 'FAILED_ADD';                Text = 'Windows cannot load the drivers required (Code 31). The driver refused to attach to the device.' }
        32 = @{ Name = 'DISABLED_SERVICE';          Text = 'The driver service is disabled (Code 32). A service Start value was set to 4.' }
        33 = @{ Name = 'TRANSLATION_FAILED';        Text = 'Windows cannot determine resources (Code 33).' }
        34 = @{ Name = 'NO_SOFTCONFIG';             Text = 'Windows cannot determine settings (Code 34).' }
        35 = @{ Name = 'BIOS_TABLE';                Text = 'Firmware does not include enough info (Code 35).' }
        36 = @{ Name = 'IRQ_TRANSLATION_FAILED';    Text = 'IRQ translation failed (Code 36).' }
        37 = @{ Name = 'FAILED_DRIVER_ENTRY';       Text = 'Driver initialisation failed (Code 37). Driver file is corrupt or mismatched with this Windows build.' }
        38 = @{ Name = 'DRIVER_FAILED_PRIOR_UNLOAD'; Text = 'A previous instance of the driver is still in memory (Code 38). Reboot.' }
        39 = @{ Name = 'DRIVER_FAILED_LOAD';        Text = 'Driver file is corrupt or missing (Code 39).' }
        40 = @{ Name = 'DRIVER_SERVICE_KEY_INVALID'; Text = 'Service key information in the registry is invalid (Code 40).' }
        41 = @{ Name = 'LEGACY_SERVICE_NO_DEVICES'; Text = 'Driver loaded but hardware not found (Code 41).' }
        42 = @{ Name = 'DUPLICATE_DEVICE';          Text = 'Duplicate device (Code 42).' }
        43 = @{ Name = 'FAILED_POST_START';         Text = 'Windows stopped this device because it reported problems (Code 43). Typical for a radio whose firmware crashed or a failing USB link.' }
        44 = @{ Name = 'HALTED';                    Text = 'An application or service shut this device down (Code 44).' }
        45 = @{ Name = 'PHANTOM';                   Text = 'Device is not connected right now (Code 45). A ghost entry from an earlier session.' }
        46 = @{ Name = 'SYSTEM_SHUTDOWN';           Text = 'System is shutting down (Code 46).' }
        47 = @{ Name = 'HELD_FOR_EJECT';            Text = 'Prepared for safe removal (Code 47).' }
        48 = @{ Name = 'DRIVER_BLOCKED';            Text = 'Driver is blocked from loading because it is known to cause problems (Code 48).' }
        49 = @{ Name = 'REGISTRY_TOO_LARGE';        Text = 'System hive too large (Code 49).' }
        50 = @{ Name = 'SETPROPERTIES_FAILED';      Text = 'Windows cannot apply device properties (Code 50).' }
        51 = @{ Name = 'WAITING_ON_DEPENDENCY';     Text = 'Waiting on another device (Code 51). For Bluetooth this is usually the USB hub/controller not being ready.' }
        52 = @{ Name = 'UNSIGNED_DRIVER';           Text = 'Driver signature could not be verified (Code 52). Unsigned or tampered driver.' }
        53 = @{ Name = 'USED_BY_DEBUGGER';          Text = 'Reserved by the kernel debugger (Code 53).' }
        54 = @{ Name = 'DEVICE_RESET';              Text = 'Device failed and is being reset (Code 54).' }
        55 = @{ Name = 'CONSOLE_LOCKED';            Text = 'Console locked (Code 55).' }
        56 = @{ Name = 'NEED_CLASS_CONFIG';         Text = 'Waiting for class configuration (Code 56).' }
    }

    NtStatus = @{
        '0xC0000206' = 'STATUS_INVALID_BUFFER_SIZE - the driver and the layer below it disagreed on data size. Seen when a USB root hub is re-created while the host controller keeps stale state; a controller restart or reboot clears it.'
        '0xC0000365' = 'STATUS_FAILED_DRIVER_ENTRY - the driver''s entry point failed. Corrupt or mismatched driver file.'
        '0xC0000034' = 'STATUS_OBJECT_NAME_NOT_FOUND - a file or registry object the driver needs is missing.'
        '0xC000000D' = 'STATUS_INVALID_PARAMETER'
        '0xC0000001' = 'STATUS_UNSUCCESSFUL - generic failure.'
        '0xC00000BB' = 'STATUS_NOT_SUPPORTED - firmware/driver mismatch or unsupported hardware revision.'
        '0xC0000022' = 'STATUS_ACCESS_DENIED'
        '0xC0000428' = 'STATUS_INVALID_IMAGE_HASH - driver signature invalid. Driver file tampered or unsigned.'
        '0xC000009A' = 'STATUS_INSUFFICIENT_RESOURCES'
        '0xC0000010' = 'STATUS_INVALID_DEVICE_REQUEST'
        '0xC00000E5' = 'STATUS_INTERNAL_ERROR'
        '0xC000000E' = 'STATUS_NO_SUCH_DEVICE - hardware vanished mid-start. Loose module, power issue, or dying radio.'
        '0xC0000185' = 'STATUS_IO_DEVICE_ERROR - the radio returned garbage. Firmware crash or hardware fault.'
        '0xC0000225' = 'STATUS_NOT_FOUND'
        '0xC0000263' = 'STATUS_DRIVER_ENTRYPOINT_NOT_FOUND - wrong driver file for this Windows version.'
        '0xC0000098' = 'STATUS_FILE_INVALID - corrupt driver file.'
        '0xC000007B' = 'STATUS_INVALID_IMAGE_FORMAT - driver file is the wrong architecture or corrupt.'
        '0xC00002D3' = 'STATUS_POWER_STATE_INVALID'
        '0xC0000120' = 'STATUS_CANCELLED'
    }

    # Devices the tool must never remove or disable, no matter what.
    # (Uninstalling a USB root hub is exactly how Bluetooth gets killed on laptops.)
    ProtectedDevicePatterns = @(
        '^USB\\ROOT_HUB',
        '^PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}.*',   # any PCI device (controllers). Restart is allowed, remove is not.
        '^ACPI\\',
        '^USB4\\',
        '^ROOT\\',
        '^HTREE\\',
        '^PCI\\CC_0C03'
    )

    # Registry keys that get backed up before any fix touches them.
    BackupKeys = @(
        'HKLM\SYSTEM\CurrentControlSet\Services\bthserv',
        'HKLM\SYSTEM\CurrentControlSet\Services\BTAGService',
        'HKLM\SYSTEM\CurrentControlSet\Services\BthAvctpSvc',
        'HKLM\SYSTEM\CurrentControlSet\Services\BluetoothUserService',
        'HKLM\SYSTEM\CurrentControlSet\Services\DeviceAssociationService',
        'HKLM\SYSTEM\CurrentControlSet\Services\RmSvc',
        'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT',
        'HKLM\SYSTEM\CurrentControlSet\Services\BTHUSB',
        'HKLM\SYSTEM\CurrentControlSet\Control\Class\{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}',
        'HKLM\SYSTEM\CurrentControlSet\Control\Class\{36fc9e60-c465-11cf-8056-444553540000}',
        'HKLM\SYSTEM\CurrentControlSet\Control\RadioManagement',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\Bluetooth',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall',
        'HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Bluetooth',
        'HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Connectivity'
    )

    BluetoothPolicyKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Bluetooth';   Values = @('AllowDiscoverableMode','AllowAdvertising','AllowPrepairing','AllowPromptedProximalConnections','ServicesAllowedList') }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Connectivity'; Values = @('AllowBluetooth') }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Bluetooth';               Values = @('AllowDiscoverableMode','AllowAdvertising','AllowPrepairing','ServicesAllowedList') }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'; Values = @('DenyUnspecified','DenyDeviceIDs','DenyDeviceClasses','DenyRemovableDevices','AllowDeviceIDs','AllowDeviceClasses') }
    )
}
