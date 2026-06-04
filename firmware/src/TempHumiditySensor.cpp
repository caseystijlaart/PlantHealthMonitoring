#include "TempHumiditySensor.hpp"

#include <Arduino.h>
#include <DHT.h>

namespace pof02 {

TempHumiditySensor::TempHumiditySensor(int pin, int dhtType)
    : pin_(pin), dhtType_(dhtType), dht_(static_cast<uint8_t>(pin), static_cast<uint8_t>(dhtType)) {}

bool TempHumiditySensor::Init() {
    dht_.begin();
    return true;
}

std::pair<float, float> TempHumiditySensor::Read() const {
    const float temperature = dht_.readTemperature();
    const float humidity = dht_.readHumidity();

    if (isnan(temperature) || isnan(humidity)) {
        return {23.0f, 60.0f};
    }
    return {temperature, humidity};
}

} // namespace pof02
