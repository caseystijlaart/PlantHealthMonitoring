#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <ArduinoOTA.h>

#include "MonitoringSystem.hpp"
#include "FileStorageService.hpp"
#include "TimeService.hpp"
#include "Certs.hpp"

#ifndef WIFI_SSID
#error "WIFI_SSID must be defined in secrets.ini"
#endif

#ifndef WIFI_PASSWORD
#error "WIFI_PASSWORD must be defined in secrets.ini"
#endif

#ifndef API_KEY
#error "API_KEY must be defined in secrets.ini"
#endif

#ifndef PLANT_LABEL
#define PLANT_LABEL "UNSET_PLANT"
#endif

#ifndef DEVICE_NAME
#define DEVICE_NAME "UNSET_DEVICE"
#endif

#ifndef DEVICE_ID
#define DEVICE_ID 0
#endif

namespace
{

const char *const kApiUrl         = "https://yjjpgvsycxlaqubvedoa.supabase.co/rest/v1/plant_readings";
const char *const kApiUrlSettings = "https://yjjpgvsycxlaqubvedoa.supabase.co/rest/v1/plant_settings"
                                    "?plant_label=eq." PLANT_LABEL "&select=*&limit=1";
const char *const kHistoryFile    = "/sensor_history.csv";

constexpr unsigned long kIntervalMs  = 1000UL * 60UL * 60UL * 3UL; // 3 hours
constexpr std::size_t   kHistorySize = 56;                           // 1 week at 3 h intervals

pof02::SoilMoistureSensor  soilSensor(34, 3500.0f, 1450.0f);
pof02::TempHumiditySensor  dhtSensor(4, 22);
pof02::LightSensor         lightSensor(35);
pof02::MLLayer             mlLayer(pof02::MLBackend::TINYML_TFLM);
pof02::RecommendationEngine recEngine;
pof02::MonitoringSystem     monitoringSystem(soilSensor, dhtSensor, lightSensor,
                                             mlLayer, recEngine,
                                             pof02::PlantRuleProfile{}, kHistorySize);
TimeService        timeService;
FileStorageService fileStorage(timeService);

unsigned long lastRun = 0;
uint8_t       currentVersion = 0; // starts at 0 so first fetch always applies

// ---------------------------------------------------------------------------
// WiFi helpers
// ---------------------------------------------------------------------------

void ConnectWifi()
{
    if (WiFi.status() == WL_CONNECTED)
        return;

    Serial.print(F("Connecting to WiFi..."));
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    const unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 30000UL)
    {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED)
    {
        Serial.print(F("WiFi connected. IP: "));
        Serial.println(WiFi.localIP());
    }
    else
    {
        Serial.println(F("WiFi connection timed out"));
    }
}

// ---------------------------------------------------------------------------
// Cloud communication
// ---------------------------------------------------------------------------

void SendToCloud(const char *json)
{
    if (WiFi.status() != WL_CONNECTED)
    {
        Serial.println(F("No WiFi, skipping cloud upload"));
        return;
    }

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);

    HTTPClient https;
    if (!https.begin(client, kApiUrl))
    {
        Serial.println(F("HTTPS begin failed"));
        return;
    }

    https.addHeader(F("Content-Type"),  F("application/json"));
    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);
    https.addHeader(F("Prefer"),        F("return=minimal"));

    const int code = https.POST(json);
    Serial.print(F("Cloud response: "));
    Serial.println(code);
    https.end();
}

// ---------------------------------------------------------------------------
// Profile settings
// ---------------------------------------------------------------------------

pof02::PreferenceBand ParsePreference(const String &payload, const char *key)
{
    if (payload.indexOf(String(key) + "\":\"pLow\"") >= 0) return pof02::PreferenceBand::pLow;
    if (payload.indexOf(String(key) + "\":\"pHigh\"") >= 0) return pof02::PreferenceBand::pHigh;
    return pof02::PreferenceBand::pMid;
}

void ApplyProfilePayload(const String &payload)
{
    pof02::PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    profile.preferences.humidity    = ParsePreference(payload, "humidityPreference");
    profile.preferences.light       = ParsePreference(payload, "lightPreference");
    profile.preferences.soilMoisture = ParsePreference(payload, "soilPreference");
    profile.preferences.temperature = ParsePreference(payload, "temperaturePreference");
    monitoringSystem.SetPlantProfile(profile);
}

bool FetchProfileSettings()
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);

    HTTPClient https;
    if (!https.begin(client, kApiUrlSettings))
        return false;

    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);

    const int code = https.GET();
    if (code <= 0)
        return false;

    const String payload = https.getString();
    https.end();

    if (payload.indexOf("\"plant_label\":\"" PLANT_LABEL "\"") < 0)
    {
        Serial.println(F("No settings found for this plant label"));
        return false;
    }

    int latestVersion = 0;
    const int vIdx = payload.indexOf("\"version\":");
    if (vIdx >= 0)
        latestVersion = payload.substring(vIdx + 10).toInt();

    if (latestVersion == currentVersion)
    {
        Serial.println(F("Profile settings up to date"));
        return true;
    }

    ApplyProfilePayload(payload);
    currentVersion = static_cast<uint8_t>(latestVersion);
    Serial.println(F("Profile settings updated"));
    return true;
}

// ---------------------------------------------------------------------------
// Monitoring cycle
// ---------------------------------------------------------------------------

void RunMonitoringCycle()
{
    const pof02::MonitoringCycleResult result = monitoringSystem.RunCycleDetailed();
    fileStorage.AppendToHistoryFile(kHistoryFile, result, PLANT_LABEL, DEVICE_ID, kHistorySize);

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    const auto &snap = result.snapshot;
    const auto &rec  = result.recommendation;

    char json[512];
    snprintf(json, sizeof(json),
        "{\"request_id\":%lld,\"plant_label\":\"" PLANT_LABEL "\","
        "\"device_id\":%d,"
        "\"soil_moisture_pct\":%.2f,\"temperature_c\":%.2f,"
        "\"humidity_pct\":%.2f,\"light_level_pct\":%.2f,"
        "\"action_water\":%s,\"action_reduce_temp\":%s,"
        "\"action_increase_light\":%s,"
        "\"recommendation_summary\":\"%s\","
        "\"risk_class\":%d}",
        static_cast<long long>(nowUnix),
        DEVICE_ID,
        snap.soilMoisturePct, snap.temperatureC,
        snap.humidityPct, snap.lightLevelPct,
        rec.water          ? "true" : "false",
        rec.reduceTemp     ? "true" : "false",
        rec.increaseLight  ? "true" : "false",
        rec.summary,
        static_cast<int>(result.mlResult.risk));

    SendToCloud(json);
}

} // namespace

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

void setup()
{
    Serial.begin(115200);
    delay(200);

    LittleFS.begin(true);

    ConnectWifi();

    if (WiFi.status() == WL_CONNECTED)
    {
        ArduinoOTA.setHostname(DEVICE_NAME);
        ArduinoOTA.setPassword(OTA_PASSWORD);
        ArduinoOTA.begin();
        Serial.println(F("OTA ready"));

        timeService.SyncTimeWithNtp(10000);
        const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
        if (nowUnix > 0)
            monitoringSystem.SetStartUnixTime(nowUnix);
    }

    // Load preferences from Supabase; keep whatever is fetched for the rest of setup
    FetchProfileSettings();

    // Apply device identity on top of whatever preferences were loaded
    pof02::PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    strncpy(profile.plantName,  PLANT_LABEL,         sizeof(profile.plantName)  - 1);
    strncpy(profile.deviceName, DEVICE_NAME,          sizeof(profile.deviceName) - 1);
    snprintf(profile.deviceId,  sizeof(profile.deviceId), "%d", DEVICE_ID);
    monitoringSystem.SetPlantProfile(profile);

    std::size_t existingEntries = 0;
    const auto snapshots = fileStorage.LoadHistoryFile(kHistoryFile, kHistorySize, existingEntries);
    if (!snapshots.empty())
    {
        monitoringSystem.LoadHistoricalSnapshots(snapshots);
        Serial.printf("Restored %u snapshots (%u on file)\n",
                      static_cast<unsigned>(snapshots.size()),
                      static_cast<unsigned>(existingEntries));
    }

    if (!monitoringSystem.Init())
    {
        Serial.println(F("Failed to initialise monitoring system"));
        while (true) {}
    }

    Serial.println(F("Monitoring system ready"));
    RunMonitoringCycle();
    lastRun = millis();
}

void loop()
{
    ArduinoOTA.handle();

    const unsigned long now = millis();
    if (now - lastRun < kIntervalMs)
        return;

    lastRun = now;

    if (WiFi.status() != WL_CONNECTED)
        ConnectWifi();

    FetchProfileSettings();
    RunMonitoringCycle();
}
