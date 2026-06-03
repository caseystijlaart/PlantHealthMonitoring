# PlantHealthMonitor

An embedded plant monitoring system that uses on-device machine learning to classify plant health and predict care needs in real time — no cloud dependency for inference.

Sensor data is collected by an ESP32 microcontroller, classified by a TinyML model running directly on the device, and surfaced to the user via a cross-platform Flutter app with push notifications.

---

## How it works

```
Sensors (soil, temp, humidity, light)
    ↓
ESP32 — TinyML inference → risk class + time-to-action prediction
    ↓
Supabase (cloud sync every 3 hours)
    ↓
Flutter app — live dashboard + push notifications
```

The ML models run fully on the ESP32. An internet connection is only needed to sync results to the app — classification never leaves the device.

---

## Features

- **Health classification** — healthy / moderate risk / high risk, using a trained MLP on TensorFlow Lite Micro
- **Predictive irrigation** — regression model predicts minutes until watering is needed
- **Care recommendations** — rule-based engine combining sensor values, ML risk output, and per-plant preferences
- **Multi-plant support** — each plant gets its own device and preference profile
- **Push notifications** — instant alert on risk change, optional daily summary
- **Cross-platform app** — iOS and Windows

---

## Hardware

| Component | Connection |
|---|---|
| Capacitive soil moisture sensor | GPIO 34 |
| DHT22 (temperature + humidity) | GPIO 4 |
| LDR + 10 kΩ resistor (light) | GPIO 35 |
| ESP32 development board (38-pin) | — |

---

## Getting started

### Firmware

Requires [PlatformIO](https://platformio.org/).

```sh
cd src/prototype-non-local
cp platformio.ini.example platformio.ini
```

Edit `platformio.ini` and fill in your credentials:

```ini
build_flags =
    -D WIFI_SSID=\"YourNetwork\"
    -D WIFI_PASSWORD=\"YourPassword\"
    -D PLANT_LABEL=\"my_plant\"
    -D DEVICE_NAME=\"Living Room\"
```

Flash to the device:

```sh
platformio run -e esp32_com3_non_local
platformio run -t upload -e esp32_com3_non_local
platformio device monitor -b 115200
```

### Flutter app

Requires Flutter 3.x or later.

```sh
cd src/phm_app
cp lib/config.example.dart lib/config.dart  # add your Supabase URL and anon key
flutter pub get
flutter run
```

---

## Project structure

```
src/
  prototype-non-local/   # Production ESP32 firmware (PlatformIO)
  phm_app/               # Flutter app (iOS, Windows)
  pof-02/                # PoC-02 — dataset redesign and model revision
datasets/                # Synthetic training data (MIT licence)
releases/                # Pre-built binaries
docs/
  manual/                # User manual
  system-design/         # Architecture diagrams and design docs
  legal-ethical/         # EU AI Act compliance assessment
```

---

## ML models

Two models are trained offline in Python (scikit-learn) and exported as C++ weight headers for on-device TFLM inference:

| Model | Type | Output |
|---|---|---|
| Health risk classifier | MLP (ReLU + softmax) | Risk class 0 / 1 / 2 with confidence |
| Predictive irrigation | MLP (ReLU + linear, log1p target) | Minutes until watering needed |

Training scripts and the synthetic dataset are in `datasets/`. The dataset is released under the **MIT licence**.

---

## Docs

- [User manual](docs/manual/manual.adoc)
- [System design](docs/system-design/system-design.adoc)
- [EU AI Act compliance](docs/legal-ethical/AI-Act-Compliance.adoc)
- [iOS sideloading instructions](releases/phm/README.adoc)

---

## Licence

Source code — MIT  
Training dataset — MIT  

---

> Built as part of the AI for Society minor at Fontys University of Applied Sciences.
