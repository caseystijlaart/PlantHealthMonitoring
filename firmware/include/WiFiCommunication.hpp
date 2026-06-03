#pragma once

#include <Arduino.h>

class WiFiCommunication
{
public:
    WiFiCommunication(const char *ssid, const char *password);

    void Connect();
    bool IsConnected() const;
    bool HasCredentials() const;
    IPAddress LocalIp() const;

private:
    const char *ssid_;
    const char *password_;
};
