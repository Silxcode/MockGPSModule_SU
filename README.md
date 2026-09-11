# KSU GPS Ghost

[![KernelSU](https://img.shields.io/badge/KernelSU--Next-supported-brightgreen.svg)](https://github.com/rifsxd/KernelSU-Next)
[![Android](https://img.shields.io/badge/Android-10--15-blue.svg)](https://developer.android.com/)
[![Version](https://img.shields.io/badge/version-v1.0.8-informational.svg)](https://github.com/Silxcode/MockGPSModule_SU/releases)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A root-level GPS spoofing module for KernelSU, KernelSU-Next, APatch, and Magisk. Operates via Android's system test provider interface — no Developer Options required, no third-party mock location app selection. Ships with an on-device WebUI and a network fingerprint shield that suppresses secondary location signals from reaching Google's servers.

---

## Background

Android does not determine location from GPS alone. A request to `FusedLocationProviderClient` is resolved using several independent signals:

| Signal | Source |
|---|---|
| GPS satellite | GNSS hardware |
| Wi-Fi BSSID scan | Router MAC addresses compared against Google's database |
| Bluetooth beacons | BLE triangulation |
| GMS network location | Google's Wi-Fi/IP geolocation API |
| IP geolocation | Server-side lookup of your public IP |

Standard mock location apps only override the GPS signal. The remaining signals continue to resolve your real position and are used to correct or override the injected coordinates. This module addresses all five.

---

## How It Works

GPS injection happens through the Android `cmd location` interface, which allows a root process to register test providers and feed arbitrary coordinates directly into `LocationManagerService`. The daemon registers itself as `gps`, `network`, and `fused` providers simultaneously, broadcasts coordinates on a 1-second interval, and applies micro-jitter to simulate realistic atmospheric drift.

The network shield runs alongside the daemon and applies `iptables DROP` rules scoped to the `com.google.android.gms` UID, targeting Google's geolocation IP ranges. This prevents GMS from resolving Wi-Fi BSSID data against Google's location database while leaving authentication, Play Store, and push notifications functional. Wi-Fi and Bluetooth background scanning are suppressed via Android settings. All rules are removed when the daemon stops.

The WebUI runs inside KernelSU Manager's sandboxed WebView and communicates with the shell layer through the `ksu.exec()` bridge.

---

## Features

- Root-level injection into `gps`, `network`, and `fused` providers with no Developer Options changes
- On-device WebUI with Leaflet.js map — drag pin or search by address
- 24 city presets
- Three tile layers: dark canvas (Esri), satellite/hybrid, OpenStreetMap — all offline-capable
- Configurable accuracy, altitude, and update interval
- Micro-jitter engine for realistic coordinate drift
- `iptables` network shield scoped to the GMS UID
- Live IP geolocation check in WebUI with match indicator against spoofed GPS region
- VPN/tunnel interface detection (`tun0`, `wg0`, `ppp0`)
- Boot persistence option
- Zero `/system` or `/vendor` partition modifications

---

## Architecture

```
WebUI (KernelSU WebView)
        |
        |  ksu.exec() bridge
        v
gps_control.sh          -- state management, daemon lifecycle, CLI entry point
        |
        |-- gps_daemon.sh     -- root loop, injects coordinates every ~1s
        |-- net_shield.sh     -- iptables rules, VPN detection, settings suppression
        |
        v
Android LocationManagerService (system_server)
        providers: gps / network / fused
```

---

## Installation

**Requirements:**
- KernelSU v0.9.0+, KernelSU-Next, APatch, or Magisk v20.4+
- Android 10 through 15
- Tested on Evolution X 14 (K20 Pro / Raphael, kernel 4.14, KernelSU-Next)

**Steps:**
1. Download `ksu_fakegps_vX.X.X.zip` from [Releases](https://github.com/Silxcode/MockGPSModule_SU/releases).
2. Open KernelSU Manager > Modules > Install from storage.
3. Select the zip and reboot.
4. After reboot: KernelSU Manager > Modules > tap the module > Open WebUI.

---

## Usage

### WebUI

1. Select a preset city, drag the map pin, or search an address.
2. Adjust accuracy and altitude if needed.
3. Press **Start**. The status badge turns green.
4. Force-close any app you want to test (swipe from Recents), then reopen it.
5. Press **Stop** to restore real GPS and remove all injected rules.

### CLI

All operations are also available via root shell:

```bash
# Status JSON — daemon state, VPN, shield, live coordinates
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh status"

# Set coordinates before starting
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh set 37.7749 -122.4194 15.0 4.5 true"

# Start / stop daemon
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh start"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh stop"

# Network shield — managed automatically, but can be toggled manually
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield on"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield off"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield status"
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh net-shield vpn"

# View daemon log
su -c "cat /data/adb/ksu_fakegps/daemon.log"

# Verify the system server accepted injected coordinates
su -c "dumpsys location | grep -A 8 'Last Known Locations'"
```

---

## IP Geolocation Bypass

The network shield blocks GMS from resolving your Wi-Fi BSSIDs against Google's location database. It does not change your public IP address. If your IP resolves to a different country than the spoofed GPS coordinates, apps may still detect the inconsistency.

To fully close this gap, connect a VPN server in the same country as the spoofed GPS location before starting the daemon. After connecting, the WebUI IP panel will confirm both signals are consistent.

VPN options that work reliably on Android with WireGuard or OpenVPN:

- **Mullvad** — anonymous accounts (no email), WireGuard, servers in 40+ countries
- **ProtonVPN** — free tier includes US, Netherlands, Japan; no logs
- **Windscribe** — free tier with 10 GB/month across many locations

The WebUI shows your current public IP, the city it resolves to, and whether it matches the spoofed GPS country. This check runs against `ip-api.com` on load and on demand via the Check IP button.

---

## Hiding the Mock Provider Flag

Apps that call `location.isMock()` (API 31+) or `location.isFromMockProvider()` can detect that coordinates originate from a test provider even if the coordinates themselves are accurate. Suppressing this flag requires hooking the `android.location.Location` class at the Zygote level.

On KernelSU-Next with a non-GKI kernel (e.g., 4.14 on Raphael):

1. Flash **ZygiskNext** in KernelSU Manager to enable the Zygisk API.
2. Flash **LSPosed** (Zygisk build) from the [LSPosed releases](https://github.com/LSPosed/LSPosed/releases).
3. Reboot, then open LSPosed Manager.
4. Install [**HideMockLocation**](https://github.com/auag0/HideMockLocation).
5. In LSPosed: enable HideMockLocation and add System Framework and your target app to its scope.
6. Reboot.

Compatibility with non-GKI kernels varies by ROM. Check your device thread before assuming it works.

---

## Troubleshooting

**Google Maps is still showing real location:**

1. Force-close Google Maps from Recents before checking — it caches location heavily in memory.
2. Disable Google Location Accuracy: Settings > Location > Location Services > Google Location Accuracy > Off.
3. Disable Wi-Fi scanning and Bluetooth scanning in the same menu.
4. Check the IP panel in the WebUI — if it shows a country mismatch, you need a VPN.

**Coordinates injected but accuracy is rejected by the app:**

Lower the accuracy value (e.g. 3m). Some apps discard locations with accuracy > 20–50m.

**Daemon exits immediately after start:**

Check the log: `su -c "cat /data/adb/ksu_fakegps/daemon.log"`. Common cause is a stale PID file from a previous crash. The control script cleans this up on stop, but if the device rebooted mid-session you may need to run stop once before start.

---

### Anti-Mock / Anti-Cheat Apps (Uber, Ola, Swiggy, Games)

Android's location subsystem automatically flags all test provider coordinates with `location.isMock() = true` (`location.isFromMockProvider()`). Standard apps (Chrome, Google Maps, WhatsApp, Telegram, Firefox, Instagram) ignore this flag and use the coordinates normally.

Apps with strict anti-fraud detection (such as ride-sharing or delivery apps) inspect `Location.isMock()` and silently drop mock coordinates:
- If Google Location Accuracy is turned on, GMS Wi-Fi scanning detects the real location (`isMock = false`), which the app accepts.
- If Google Location Accuracy is off, the app receives the mock location, sees `isMock == true`, and discards it (causing "location not fetched" or infinite loading).

**Solution for Anti-Mock Apps:**
To spoof location in apps that check `Location.isMock()`:
1. Install **ZygiskNext** (KernelSU module) to enable Zygisk.
2. Install **LSPosed** (Zygisk release).
3. Install **[Hide Mock Location](https://github.com/auag0/HideMockLocation)** Xposed module.
4. Add the target app (e.g. Uber) in Hide Mock Location.
5. The Xposed module hooks `Location.isMock()` within the app's process, allowing it to seamlessly accept the spoofed coordinates injected by this module.

---

## Changelog

**v1.0.8**
- Removed disruptive `network_location_opt_in=0` content insert that triggered the Google Location Accuracy modal prompt
- Removed restrictive `--requiresNetwork` and `--requiresSatellite` flags from `cmd location providers add-test-provider`
- Made iptables packet-dropping network shield optional in WebUI rather than auto-enabled on daemon start
- Added on-screen guidance and documentation for apps enforcing `isMock` checks (Uber, Ola, etc.)

**v1.0.7**
- Added dynamic target apps list with live package management and preset buttons in WebUI
- Added instant coordinate injection and immediate app cache eviction on coordinate set
- Persistent target apps stored in `/data/adb/ksu_fakegps/config.json`

**v1.0.6**
- Pre-granted mock location appops across Android system UIDs (UID 0, 1000, 2000, com.android.shell, android)
- Added live daemon log streaming to WebUI

**v1.0.5**
- Fixed locale decimal parsing in jitter calculations across global mksh locales
- Isolated iptables chains to avoid duplicate rules
- Fixed daemon PID verification to prevent process recycling collisions

**v1.0.4**
- Added provider keepalive watchdog
- Improved IP check tool with fallback to toybox wget

**v1.0.3**
- Added `net_shield.sh` — iptables rules scoped to GMS UID
- Added IP geolocation check panel to WebUI
- Added VPN/tunnel interface detector to WebUI

---

## Legal

This software is provided for use in software development, application QA, geolocation testing, and personal location privacy.

It is not intended to defraud ride-sharing or delivery platforms, bypass anti-cheat systems in games, spoof attendance or time-tracking systems, or violate the terms of service of any third-party application. The author takes no responsibility for misuse.

Distributed under the [MIT License](LICENSE).  
Map tiles: OpenStreetMap contributors, Esri, Leaflet.js.
