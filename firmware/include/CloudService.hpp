/**
 * @file CloudService.hpp
 * @brief Supabase REST client for the devices, plant_settings, plant_readings, and model_metrics tables.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>
#include "PlantTypes.hpp"

/**
 * @brief Handles all Supabase REST API communication.
 *
 * The base URL and API key are loaded from the pairing document at boot
 * (received from the app over BLE during provisioning) so the firmware
 * binary itself contains no hardcoded secrets.
 */
class CloudService
{
public:
    CloudService() = default;

    /** @brief Sets the Supabase project URL and anon key. */
    void SetConfig(const String &supabaseBase, const String &apiKey);

    /** @brief Upserts the device row with status "active", its name and the current timestamp. */
    void RegisterDevice(const String &deviceId, const String &deviceName, std::int64_t nowUnix);

    /** @brief Deletes this device's row from the devices table. */
    void DeleteDevice(const String &deviceId);

    /** @brief PATCHes the last_seen timestamp on the device row. */
    void UpdateLastSeen(const String &deviceId, std::int64_t nowUnix);

    /** @brief PATCHes the model_version on the device row (called once per boot). */
    void ReportModelVersion(const String &deviceId, const char *modelVersion);

    /**
     * @brief Fetches the plant label for this device from plant_settings.
     * @param[out] outLabel Populated on success.
     * @return true if a label was found.
     */
    bool FetchPlantLabel(const String &deviceId, String &outLabel);

    /**
     * @brief Fetches plant preferences and applies them to the MonitoringSystem.
     * @param[out] outProfile Updated with fetched preferences.
     * @param[out] outVersion Updated with the fetched version number.
     * @return true if settings were fetched.
     */
    bool FetchProfileSettings(const String &plantLabel,
                              PlantRuleProfile &outProfile,
                              uint8_t &outVersion,
                              uint8_t currentVersion);

    /** @brief POSTs a JSON reading payload to plant_readings. */
    void SendReading(const char *json);

    /** @brief POSTs a JSON model-performance payload to model_metrics. */
    void SendModelMetrics(const char *json);

    /**
     * @brief Polls trigger_reset; returns true if the flag was set.
     * Does NOT perform the reset itself.
     */
    bool CheckTriggerReset(const String &deviceId);

    /**
     * @brief Polls trigger_measurement; clears the flag and returns true if set.
     */
    bool CheckTriggerMeasurement(const String &deviceId);

private:
    bool Post(const String &url, const String &json);
    String Get(const String &url);
    bool Patch(const String &url, const String &json);
    void AddAuth(class HTTPClient &https);

    static PreferenceBand ParsePreference(const String &payload, const char *key);

    String base_;
    String apiKey_;

    static constexpr const char *kReadingsEndpoint = "/plant_readings";
    static constexpr const char *kMetricsEndpoint = "/model_metrics";
    static constexpr const char *kDevicesEndpoint = "/devices";
    static constexpr const char *kSettingsEndpoint = "/plant_settings";
};
