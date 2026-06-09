# PlantHealthMonitor — Firmware

ESP32 firmware for the PlantHealthMonitor system. Collects sensor data, runs TinyML inference on-device, and syncs results to Supabase.

---

## Build environments

| Environment | Purpose |
|---|---|
| `esp32_provisioning` | All devices — BLE provisioning at runtime |

WiFi credentials and the Supabase API key are **not** stored in the firmware binary. They are sent to the device once over BLE by the phone app during provisioning and stored in the LittleFS pairing document.

---

## Setup
Flash a device:

```sh
platformio run -e esp32_provisioning -t upload
platformio device monitor -b 115200
```

---

## Provisioning flow

On first boot (or after a reset), the device enters BLE provisioning mode:

1. Generates a UUID (or loads existing one) and starts BLE advertising as `PHM-XXXXXX`
2. App connects, reads the `device_id` characteristic, writes SSID + password
3. Device stops BLE, connects to WiFi
4. Calls `RegisterDevice()` — inserts itself into the Supabase `devices` table with `status = 'active'`
5. Saves WiFi credentials + pairing state to LittleFS (`/pairing_state.txt`)
6. App polls the `devices` table, detects the new row, shows the plant setup screen
7. User saves plant name and preferences — app inserts a `plant_settings` row
8. Device polls for `plant_settings` every 5 seconds, picks up the plant label, runs first cycle

---

## Pairing state file

WiFi credentials and pairing state are stored in a single LittleFS document at `/pairing_state.txt`:

```
paired
MyWiFiNetwork
MyWiFiPassword
```

Or, when unpaired:

```
unpaired
```

This is the **only place** WiFi credentials are persisted. Marking the device unpaired erases them by construction — an unpaired device retains no WiFi secrets. NVS is no longer used for credentials.

**Pairing states:**

| State | Behaviour |
|---|---|
| File missing | Created as `unpaired` on first read → BLE provisioning mode |
| `unpaired` | BLE provisioning mode — wait for app |
| `paired` + plant_settings exists | Normal operation |
| `paired` + no plant_settings (boot) | Immediate reset → BLE mode |
| `paired` + no plant_settings (running) | Grace period (10 min) → reset → BLE mode |

---

## Boot sequence

```
setup()
  ├─ ReadPairingDoc()
  │    ├─ Not paired → RunProvisioningMode() [blocks until done]
  │    └─ Paired → load WiFi credentials from pairing doc
  ├─ ConnectWifi()
  ├─ NTP sync
  ├─ UpdateLastSeen()   ← PATCH only, never INSERT
  ├─ FetchPlantLabelByDeviceId()
  │    └─ No label + not just provisioned → reset to BLE mode
  ├─ FetchProfileSettings()
  ├─ LoadHistoryFile()
  └─ RunMonitoringCycle()  ← skipped if no plant label yet

loop() — every 5 seconds:
  ├─ CheckTriggerMeasurement()  → immediate cycle if flagged
  ├─ CheckTriggerReset()        → full reset if flagged
  └─ Plant label polling        → grace period countdown if empty

loop() — every 3 hours:
  ├─ FetchProfileSettings()
  ├─ RunMonitoringCycle()
  └─ UpdateLastSeen()
```

---

## Command flags (polled every 5 seconds)

| Flag | Table | Set by | Effect |
|---|---|---|---|
| `trigger_measurement` | `devices` | App | Immediate sensor reading; flag reset to `false` after |
| `trigger_reset` | `devices` | App (delete device) | Clear history, mark unpaired, delete DB row, wipe credentials, reboot into BLE |

---

## Reset paths

All reset paths perform the same sequence before rebooting:

1. `ClearLocalHistory()` — removes `/sensor_history.csv`
2. `SetPairedWithApp(false)` — overwrites `/pairing_state.txt` with `unpaired` (clears WiFi credentials)
3. `DeleteDeviceFromDb()` — DELETE from `devices` table
4. `NvsStorage::clearAll()` — wipe any remaining NVS data
5. `ESP.restart()`

---

## Sensors

| Sensor | Pin | Notes |
|---|---|---|
| Capacitive soil moisture | GPIO 34 | Calibrated: 3500 (dry) → 1450 (wet) |
| DHT22 (temp + humidity) | GPIO 4 | 22-type sensor |
| LDR (light level) | GPIO 35 | 10 kΩ pull-down |

---

## Partition tables

The default ESP32 partition (1.25 MB) is too small for BLE + TinyML + TLS together.

| Environment | Partition table | App slot |
|---|---|---|
| `esp32_provisioning` | `huge_app.csv` (built-in) | 3.0 MB |

The default ESP32 partition (1.25 MB) is too small for BLE + TinyML + TLS combined.

---

## Key constants

| Constant | Value | Purpose |
|---|---|---|
| `kIntervalMs` | 3 hours | Regular monitoring cycle |
| `kCommandCheckMs` | 5 seconds | Command flag poll interval |
| `kHistorySize` | 56 entries | Local sensor history ring buffer |
| `kMaxNoPlantTicks` | 30 ticks | Grace period before reset (30 × 5 s = 2.5min) |
| `_kRegistrationTimeout` | 90 seconds | Provisioning poll timeout (app side) |
