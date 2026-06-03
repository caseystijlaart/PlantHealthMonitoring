#pragma once

#include "PlantTypes.hpp"
#include "SensorHistory.hpp"

namespace pof02 {

class FeatureEngineering {
public:
    static FeatureVector Build(const SensorHistory& history);
};

} // namespace pof02
