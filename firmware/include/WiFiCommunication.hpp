/**
 * @file WiFiCommunication.hpp
 * @brief WiFi connection management with credentials set at runtime.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>

/**
 * @brief Manages WiFi connection using credentials that can be set at runtime.
 */
class WiFiCommunication
{
public:
    WiFiCommunication() = default;

    /**
     * @brief Sets the WiFi credentials. Call before EnsureConnected().
     * @param ssid name of the wifi
     * @param password wifi password
     */
    void SetCredentials(const String &ssid, const String &password);

    /**
     * @brief Connects to WiFi if not already connected. No-op with empty credentials.
     */
    void EnsureConnected();

    /**
     * @brief Check whether the wifi is connected
     * @return @c true while the WiFi link is up.
     */
    bool IsConnected() const;

    /**
     * @brief Validates if the wifi has credentials.
     * @return @c true once non-empty credentials have been set.
     */
    bool HasCredentials() const;

private:
    String ssid_;
    String password_;
};
