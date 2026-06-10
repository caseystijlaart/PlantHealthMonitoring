/**
 * @file WiFiCommunication.cpp
 * @brief Implementation of WiFiCommunication. WiFi connection management with credentials set at runtime.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "WiFiCommunication.hpp"
#include "CloudLogger.hpp"

#include <WiFi.h>

void WiFiCommunication::SetCredentials(const String &ssid, const String &password)
{
    ssid_     = ssid;
    password_ = password;
}

void WiFiCommunication::EnsureConnected()
{
    if (WiFi.status() == WL_CONNECTED)
        return;
    if (!HasCredentials())
    {
        Log.log("[WiFi] No credentials — skipping");
        return;
    }

    Log.logf("[WiFi] Connecting to %s", ssid_.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid_.c_str(), password_.c_str());

    const unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 30000UL)
    {
        delay(500);
    }

    if (WiFi.status() == WL_CONNECTED)
        Log.logf("[WiFi] Connected — IP: %s", WiFi.localIP().toString().c_str());
    else
        Log.log("[WiFi] Connection timed out");
}

bool WiFiCommunication::IsConnected() const
{
    return WiFi.status() == WL_CONNECTED;
}

bool WiFiCommunication::HasCredentials() const
{
    return ssid_.length() > 0;
}
