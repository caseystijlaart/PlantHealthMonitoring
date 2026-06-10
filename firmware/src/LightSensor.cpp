/**
 * @file LightSensor.cpp
 * @brief Implementation of LightSensor. Analog light sensor driver (percentage of full-scale ADC).
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "LightSensor.hpp"

#include <Arduino.h>

LightSensor::LightSensor(int pin) : pin_(pin) {}

float LightSensor::ReadLightLevelPct() const
{
    const int raw = analogRead(pin_);
    const float ratio = static_cast<float>(raw) / 4095.0f;
    const float percent = ratio * 100.0f;
    if (percent < 0.0f)
    {
        return 0.0f;
    }
    if (percent > 100.0f)
    {
        return 100.0f;
    }
    return percent;
}
