# PlantHealthMonitor — Flutter App

Flutter app for the PlantHealthMonitor system. Displays live sensor readings and plant health status, manages per-plant care preferences, and adds ESP32 devices via BLE provisioning.

**Platform support:**

| Feature | Android | Windows | iOS |
|---|---|---|---|
| Dashboard, charts, data | ✅ | ✅ | ✅ |
| Plant preferences | ✅ | ✅ | ✅ |
| Local notifications | ✅ | ❌ | ✅ |
| Settings, device list | ✅ | ✅ | ✅ |
| Add Device (BLE provisioning) | ✅ | ✅ | ❌ |
| Delete / reset device | ✅ | ✅ | ✅ |

BLE provisioning works on Android and Windows. On Windows, BLE uses `flutter_blue_plus_windows` (WinRT backend, same API) and WiFi network suggestions come from parsing `netsh wlan show networks` instead of the Android-only `wifi_scan` plugin. Notifications are Android/iOS only (the service no-ops on Windows). Devices provisioned from any platform are accessible from all of them.

---

## Setup

Requires Flutter 3.x or later.

Create `lib/secrets.dart` (gitignored):

```dart
const supabaseUrl  = 'https://your-project.supabase.co';
const supabaseAnon = 'your-anon-key';
```

Install dependencies and run:

```sh
flutter pub get
flutter run -d android   # or: flutter run -d windows
```

---

## Screens

### Dashboard
- Plant selector dropdown (auto-selects if only one plant)
- Risk status card (healthy / moderate / high risk)
- Live sensor grid: soil moisture, temperature, humidity, light
  - Each tile shows current value + band indicator vs. preference
- Last reading timestamp
- View Charts & Data button
- Realtime updates via Supabase subscription on `plant_readings`

### Settings
- **Devices section** — lists all paired devices with online/offline status (based on `last_seen` within 4 hours); delete button per device
- **Add Device** button (Android only) — opens BLE scan screen
- **Notifications** — plant alert toggle; daily report toggle with time picker

### Plant Preferences
- Per-plant care thresholds: soil moisture, temperature, humidity, light
- Each preference has three bands: Low / Medium / High with value ranges
- Independent plant selection from dashboard

### Charts & Data
- Line charts per sensor metric with time-range filter
- Inline data table

---

## Add Device flow

1. Settings → Add Device → BLE scan screen
2. App scans for ESP32 devices advertising the PHM provisioning service
3. Tap a device → WiFi credentials form
4. App sends SSID + password over BLE; ESP32 connects to WiFi and registers itself in Supabase
5. App polls the `devices` table (every 2 seconds); navigates to plant setup when row appears
6. Enter plant name and care preferences (soil, temp, humidity, light) → Save
7. Returns to dashboard with new plant selected

Cancel is available at every step. Cancelling after the device has connected to WiFi sets `trigger_reset = true` — the ESP32 resets to BLE provisioning mode within 5 seconds.

---

## Delete device flow

1. Settings → tap delete (🗑) on a device
2. Confirmation dialog
3. App deletes `plant_settings` row → plant disappears from dashboard
4. App sets `trigger_reset = true` on the `devices` row
5. ESP32 polls within 5 seconds, clears local history, marks itself unpaired, deletes its own DB row, wipes credentials, reboots into BLE provisioning mode

If the device is offline when deleted, the boot-time check ("paired but no plant_settings → immediate reset") handles cleanup on next power-on.

---

## Permissions

### Android (`AndroidManifest.xml`)

| Permission | When used |
|---|---|
| `BLUETOOTH_SCAN` | BLE device discovery (Android 12+) |
| `BLUETOOTH_CONNECT` | BLE connection (Android 12+) |
| `BLUETOOTH` | BLE (Android ≤ 11) |
| `BLUETOOTH_ADMIN` | BLE scanning (Android ≤ 11) |
| `ACCESS_FINE_LOCATION` | Required for BLE scan (Android ≤ 11) |

Permissions are requested at runtime before scanning begins.

### iOS

No BLE permissions are required since provisioning is not supported on iOS. Standard notification permissions apply for push alerts.

---

## Key dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Database client + Realtime |
| `flutter_blue_plus` | BLE provisioning |
| `flutter_blue_plus_windows` | WinRT BLE backend for Windows (same API) |
| `permission_handler` | Runtime BLE permissions (Android) |
| `flutter_local_notifications` | Push alerts + daily report |
| `fl_chart` | Sensor history charts |
| `google_fonts` | Outfit typeface |
| `shared_preferences` | Notification settings persistence |
