/**
 * @file CloudService.cpp
 * @brief Implementation of CloudService. Supabase REST client for the devices, plant_settings, plant_readings, and model_metrics tables.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "CloudService.hpp"
#include "CloudLogger.hpp"

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

#include "Certs.hpp"

void CloudService::SetConfig(const String &supabaseBase, const String &apiKey)
{
    base_    = supabaseBase;
    apiKey_  = apiKey;
}

void CloudService::AddAuth(HTTPClient &https)
{
    https.addHeader(F("apikey"), apiKey_);
    https.addHeader(F("Authorization"), "Bearer " + apiKey_);
}

bool CloudService::Post(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddAuth(https);
    https.addHeader(F("Prefer"), F("return=minimal"));

    const int code = https.POST(json);
    Log.logf("[HTTP] POST %s → %d", url.c_str(), code);
    https.end();
    return code >= 200 && code < 300;
}

String CloudService::Get(const String &url)
{
    if (WiFi.status() != WL_CONNECTED)
        return "";

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return "";

    AddAuth(https);
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

bool CloudService::Patch(const String &url, const String &json)
{
    if (WiFi.status() != WL_CONNECTED)
        return false;

    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return false;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddAuth(https);
    https.addHeader(F("Prefer"), F("return=minimal"));

    const int code = https.sendRequest("PATCH", json);
    Log.logf("[HTTP] PATCH %d", code);
    https.end();
    return code >= 200 && code < 300;
}

void CloudService::RegisterDevice(const String &deviceId, const String &deviceName, std::int64_t nowUnix)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    String json;
    json.reserve(192);
    json = "{\"device_id\":\"";
    json += deviceId;
    json += "\",\"status\":\"active\"";
    if (!deviceName.isEmpty())
    {
        json += ",\"device_name\":\"";
        json += deviceName;
        json += "\"";
    }
    if (nowUnix > 0)
    {
        char buf[21];
        const time_t t = static_cast<time_t>(nowUnix);
        strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));
        json += ",\"last_seen\":\"";
        json += buf;
        json += "\"";
    }
    json += "}";

    const String url = base_ + kDevicesEndpoint;
    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader(F("Content-Type"), F("application/json"));
    AddAuth(https);
    https.addHeader(F("Prefer"), F("resolution=merge-duplicates,return=minimal"));

    const int code = https.POST(json);
    Log.logf("[Cloud] Device registration → %d", code);
    https.end();
}

void CloudService::DeleteDevice(const String &deviceId)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = base_ + kDevicesEndpoint + "?device_id=eq." + deviceId;
    WiFiClientSecure client;
    client.setCACert(kSupabaseRootCA);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    AddAuth(https);
    const int code = https.sendRequest("DELETE");
    Log.logf("[Cloud] Device self-delete → %d", code);
    https.end();
}

void CloudService::UpdateLastSeen(const String &deviceId, std::int64_t nowUnix)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED || nowUnix <= 0)
        return;

    char buf[21];
    const time_t t = static_cast<time_t>(nowUnix);
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));

    const String url = base_ + kDevicesEndpoint + "?device_id=eq." + deviceId;
    Patch(url, String("{\"last_seen\":\"") + buf + "\"}");
}

void CloudService::ReportModelVersion(const String &deviceId, const char *modelVersion)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return;

    const String url = base_ + kDevicesEndpoint + "?device_id=eq." + deviceId;
    Patch(url, String("{\"model_version\":\"") + modelVersion + "\"}");
}

bool CloudService::FetchPlantLabel(const String &deviceId, String &outLabel)
{
    const String url = base_ + kSettingsEndpoint
                     + "?device_id=eq." + deviceId
                     + "&select=plant_label&limit=1";

    const String body = Get(url);
    if (body.isEmpty() || body == "[]")
    {
        Log.log("[Cloud] No plant_settings row for this device");
        return false;
    }

    const int idx = body.indexOf("\"plant_label\":\"");
    if (idx < 0)
        return false;

    const int start = idx + 15;
    const int end   = body.indexOf('"', start);
    if (end < 0)
        return false;

    outLabel = body.substring(start, end);
    Log.logf("[Cloud] Plant label: %s", outLabel.c_str());
    return true;
}

PreferenceBand CloudService::ParsePreference(const String &payload, const char *key)
{
    if (payload.indexOf(String(key) + "\":\"pLow\"")  >= 0)
        return PreferenceBand::pLow;
    if (payload.indexOf(String(key) + "\":\"pHigh\"") >= 0)
        return PreferenceBand::pHigh;
    return PreferenceBand::pMid;
}

bool CloudService::FetchProfileSettings(const String &plantLabel,
                                          PlantRuleProfile &outProfile,
                                          uint8_t &outVersion,
                                          uint8_t currentVersion)
{
    if (plantLabel.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = base_ + kSettingsEndpoint
                     + "?plant_label=eq." + plantLabel
                     + "&select=*&limit=1";

    const String payload = Get(url);
    if (payload.isEmpty() || payload == "[]")
        return false;
    if (payload.indexOf("\"plant_label\":\"" + plantLabel + "\"") < 0)
        return false;

    int latestVersion = 0;
    const int vIdx = payload.indexOf("\"version\":");
    if (vIdx >= 0)
        latestVersion = payload.substring(vIdx + 10).toInt();

    if (latestVersion == currentVersion)
    {
        Log.log("[Cloud] Profile up to date");
        return true;
    }

    outProfile.preferences.humidity     = ParsePreference(payload, "humidity_preference");
    outProfile.preferences.light        = ParsePreference(payload, "light_preference");
    outProfile.preferences.soilMoisture = ParsePreference(payload, "soil_preference");
    outProfile.preferences.temperature  = ParsePreference(payload, "temperature_preference");
    outVersion = static_cast<uint8_t>(latestVersion);
    Log.log("[Cloud] Profile updated");
    return true;
}

void CloudService::SendReading(const char *json)
{
    const String url = base_ + kReadingsEndpoint;
    if (!Post(url, json))
        Log.log("[Cloud] Upload failed");
}

void CloudService::SendModelMetrics(const char *json)
{
    const String url = base_ + kMetricsEndpoint;
    if (!Post(url, json))
        Log.log("[Cloud] Metrics upload failed");
}

bool CloudService::CheckTriggerReset(const String &deviceId)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = base_ + kDevicesEndpoint
                     + "?device_id=eq." + deviceId
                     + "&select=trigger_reset&limit=1";

    return Get(url).indexOf("\"trigger_reset\":true") >= 0;
}

bool CloudService::CheckTriggerMeasurement(const String &deviceId)
{
    if (deviceId.isEmpty() || WiFi.status() != WL_CONNECTED)
        return false;

    const String url = base_ + kDevicesEndpoint
                     + "?device_id=eq." + deviceId
                     + "&select=trigger_measurement&limit=1";

    if (Get(url).indexOf("\"trigger_measurement\":true") < 0)
        return false;

    const String patchUrl = base_ + kDevicesEndpoint + "?device_id=eq." + deviceId;
    Patch(patchUrl, "{\"trigger_measurement\":false}");
    Log.log("[Cloud] trigger_measurement — running immediate cycle");
    return true;
}
