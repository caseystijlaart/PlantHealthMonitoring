#include "LightSensor.hpp"

#include <Arduino.h>

namespace pof02 {

LightSensor::LightSensor(int pin) : pin_(pin) {}

float LightSensor::ReadLightLevelPct() const {
    const int raw = analogRead(pin_);
    const float ratio = static_cast<float>(raw) / 4095.0f;
    const float percent = ratio * 100.0f;
    if (percent < 0.0f) {
        return 0.0f;
    }
    if (percent > 100.0f) {
        return 100.0f;
    }
    return percent;
}

} // namespace pof02
