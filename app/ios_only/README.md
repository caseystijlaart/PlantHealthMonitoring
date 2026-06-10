# PlantHealthMonitor — iOS App (stripped)

iOS-only Flutter app for the PlantHealthMonitor system, stripped to features that work in unsigned builds without an Apple developer account. Displays live sensor readings and plant health status, and manages per-plant care preferences.

**Included features:**

| Feature | Status |
|---|---|
| Dashboard, charts, data | ✅ |
| Plant preferences | ✅ |
| Local notifications (alerts + daily report) | ✅ |
| Settings, device list (from database) | ✅ |
| Delete / reset device (via database `trigger_reset`) | ✅ |
| Add Device (BLE provisioning, WiFi scan) | ❌ removed — use the Android app |

BLE provisioning and WiFi scanning are removed entirely (no `flutter_blue_plus`, `wifi_scan`, or `permission_handler` dependencies), so the build contains no CoreBluetooth code and needs no restricted entitlements. Devices provisioned from the Android app appear here automatically; deleting a device works because it is a pure database operation (the ESP32 polls `trigger_reset` and resets itself).

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
flutter run
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
- **Devices section** — lists all paired devices with online/offline status (based on `last_seen` within 4 hours); delete button per device. New devices are provisioned from the Android app and appear here automatically.
- **Notifications** — plant alert toggle; daily report toggle with time picker

### Plant Preferences
- Per-plant care thresholds: soil moisture, temperature, humidity, light
- Each preference has three bands: Low / Medium / High with value ranges
- Independent plant selection from dashboard

### Charts & Data
- Line charts per sensor metric with time-range filter
- Inline data table

---

## Add Device

Not available in this app. Provision new ESP32 devices with the Android app (BLE + WiFi provisioning); they appear in this app's device list automatically because both apps share the same Supabase database.

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

No BLE or location permissions are required — provisioning is not part of this app. Standard local-notification permission applies for plant alerts and the daily report (works without an Apple developer account; APNs remote push is not used).

---

## Key dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Database client + Realtime |
| `flutter_local_notifications` | Local alerts + daily report |
| `fl_chart` | Sensor history charts |
| `google_fonts` | Outfit typeface |
| `shared_preferences` | Notification settings persistence |
