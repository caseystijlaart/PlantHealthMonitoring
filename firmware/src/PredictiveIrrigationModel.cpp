#include "PredictiveIrrigationModel.hpp"

#include <algorithm>
#include <cmath>

#include "ModelExport.hpp"

namespace pof02 {

float PredictiveIrrigationModel::PredictMinutesUntilWatering(
    const FeatureVector& features, const PlantRuleProfile& profile) const
{
    // soil_now is the first feature — if already at/below threshold, water now
    const float soilNow   = features.values[0];
    const float threshold = profile.soilMoistureThresholds.midMin;
    if (soilNow <= threshold) return 0.0f;

    using namespace modelexport;

    // Scale features using the shared scaler
    std::array<float, kFeatureCount> x{};
    for (std::size_t i = 0; i < kFeatureCount; ++i) {
        const float denom = kScalerStd[i] > 0.0f ? kScalerStd[i] : 1.0f;
        x[i] = (features.values[i] - kScalerMean[i]) / denom;
    }

    // Hidden layer with ReLU
    std::array<float, kRegHiddenCount> hidden{};
    for (std::size_t j = 0; j < kRegHiddenCount; ++j) {
        float z = kRegB1[j];
        for (std::size_t i = 0; i < kFeatureCount; ++i) {
            z += x[i] * kRegW1[i][j];
        }
        hidden[j] = std::max(0.0f, z); // ReLU
    }

    // Output layer (linear — no activation)
    float logMinutes = kRegB2;
    for (std::size_t j = 0; j < kRegHiddenCount; ++j) {
        logMinutes += hidden[j] * kRegW2[j];
    }

    // Training used log1p(minutes) as target, so recover with expm1
    const float minutes = std::expm1(std::max(0.0f, logMinutes));
    return std::clamp(minutes, 0.0f, 15.0f * 24.0f * 60.0f);
}

} // namespace pof02
