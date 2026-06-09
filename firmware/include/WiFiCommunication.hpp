#pragma once

#include <Arduino.h>

/**
 * @brief A class for managing WiFi communication, including connection handling and status checks.
 */
class WiFiCommunication
{
public:
    /**
     * @brief Constructs a new WiFi communication instance.
     * @param ssid The SSID of the WiFi network to connect to.
     * @param password The password for the WiFi network.
     */
    WiFiCommunication(const char *ssid, const char *password);

    /**
     * @brief Connects to the WiFi network using the provided credentials.
     */
    void Connect();

    /**
     * @brief Checks if the device is currently connected to the WiFi network.
     * @return True if connected, false otherwise.
     */
    bool IsConnected() const;

    /**
     * @brief Checks if WiFi credentials are provided.
     * @return True if credentials are available, false otherwise.
     */
    bool HasCredentials() const;

    /**
     * @brief Gets the local IP address assigned to the device.
     * @return The local IP address.
     */
    IPAddress LocalIp() const;

private:
    const char *ssid_;
    const char *password_;
};
