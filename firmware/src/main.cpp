/**
 * @file main.cpp
 * @brief PlantHealthMonitor ESP32 firmware — main application entry point.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <esp_system.h>

#include "MonitoringSystem.hpp"
#include "FileStorageService.hpp"
#include "TimeService.hpp"
#include "NvsStorage.hpp"
#include "ProvisioningService.hpp"
#include "WiFiCommunication.hpp"
#include "CloudService.hpp"
#include "CloudLogger.hpp"
#include "Certs.hpp"
#include "ModelExport.hpp"

/** File paths */
static constexpr const char *kHistoryFile = "/sensor_history.csv";

/** Timing constants */
constexpr unsigned long kIntervalMs = 1000UL * 60UL * 60UL * 3UL; ///< 3-hour monitoring cycle.
constexpr unsigned long kCommandCheckMs = 5000UL;                 ///< Command poll interval (5 s).
constexpr std::size_t kHistorySize = 56;
constexpr uint8_t kMaxNoPlantTicks = 30;

/** ML model generation baked into this firmware (stamped by retrain_from_logs.py). */
constexpr const char *kModelVersion = modelexport::kModelVersion;

/** Subsystems */
SoilMoistureSensor soilSensor(34, 3500.0f, 1450.0f);
TempHumiditySensor dhtSensor(4, 22);
LightSensor lightSensor(35);
MLLayer mlLayer(MLBackend::TINYML_TFLM);
RecommendationEngine recEngine;
MonitoringSystem monitoringSystem(soilSensor, dhtSensor, lightSensor,
                                  mlLayer, recEngine,
                                  PlantRuleProfile{}, kHistorySize);
TimeService timeService;
FileStorageService fileStorage(timeService);
WiFiCommunication wifi;
CloudService cloud;

/** Global state */
String gDeviceId;
String gPlantLabel;
String gDeviceName;

unsigned long lastRun = 0;
unsigned long lastCommandCheck = 0;
uint8_t currentVersion = 0;
uint8_t gNoPlantCount = 0;
bool gJustProvisioned = false;

/** helper functions */
static String DeriveDeviceName()
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char name[12];
    snprintf(name, sizeof(name), "PHM-%02X%02X%02X", mac[3], mac[4], mac[5]);
    return String(name);
}

static void PerformFactoryReset()
{
    // Flush any pending logs while we still have a device_id and credentials —
    // after the wipe + reboot they'd be lost.
    Log.uploadPending(gDeviceId, gDeviceName);

    fileStorage.ClearHistory(kHistoryFile);
    fileStorage.WriteUnpaired();
    cloud.DeleteDevice(gDeviceId);
    NvsStorage::clearAll();
    delay(500);
    ESP.restart();
}

static void RunMonitoringCycle()
{
    const MonitoringCycleResult result = monitoringSystem.RunCycleDetailed();
    fileStorage.AppendToHistoryFile(kHistoryFile, result,
                                    gPlantLabel.c_str(), gDeviceId.c_str(),
                                    kHistorySize);

    if (gPlantLabel.isEmpty())
    {
        Log.println(F("[Cycle] No plant label — skipping upload"));
        return;
    }

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    const auto &snap = result.snapshot;
    const auto &rec = result.recommendation;

    // plant_readings is plant-scoped: the app queries/subscribes by plant_label
    // and never reads device_id from this table, and device_id is volatile
    // (regenerated on re-provision), so it is intentionally left out here.
    char json[640];
    snprintf(json, sizeof(json),
             "{\"request_id\":%lld,"
             "\"plant_label\":\"%s\","
             "\"soil_moisture_pct\":%.2f,\"temperature_c\":%.2f,"
             "\"humidity_pct\":%.2f,\"light_level_pct\":%.2f,"
             "\"action_water\":%s,\"action_reduce_temp\":%s,"
             "\"action_increase_light\":%s,"
             "\"recommendation_summary\":\"%s\","
             "\"risk_class\":%d,"
             "\"confidence\":%.3f,"
             "\"model_version\":\"%s\"}",
             static_cast<long long>(nowUnix),
             gPlantLabel.c_str(),
             snap.soilMoisturePct, snap.temperatureC,
             snap.humidityPct, snap.lightLevelPct,
             rec.water ? "true" : "false",
             rec.reduceTemp ? "true" : "false",
             rec.increaseLight ? "true" : "false",
             rec.summary,
             static_cast<int>(result.mlResult.risk),
             result.mlResult.confidence,
             kModelVersion);

    cloud.SendReading(json);
}

/** Provisioning mode */
static void RunProvisioningMode()
{
    Log.println(F("[Prov] Entering BLE provisioning mode"));

    gDeviceId = ProvisioningService::getOrCreateDeviceId();
    ProvisioningService::begin(gDeviceName.c_str(), gDeviceId);

    while (!ProvisioningService::isProvisioned())
    {
        delay(100);
        yield();
        ProvisioningService::maintainAdvertising(); // re-advertise if a setup was cancelled
    }

    const String ssid = ProvisioningService::getSsid();
    const String password = ProvisioningService::getPassword();
    const String apiKey = ProvisioningService::getApiKey();
    const String supabaseUrl = ProvisioningService::getSupabaseUrl();

    Log.println(F("[Prov] Credentials received — stopping BLE"));
    ProvisioningService::stop();

    wifi.SetCredentials(ssid, password);
    wifi.EnsureConnected();

    if (!wifi.IsConnected())
    {
        Log.println(F("[Prov] WiFi failed — rebooting"));
        NvsStorage::clearAll();
        delay(2000);
        ESP.restart();
        return;
    }

    // Remove trailing /rest/v1 if the app sent just the project URL.
    String base = supabaseUrl;
    if (!base.endsWith("/rest/v1"))
        base += "/rest/v1";

    cloud.SetConfig(base, apiKey);

    timeService.SyncTimeWithNtp(10000);
    cloud.RegisterDevice(gDeviceId, gDeviceName, timeService.GetCurrentUnixTimeUtc());

    NvsStorage::writeString("device_id", gDeviceId);
    fileStorage.WritePaired(ssid, password, apiKey, supabaseUrl);

    gJustProvisioned = true;
    Log.println(F("[Prov] Provisioning complete"));
}

/** Main application entry point */
void setup()
{
    Serial.begin(115200);
    delay(200);

    gDeviceId = NvsStorage::readString("device_id");
    gDeviceName = DeriveDeviceName();
    Log.printf("[Init] Device name: %s\n", gDeviceName.c_str());

    String ssid, password, apiKey, supabaseUrl;
    const bool paired = fileStorage.ReadPairing(ssid, password, apiKey, supabaseUrl);

    if (!paired)
    {
        Log.println(F("[Init] Not paired — entering BLE provisioning mode"));
        RunProvisioningMode();
        // After RunProvisioningMode returns, re-read the just-written values.
        fileStorage.ReadPairing(ssid, password, apiKey, supabaseUrl);
    }
    else
    {
        Log.printf("[Init] Paired — device_id: %s\n", gDeviceId.c_str());
    }

    String base = supabaseUrl;
    if (!base.endsWith("/rest/v1"))
        base += "/rest/v1";
    cloud.SetConfig(base, apiKey);

    // Mirror serial output to the cloud `logs` table.  Lines emitted earlier in
    // boot/provisioning were queued and flush on the first uploadPending() once
    // WiFi is up.
    Log.configure(base, apiKey, kSupabaseRootCA);

    wifi.SetCredentials(ssid, password);
    wifi.EnsureConnected();

    if (wifi.IsConnected())
    {
        timeService.SyncTimeWithNtp(10000);
        const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
        if (nowUnix > 0)
            monitoringSystem.SetStartUnixTime(nowUnix);
        cloud.UpdateLastSeen(gDeviceId, nowUnix);
        cloud.ReportModelVersion(gDeviceId, kModelVersion);
    }

    if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
    {
        cloud.FetchPlantLabel(gDeviceId, gPlantLabel);

        if (gPlantLabel.isEmpty() && !gJustProvisioned)
        {
            Log.println(F("[Init] Paired but no plant_settings — resetting"));
            PerformFactoryReset();
        }
    }

    PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    cloud.FetchProfileSettings(gPlantLabel, profile, currentVersion, currentVersion);
    strncpy(profile.plantName, gPlantLabel.c_str(), sizeof(profile.plantName) - 1);
    strncpy(profile.deviceId, gDeviceId.c_str(), sizeof(profile.deviceId) - 1);
    strncpy(profile.deviceName, gDeviceName.c_str(), sizeof(profile.deviceName) - 1);
    monitoringSystem.SetPlantProfile(profile);

    std::size_t existingEntries = 0;
    const auto snapshots = fileStorage.LoadHistoryFile(kHistoryFile, kHistorySize, existingEntries);
    if (!snapshots.empty())
    {
        monitoringSystem.LoadHistoricalSnapshots(snapshots);
        Log.printf("[Init] Restored %u snapshots\n", static_cast<unsigned>(snapshots.size()));
    }

    if (!monitoringSystem.Init())
    {
        Log.println(F("[Init] Monitoring system failed to initialise"));
        while (true)
        {
        }
    }

    Log.println(F("[Init] Ready"));

    if (!gPlantLabel.isEmpty())
    {
        RunMonitoringCycle();
        cloud.UpdateLastSeen(gDeviceId, timeService.GetCurrentUnixTimeUtc());
    }
    else
    {
        Log.println(F("[Init] Waiting for plant setup in app"));
    }

    lastRun = lastCommandCheck = millis();

    // Flush everything logged during boot now that we're online.
    Log.uploadPending(gDeviceId, gDeviceName);
}

void loop()
{
    const unsigned long now = millis();

    if (now - lastCommandCheck >= kCommandCheckMs)
    {
        lastCommandCheck = now;

        if (!wifi.IsConnected())
            wifi.EnsureConnected();

        if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
        {
            if (cloud.FetchPlantLabel(gDeviceId, gPlantLabel))
            {
                Log.println(F("[Loop] Plant label acquired — running first cycle"));
                PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
                cloud.FetchProfileSettings(gPlantLabel, profile, currentVersion, currentVersion);
                strncpy(profile.plantName, gPlantLabel.c_str(), sizeof(profile.plantName) - 1);
                monitoringSystem.SetPlantProfile(profile);
                RunMonitoringCycle();
                cloud.UpdateLastSeen(gDeviceId, timeService.GetCurrentUnixTimeUtc());
                lastRun = now;
                gNoPlantCount = gJustProvisioned = 0;
            }
            else
            {
                if (++gNoPlantCount >= kMaxNoPlantTicks)
                {
                    Log.println(F("[Loop] Grace period expired — resetting"));
                    PerformFactoryReset();
                }
                Log.printf("[Loop] No plant label (%u/%u)\n", gNoPlantCount, kMaxNoPlantTicks);
            }
        }
        else if (!gPlantLabel.isEmpty())
        {
            gNoPlantCount = gJustProvisioned = 0;
        }

        if (cloud.CheckTriggerReset(gDeviceId))
        {
            Log.println(F("[Cloud] trigger_reset — performing factory reset"));
            PerformFactoryReset();
        }

        if (cloud.CheckTriggerMeasurement(gDeviceId))
        {
            RunMonitoringCycle();
            cloud.UpdateLastSeen(gDeviceId, timeService.GetCurrentUnixTimeUtc());
            lastRun = now;
        }
        Log.uploadPending(gDeviceId, gDeviceName);
    }

    if (now - lastRun < kIntervalMs)
        return;

    lastRun = now;
    if (!wifi.IsConnected())
        wifi.EnsureConnected();

    PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    cloud.FetchProfileSettings(gPlantLabel, profile, currentVersion, currentVersion);
    monitoringSystem.SetPlantProfile(profile);

    RunMonitoringCycle();
    cloud.UpdateLastSeen(gDeviceId, timeService.GetCurrentUnixTimeUtc());
}
