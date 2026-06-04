#pragma once

namespace pof02 {

class LightSensor {
public:
    explicit LightSensor(int pin);
    float ReadLightLevelPct() const; // 0 = dark, 100 = max ADC brightness

private:
    int pin_;
};

} // namespace pof02
