# KSU Location Sandbox

[![KernelSU Compatible](https://img.shields.io/badge/KernelSU-Supported-emerald.svg)](https://kernelsu.org/)
[![Android Version](https://img.shields.io/badge/Android-10%20to%2015-blue.svg)](https://developer.android.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, developer-oriented geolocation simulation and privacy testing suite for **KernelSU**, **KernelSU Next**, and **APatch** (also compatible with **Magisk**).

Equipped with an on-device **WebUI**, it allows mobile application developers, QA engineers, and security researchers to simulate GPS coordinates and test location-based features directly through Android's system test provider APIs — without needing to turn on "Developer Options" or select a third-party mock location app in system settings.

---

## Why I Built This

When developing or QA-testing location-aware Android applications (such as geofencing, delivery logistics, mapping, or regional feature flags), developers often face practical hurdles:

1. **Enterprise & MDM Policy Conflicts:** Many test devices enrolled in corporate MDM profiles or enterprise test suites strictly restrict enabling "Developer Options".
2. **Ad-Ridden Third-Party Mock Apps:** Most Play Store mock location tools bundle invasive analytics SDKs, full-screen ads, and background trackers.
3. **Realistic Sensor Testing:** Real-world GPS signals naturally drift by 1–2 meters due to atmospheric interference. Standard mock tools feed frozen, static coordinates down to 8 decimal places, preventing developers from validating noise-filtering and Kalman filter algorithms.

This module provides a clean, open-source, root-level environment that bridges Android's built-in `cmd location` test provider interface directly to a clean interactive map on your phone.

---

## Features

- **No Developer Options Toggle Required:** Leverages root shell access (`uid 0`) to communicate directly with Android's `LocationManagerService`. The system setting `development_settings_enabled` stays `0` (Disabled).
- **Embedded On-Device WebUI:** Tap the module inside KernelSU Manager to open a complete, responsive map interface powered by Leaflet.js.
- **Multiple Map Layers (No API Keys Needed):**
  - **Dark Canvas:** Clean, high-contrast vector tiles that seamlessly blend with the UI.
  - **Satellite / Hybrid:** Photorealistic aerial imagery with street labels.
  - **OpenStreetMap:** Classic street cartography.
- **Realistic Atmospheric Drift:** Built-in micro-jitter engine simulates authentic satellite signal fluctuation (±1.5m) so you can test how your app handles live sensor noise.
- **Multi-Provider Injection:** Automatically binds to `gps`, `network`, and `fused` providers for consistent behavior across both native Android location APIs and Google Play Services.
- **Bootloop-Safe Architecture:** 
  - Zero modifications to `/system` or `/vendor` partitions.
  - No `system.prop` alterations.
  - Zero `post-fs-data.sh` early-boot scripts.
  - Late-boot service runs detached with a 60-second watchdog timeout.
- **Offline Capable:** The core map engine, styles, and controls are completely vendored and bundled within the module. You can test manual coordinates and presets even in airplane mode.

---

## Technical Architecture

```text
Android Framework (system_server)
       ▲
       │  cmd location providers set-test-provider-location
       ▼
gps_daemon.sh  ◄───  gps_control.sh  ◄───  WebUI (ksu.exec bridge)
 (Root Loop)           (CLI Utility)            (KernelSU WebView)
```

1. **WebUI:** Runs inside KernelSU Manager's sandboxed WebView (`webroot/index.html`). User interactions trigger shell commands via the `ksu.exec()` JavaScript bridge.
2. **Controller (`gps_control.sh`):** Handles state updates, reads current system parameters, and manages daemon lifecycles.
3. **Daemon (`gps_daemon.sh`):** A lightweight background POSIX shell loop that updates system test providers at configurable intervals.

---

## Installation

### Prerequisites
- A device rooted with **KernelSU** (v0.9.0+), **KernelSU Next**, **APatch**, or **Magisk** (v20.4+).
- Android 10, 11, 12, 13, 14, or 15.

### Flashing Steps
1. Download the latest `ksu_fakegps_vX.X.X.zip` from [Releases](https://github.com).
2. Open your root manager app (**KernelSU Manager** / **APatch** / **Magisk**).
3. Navigate to **Modules** ➔ **Install from storage**.
4. Select the downloaded `.zip` file.
5. Reboot your device after installation completes.
6. Open **KernelSU Manager**, go to **Modules**, and tap **KSU Location Sandbox** to launch the WebUI.

---

## CLI / Automation Usage

For automated testing or headless CI scripts via ADB:

```bash
# Check daemon and system status
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh status"

# Set target coordinates (lat, lng, altitude, accuracy, jitter)
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh set 37.7749 -122.4194 15.0 4.5 true"

# Start simulation
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh start"

# Stop simulation and restore genuine hardware GPS
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh stop"
```

---

## Responsible Use & Legal Disclaimer

> [!IMPORTANT]
> This software is designed and distributed strictly for **software development, application quality assurance (QA), academic research, and personal privacy protection**.
>
> - **Compliance with Terms:** You agree to use this software in compliance with all applicable local laws, regulations, and the Terms of Service of any third-party applications.
> - **Anti-Fraud & Fair Play:** This tool is **not** intended to bypass security protections, commit financial or rideshare fraud, spoof attendance systems, or gain unauthorized advantages in online games. The authors do not condone, support, or take responsibility for any unauthorized or illicit use of this software.
> - **As-Is Warranty:** Provided under the MIT License on an "AS IS" basis without warranties of any kind. Use responsibly on your own devices.

---

## License

This project is licensed under the [MIT License](LICENSE).
Open source map data &copy; [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), Esri, and Leaflet.js.
