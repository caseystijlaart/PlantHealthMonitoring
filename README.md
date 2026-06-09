# PlantHealthMonitor

An embedded plant monitoring system that uses on-device machine learning to classify plant health and predict care needs in real time — no cloud dependency for inference.

Sensor data is collected by an ESP32 microcontroller, classified by a TinyML model running directly on the device, and surfaced to the user via a Flutter app (iOS + Android) with push notifications.

---

## How it works

```
Sensors (soil, temp, humidity, light)
    ↓
ESP32 — TinyML inference → risk class + time-to-action prediction
    ↓
Supabase (cloud sync every 3 hours)
    ↓
Flutter app (iOS + Android) — live dashboard + push notifications
```

ML inference runs fully on the ESP32. An internet connection is only needed to sync results to the app — classification never leaves the device.

---

## System architecture

```
┌─────────────────────────────────────────────────────────┐
│  ESP32 firmware                                         │
│                                                         │
│  LittleFS pairing doc  →  WiFi credentials + state      │
│  BLE provisioning      →  receive WiFi creds from app   │
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
│  Flutter app (Android)                                  │
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
- **BLE provisioning** — add devices wirelessly from the app; no hardcoded credentials
- **Multi-plant support** — each plant has its own device and preference profile
- **On-demand measurement** — request an immediate sensor reading from the app
- **Push notifications** — instant alert on risk change; optional daily summary
- **Cross-platform app** — iOS and Android; BLE provisioning is Android-only, all other features work on both platforms

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
firmware/          ESP32 firmware (PlatformIO)
  src/main.cpp     Main application
  platformio.ini   Build environments
  partitions_ota_large.csv  Custom partition table for OTA builds
app/               Flutter Android app
  lib/main.dart    Dashboard, settings, notifications
  lib/provisioning.dart  BLE provisioning + plant setup screens
  lib/secrets.dart Supabase URL and anon key (gitignored)
supabase/
  migrations.sql   All database schema changes — run in order
datasets/          Synthetic training data (MIT licence)
```

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

Requires [PlatformIO](https://platformio.org/).

```sh
cd firmware
cp secrets.ini.example secrets.ini
```

Fill in `secrets.ini` with your Supabase API key (and WiFi credentials for legacy environments). Flash the provisioning environment to a new device:

```sh
platformio run -e esp32_provisioning -t upload
platformio device monitor -b 115200
```

The device will enter BLE provisioning mode on first boot and wait for the app to send WiFi credentials.

For legacy devices with hardcoded credentials:

```sh
platformio run -e esp32_com3_non_local -t upload
```

### Flutter app

Requires Flutter 3.x or later.

```sh
cd app
flutter pub get
flutter run        # Android or iOS
```

> BLE provisioning (Add Device) is Android-only. On iOS the dashboard, charts, settings, preferences, and notifications all work — devices must be provisioned from an Android device first.

Create `lib/secrets.dart`:

```dart
const supabaseUrl  = 'https://your-project.supabase.co';
const supabaseAnon = 'your-anon-key';
```

---

## Provisioning flow

1. Flash `esp32_provisioning` to a new ESP32 — device advertises over BLE
2. Open the app → Settings → Add Device
3. App scans for BLE devices, shows discovered PHM devices
4. Tap a device → enter WiFi credentials → tap Provision
5. ESP32 connects to WiFi, registers itself in the `devices` table
6. App detects the new row and shows the plant setup screen
7. Enter plant name and care preferences → Save
8. Device picks up the plant label within 5 seconds and begins monitoring

---

## Partition table

The default ESP32 partition (1.25 MB) is too small for BLE + TinyML + TLS combined. The `esp32_provisioning` environment uses `huge_app.csv` (built-in), which provides a 3 MB app slot.

---

## ML models

Two models trained offline in Python (scikit-learn) and exported as C++ weight headers for on-device TFLM inference:

| Model | Type | Output |
|---|---|---|
| Health risk classifier | MLP (ReLU + softmax) | Risk class 0 / 1 / 2 |
| Predictive irrigation | MLP (ReLU + linear, log1p target) | Minutes until watering needed |

Training scripts and the synthetic dataset are in `datasets/`. The dataset is released under the **MIT licence**.

---

## Licence

Source code — MIT
Training dataset — MIT

---

> Built as part of the AI for Society minor at Fontys University of Applied Sciences.
