#include "SoilMoistureSensor.hpp"

#include <Arduino.h>

#include <algorithm>

namespace pof02 {

SoilMoistureSensor::SoilMoistureSensor(int pin, float adcDry, float adcWet)
    : pin_(pin), adcDry_(adcDry), adcWet_(adcWet) {}

float SoilMoistureSensor::ReadPercent() const {
    constexpr int kSamples = 16;
    constexpr int kAdcMax = 4095;

    long sum = 0;
    for (int i = 0; i < kSamples; ++i) {
        sum += analogRead(pin_);
    }
    const int raw = static_cast<int>(sum / kSamples);

    // Rail values indicate a disconnected or shorted sensor
    if (raw <= 0 || raw >= kAdcMax) {
        return -1.0f;
    }

    const float scaled = (static_cast<float>(raw) - adcDry_) / (adcWet_ - adcDry_);
    return std::max(0.0f, std::min(100.0f, scaled * 100.0f));
}

} // namespace pof02
