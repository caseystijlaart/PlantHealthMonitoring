#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <ArduinoOTA.h>
#include <esp_system.h>   // esp_read_mac()

#include "MonitoringSystem.hpp"
#include "FileStorageService.hpp"
#include "TimeService.hpp"
#include "Certs.hpp"
#include "NvsStorage.hpp"
#include "ProvisioningService.hpp"

#ifndef API_KEY
#error "API_KEY must be defined in secrets.ini"
#endif

// WIFI_SSID / WIFI_PASSWORD / PLANT_LABEL / DEVICE_ID are OPTIONAL compile-time
// defines.  When absent the firmware enters BLE provisioning mode on first boot
// and loads its identity from NVS thereafter.
//
// Legacy environments (esp32_com3_non_local, esp32_com4_non_local …) still
// define all four constants and skip provisioning entirely, preserving
// backwards compatibility.

#ifndef PLANT_LABEL
#define PLANT_LABEL ""   // empty → fetched from Supabase by device_id
#endif

// DEVICE_NAME is optional.
//   Legacy builds define it explicitly (e.g. "ESP32_COM3").
//   Provisioning builds leave it undefined; the name is derived at runtime
//   from the last three bytes of the MAC address → "PHM-A1B2C3".

namespace
{

// Supabase endpoints
const char *const kSupabaseBase     = "https://yjjpgvsycxlaqubvedoa.supabase.co/rest/v1";
const char *const kReadingsEndpoint = "/plant_readings";
const char *const kDevicesEndpoint  = "/devices";
const char *const kSettingsEndpoint = "/plant_settings";
const char *const kHistoryFile      = "/sensor_history.csv";

// ── App pairing document ──────────────────────────────────────────────────────
// Stored on LittleFS so it survives reboots independently of NVS.
//
// This single document holds BOTH the pairing state and the WiFi credentials.
// Keeping the credentials *inside* the pairing document — and nowhere else — is
// a deliberate privacy decision:
//
//   * WiFi credentials never leave the device.  They are sent to the ESP32 once
//     over BLE during provisioning and are NOT stored in the cloud database.
//   * Because the credentials live in the pairing document, marking the device
//     "unpaired" erases them by construction — an unpaired device retains no
//     WiFi secrets.
//
// File format (newline-separated, written with a bare '\n'):
//
//   line 1: "paired" | "unpaired"
//   line 2: WiFi SSID        (only written when paired)
//   line 3: WiFi password    (only written when paired)
//
// This is the only gate that controls whether the device is allowed to start
// up normally, and the only place WiFi credentials are persisted.
const char *const kPairingFile = "/pairing_state.txt";

void ClearLocalHistory()
{
    if (LittleFS.exists(kHistoryFile))
    {
        LittleFS.remove(kHistoryFile);
        Serial.println(F("[FS] Sensor history cleared"));
    }
}

// Strip a single trailing '\r' so credentials saved by older firmware (which
// used println → "\r\n" line endings) read back cleanly.  Only '\r' is removed
// so that legitimate trailing spaces in a password are preserved.
void StripTrailingCr(String &s)
{
    if (s.endsWith("\r"))
        s.remove(s.length() - 1);
}

// Write the pairing document.  When paired, the WiFi credentials are stored
// alongside the state; when unpaired, only "unpaired" is written, which deletes
// any previously stored credentials.
void SetPairedWithApp(bool paired, const String &ssid = "", const String &password = "")
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
        f.print(ssid);     f.print('\n');
        f.print(password); f.print('\n');
    }
    else
    {
        f.print("unpaired\n");   // no credentials — unpaired devices store no secrets
    }
    f.close();
    Serial.printf("[FS] Pairing document → %s%s\n",
                  paired ? "paired" : "unpaired",
                  paired ? " (+ WiFi credentials)" : " (credentials cleared)");
}

// Read the pairing document.  Returns true if the device is paired; on success
// the stored WiFi credentials are returned via ssidOut / passwordOut.
bool ReadPairingDoc(String &ssidOut, String &passwordOut)
{
    ssidOut     = "";
    passwordOut = "";

    if (!LittleFS.exists(kPairingFile))
    {
        // First boot — create the document in the default unpaired state.
        Serial.println(F("[FS] pairing_state.txt not found — creating as 'unpaired'"));
        SetPairedWithApp(false);
        return false;
    }

    File f = LittleFS.open(kPairingFile, "r");
    if (!f) return false;

    String state = f.readStringUntil('\n');
    StripTrailingCr(state);
    const bool paired = state.startsWith("paired");

    if (paired)
    {
        ssidOut     = f.readStringUntil('\n');
        passwordOut = f.readStringUntil('\n');
        StripTrailingCr(ssidOut);
        StripTrailingCr(passwordOut);
    }
    f.close();
    return paired;
}

constexpr unsigned long kIntervalMs         = 1000UL * 60UL * 60UL * 3UL; // 3 hours
constexpr unsigned long kCommandCheckMs     = 5000UL;                      // 5 seconds
constexpr std::size_t   kHistorySize        = 56;

// ── Sensors & subsystems (same pins as before) ────────────────────────────────
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

// ── Runtime identity (loaded from compile-time defines or NVS) ────────────────
String gWifiSsid;
String gWifiPassword;
String gDeviceId;      // UUID string for provisioned devices; "1"/"2" for legacy
String gPlantLabel;
String gDeviceName;    // set in setup() — compile-time for legacy, MAC-derived for provisioning
bool   gLegacyDevice = false;

// ── Device name derivation ────────────────────────────────────────────────────

String DeriveDeviceName()
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char name[12]; // "PHM-" + 6 hex digits + null terminator
    snprintf(name, sizeof(name), "PHM-%02X%02X%02X", mac[3], mac[4], mac[5]);
    return String(name);
}

unsigned long lastRun          = 0;
unsigned long lastCommandCheck = 0;
uint8_t       currentVersion   = 0;
uint8_t       gNoPlantCount    = 0;   // consecutive 30 s ticks with no plant label while running
bool          gJustProvisioned = false; // true when BLE provisioning ran in this boot session

// 120 ticks × 5 s = 10 minutes grace period before resetting a running device
// that has lost its plant_settings row.  Not applied at boot — that resets immediately.
// Also used as the waiting period after fresh provisioning so the user has time
// to complete plant setup in the app before the device gives up.
constexpr uint8_t kMaxNoPlantTicks = 120;

// ── WiFi ─────────────────────────────────────────────────────────────────────

void ConnectWifi()
{
    if (WiFi.status() == WL_CONNECTED)
        return;
    if (gWifiSsid.isEmpty())
    {
        Serial.println(F("No WiFi credentials — skipping connect"));
        return;
    }

    Serial.print(F("Connecting to WiFi: "));
    Serial.println(gWifiSsid);
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
    {
        Serial.print(F("WiFi connected. IP: "));
        Serial.println(WiFi.localIP());
    }
    else
    {
        Serial.println(F("WiFi timed out"));
    }
}

// ── Generic HTTPS POST / GET helpers ─────────────────────────────────────────

bool HttpsPost(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"),  F("application/json"));
    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);
    https.addHeader(F("Prefer"),        F("return=minimal"));

    const int code = https.POST(json);
    Serial.printf("[HTTP] POST %s → %d\n", url.c_str(), code);
    https.end();
    return code >= 200 && code < 300;
}

String HttpsGet(const String &url)
{
    if (WiFi.status() != WL_CONNECTED)
        return "";

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return "";

    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);

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

bool HttpsPatch(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"),  F("application/json"));
    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);
    https.addHeader(F("Prefer"),        F("return=minimal"));

    const int code = https.sendRequest("PATCH", json);
    Serial.printf("[HTTP] PATCH %s → %d\n", url.c_str(), code);
    https.end();
    return code >= 200 && code < 300;
}

// ── Device registration ───────────────────────────────────────────────────────
// Called on every boot after WiFi connects (upsert — safe to call repeatedly).
// Sets status = 'active' and stamps last_seen so the app can show online state.

void RegisterDevice()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = String(kSupabaseBase) + kDevicesEndpoint;

    // Build payload with last_seen if NTP time is available
    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    String json;
    json.reserve(160);
    json  = "{\"device_id\":\"";
    json += gDeviceId;
    json += "\",\"status\":\"active\"";
    if (nowUnix > 0)
    {
        char timeBuf[21];
        const time_t t = static_cast<time_t>(nowUnix);
        strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));
        json += ",\"last_seen\":\"";
        json += timeBuf;
        json += "\"";
    }
    json += "}";

    // Upsert: inserts on first provisioning, updates on every subsequent boot
    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader(F("Content-Type"),  F("application/json"));
    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);
    https.addHeader(F("Prefer"),        F("resolution=merge-duplicates,return=minimal"));

    const int code = https.POST(json);
    Serial.printf("[Cloud] Device registration → %d\n", code);
    https.end();
}

// ── Device self-delete ────────────────────────────────────────────────────────
// Called just before the device clears NVS and reboots into BLE mode so the
// devices table row is cleaned up.  The app set trigger_reset (or the grace
// period expired / setup was cancelled), so the row is no longer needed.

void DeleteDeviceFromDb()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = String(kSupabaseBase) + kDevicesEndpoint
                       + "?device_id=eq." + gDeviceId;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader(F("apikey"),        API_KEY);
    https.addHeader(F("Authorization"), "Bearer " API_KEY);

    const int code = https.sendRequest("DELETE");
    Serial.printf("[Cloud] Device self-delete → %d\n", code);
    https.end();
}

// ── Update last_seen timestamp ────────────────────────────────────────────────
// Lightweight PATCH called after each monitoring cycle so the app can tell
// whether the device is currently online (last_seen within the last ~4 hours).

void UpdateLastSeen()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    if (nowUnix <= 0)
        return;

    char timeBuf[21];
    const time_t t = static_cast<time_t>(nowUnix);
    strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));

    const String url = String(kSupabaseBase) + kDevicesEndpoint
                       + "?device_id=eq." + gDeviceId;

    String json = "{\"last_seen\":\"";
    json += timeBuf;
    json += "\"}";

    HttpsPatch(url, json);
    Serial.printf("[Cloud] last_seen → %s\n", timeBuf);
}

// ── Plant label lookup (provisioned devices only) ─────────────────────────────

bool FetchPlantLabelByDeviceId()
{
    const String url = String(kSupabaseBase) + kSettingsEndpoint
                       + "?device_id=eq." + gDeviceId
                       + "&select=plant_label&limit=1";

    const String body = HttpsGet(url);
    if (body.isEmpty() || body == "[]")
    {
        Serial.println(F("[Cloud] No plant_settings row for this device yet"));
        return false;
    }

    // Body: [{"plant_label":"..."}]
    const int idx = body.indexOf("\"plant_label\":\"");
    if (idx < 0)
        return false;

    const int start = idx + 15;
    const int end   = body.indexOf('"', start);
    if (end < 0)
        return false;

    gPlantLabel = body.substring(start, end);
    Serial.printf("[Cloud] Plant label: %s\n", gPlantLabel.c_str());
    return true;
}

// ── Profile settings ──────────────────────────────────────────────────────────

pof02::PreferenceBand ParsePreference(const String &payload, const char *key)
{
    if (payload.indexOf(String(key) + "\":\"pLow\"")  >= 0) return pof02::PreferenceBand::pLow;
    if (payload.indexOf(String(key) + "\":\"pHigh\"") >= 0) return pof02::PreferenceBand::pHigh;
    return pof02::PreferenceBand::pMid;
}

void ApplyProfilePayload(const String &payload)
{
    pof02::PlantRuleProfile profile   = monitoringSystem.GetPlantProfile();
    profile.preferences.humidity      = ParsePreference(payload, "humidity_preference");
    profile.preferences.light         = ParsePreference(payload, "light_preference");
    profile.preferences.soilMoisture  = ParsePreference(payload, "soil_preference");
    profile.preferences.temperature   = ParsePreference(payload, "temperature_preference");
    monitoringSystem.SetPlantProfile(profile);
}

bool FetchProfileSettings()
{
    if (gPlantLabel.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = String(kSupabaseBase) + kSettingsEndpoint
                       + "?plant_label=eq." + gPlantLabel
                       + "&select=*&limit=1";

    const String payload = HttpsGet(url);
    if (payload.isEmpty() || payload == "[]")
        return false;

    if (payload.indexOf("\"plant_label\":\"" + gPlantLabel + "\"") < 0)
    {
        Serial.println(F("[Cloud] No settings row for this plant label"));
        return false;
    }

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

// ── Cloud: send reading ───────────────────────────────────────────────────────

void SendToCloud(const char *json)
{
    const String url = String(kSupabaseBase) + kReadingsEndpoint;
    if (!HttpsPost(url, json))
        Serial.println(F("[Cloud] Upload failed"));
}

// ── Factory-reset command poll ────────────────────────────────────────────────
// Called when the app removes a device from Settings > Connected Devices.
// Wipes NVS (WiFi credentials + device_id) and reboots into provisioning mode.
// Historical readings and the device row in Supabase are left intact.

void CheckTriggerReset()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = String(kSupabaseBase) + kDevicesEndpoint
                       + "?device_id=eq." + gDeviceId
                       + "&select=trigger_reset&limit=1";

    const String body = HttpsGet(url);
    if (body.indexOf("\"trigger_reset\":true") < 0)
        return;

    Serial.println(F("[Cloud] trigger_reset set — device removed by app"));

    // Full reset to factory state: clear local history, mark unpaired,
    // remove the DB row, wipe NVS credentials.
    ClearLocalHistory();
    SetPairedWithApp(false);
    DeleteDeviceFromDb();
    NvsStorage::clearAll();

    delay(500);
    ESP.restart();
}

// ── Trigger-measurement command poll ─────────────────────────────────────────

bool CheckTriggerMeasurement()
{
    if (gDeviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = String(kSupabaseBase) + kDevicesEndpoint
                       + "?device_id=eq." + gDeviceId
                       + "&select=trigger_measurement&limit=1";

    const String body = HttpsGet(url);
    if (body.indexOf("\"trigger_measurement\":true") < 0)
        return false;

    Serial.println(F("[Cloud] trigger_measurement set — running immediate cycle"));

    // Clear the flag
    const String patchUrl = String(kSupabaseBase) + kDevicesEndpoint
                            + "?device_id=eq." + gDeviceId;
    HttpsPatch(patchUrl, "{\"trigger_measurement\":false}");
    return true;
}

// ── Monitoring cycle ──────────────────────────────────────────────────────────

void RunMonitoringCycle()
{
    const pof02::MonitoringCycleResult result = monitoringSystem.RunCycleDetailed();
    fileStorage.AppendToHistoryFile(kHistoryFile, result,
                                    gPlantLabel.c_str(), gDeviceId.c_str(),
                                    kHistorySize);

    if (gPlantLabel.isEmpty())
    {
        Serial.println(F("[Cycle] No plant label — skipping cloud upload"));
        return;
    }

    const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
    const auto &snap = result.snapshot;
    const auto &rec  = result.recommendation;

    char json[512];
    snprintf(json, sizeof(json),
        "{\"request_id\":%lld,"
        "\"plant_label\":\"%s\","
        "\"soil_moisture_pct\":%.2f,\"temperature_c\":%.2f,"
        "\"humidity_pct\":%.2f,\"light_level_pct\":%.2f,"
        "\"action_water\":%s,\"action_reduce_temp\":%s,"
        "\"action_increase_light\":%s,"
        "\"recommendation_summary\":\"%s\","
        "\"risk_class\":%d}",
        static_cast<long long>(nowUnix),
        gPlantLabel.c_str(),
        snap.soilMoisturePct, snap.temperatureC,
        snap.humidityPct, snap.lightLevelPct,
        rec.water         ? "true" : "false",
        rec.reduceTemp    ? "true" : "false",
        rec.increaseLight ? "true" : "false",
        rec.summary,
        static_cast<int>(result.mlResult.risk));

    SendToCloud(json);
}

// ── Provisioning flow (blocks until complete) ─────────────────────────────────

void RunProvisioningMode()
{
    Serial.println(F("[Prov] Entering BLE provisioning mode"));

    // Generate (or reload) the device UUID before advertising —
    // the app will read it from the device, not write it.
    gDeviceId = ProvisioningService::getOrCreateDeviceId();

    ProvisioningService::begin(gDeviceName.c_str(), gDeviceId);

    while (!ProvisioningService::isProvisioned())
    {
        delay(100);
        yield();
    }

    gWifiSsid     = ProvisioningService::getSsid();
    gWifiPassword = ProvisioningService::getPassword();
    // gDeviceId was already set above — no need to read it back

    Serial.println(F("[Prov] Credentials received — stopping BLE"));
    ProvisioningService::stop();

    // Attempt WiFi
    ConnectWifi();
    if (WiFi.status() != WL_CONNECTED)
    {
        Serial.println(F("[Prov] WiFi failed — clearing credentials and rebooting"));
        NvsStorage::clearAll();
        delay(2000);
        ESP.restart();
        return;
    }

    // Sync time before registering
    timeService.SyncTimeWithNtp(10000);

    // Register device in Supabase — this is the one and only place the device
    // is allowed to INSERT itself into the devices table, because the app just
    // explicitly authorised it by sending WiFi credentials over BLE.
    RegisterDevice();

    // Persist the device UUID to NVS (identity, not a secret).
    NvsStorage::writeString("device_id", gDeviceId);

    // Mark as paired and persist the WiFi credentials inside the pairing
    // document.  The credentials live only here on the device — never in NVS and
    // never in the cloud database — and are erased automatically on unpair.
    SetPairedWithApp(true, gWifiSsid, gWifiPassword);

    // Remember that provisioning ran in this session so setup() knows not to
    // do an immediate reset if plant_settings doesn't exist yet — the app is
    // about to show the plant setup screen and the user needs time to fill it in.
    gJustProvisioned = true;

    Serial.println(F("[Prov] Provisioning complete"));
}

} // namespace

// ── Arduino entry points ──────────────────────────────────────────────────────

void setup()
{
    Serial.begin(115200);
    delay(200);
    LittleFS.begin(true);

    // ── Load identity ─────────────────────────────────────────────────────────
#ifdef WIFI_SSID
    // Legacy device: credentials baked into firmware at compile time
    gLegacyDevice = true;
    gWifiSsid     = WIFI_SSID;
    gWifiPassword = WIFI_PASSWORD;
    gDeviceId     = String(DEVICE_ID);
    gPlantLabel   = PLANT_LABEL;
    gDeviceName   = DEVICE_NAME;          // compile-time name (e.g. "ESP32_COM3")
    Serial.printf("[Init] Legacy device #%s / plant '%s'\n",
                  gDeviceId.c_str(), gPlantLabel.c_str());
#else
    // Provisioned device: identity (device UUID) lives in NVS; the WiFi
    // credentials live in the local pairing document.
    gDeviceId     = NvsStorage::readString("device_id");
    gDeviceName   = DeriveDeviceName();   // unique per board: "PHM-A1B2C3"
    Serial.printf("[Init] Device name: %s\n", gDeviceName.c_str());

    const bool paired = ReadPairingDoc(gWifiSsid, gWifiPassword);
    if (!paired)
    {
        // Not paired with the app yet (or was removed by the app).
        // Enter BLE provisioning and wait — the device stays here until
        // the user adds it through the phone app.
        Serial.println(F("[Init] Not paired — entering BLE provisioning mode"));
        RunProvisioningMode();
    }
    else
    {
        // Migration: older firmware kept the credentials in NVS and only the
        // pairing *state* in the document.  If this device was paired before the
        // upgrade, move the NVS credentials into the pairing document and wipe
        // them from NVS so secrets live in exactly one place.
        if (gWifiSsid.isEmpty())
        {
            const String nvsSsid = NvsStorage::readString("ssid");
            const String nvsPass = NvsStorage::readString("password");
            if (!nvsSsid.isEmpty())
            {
                Serial.println(F("[Init] Migrating WiFi credentials from NVS into pairing document"));
                gWifiSsid     = nvsSsid;
                gWifiPassword = nvsPass;
                SetPairedWithApp(true, gWifiSsid, gWifiPassword);
            }
        }
        // Always clear any legacy NVS credentials — they must not linger there.
        NvsStorage::remove("ssid");
        NvsStorage::remove("password");

        Serial.printf("[Init] Paired — loaded credentials from pairing document (device_id: %s)\n",
                      gDeviceId.c_str());
    }
#endif

    // ── WiFi + OTA ────────────────────────────────────────────────────────────
    ConnectWifi();

    if (WiFi.status() == WL_CONNECTED)
    {
#ifdef OTA_PASSWORD
        ArduinoOTA.setHostname(gDeviceName.c_str());
        ArduinoOTA.setPassword(OTA_PASSWORD);
        ArduinoOTA.begin();
        Serial.println(F("[OTA] Ready"));
#endif
        timeService.SyncTimeWithNtp(10000);
        const std::int64_t nowUnix = timeService.GetCurrentUnixTimeUtc();
        if (nowUnix > 0)
            monitoringSystem.SetStartUnixTime(nowUnix);

        // Only update last_seen — never INSERT a new devices row here.
        // A device may only add itself to the database during BLE provisioning
        // (RunProvisioningMode), when the app explicitly authorised it by
        // sending WiFi credentials.  On every subsequent boot we just stamp
        // the existing row.  If the row no longer exists (e.g. the app deleted
        // the device while it was offline) the PATCH is a silent no-op and the
        // 10-minute grace period will eventually reboot into BLE mode so the
        // user can re-add it properly through the app.
#ifndef WIFI_SSID
        UpdateLastSeen();
#endif
    }

    // ── Fetch plant label (provisioned builds) ────────────────────────────────
#ifndef WIFI_SSID
    if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
    {
        FetchPlantLabelByDeviceId();

        // If we loaded credentials from NVS (previous session) but there is no
        // plant_settings row, the setup was never completed or was removed.
        // Reset immediately so the user can re-add via the app.
        //
        // Do NOT reset if provisioning just ran in this session — the app is
        // about to show the plant setup screen and the user needs time to save.
        // The loop grace period handles that case instead.
        if (gPlantLabel.isEmpty() && !gJustProvisioned)
        {
            Serial.println(F("[Init] Paired but no plant_settings found — resetting to BLE mode"));
            ClearLocalHistory();
            SetPairedWithApp(false);
            DeleteDeviceFromDb();
            NvsStorage::clearAll();
            delay(500);
            ESP.restart();
        }
    }
#endif

    // ── Apply profile ─────────────────────────────────────────────────────────
    FetchProfileSettings();

    pof02::PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
    strncpy(profile.plantName,  gPlantLabel.c_str(),  sizeof(profile.plantName)  - 1);
    strncpy(profile.deviceId,   gDeviceId.c_str(),    sizeof(profile.deviceId)   - 1);
    strncpy(profile.deviceName, gDeviceName.c_str(),  sizeof(profile.deviceName) - 1);
    monitoringSystem.SetPlantProfile(profile);

    // ── Restore history from flash ────────────────────────────────────────────
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
        while (true) {}
    }

    Serial.println(F("[Init] Monitoring system ready"));

    if (!gPlantLabel.isEmpty())
    {
        RunMonitoringCycle();
        UpdateLastSeen();
    }
    else
    {
        // Just provisioned — waiting for user to complete plant setup in the app.
        // The loop will poll every 30 s and run the first cycle as soon as the
        // plant_settings row appears.
        Serial.println(F("[Init] Waiting for plant setup in app (polling every 30 s)"));
    }

    lastRun          = millis();
    lastCommandCheck = millis();
}

void loop()
{
#ifdef OTA_PASSWORD
    ArduinoOTA.handle();
#endif

    const unsigned long now = millis();

    // ── Command poll (every 30 s) ─────────────────────────────────────────────
    if (now - lastCommandCheck >= kCommandCheckMs)
    {
        lastCommandCheck = now;

        if (WiFi.status() != WL_CONNECTED)
            ConnectWifi();

#ifndef WIFI_SSID
        if (gPlantLabel.isEmpty() && !gDeviceId.isEmpty())
        {
            if (FetchPlantLabelByDeviceId())
            {
                // Plant label just appeared (user finished setup in app).
                // Apply profile and run the first cycle immediately.
                Serial.println(F("[Loop] Plant label acquired — running first cycle"));
                FetchProfileSettings();
                pof02::PlantRuleProfile profile = monitoringSystem.GetPlantProfile();
                strncpy(profile.plantName, gPlantLabel.c_str(), sizeof(profile.plantName) - 1);
                monitoringSystem.SetPlantProfile(profile);
                RunMonitoringCycle();
                UpdateLastSeen();
                lastRun          = now;
                gNoPlantCount    = 0;
                gJustProvisioned = false;
            }
            else
            {
                // Still no plant_settings — apply grace period before resetting.
                // This covers both fresh provisioning (user filling in the app)
                // and a running device that lost its plant_settings row.
                gNoPlantCount++;
                Serial.printf("[Loop] No plant label (%u/%u)\n", gNoPlantCount, kMaxNoPlantTicks);

                if (gNoPlantCount >= kMaxNoPlantTicks)
                {
                    Serial.println(F("[Loop] Grace period expired — resetting to BLE mode"));
                    ClearLocalHistory();
                    SetPairedWithApp(false);
                    DeleteDeviceFromDb();
                    NvsStorage::clearAll();
                    delay(500);
                    ESP.restart();
                }
            }
        }
        else if (!gPlantLabel.isEmpty())
        {
            // Plant label healthy — reset the counter
            gNoPlantCount    = 0;
            gJustProvisioned = false;
        }

        // Only provisioned devices support remote factory reset
        CheckTriggerReset();
#endif

        if (CheckTriggerMeasurement())
        {
            RunMonitoringCycle();
            UpdateLastSeen();
            lastRun = now; // reset the regular timer so we don't double-fire
        }
    }

    // ── Regular 3-hour cycle ──────────────────────────────────────────────────
    if (now - lastRun < kIntervalMs)
        return;

    lastRun = now;

    if (WiFi.status() != WL_CONNECTED)
        ConnectWifi();

    FetchProfileSettings();
    RunMonitoringCycle();
    UpdateLastSeen();
}
