# PlantHealthMonitor

An embedded plant monitoring system that uses on-device machine learning to classify plant health and predict care needs in real time — no cloud dependency for inference.

Sensor data is collected by an ESP32 microcontroller, classified by a TinyML model running directly on the device, and surfaced to the user via a Flutter app (Android, Windows, iOS) with push notifications.

---

## How it works

```
Sensors (soil, temp, humidity, light)
    ↓
ESP32 — TinyML inference → risk class + time-to-action prediction
    ↓
Supabase (cloud sync every 3 hours)
    ↓
Flutter app (Android / Windows / iOS) — live dashboard + push notifications
```

ML inference runs fully on the ESP32. An internet connection is only needed to sync results to the app — classification never leaves the device.

---

## System architecture

```
┌─────────────────────────────────────────────────────────┐
│  ESP32 firmware                                         │
│                                                         │
│  LittleFS pairing doc  →  WiFi creds, API key, URL      │
│  BLE provisioning      →  receive WiFi creds, Supabase  │
│                           URL + API key from the app    │
│  TinyML (TFLM)         →  risk classification           │
│  Supabase HTTP         →  upload readings every 3 h     │
│  Command poll (5 s)    →  trigger_measurement / reset   │
└─────────────────────────────────────────────────────────┘
             ↕ HTTPS / Supabase REST
┌─────────────────────────────────────────────────────────┐
│  Supabase (PostgreSQL)                                  │
│                                                         │
│  devices        — registered devices + control flags    │
│  plant_settings — per-plant preferences + device link   │
│  plant_readings — historical sensor + ML results        │
└─────────────────────────────────────────────────────────┘
             ↕ Supabase client + Realtime
┌─────────────────────────────────────────────────────────┐
│  Flutter app (Android / Windows / iOS)                  │
│                                                         │
│  BLE provisioning  →  scan, send WiFi creds to ESP32    │
│  Dashboard         →  live readings, risk, predictions  │
│  Settings          →  manage devices, preferences       │
│  Push notifications→  risk alerts + daily report        │
└─────────────────────────────────────────────────────────┘
```

---

## Features

- **Health classification** — healthy / moderate risk / high risk via TensorFlow Lite Micro MLP
- **Predictive irrigation** — regression model predicts minutes until watering is needed
- **Care recommendations** — rule-based engine combining sensor values, ML output, and per-plant preferences
- **BLE provisioning** — add devices wirelessly from the app; no hardcoded credentials, no secrets in the firmware build
- **Multi-plant support** — each plant has its own device and preference profile
- **On-demand measurement** — request an immediate sensor reading from the app
- **Push notifications** — instant alert on risk change; optional daily summary
- **Cross-platform app** — Android, Windows, and iOS

**Platform support:**

| Feature | Android | Windows | iOS |
|---|---|---|---|
| Dashboard, charts, data | ✅ | ✅ | ✅ |
| Plant preferences | ✅ | ✅ | ✅ |
| Local notifications | ✅ | ❌ | ✅ |
| Settings, device list | ✅ | ✅ | ✅ |
| Add Device (BLE provisioning) | ✅ | ✅ | ❌ |
| Delete / reset device | ✅ | ✅ | ✅ |

Devices provisioned from any platform are accessible from all of them.

---

## Hardware

| Component | Connection |
|---|---|
| Capacitive soil moisture sensor | GPIO 34 |
| DHT22 (temperature + humidity) | GPIO 4 |
| LDR + 10 kΩ resistor (light) | GPIO 35 |
| ESP32 development board (38-pin) | — |

---

## Project structure

```
firmware/                ESP32 firmware (PlatformIO)
  src/                   One .cpp per class — main.cpp is orchestration only
  include/               Headers (CloudService, ProvisioningService, MLLayer,
                         FileStorageService, RecommendationEngine, sensors, …)
  web/                   Small web app for adjusting settings on a connected device
  platformio.ini         Single build environment: esp32_provisioning

app/
  android_/              Main Flutter app (Android, Windows, iOS targets)
    lib/main.dart        Entry point
    lib/core/            Theme and colors
    lib/services/        Supabase, app settings, notifications, BLE constants
    lib/screens/         Dashboard, data, settings, provisioning screens
    lib/widgets/         Shared widgets
    lib/secrets.dart     Supabase URL and anon key (gitignored)
  ios_only/              Stripped iOS build — no BLE/WiFi plugins, runs unsigned
                         (same lib/ layout, minus provisioning screens)

model/                   ML training pipeline
  python/                Training, validation, TinyML export, retraining scripts
  datasets/              Source datasets (MIT licence)
  data/                  Training outputs, validation results, exports
  logs/                  Device logs used for retraining

data/models/             Exported model weights shipped in the firmware

supabase/
  migrations.sql         All database schema changes — run in order

docs/                    Manual, system design, AI Act compliance (AsciiDoc + PDF)

codemagic.yaml           CI: unsigned iOS .ipa build of app/ios_only
```

Both Flutter projects share the same `lib/` architecture: `core/` (theme), `services/` (Supabase, settings, notifications), `screens/` (one file per screen), `widgets/`.

---

## Releases

Pre-built binaries (Android `.apk`, iOS `.ipa`, Windows `.msix`/`.zip`, and ESP32 firmware `.bin`) are published on the [GitHub Releases page](https://github.com/caseystijlaart/PlantHealthMonitoring/releases) — latest: [v1.2](https://github.com/caseystijlaart/PlantHealthMonitoring/releases/tag/v1.2). iOS sideloading instructions are in [docs/manual/ios-sideloading.adoc](docs/manual/ios-sideloading.adoc).

---

## Database setup

Run `supabase/migrations.sql` in the Supabase SQL editor in order. The migrations:

1. Widen `device_id` columns to `text` (legacy integer → UUID support)
2. Create the `devices` table (`device_id`, `status`, `last_seen`, `trigger_measurement`, `trigger_reset`)
3. Seed legacy device rows
4. Add FK from `plant_settings` → `devices`
5. Add `trigger_reset` column
6. Fix `plant_settings.id` auto-increment

---

## Getting started

### Firmware

Requires [PlatformIO](https://platformio.org/). No secrets are needed at build time — WiFi credentials, the Supabase URL, and the API key are sent to the device at runtime over BLE during provisioning and stored in the on-device pairing document.

```sh
cd firmware
platformio run -e esp32_provisioning -t upload
platformio device monitor -b 115200
```

The device enters BLE provisioning mode on first boot and waits for the app to send WiFi credentials.

### Flutter app

Requires Flutter 3.x or later. The main app is in `app/android_/`:

```sh
cd app/android_
flutter pub get
flutter run        # Android, Windows, or iOS
```

Create `lib/secrets.dart`:

```dart
const supabaseUrl  = 'https://your-project.supabase.co';
const supabaseAnon = 'your-anon-key';
```

> BLE provisioning (Add Device) works on Android and Windows. On iOS the dashboard, charts, settings, preferences, and notifications all work — devices must be provisioned from another platform first. For unsigned iOS sideloading, use the stripped `app/ios_only/` project instead (see its README).

---

## Provisioning flow

1. Flash `esp32_provisioning` to a new ESP32 — device advertises over BLE
2. Open the app → Settings → Add Device
3. App scans for BLE devices, shows discovered PHM devices
4. Tap a device → enter WiFi credentials → tap Provision
5. App sends WiFi credentials, Supabase URL, and API key over BLE
6. ESP32 connects to WiFi, registers itself in the `devices` table
7. App detects the new row and shows the plant setup screen
8. Enter plant name and care preferences → Save
9. Device picks up the plant label within 5 seconds and begins monitoring

---

## Partition table

The default ESP32 partition (1.25 MB) is too small for BLE + TinyML + TLS combined. The `esp32_provisioning` environment uses `huge_app.csv` (built-in), which provides a 3 MB app slot. `partitions_ota_large.csv` is available for OTA builds.

---

## ML models

Two models trained offline in Python (scikit-learn) and exported as C++ weight headers for on-device TFLM inference:

| Model | Type | Output |
|---|---|---|
| Health risk classifier | MLP (ReLU + softmax) | Risk class 0 / 1 / 2 |
| Predictive irrigation | MLP (ReLU + linear, log1p target) | Minutes until watering needed |

Training scripts, datasets, and validation outputs are in `model/` (`python/`, `datasets/`, `data/`); the scripts also support retraining from real device logs. The exported weights used by the firmware live in `data/models/`. The datasets are released under the **MIT licence**.

---

## Licence

Source code — MIT

Training dataset — MIT

---

> Built as part of the AI for Society minor at Fontys University of Applied Sciences.
