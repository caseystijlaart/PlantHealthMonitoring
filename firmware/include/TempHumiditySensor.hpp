/**
 * @file TempHumiditySensor.hpp
 * @brief DHT temperature and humidity sensor driver.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <DHT.h>
#include <utility>

/**
 * @brief A class for managing the temperature and humidity sensor.
 */
class TempHumiditySensor
{
public:
    /**
     * @brief Constructs a new temperature and humidity sensor instance.
     * @param pin The GPIO pin to which the sensor is connected.
     * @param dhtType The type of the DHT sensor (22 for DHT22, etc.).
     */
    TempHumiditySensor(int pin, int dhtType = 22);

    /**
     * @brief Initializes the sensor.
     * @return True if initialization was successful, false otherwise.
     */
    bool Init();

    /**
     * @brief Reads the temperature and humidity from the sensor.
     * @return A pair containing the temperature in Celsius and the humidity percentage.
     */
    std::pair<float, float> Read() const; // temperature C, humidity %

private:
    int pin_;
    int dhtType_;
    mutable DHT dht_;
};
