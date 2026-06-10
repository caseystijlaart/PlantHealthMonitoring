/**
 * @file PredictiveIrrigationModel.hpp
 * @brief Regression MLP predicting the minutes until the plant needs watering.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include "PlantTypes.hpp"

/**
 * @brief A predictive model for determining when a plant needs watering.
 */
class PredictiveIrrigationModel
{
public:
    /**
     * @brief Predicts the number of minutes until the plant needs watering.
     * @param features The engineered feature vector.
     * @param profile The plant rule profile.
     * @return The predicted minutes until watering is needed.
     */
    float PredictMinutesUntilWatering(const FeatureVector &features,
                                      const PlantRuleProfile &profile) const;
};
