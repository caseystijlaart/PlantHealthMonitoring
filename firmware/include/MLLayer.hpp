#pragma once

#include "PlantTypes.hpp"

namespace pof02 {

enum class MLBackend {
    RULE_BASED,
    TINYML_TFLM,
    EDGE_IMPULSE,
};

class MLLayer {
public:
    explicit MLLayer(MLBackend backend = MLBackend::TINYML_TFLM);
    MLResult Predict(const FeatureVector& features) const;

private:
    MLBackend backend_;

    MLResult PredictRuleBased(const FeatureVector& features) const;
    MLResult PredictEmbeddedMLP(const FeatureVector& features) const;
};

} // namespace pof02
