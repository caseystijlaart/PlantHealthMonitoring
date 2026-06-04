#pragma once

namespace pof02 {

class SoilMoistureSensor {
public:
    SoilMoistureSensor(int pin, float adcDry, float adcWet);
    float ReadPercent() const;

private:
    int pin_;
    float adcDry_;
    float adcWet_;
};

} // namespace pof02
