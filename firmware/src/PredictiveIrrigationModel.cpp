/**
 * @file PredictiveIrrigationModel.cpp
 * @brief Implementation of PredictiveIrrigationModel. Regression MLP predicting the minutes until the plant needs watering.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "PredictiveIrrigationModel.hpp"

#include <algorithm>
#include <cmath>

#include "ModelExport.hpp"

float PredictiveIrrigationModel::PredictMinutesUntilWatering(
    const FeatureVector &features, const PlantRuleProfile &profile) const
{
    const float soilNow = features.values[0];
    const float threshold = profile.soilMoistureThresholds.midMin;
    if (soilNow <= threshold)
        return 0.0f;

    using namespace modelexport;

    std::array<float, kFeatureCount> x{};
    for (std::size_t i = 0; i < kFeatureCount; ++i)
    {
        const float denom = kScalerStd[i] > 0.0f ? kScalerStd[i] : 1.0f;
        x[i] = (features.values[i] - kScalerMean[i]) / denom;
    }

    std::array<float, kRegHiddenCount> hidden{};
    for (std::size_t j = 0; j < kRegHiddenCount; ++j)
    {
        float z = kRegB1[j];
        for (std::size_t i = 0; i < kFeatureCount; ++i)
        {
            z += x[i] * kRegW1[i][j];
        }
        hidden[j] = std::max(0.0f, z);
    }

    float logMinutes = kRegB2;
    for (std::size_t j = 0; j < kRegHiddenCount; ++j)
    {
        logMinutes += hidden[j] * kRegW2[j];
    }

    const float minutes = std::expm1(std::max(0.0f, logMinutes));
    return std::clamp(minutes, 0.0f, 15.0f * 24.0f * 60.0f);
}
