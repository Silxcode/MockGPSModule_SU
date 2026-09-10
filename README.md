# KernelSU Mock GPS (WebUI)
**System-level Mock GPS without Developer Options Toggle**

A specialized module for **KernelSU**, **KernelSU Next**, and **APatch** (also compatible with **Magisk**) that spoofs your Android device's GPS coordinates using system-level root test providers while keeping **Developer Options completely OFF**.

---

## Key Highlights

- **Zero Developer Options Required:** Standard mock location requires toggling Developer Options and selecting a mock location app. Strict apps (banking, rideshare, games) instantly detect this. This module operates via KernelSU root (`uid 0`), injecting directly into Android's `LocationManagerService` test providers.
- **Embedded WebUI:** Tap the module in KernelSU Manager to open a complete, interactive Leaflet map interface directly on your device.
- **Atmospheric Satellite Jitter:** Simulates authentic GNSS micro-drift (±1.5 meters) so your coordinates do not appear artificially frozen to anti-cheat algorithms.
- **Multi-Provider Injection:** Simultaneously registers and updates `gps`, `network`, and `fused` providers to ensure both standard location queries and Google Play Services location clients receive the spoofed fix.
- **Boot Persistence:** Optional toggle to automatically resume spoofing the last known coordinates after device reboot.

---

## Module Structure

```text
ksu_fakegps_v1.0.0.zip
├── META-INF/com/google/android/
│   ├── update-binary          # Universal installer script
│   └── updater-script         # Marker
├── module.prop                # Module ID, name, author, version
├── customize.sh               # Post-install permissions & setup
├── service.sh                 # Late-boot persistence service
├── action.sh                  # KernelSU Quick Action button trigger
├── scripts/
│   ├── gps_daemon.sh          # Background root coordinate injection loop
│   └── gps_control.sh         # CLI control script (start, stop, status, set)
└── webroot/                   # On-device WebUI
    ├── index.html             # Main interface
    ├── css/
    │   ├── style.css          # Dark cyber aesthetic styles
    │   ├── leaflet.css        # Bundled Leaflet styles
    │   └── images/            # Leaflet marker icons
    └── js/
        ├── leaflet.js         # Bundled Leaflet map engine
        └── app.js             # WebUI logic and ksu.exec bridge
```

---

## How to Install

1. Download or copy `ksu_fakegps_v1.0.0.zip` to your phone.
2. Open **KernelSU Manager** (or APatch / Magisk).
3. Navigate to **Modules** -> **Install from storage**.
4. Select `ksu_fakegps_v1.0.0.zip`.
5. Once installation finishes, **Reboot** your device.
6. After reboot, open **KernelSU Manager**, go to **Modules**, and tap on **KernelSU Mock GPS** to open the WebUI!

---

## WebUI Controls

- **Interactive Map:** Tap anywhere or drag the glowing radar pin to choose your location.
- **Preset Chips:** Quick-teleport to iconic cities (Tokyo, New York, London, Paris, Sydney, Dubai, Singapore, San Francisco).
- **Search Bar:** Type any city or landmark to look up coordinates.
- **Master Button:** Tap **START SPOOFING** to begin broadcasting; tap **STOP SPOOFING** to cleanly restore genuine GPS.
- **Parameters:** Fine-tune accuracy (meters), altitude (meters), satellite jitter, and boot persistence.
- **Live Diagnostics:** Shows current daemon PID, Developer Options state (`Disabled (value: 0)`), and injected providers.

---

## Terminal / CLI Commands

You can also manage the spoofing directly from Termux or ADB root shell:

```bash
# Check status
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh status"

# Start spoofing
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh start"

# Set new coordinates (latitude, longitude, altitude, accuracy, jitter)
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh set 35.6895 139.6917 40.0 5.0 true"

# Stop spoofing and restore real GPS
su -c "/data/adb/modules/ksu_fakegps/scripts/gps_control.sh stop"
```

---

## For Ultra-Strict Apps (Banking / Anti-Cheat)

Most apps only verify:
1. `Settings.Global.DEVELOPMENT_SETTINGS_ENABLED == 0` (Bypassed: remains 0).
2. `Settings.Secure.MOCK_LOCATION == 0` (Bypassed: remains 0).
3. Known mock GPS app package installed (Bypassed: no third-party mock app APK needed).

If you are dealing with games or banking apps that also perform bytecode inspection on `Location.isFromMockProvider()`:
- The active coordinates are continuously synced to `/data/adb/ksu_fakegps/config.json`.
- You can combine this module with LSPosed + `HideMockLocation` or Zygisk hooks to intercept and force `isFromMockProvider()` to return `false` on a per-app basis.
