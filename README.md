# KSU GPS Ghost — Mock GPS & Geolocation Suite

[![KernelSU Compatible](https://img.shields.io/badge/KernelSU--Next-Supported-brightgreen.svg)](https://github.com/rifsxd/KernelSU-Next)
[![Android Version](https://img.shields.io/badge/Android-10%20→%2015-blue.svg)](https://developer.android.com/)
[![Version](https://img.shields.io/badge/version-v1.0.3-cyan.svg)](https://github.com/Silxcode/MockGPSModule_SU/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A developer-grade **Mock GPS** and geolocation simulation suite for **KernelSU**, **KernelSU-Next**, **APatch**, and **Magisk**.  
Built with an on-device **WebUI** and a multi-layer **Network Fingerprint Shield** to suppress all major location signals.

---

## What This Does

On modern Android, apps like Google Maps determine your location using **five independent signals**:

| Signal | Source | Bypassed? |
|---|---|---|
| GPS satellite | Hardware GNSS chip | ✅ Injected via `cmd location` root API |
| Wi-Fi BSSID scanning | Nearby router MAC addresses | ✅ Suppressed automatically |
| Bluetooth beacon scanning | BLE beacon triangulation | ✅ Suppressed automatically |
| GMS network geolocation | Google's BSSID/IP database | ✅ Blocked via `iptables` (Network Shield) |
| **IP geolocation** | Your public IP → country lookup | ⚠️ Requires a VPN (see below) |

This module injects mock GPS coordinates at the **Android system level** using root — **without** enabling Developer Options or selecting a mock location app in settings.

---

## Features

- **Root-Level GPS Injection:** Injects coordinates directly into `LocationManagerService` via `cmd location providers`. The system setting `development_settings_enabled` stays `0`.
- **On-Device WebUI:** Tap the module in KernelSU Manager to open a full interactive map (Leaflet.js, offline-capable, no API keys).
- **24 City Presets:** One-tap teleport to Tokyo, New York, London, Paris, Dubai, Singapore, and more.
- **Draggable Pin + Search:** Drag the map pin or search any address to set coordinates.
- **Three Map Layers (No Watermarks):** Dark Canvas (Esri), Google Satellite/Hybrid, OpenStreetMap.
- **Atmospheric Jitter Engine:** Simulates authentic GNSS drift (±1.5m) to defeat static-coordinate anti-cheat checks.
- **Network Fingerprint Shield (v1.0.3):** Automatically applies `iptables` rules that block GMS from sending your Wi-Fi BSSIDs to Google's geolocation servers.
- **Live IP Check Panel (v1.0.3):** WebUI fetches your public IP and detected country, then shows a ✅ / ⚠️ match indicator against your spoofed GPS location.
- **VPN Detector:** Auto-detects active `tun0`/`wg0`/`ppp0` tunnel interfaces and shows them in the WebUI.
- **Boot Persistence:** Optional auto-start with saved coordinates on reboot.
- **Bootloop-Safe:** Zero `/system` modifications. Zero early-boot scripts. Late-boot only with 60s watchdog timeout.

---

## Technical Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  KernelSU WebUI (WebView)               │
│   Leaflet Map · IP Check · Shield Toggle · Presets      │
└────────────────────┬────────────────────────────────────┘
                     │ ksu.exec() bridge
                     ▼
┌─────────────────────────────────────────────────────────┐
│              gps_control.sh  (CLI controller)           │
│  start · stop · set · status · save-config · net-shield │
└──────┬───────────────────────────────┬──────────────────┘
       │                               │
       ▼                               ▼
┌─────────────────┐         ┌──────────────────────┐
│  gps_daemon.sh  │         │   net_shield.sh      │
│  Root loop:     │         │  iptables DROP rules │
│  injects coords │         │  GMS UID geoloc block│
│  every 1 second │         │  VPN interface check │
└────────┬────────┘         └──────────────────────┘
         │  cmd location providers set-test-provider-location
         ▼
┌─────────────────────────────────────────────────────────┐
│         Android LocationManagerService (system_server)  │
│                 gps · network · fused                   │
└─────────────────────────────────────────────────────────┘
```

---

## Installation

### Requirements
- Device rooted with **KernelSU** (v0.9.0+), **KernelSU-Next**, **APatch**, or **Magisk** (v20.4+)
- Android 10 – 15 (tested on Evolution X Android 14, Kernel 4.14, KernelSU-Next v3.3.0)

### Steps
1. Download the latest `ksu_fakegps_vX.X.X.zip` from [**Releases**](https://github.com/Silxcode/MockGPSModule_SU/releases).
2. Open **KernelSU Manager** → **Modules** → **Install from storage**.
3. Select the `.zip` file and let it flash.
4. **Reboot** your device.
5. Return to **KernelSU Manager** → **Modules** → tap **KSU GPS Ghost** → **Open WebUI**.

---

## Using the WebUI

1. **Pick a city** from the scrollable preset flags row, or drag the map pin, or type an address in the search bar.
2. Adjust **Accuracy** (meters) and **Altitude** to taste.
3. Tap **START SPOOFING** — the badge turns green **ACTIVE**.
4. Open **Google Maps** (swipe it away from Recent Apps first if it was already open) and tap the locate button. The blue dot will jump to your spoofed location.
5. Tap **STOP SPOOFING** to restore real hardware GPS.

---

## IP Check & Network Shield

### The Problem
Even with perfect GPS spoofing, Google Maps and most apps verify location using **IP geolocation**. If your IP says you're in India but your GPS says Tokyo, Google detects the mismatch and overrides or ignores the GPS signal.

### What the Network Shield Does (automatic when you press START)
- Resolves the UID of `com.google.android.gms` from `/data/system/packages.list`
- Applies `iptables DROP` rules for Google's geolocation IP ranges (`142.250.0.0/15`, `216.58.0.0/16`, `74.125.0.0/16`) **only for the GMS UID** — so Play Store, authentication, and notifications are unaffected
- Suppresses Wi-Fi scanning (`wifi_scan_always_enabled 0`) and BLE scanning (`ble_scan_always_enabled 0`)
- Opts out of Google Network Location via the `com.google.settings` content provider
- Force-stops Google Maps to clear its in-memory location cache
- All rules are cleanly removed when you tap STOP SPOOFING

### Checking IP Match in the WebUI
Open the **"IP & Network Fingerprint Shield"** panel in the WebUI:

| Row | What it shows |
|---|---|
| Your Public IP | Your real outgoing IP address |
| IP-Geolocated City | City/country Google sees from your IP |
| IP vs GPS Match | ✅ Match or ⚠️ MISMATCH with reason |
| GMS Network Shield | Whether iptables rules are active |
| VPN / Tunnel Active | Detected `tun0`, `wg0`, etc. interface |
| Wi-Fi Scanning | Whether Android's always-on Wi-Fi scan is suppressed |

### Achieving Full IP Bypass — Use a VPN

The Network Shield prevents GMS from **resolving** your Wi-Fi/cell location, but it cannot change your **actual public IP address**. For complete location consistency, connect a VPN to a server near your spoofed GPS city:

| VPN | Notes |
|---|---|
| **[Mullvad VPN](https://mullvad.net)** | Best privacy, anonymous accounts, €5/month, WireGuard |
| **[ProtonVPN Free](https://protonvpn.com)** | Free tier (US/NL/JP), no logs, fast |
| **[Windscribe Free](https://windscribe.com)** | 10 GB/month free, many server locations |

**Steps:**
1. Install Mullvad or ProtonVPN from the Play Store.
2. Select a server in the **same country** as your spoofed GPS location.
3. Connect the VPN, then start spoofing.
4. The WebUI **IP Check panel** will show ✅ when both signals match.

---

## Troubleshooting

### Google Maps still shows real location after START SPOOFING

1. **Swipe Google Maps away from Recent Apps** before checking. It caches location aggressively in RAM.
2. Disable **Google Location Accuracy**: Settings → Location → Location Services → Google Location Accuracy → **OFF**.
3. Disable **Wi-Fi scanning** and **Bluetooth scanning** in the same menu.
4. Check the WebUI **IP Check panel** — if it shows ⚠️ MISMATCH, you need a VPN (see above).

### Coordinates are accepted but accuracy is poor

Increase the **Accuracy** slider in the WebUI to a lower value (e.g. 3m). Some apps reject locations with accuracy > 50m.

### Daemon log for debugging

```bash
su -c "cat /data/adb/ksu_fakegps/daemon.log"
```

To verify the system server accepted your injected coordinates:
```bash
su -c "dumpsys location | grep -A 8 'Last Known Locations'"
```

### Module not appearing in KernelSU

On non-GKI legacy kernels (kernel 4.14, Metamodule = Not Installed), the module mounts correctly but the Metamodule status warning is cosmetic. The shell scripts run independently of the mount and work fine.

---

## CLI / ADB Usage

All operations are available via root shell for CI pipelines and headless testing:

```bash
# Full status (JSON) including daemon state, VPN, and network shield
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh status"

# Set target coordinates
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh set 37.7749 -122.4194 15.0 4.5 true"

# Start the GPS daemon
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh start"

# Stop and restore real GPS
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh stop"

# Toggle GMS network shield independently
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield on"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield off"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield status"

# Check VPN / tunnel interface status
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield vpn"
```

---

## Advanced: Hiding `isFromMockProvider` Flag (LSPosed)

Apps that call `location.isMock()` (Android 12+) or `location.isFromMockProvider()` can still detect that coordinates are from a test provider. To hide this flag completely, you need an Xposed hook:

1. Flash **ZygiskNext** module in KernelSU Manager (enables Zygisk API without Magisk).
2. Flash **LSPosed** (Zygisk edition) from the [LSPosed releases](https://github.com/LSPosed/LSPosed/releases).
3. Reboot. Open **LSPosed Manager**.
4. Install and enable [**HideMockLocation**](https://github.com/auag0/HideMockLocation) module.
5. In LSPosed Manager → HideMockLocation → Scope → enable for **System Framework** and your target app (e.g. Google Maps).
6. Reboot again.

> **Note:** ZygiskNext on non-GKI kernels (like Qualcomm 4.14 on Raphael/K20 Pro) may have limited compatibility. Check your ROM thread for tested module combinations.

---

## Changelog

### v1.0.3 — Network Fingerprint Shield
- **New:** `scripts/net_shield.sh` — UID-targeted `iptables` rules blocking GMS geolocation signals
- **New:** Live **IP geolocation check** in WebUI with country match indicator
- **New:** VPN / tunnel interface detector in WebUI
- **New:** `net-shield` sub-command in `gps_control.sh`
- **Improved:** `gps_daemon.sh` now auto-enables shield on start and restores on stop
- **Improved:** `am kill com.google.android.gms` to flush stale location cache on daemon start

### v1.0.2 — Provider Fix & GLA Bypass
- Fixed SIGHUP daemon termination (`trap '' SIGHUP`)
- Added Google Location Accuracy suppression via settings + Google partner content provider
- Added provider reset before re-registration (prevents stale test provider conflicts)
- Added daemon logging to `/data/adb/ksu_fakegps/daemon.log`
- Added Wi-Fi/BLE scanning suppression on start, restore on stop
- Bumped provider registration flags (`--requiresNetwork --requiresSatellite --supportsAltitude --supportsSpeed --supportsBearing`)

### v1.0.1 — Initial Release
- Root-level GPS injection without Developer Options
- KernelSU WebUI with Leaflet.js map
- 24 city presets, drag-to-set pin
- Jitter engine, multi-provider support
- Boot persistence option

---

## Responsible Use & Legal Disclaimer

> [!IMPORTANT]
> This software is designed and distributed strictly for **software development, application QA testing, academic research, location privacy, and geolocation simulation**.
>
> - **Compliance:** Use in compliance with all applicable local laws and the Terms of Service of any third-party application.
> - **Anti-Fraud:** This tool is **not** intended to bypass anti-cheat systems in games, commit rideshare or delivery fraud, spoof attendance or time-tracking systems, or gain unauthorized advantages in any system. The author does not condone or take responsibility for illicit use.
> - **As-Is:** Provided under MIT License without warranties of any kind. Use at your own risk on your own devices.

---

## License

MIT License © 2024 [Silxcode](https://github.com/Silxcode)  
Open source map tiles © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), Esri, and [Leaflet.js](https://leafletjs.com).
