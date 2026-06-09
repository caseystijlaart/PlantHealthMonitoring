/**
 * @file main.cpp
 * @brief PlantHealthMonitor ESP32 firmware — main application entry point.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <esp_system.h>

#include "MonitoringSystem.hpp"
#include "FileStorageService.hpp"
#include "TimeService.hpp"
#include "Certs.hpp"
#include "NvsStorage.hpp"
#include "ProvisioningService.hpp"

/** Configuration */
const char *const kSupabaseBase = "https://yjjpgvsycxlaqubvedoa.supabase.co/rest/v1";
const char *const kReadingsEndpoint = "/plant_readings"; ///< Sensor readings table.
const char *const kDevicesEndpoint = "/devices";         ///< Device registry table.
const char *const kSettingsEndpoint = "/plant_settings"; ///< Per-plant settings table.
const char *const kHistoryFile = "/sensor_history.csv";  ///< Local LittleFS history file.
const char *const kPairingFile = "/pairing_state.txt";   ///< LittleFS pairing document.

constexpr unsigned long kIntervalMs = 1000UL * 60UL * 60UL * 3UL; ///< Monitoring cycle interval (3 h).
constexpr unsigned long kCommandCheckMs = 5000UL;                 ///< Command poll interval (5 s).
constexpr std::size_t kHistorySize = 56;                          ///< Local history ring-buffer depth.
constexpr uint8_t kMaxNoPlantTicks = 30;                          ///< Grace period before reset when plant label is missing (30 ticks = 2.5 minutes).

/** Monitoring subsystems */
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

/** Global state loaded from NVS and/or pairing document */
String gWifiSsid;     ///< WiFi SSID — loaded from pairing document.
String gWifiPassword; ///< WiFi password — loaded from pairing document.
String gApiKey;       ///< Supabase anon key — received over BLE during provisioning.
String gDeviceId;     ///< Device UUID — generated once and stored in NVS.
String gPlantLabel;   ///< Plant label — fetched from plant_settings after pairing.
String gDeviceName;   ///< Human-readable device name derived from MAC address.

unsigned long lastRun = 0;
unsigned long lastCommandCheck = 0;
uint8_t currentVersion = 0;
uint8_t gNoPlantCount = 0;     ///< Consecutive ticks with no plant label while running.
bool gJustProvisioned = false; ///< True when BLE provisioning ran in this boot session.

// ---------------------------------------------------------------------------
// Helper — device name
// ---------------------------------------------------------------------------

/**
 * @brief Derives a unique device name from the last three bytes of the MAC address.
 * @return Device name in the form @c PHM-AABBCC.
 */
String DeriveDeviceName()
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char name[12];
    snprintf(name, sizeof(name), "PHM-%02X%02X%02X", mac[3], mac[4], mac[5]);
    return String(name);
}

// ---------------------------------------------------------------------------
// Pairing document helpers
// ---------------------------------------------------------------------------

/**
 * @brief Removes a single trailing CR from @p s.
 * @param s String to strip in place.
 */
void StripTrailingCr(String &s)
{
    if (s.endsWith("\r"))
        s.remove(s.length() - 1);
}

/**
 * @brief Writes the pairing document to LittleFS.
 *
 * When @p paired is @c true the WiFi credentials and API key are written
 * alongside the state; when @c false only "unpaired" is written, erasing
 * all stored secrets.
 *
 * @param paired   Whether the device is paired with the app.
 * @param ssid     WiFi SSID (used when @p paired is @c true).
 * @param password WiFi password (used when @p paired is @c true).
 * @param apiKey   Supabase anon key (used when @p paired is @c true).
 */
void SetPairedWithApp(bool paired,
                      const String &ssid = "",
                      const String &password = "",
                      const String &apiKey = "")
{
    File f = LittleFS.open(kPairingFile, "w");
    if (!f)
    {
        Serial.println(F("[FS] Failed to write pairing document"));
        return;
    }
    if (paired)
    {
        f.print("paired\n");
        f.print(ssid);
        f.print('\n');
        f.print(password);
        f.print('\n');
        f.print(apiKey);
        f.print('\n');
    }
    else
    {
        f.print("unpaired\n");
    }
    f.close();
    Serial.printf("[FS] Pairing document → %s\n", paired ? "paired" : "unpaired");
}

/**
 * @brief Reads the pairing document from LittleFS.
 *
 * If the file does not exist it is created in the unpaired state.
 *
 * @param[out] ssidOut     WiFi SSID.
 * @param[out] passwordOut WiFi password.
 * @param[out] apiKeyOut   Supabase anon key.
 * @return @c true if the device is paired, @c false otherwise.
 */
bool ReadPairingDoc(String &ssidOut, String &passwordOut, String &apiKeyOut)
{
    ssidOut = passwordOut = apiKeyOut = "";

    if (!LittleFS.exists(kPairingFile))
    {
        Serial.println(F("[FS] Pairing document not found — creating as unpaired"));
        SetPairedWithApp(false);
        return false;
    }

    File f = LittleFS.open(kPairingFile, "r");
    if (!f)
        return false;

    String state = f.readStringUntil('\n');
    StripTrailingCr(state);
    const bool paired = state.startsWith("paired");

    if (paired)
    {
        ssidOut = f.readStringUntil('\n');
        passwordOut = f.readStringUntil('\n');
        apiKeyOut = f.readStringUntil('\n');
        StripTrailingCr(ssidOut);
        StripTrailingCr(passwordOut);
        StripTrailingCr(apiKeyOut);
    }
    f.close();
    return paired;
}

// ---------------------------------------------------------------------------
// Local history
// ---------------------------------------------------------------------------

/**
 * @brief Deletes the local sensor history file from LittleFS.
 */
void ClearLocalHistory()
{
    if (LittleFS.exists(kHistoryFile))
    {
        LittleFS.remove(kHistoryFile);
        Serial.println(F("[FS] Sensor history cleared"));
    }
}

// ---------------------------------------------------------------------------
// WiFi
// ---------------------------------------------------------------------------

/**
 * @brief Connects to WiFi using the credentials stored in @c gWifiSsid and
 *        @c gWifiPassword. No-op if already connected or credentials are empty.
 */
void ConnectWifi()
{
    if (WiFi.status() == WL_CONNECTED)
        return;
    if (gWifiSsid.isEmpty())
    {
        Serial.println(F("[WiFi] No credentials — skipping"));
        return;
    }

    Serial.printf("[WiFi] Connecting to %s\n", gWifiSsid.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.begin(gWifiSsid.c_str(), gWifiPassword.c_str());

    const unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 30000UL)
    {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED)
        Serial.printf("[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
    else
        Serial.println(F("[WiFi] Connection timed out"));
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

/**
 * @brief Adds the Supabase authentication headers to an HTTPClient instance.
 * @param https HTTPClient to configure.
 */
void AddSupabaseAuth(HTTPClient &https)
{
    https.addHeader(F("apikey"), gApiKey);
    https.addHeader(F("Authorization"), "Bearer " + gApiKey);
}

/**
 * @brief Sends an HTTPS POST request with a JSON body.
 * @param url  Target URL.
 * @param json JSON payload.
 * @return @c true on HTTP 2xx, @c false otherwise.
 */
bool HttpsPost(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddSupabaseAuth(https);
    https.addHeader(F("Prefer"), F("return=minimal"));

    const int code = https.POST(json);
    Serial.printf("[HTTP] POST %s → %d\n", url.c_str(), code);
    https.end();
    return code >= 200 && code < 300;
}

/**
 * @brief Sends an HTTPS GET request and returns the response body.
 * @param url Target URL.
 * @return Response body, or an empty string on failure.
 */
String HttpsGet(const String &url)
{
    if (WiFi.status() != WL_CONNECTED)
        return "";

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return "";

    AddSupabaseAuth(https);

    const int code = https.GET();
    if (code <= 0)
    {
        https.end();
        return "";
    }

    const String body = https.getString();
    https.end();
    return body;
}

/**
 * @brief Sends an HTTPS PATCH request with a JSON body.
 * @param url  Target URL.
 * @param json JSON payload.
 * @return @c true on HTTP 2xx, @c false otherwise.
 */
bool HttpsPatch(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddSupabaseAuth(https);
    https.addHeader(F("Prefer"), F("return=minimal"));

    const int code = https.sendRequest("PATCH", json);
    Serial.printf("[HTTP] PATCH %s → %d\n", url.c_str(), code);
    https.end();
    return code >= 200 && code < 300;
}

// ---------------------------------------------------------------------------
// Cloud operations
// ---------------------------------------------------------------------------

/**
 * @brief Upserts the device row in Supabase with status "active" and a
 *        current @c last_seen timestamp.
 *
 * @note Called only from RunProvisioningMode(). Subsequent boots call
 *       UpdateLastSeen() instead to avoid unauthorised inserts.
 */
void RegisterDevice()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    String json;
    json.reserve(160);
    json = "{\"device_id\":\"";
    json += gDeviceId;
    json += "\",\"status\":\"active\"";
    if (nowUnix > 0)
    {
        char buf[21];
        strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ",
                 gmtime(reinterpret_cast<const time_t *>(&nowUnix)));
        json += ",\"last_seen\":\"";
        json += buf;
        json += "\"";
    }
    json += "}";

    const String url = String(kSupabaseBase) + kDevicesEndpoint;
    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddSupabaseAuth(https);
    https.addHeader(F("Prefer"), F("resolution=merge-duplicates,return=minimal"));

    const int code = https.POST(json);
    Serial.printf("[Cloud] Device registration → %d\n", code);
    https.end();
}

/**
 * @brief Deletes this device's row from the Supabase devices table.
 *
 * Called immediately before a factory reset so the database is cleaned up
 * at the same time as local state.
 */
void DeleteDeviceFromDb()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = String(kSupabaseBase) + kDevicesEndpoint + "?device_id=eq." + gDeviceId;
    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    AddSupabaseAuth(https);
    const int code = https.sendRequest("DELETE");
    Serial.printf("[Cloud] Device self-delete → %d\n", code);
    https.end();
}

/**
 * @brief PATCHes the @c last_seen timestamp on the device row.
 *
 * Called after each monitoring cycle to allow the app to determine whether
 * the device is currently online.
 */
void UpdateLastSeen()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    if (nowUnix <= 0)
        return;

    char buf[21];
    const time_t t = static_cast<time_t>(nowUnix);
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));

    const String url = String(kSupabaseBase) + kDevicesEndpoint + "?device_id=eq." + gDeviceId;
    HttpsPatch(url, String("{\"last_seen\":\"") + buf + "\"}");
    Serial.printf("[Cloud] last_seen → %s\n", buf);
}

/**
 * @brief Fetches the plant label associated with this device from
 *        @c plant_settings and stores it in @c gPlantLabel.
 * @return @c true if a label was found and stored, @c false otherwise.
 */
bool FetchPlantLabelByDeviceId()
{
    const String url = String(kSupabaseBase) + kSettingsEndpoint + "?device_id=eq." + gDeviceId + "&select=plant_label&limit=1";

    const String body = HttpsGet(url);
    if (body.isEmpty() || body == "[]")
    {
        Serial.println(F("[Cloud] No plant_settings row for this device"));
        return false;
    }

    const int idx = body.indexOf("\"plant_label\":\"");
    if (idx < 0)
        return false;

    const int start = idx + 15;
    const int end = body.indexOf('"', start);
    if (end < 0)
        return false;

    gPlantLabel = body.substring(start, end);
    Serial.printf("[Cloud] Plant label: %s\n", gPlantLabel.c_str());
    return true;
}

/**
 * @brief Parses a preference band value from a JSON payload.
 * @param payload JSON string.
 * @param key     Preference key to look up.
 * @return Parsed @c PreferenceBand value.
 */
PreferenceBand ParsePreference(const String &payload, const char *key)
{
    if (payload.indexOf(String(key) + "\":\"pLow\"") >= 0)
        return PreferenceBand::pLow;
    if (payload.indexOf(String(key) + "\":\"pHigh\"") >= 0)
        return PreferenceBand::pHigh;
    return PreferenceBand::pMid;
}

/**
 * @brief Applies parsed preference values from a JSON payload to the monitoring system.
 * @param payload JSON string containing preference fields.
 */
void ApplyProfilePayload(const String &payload)
{
    PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    profile.preferences.humidity = ParsePreference(payload, "humidity_preference");
    profile.preferences.light = ParsePreference(payload, "light_preference");
    profile.preferences.soilMoisture = ParsePreference(payload, "soil_preference");
    profile.preferences.temperature = ParsePreference(payload, "temperature_preference");
    monitoringSystem.SetPlantProfile(profile);
}

/**
 * @brief Fetches the plant profile from Supabase and applies it if the version
 *        has changed since the last fetch.
 * @return @c true if settings were fetched successfully, @c false otherwise.
 */
bool FetchProfileSettings()
{
    if (gPlantLabel.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = String(kSupabaseBase) + kSettingsEndpoint + "?plant_label=eq." + gPlantLabel + "&select=*&limit=1";

    const String payload = HttpsGet(url);
    if (payload.isEmpty() || payload == "[]")
        return false;
    if (payload.indexOf("\"plant_label\":\"" + gPlantLabel + "\"") < 0)
        return false;

    int latestVersion = 0;
    const int vIdx = payload.indexOf("\"version\":");
    if (vIdx >= 0)
        latestVersion = payload.substring(vIdx + 10).toInt();

    if (latestVersion == currentVersion)
    {
        Serial.println(F("[Cloud] Profile up to date"));
        return true;
    }

    ApplyProfilePayload(payload);
    currentVersion = static_cast<uint8_t>(latestVersion);
    Serial.println(F("[Cloud] Profile updated"));
    return true;
}

/**
 * @brief Uploads a sensor reading JSON string to Supabase.
 * @param json Serialised reading payload.
 */
void SendToCloud(const char *json)
{
    const String url = String(kSupabaseBase) + kReadingsEndpoint;
    if (!HttpsPost(url, json))
        Serial.println(F("[Cloud] Upload failed"));
}

/**
 * @brief Polls @c trigger_reset on the device row; performs a full factory
 *        reset and reboots into BLE provisioning mode if the flag is set.
 */
void CheckTriggerReset()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = String(kSupabaseBase) + kDevicesEndpoint + "?device_id=eq." + gDeviceId + "&select=trigger_reset&limit=1";

    if (HttpsGet(url).indexOf("\"trigger_reset\":true") < 0)
        return;

    Serial.println(F("[Cloud] trigger_reset — performing factory reset"));
    ClearLocalHistory();
    SetPairedWithApp(false);
    DeleteDeviceFromDb();
    NvsStorage::clearAll();
    delay(500);
    ESP.restart();
}

/**
 * @brief Polls @c trigger_measurement on the device row; clears the flag
 *        and returns @c true if an immediate measurement cycle should run.
 * @return @c true if the flag was set, @c false otherwise.
 */
bool CheckTriggerMeasurement()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = String(kSupabaseBase) + kDevicesEndpoint + "?device_id=eq." + gDeviceId + "&select=trigger_measurement&limit=1";

    if (HttpsGet(url).indexOf("\"trigger_measurement\":true") < 0)
        return false;

    Serial.println(F("[Cloud] trigger_measurement — running immediate cycle"));
    const String patchUrl = String(kSupabaseBase) + kDevicesEndpoint + "?device_id=eq." + gDeviceId;
    HttpsPatch(patchUrl, "{\"trigger_measurement\":false}");
    return true;
}

/**
 * @brief Runs one full sensor + ML + cloud upload cycle.
 */
void RunMonitoringCycle()
{
    const MonitoringCycleResult result = monitoringSystem.RunCycleDetailed();
    fileStorage.AppendToHistoryFile(kHistoryFile, result,
                                    gPlantLabel.c_str(), gDeviceId.c_str(),
                                    kHistorySize);

    if (gPlantLabel.isEmpty())
    {
        Serial.println(F("[Cycle] No plant label — skipping upload"));
        return;
    }

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    const auto &snap = result.snapshot;
    const auto &rec = result.recommendation;

    char json[512];
    snprintf(json, sizeof(json),
             "{\"request_id\":%lld,"
             "\"plant_label\":\"%s\","
             "\"device_id\":\"%s\","
             "\"soil_moisture_pct\":%.2f,\"temperature_c\":%.2f,"
             "\"humidity_pct\":%.2f,\"light_level_pct\":%.2f,"
             "\"action_water\":%s,\"action_reduce_temp\":%s,"
             "\"action_increase_light\":%s,"
             "\"recommendation_summary\":\"%s\","
             "\"risk_class\":%d}",
             static_cast<long long>(nowUnix),
             gPlantLabel.c_str(), gDeviceId.c_str(),
             snap.soilMoisturePct, snap.temperatureC,
             snap.humidityPct, snap.lightLevelPct,
             rec.water ? "true" : "false",
             rec.reduceTemp ? "true" : "false",
             rec.increaseLight ? "true" : "false",
             rec.summary,
             static_cast<int>(result.mlResult.risk));

    SendToCloud(json);
}

// ---------------------------------------------------------------------------
// BLE provisioning
// ---------------------------------------------------------------------------

/**
 * @brief Blocks until the app completes BLE provisioning (WiFi credentials +
 *        API key received), then connects to WiFi and registers the device.
 *
 * On successful completion @c gJustProvisioned is set to @c true so that
 * setup() does not immediately reset the device while the app is showing
 * the plant-setup screen.
 */
void RunProvisioningMode()
{
    Serial.println(F("[Prov] Entering BLE provisioning mode"));

    gDeviceId = ProvisioningService::getOrCreateDeviceId();
    ProvisioningService::begin(gDeviceName.c_str(), gDeviceId);

    while (!ProvisioningService::isProvisioned())
    {
        delay(100);
        yield();
    }

    gWifiSsid = ProvisioningService::getSsid();
    gWifiPassword = ProvisioningService::getPassword();
    gApiKey = ProvisioningService::getApiKey();

    Serial.println(F("[Prov] Credentials received — stopping BLE"));
    ProvisioningService::stop();

    ConnectWifi();
    if (WiFi.status() != WL_CONNECTED)
    {
        Serial.println(F("[Prov] WiFi failed — rebooting"));
        NvsStorage::clearAll();
        delay(2000);
        ESP.restart();
        return;
    }

    timeService.SyncTimeWithNtp(10000);
    RegisterDevice();

    NvsStorage::writeString("device_id", gDeviceId);
    SetPairedWithApp(true, gWifiSsid, gWifiPassword, gApiKey);

    gJustProvisioned = true;
    Serial.println(F("[Prov] Provisioning complete"));
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

/**
 * @brief Arduino setup — runs once on boot.
 */
void setup()
{
    Serial.begin(115200);
    delay(200);
    LittleFS.begin(true);

    gDeviceId = NvsStorage::readString("device_id");
    gDeviceName = DeriveDeviceName();
    Serial.printf("[Init] Device name: %s\n", gDeviceName.c_str());

    const bool paired = ReadPairingDoc(gWifiSsid, gWifiPassword, gApiKey);
    if (!paired)
    {
        Serial.println(F("[Init] Not paired — entering BLE provisioning mode"));
        RunProvisioningMode();
    }
    else
    {
        Serial.printf("[Init] Paired — device_id: %s\n", gDeviceId.c_str());
    }

    ConnectWifi();

    if (WiFi.status() == WL_CONNECTED)
    {
        timeService.SyncTimeWithNtp(10000);
        const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
        if (nowUnix > 0)
            monitoringSystem.SetStartUnixTime(nowUnix);

        UpdateLastSeen();
    }

    if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
    {
        FetchPlantLabelByDeviceId();

        if (gPlantLabel.isEmpty() && !gJustProvisioned)
        {
            Serial.println(F("[Init] Paired but no plant_settings — resetting"));
            ClearLocalHistory();
            SetPairedWithApp(false);
            DeleteDeviceFromDb();
            NvsStorage::clearAll();
            delay(500);
            ESP.restart();
        }
    }

    FetchProfileSettings();

    PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    strncpy(profile.plantName, gPlantLabel.c_str(), sizeof(profile.plantName) - 1);
    strncpy(profile.deviceId, gDeviceId.c_str(), sizeof(profile.deviceId) - 1);
    strncpy(profile.deviceName, gDeviceName.c_str(), sizeof(profile.deviceName) - 1);
    monitoringSystem.SetPlantProfile(profile);

    std::size_t existingEntries = 0;
    const auto snapshots = fileStorage.LoadHistoryFile(kHistoryFile, kHistorySize, existingEntries);
    if (!snapshots.empty())
    {
        monitoringSystem.LoadHistoricalSnapshots(snapshots);
        Serial.printf("[Init] Restored %u snapshots\n", static_cast<unsigned>(snapshots.size()));
    }

    if (!monitoringSystem.Init())
    {
        Serial.println(F("[Init] Monitoring system failed to initialise"));
        while (true)
        {
        }
    }

    Serial.println(F("[Init] Ready"));

    if (!gPlantLabel.isEmpty())
    {
        RunMonitoringCycle();
        UpdateLastSeen();
    }
    else
    {
        Serial.println(F("[Init] Waiting for plant setup in app"));
    }

    lastRun = lastCommandCheck = millis();
}

/**
 * @brief Arduino loop — runs continuously after setup().
 */
void loop()
{
    const unsigned long now = millis();

    if (now - lastCommandCheck >= kCommandCheckMs)
    {
        lastCommandCheck = now;

        if (WiFi.status() != WL_CONNECTED)
            ConnectWifi();

        if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
        {
            if (FetchPlantLabelByDeviceId())
            {
                Serial.println(F("[Loop] Plant label acquired — running first cycle"));
                FetchProfileSettings();
                PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
                strncpy(profile.plantName, gPlantLabel.c_str(), sizeof(profile.plantName) - 1);
                monitoringSystem.SetPlantProfile(profile);
                RunMonitoringCycle();
                UpdateLastSeen();
                lastRun = now;
                gNoPlantCount = gJustProvisioned = 0;
            }
            else
            {
                if (++gNoPlantCount >= kMaxNoPlantTicks)
                {
                    Serial.println(F("[Loop] Grace period expired — resetting"));
                    ClearLocalHistory();
                    SetPairedWithApp(false);
                    DeleteDeviceFromDb();
                    NvsStorage::clearAll();
                    delay(500);
                    ESP.restart();
                }
                Serial.printf("[Loop] No plant label (%u/%u)\n", gNoPlantCount, kMaxNoPlantTicks);
            }
        }
        else if (!gPlantLabel.isEmpty())
        {
            gNoPlantCount = gJustProvisioned = 0;
        }

        CheckTriggerReset();

        if (CheckTriggerMeasurement())
        {
            RunMonitoringCycle();
            UpdateLastSeen();
            lastRun = now;
        }
    }

    if (now - lastRun < kIntervalMs)
        return;

    lastRun = now;
    if (WiFi.status() != WL_CONNECTED)
        ConnectWifi();
    FetchProfileSettings();
    RunMonitoringCycle();
    UpdateLastSeen();
}
