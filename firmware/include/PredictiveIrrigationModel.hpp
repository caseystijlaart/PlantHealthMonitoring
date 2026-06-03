#pragma once

#include "PlantTypes.hpp"

namespace pof02 {

class PredictiveIrrigationModel {
public:
    // Predict minutes until soil moisture drops to the watering threshold.
    // Uses the regression MLP whose weights live in ModelExport.hpp.
    // Features are the same 12-element vector already computed by FeatureEngineering
    // (includes hour_sin / hour_cos, so day/night patterns come from training data).
    float PredictMinutesUntilWatering(const FeatureVector& features,
                                      const PlantRuleProfile& profile) const;
};

} // namespace pof02
