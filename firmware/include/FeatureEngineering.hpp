#pragma once

#include "PlantTypes.hpp"
#include "SensorHistory.hpp"

/**
 * @brief A class for engineering features from sensor data.
 */
class FeatureEngineering {
public:
    /**
     * @brief Builds a feature vector from the given sensor history.
     * @param history The sensor history.
     * @return The engineered feature vector.
     */
    static FeatureVector Build(const SensorHistory& history);
};

