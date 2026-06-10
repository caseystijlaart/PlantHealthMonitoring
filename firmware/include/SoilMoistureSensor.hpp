/**
 * @file SoilMoistureSensor.hpp
 * @brief Capacitive soil moisture sensor driver with dry/wet calibration.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

/**
 * @brief Reads a capacitive soil moisture sensor and returns a calibrated
 *        percentage value.
 *
 * ADC readings are mapped linearly between the dry and wet calibration points.
 */
class SoilMoistureSensor
{
public:
    /**
     * @brief Constructs the sensor with its GPIO pin and calibration bounds.
     * @param pin    ADC-capable GPIO pin the sensor is connected to.
     * @param adcDry Raw ADC value when the sensor is in dry air.
     * @param adcWet Raw ADC value when the sensor is in water.
     */
    SoilMoistureSensor(int pin, float adcDry, float adcWet);

    /**
     * @brief Reads the sensor and returns the soil moisture as a percentage.
     * @return Moisture level (0 = dry, 100 = saturated).
     */
    float ReadPercent() const;

private:
    int pin_;
    float adcDry_;
    float adcWet_;
};
