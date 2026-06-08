#pragma once

#include <Arduino.h>

// BLE provisioning service.
//
// BLE UUIDs — must match the Flutter app (lib/provisioning.dart):
//
//   Service:     4fafc201-1fb5-459e-8fcc-c5c9c331914b
//
//   Characteristics:
//     SSID:      beb5483e-36e1-4688-b7f5-ea07361b26a8  (WRITE)
//     Password:  beb5483e-36e1-4688-b7f5-ea07361b26a9  (WRITE, no read)
//     Device ID: beb5483e-36e1-4688-b7f5-ea07361b26aa  (READ)
//
// Note on UUIDs:
//   Service and characteristic UUIDs are fixed protocol identifiers — every
//   PHM device advertises the same service UUID so the app can discover them.
//   They are NOT device identities.
//
//   The *device* UUID (device_id) is a per-device value generated once on
//   first boot using the ESP32 hardware RNG, stored in NVS, and exposed via
//   the read-only Device ID characteristic.  The app reads it; it never writes
//   it.  This mirrors how real IoT provisioning works (Matter, BLE Mesh, etc.).
//
// Usage:
//   // On first boot, generate and persist the device UUID:
//   String id = ProvisioningService::getOrCreateDeviceId();
//
//   // Then start advertising:
//   ProvisioningService::begin("PHM-Device", id);
//   while (!ProvisioningService::isProvisioned()) { delay(100); }
//   // getSsid() / getPassword() / getDeviceId() are now valid
//   ProvisioningService::stop();

class ProvisioningService
{
public:
    // Generate a UUID v4 for this device (or load from NVS if already created).
    // Call once before begin(); store the result in NVS and in gDeviceId.
    static String getOrCreateDeviceId();

    // Start BLE server and advertising.
    // deviceId must already be set — it is served as a readable characteristic.
    static void begin(const char *deviceName, const String &deviceId);

    // Stop BLE and free resources.
    static void stop();

    // True once both SSID and password have been written by the app.
    static bool isProvisioned();

    static const String &getSsid();
    static const String &getPassword();
    static const String &getDeviceId();

    // Internal — called by BLE write callbacks; do not call directly.
    static void _onSsidWritten    (const String &v);
    static void _onPasswordWritten(const String &v);

private:
    static String ssid_;
    static String password_;
    static String deviceId_;   // set in begin(), served read-only over BLE
    static bool   ssidSet_;
    static bool   passwordSet_;
};
