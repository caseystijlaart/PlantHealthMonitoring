#pragma once

#include <DHT.h>
#include <utility>

namespace pof02 {

class TempHumiditySensor {
public:
    TempHumiditySensor(int pin, int dhtType = 22);
    bool Init();
    std::pair<float, float> Read() const; // temperature C, humidity %

private:
    int pin_;
    int dhtType_;
    mutable DHT dht_;
};

} // namespace pof02
