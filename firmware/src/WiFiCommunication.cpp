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
        Log.println(F("[WiFi] No credentials — skipping"));
        return;
    }

    Log.printf("[WiFi] Connecting to %s\n", ssid_.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid_.c_str(), password_.c_str());

    const unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 30000UL)
    {
        delay(500);
    }

    if (WiFi.status() == WL_CONNECTED)
        Log.printf("[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
    else
        Log.println(F("[WiFi] Connection timed out"));
}

bool WiFiCommunication::IsConnected() const
{
    return WiFi.status() == WL_CONNECTED;
}

bool WiFiCommunication::HasCredentials() const
{
    return ssid_.length() > 0;
}
