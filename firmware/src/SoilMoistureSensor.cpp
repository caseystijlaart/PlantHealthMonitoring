/**
 * @file SoilMoistureSensor.cpp
 * @brief Implementation of SoilMoistureSensor. Capacitive soil moisture sensor driver with dry/wet calibration.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "SoilMoistureSensor.hpp"

#include <Arduino.h>

#include <algorithm>

SoilMoistureSensor::SoilMoistureSensor(int pin, float adcDry, float adcWet)
    : pin_(pin), adcDry_(adcDry), adcWet_(adcWet) {}

float SoilMoistureSensor::ReadPercent() const
{
    constexpr int kSamples = 16;
    constexpr int kAdcMax = 4095;

    long sum = 0;
    for (int i = 0; i < kSamples; ++i)
    {
        sum += analogRead(pin_);
    }
    const int raw = static_cast<int>(sum / kSamples);

    if (raw <= 0 || raw >= kAdcMax)
    {
        return -1.0f;
    }

    const float scaled = (static_cast<float>(raw) - adcDry_) / (adcWet_ - adcDry_);
    return std::max(0.0f, std::min(100.0f, scaled * 100.0f));
}
