#pragma once

#include "PlantTypes.hpp"

/**
 * @brief A class for generating care recommendations based on sensor data and ML results.
 */
class RecommendationEngine
{
public:
    /**
     * @brief Builds a care recommendation for the plant.
     * @param snapshot The latest sensor snapshot.
     * @param mlResult The result from the ML classifier.
     * @param profile The plant rule profile containing thresholds and preferences.
     * @param predictedMinutesToWater The predicted minutes until watering is needed.
     * @return A care recommendation for the plant.
     * This method combines the ML result with the plant's preferences and thresholds to generate actionable recommendations, such as whether to water the plant, adjust temperature, or change light levels. It also provides a human-readable summary of the recommendation.
     */
    Recommendation Build(const SensorSnapshot &snapshot, const MLResult &mlResult, const PlantRuleProfile &profile, float predictedMinutesToWater) const;
};
