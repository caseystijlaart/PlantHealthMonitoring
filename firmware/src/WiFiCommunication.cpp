#include "WiFiCommunication.hpp"

#include <WiFi.h>


WiFiCommunication::WiFiCommunication(const char *ssid, const char *password)
    : ssid_(ssid), password_(password)
{
}

void WiFiCommunication::Connect()
{
    if (!HasCredentials())
    {
        Serial.println("WIFI_SSID is empty; WiFi disabled");
        return;
    }

    if (WiFi.status() == WL_CONNECTED)
    {
        Serial.print("WiFi connected. IP: ");
        Serial.println(WiFi.localIP());
        delay(1000);
        return;
    }

    Serial.print("Connecting to WiFi SSID: ");
    Serial.println(ssid_);

    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid_, password_);

    const unsigned long startedAt = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 30000)
    {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED)
    {
        Serial.print("WiFi connected. IP: ");
        Serial.println(WiFi.localIP());
        delay(1000);
    }
    else
    {
        Serial.println("WiFi connection timed out");
    }
}

bool WiFiCommunication::IsConnected() const
{
    return WiFi.status() == WL_CONNECTED;
}

bool WiFiCommunication::HasCredentials() const
{
    return String(ssid_).length() > 0;
}

IPAddress WiFiCommunication::LocalIp() const
{
    return WiFi.localIP();
}
