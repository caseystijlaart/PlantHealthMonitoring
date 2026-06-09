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
 * (@c lib/provisioning.dart).
 */
static constexpr const char *kProvisionServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static constexpr const char *kSsidCharUuid         = "beb5483e-36e1-4688-b7f5-ea07361b26a8"; ///< WRITE
static constexpr const char *kPasswordCharUuid     = "beb5483e-36e1-4688-b7f5-ea07361b26a9"; ///< WRITE (no read)
static constexpr const char *kDeviceIdCharUuid     = "beb5483e-36e1-4688-b7f5-ea07361b26aa"; ///< READ
static constexpr const char *kApiKeyCharUuid       = "beb5483e-36e1-4688-b7f5-ea07361b26ab"; ///< WRITE (no read)

/**
 * @brief Static BLE provisioning service.
 *
 * Manages the BLE server lifecycle and exposes characteristics for receiving
 * WiFi credentials and the Supabase API key from the phone app, and for
 * serving the device UUID back to the app.
 */
class ProvisioningService
{
public:
    /**
     * @brief Returns the device UUID, generating and persisting it in NVS if
     *        this is the first call.
     * @return UUID v4 string.
     */
    static String getOrCreateDeviceId();

    /**
     * @brief Initialises the BLE server and starts advertising.
     * @param deviceName BLE advertised device name.
     * @param deviceId   Device UUID served via the read-only characteristic.
     */
    static void begin(const char *deviceName, const String &deviceId);

    /**
     * @brief Stops BLE advertising and releases BLE resources.
     */
    static void stop();

    /**
     * @brief Returns @c true once SSID, password, and API key have all been
     *        written by the app.
     */
    static bool isProvisioned();

    static const String &getSsid();      ///< @return Received WiFi SSID.
    static const String &getPassword();  ///< @return Received WiFi password.
    static const String &getDeviceId();  ///< @return Device UUID.
    static const String &getApiKey();    ///< @return Received Supabase API key.

    /// @cond INTERNAL
    static void _onSsidWritten    (const String &v);
    static void _onPasswordWritten(const String &v);
    static void _onApiKeyWritten  (const String &v);
    /// @endcond

private:
    static String ssid_;
    static String password_;
    static String deviceId_;
    static String apiKey_;
    static bool   ssidSet_;
    static bool   passwordSet_;
    static bool   apiKeySet_;
};
