# POF-03 — Personalized Plant Monitoring (based on POF-02)

This folder contains the POF-03 proof of concept, built from `src/pof-02` and extended with personalization + settings-management support while keeping TinyML-ready ESP32 integration.

## Goal
Build a real-time monitoring pipeline:

`Sensors -> Preprocessing -> Classification -> Temporal Analysis -> ML Layer -> Recommendation`

## C++ modules
- Sensor layer: moisture, temp/humidity, light from a standard LDR + 10k resistor (0 = dark) with calibration + averaging
- Classification layer: `kLow  / kOk / kHigh` per environmental factor
- Stress layer: per-factor and combined stress
- Temporal core: circular history buffer with mean, delta, slope, dry-duration proxies
- Feature engineering: compact feature vector
- ML layer: pluggable backend (`RULE_BASED`, `TINYML_TFLM`, `EDGE_IMPULSE`)
- Recommendation engine: actionable outputs (`water`, `reduceTemp`, `increaseLight`)
- POC-03 extension: per-plant rule thresholds + user `pLow/pMid/pHigh` preferences for humidity, temperature, soil moisture, and light, producing personalized recommendations

## TinyML-ready backend strategy
The ML abstraction lives in `MLLayer` and supports swapping backends:
1. `RULE_BASED` (local/dev fallback, deterministic)
2. `TINYML_TFLM` (TensorFlow Lite Micro / EloquentTinyML adapter point)
3. `EDGE_IMPULSE` (Edge Impulse C++ SDK adapter point)

This lets you train using external platforms and only map outputs to `MLResult` on-device.

## ESP32 integration suggestions
### Option A — Edge Impulse (recommended for anomaly + classification)
- Train impulse with the same engineered features.
- Export Arduino/C++ library.
- Enable `POF02_ENABLE_EDGE_IMPULSE` and call `run_classifier()` inside `EdgeImpulseBackend`.

### Option B — TensorFlow Lite Micro / EloquentTinyML
- Train tiny model (MLP/tree equivalent) offline.
- Export `.tflite` and convert to C array.
- Enable `POF02_ENABLE_TINYML_TFLM` and call inference inside `TinyMLTFLMBackend`.

## Time-aware dataset note
Synthetic training data now uses real timestamps (e.g. `2026-03-04 10:20:00`) with unix epoch and cyclical time features (`hour_sin/cos`, `dow_sin/cos`) so training is date/time-aware instead of simple step ids.

## Build and upload (Arduino/PlatformIO)
```bash
platformio run
platformio run -t upload
platformio device monitor -b 115200
```

## POC-03 personalization web app (settings only)
- ESP32 web UI (`/`) includes a small settings app for the already-connected plant/ESP32 pair.
- It updates only the active plant profile preferences and plant name on that device.
- Preferences use `pLow/pMid/pHigh` to avoid collisions with Arduino macros.
- API routes:
  - `GET /api/plant-settings`
  - `POST /api/plant-settings`

### Standalone mini web app (optional)
This folder also includes a small standalone browser app in `web/`:
- `web/index.html`
- `web/styles.css`
- `web/app.js`

Use it to connect to an ESP32 by entering the base URL (for example `http://192.168.1.33`), load current settings, and update preferences through the same API endpoints.

Quick start:
```bash
cd web
python3 -m http.server 8080
```
Then open `http://localhost:8080`.

## Python workflow
```bash
python3 python/generate_training_data.py
python3 python/train_models.py
python3 python/validate_models.py
python3 python/export_for_tinyml.py
```


## WiFi logging to a shared CSV-friendly store (Google Sheets)
`main.cpp` now logs every cycle through WiFi (`INTERVAL = 3600000`, so once per hour) by sending JSON to a web endpoint. This allows **multiple ESP32 devices** to upload without being connected to a laptop.

Recommended target: a Google Apps Script web app that appends to a Google Sheet (which you can download as CSV anytime).

### 1) Configure each ESP32 environment
`platformio.ini` now includes:
- `WIFI_SSID`
- `WIFI_PASSWORD`
- `LOG_ENDPOINT_URL` (Google Apps Script URL)
- `PLANT_LABEL` (e.g. `aglaonema`, `prayer_plant`)

Set these values for each environment before upload.

### 2) Create Apps Script endpoint (example)
In a Google Sheet: **Extensions -> Apps Script**, then paste:

```javascript
const SHEET_NAME = 'logs';

function doPost(e) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME)
    || SpreadsheetApp.getActiveSpreadsheet().insertSheet(SHEET_NAME);

  const payload = JSON.parse(e.postData.contents);

  if (sheet.getLastRow() === 0) {
    sheet.appendRow([
      'timestamp_utc', 'unix_time', 'plant_label', 'device_name', 'device_id',
      'soil_moisture_pct', 'temperature_c', 'humidity_pct', 'light_level_pct',
      'risk_class', 'confidence', 'prob_healthy', 'prob_moderate_stress',
      'prob_high_stress', 'action_water', 'action_reduce_temp',
      'action_increase_humidity', 'action_increase_light', 'recommendation_summary'
    ]);
  }

  sheet.appendRow([
    payload.timestamp_utc,
    payload.unix_time,
    payload.plant_label,
    payload.device_name,
    payload.device_id,
    payload.soil_moisture_pct,
    payload.temperature_c,
    payload.humidity_pct,
    payload.light_level_pct,
    payload.risk_class,
    payload.confidence,
    payload.prob_healthy,
    payload.prob_moderate_stress,
    payload.prob_high_stress,
    payload.action_water,
    payload.action_reduce_temp,
    payload.action_increase_humidity,
    payload.action_increase_light,
    payload.recommendation_summary
  ]);

  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok' }))
    .setMimeType(ContentService.MimeType.JSON);
}
```

Deploy with **Deploy -> New deployment -> Web app**, access level:
- Execute as: **Me**
- Who has access: **Anyone with the link**

Copy the web app URL into `LOG_ENDPOINT_URL`.

### 3) Export to CSV
In Google Sheets:
- `File -> Download -> Comma Separated Values (.csv)`

The `plant_label` column is included so you can quickly filter rows per plant/device.

## MQTT logging (HiveMQ Cloud Serverless)
This prototype now publishes each monitoring cycle as JSON over **MQTT (TLS)** instead of writing cycle logs to local CSV files.

- Broker type: HiveMQ Cloud Serverless (remote, no local MQTT broker needed)
- Transport: MQTT over TLS (`MQTT_HOST` + `MQTT_PORT`, default `8883`)
- Auth: username/password
- Topic format: `<MQTT_TOPIC_PREFIX>/<PLANT_LABEL>/<DEVICE_ID>`

### PlatformIO configuration
Set these build flags per device environment:
- `MQTT_HOST`
- `MQTT_PORT` (typically `8883`)
- `MQTT_USERNAME`
- `MQTT_PASSWORD`
- `MQTT_TOPIC_PREFIX`

### MongoDB Atlas storage flow
The ESP32 publishes to HiveMQ. Persisting into MongoDB Atlas is done by a downstream cloud subscriber (for example HiveMQ Data Hub extension, HiveMQ webhook bridge + serverless function, Node-RED cloud flow, or custom consumer) that validates incoming messages and inserts valid records into Atlas.
