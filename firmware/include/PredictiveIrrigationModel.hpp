#pragma once

#include "PlantTypes.hpp"

/**
 * @brief A predictive model for determining when a plant needs watering.
 */
class PredictiveIrrigationModel {
public:
    /**
     * @brief Predicts the number of minutes until the plant needs watering.
     * @param features The engineered feature vector.
     * @param profile The plant rule profile.
     * @return The predicted minutes until watering is needed.
     */
    float PredictMinutesUntilWatering(const FeatureVector& features,
                                      const PlantRuleProfile& profile) const;
};

