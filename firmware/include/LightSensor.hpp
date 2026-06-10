/**
 * @file LightSensor.hpp
 * @brief Analog light sensor driver (percentage of full-scale ADC).
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

/**
 * @brief Reads an analog light sensor and reports brightness as a percentage.
 */
class LightSensor
{
public:
    /**
     * @brief Constructs a LightSensor instance.
     * @param pin The analog pin to which the light sensor is connected.
     */
    explicit LightSensor(int pin);

    /**
     * @brief Reads the light level as a percentage.
     * @return The light level percentage (0 = dark, 100 = max ADC brightness).
     */
    float ReadLightLevelPct() const;

private:
    int pin_;
};
