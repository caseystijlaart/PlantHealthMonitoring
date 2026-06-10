/**
 * @file FeatureEngineering.hpp
 * @brief Builds the 13-feature ML input vector from the sensor history.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include "PlantTypes.hpp"
#include "SensorHistory.hpp"

/**
 * @brief A class for engineering features from sensor data.
 */
class FeatureEngineering
{
public:
    /**
     * @brief Builds a feature vector from the given sensor history.
     * @param history The sensor history.
     * @return The engineered feature vector.
     */
    static FeatureVector Build(const SensorHistory &history);
};
