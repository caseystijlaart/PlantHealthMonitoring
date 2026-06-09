#pragma once

#include <Arduino.h>

/**
 * @brief Manages WiFi connection using credentials that can be set at runtime.
 */
class WiFiCommunication
{
public:
    WiFiCommunication() = default;

    /** @brief Sets the WiFi credentials. Call before EnsureConnected(). */
    void SetCredentials(const String &ssid, const String &password);

    /** @brief Connects to WiFi if not already connected. No-op with empty credentials. */
    void EnsureConnected();

    bool IsConnected() const;
    bool HasCredentials() const;

private:
    String ssid_;
    String password_;
};
