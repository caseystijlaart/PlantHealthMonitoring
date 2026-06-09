/**
 * @file ProvisioningService.hpp
 * @brief BLE provisioning service for the PlantHealthMonitor ESP32 firmware.
 */

#pragma once

#include <Arduino.h>

/**
 * @brief BLE UUIDs for the PHM provisioning service.
 *
 * All UUIDs must match the values declared in the Flutter app
 * (@c lib/services/ble_constants.dart).
 */
static constexpr const char *kProvisionServiceUuid  = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static constexpr const char *kSsidCharUuid          = "beb5483e-36e1-4688-b7f5-ea07361b26a8"; ///< WRITE
static constexpr const char *kPasswordCharUuid      = "beb5483e-36e1-4688-b7f5-ea07361b26a9"; ///< WRITE
static constexpr const char *kDeviceIdCharUuid      = "beb5483e-36e1-4688-b7f5-ea07361b26aa"; ///< READ
static constexpr const char *kApiKeyCharUuid        = "beb5483e-36e1-4688-b7f5-ea07361b26ab"; ///< WRITE
static constexpr const char *kSupabaseUrlCharUuid   = "beb5483e-36e1-4688-b7f5-ea07361b26ac"; ///< WRITE

/**
 * @brief Static BLE provisioning service.
 *
 * Manages the BLE server lifecycle and exposes characteristics for receiving
 * WiFi credentials, the Supabase API key, and Supabase URL from the phone app,
 * and for serving the device UUID back to the app.
 */
class ProvisioningService
{
public:
    static String getOrCreateDeviceId();
    static void begin(const char *deviceName, const String &deviceId);
    static void stop();

    /** @return true once SSID, password, API key, and Supabase URL have all been written. */
    static bool isProvisioned();

    static const String &getSsid();
    static const String &getPassword();
    static const String &getDeviceId();
    static const String &getApiKey();
    static const String &getSupabaseUrl();

    /// @cond INTERNAL
    static void _onSsidWritten        (const String &v);
    static void _onPasswordWritten    (const String &v);
    static void _onApiKeyWritten      (const String &v);
    static void _onSupabaseUrlWritten (const String &v);
    /// @endcond

private:
    static String ssid_;
    static String password_;
    static String deviceId_;
    static String apiKey_;
    static String supabaseUrl_;
    static bool   ssidSet_;
    static bool   passwordSet_;
    static bool   apiKeySet_;
    static bool   supabaseUrlSet_;
};
