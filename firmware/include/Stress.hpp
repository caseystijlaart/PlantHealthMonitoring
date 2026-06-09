#pragma once

#include "PlantTypes.hpp"

/**
 * @brief A class for computing a combined stress score from individual sensor levels.
 */
class Stress
{
public:
    /**
     * @brief Computes a stress score for a single metric level.
     * @param level The level of the metric (Low, Ok, High).
     * @return A float score representing the stress contribution of this metric.
     */
    static float Score(Level level);

    /**
     * @brief Combines the levels of all metrics into a single overall stress score.
     * @param moisture The soil moisture level.
     * @param temp The temperature level.
     * @param humidity The humidity level.
     * @param light The light level.
     * @return A float score representing the overall stress level of the plant.
     */
    static float Combined(Level moisture, Level temp, Level humidity, Level light);
};
