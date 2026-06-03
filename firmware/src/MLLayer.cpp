#include "MLLayer.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>

#include "ModelExport.hpp"

namespace pof02 {

namespace {

std::array<float, 3> Softmax(const std::array<float, 3>& logits) {
    const float maxLogit = *std::max_element(logits.begin(), logits.end());
    std::array<float, 3> exps{};
    float sum = 0.0f;
    for (std::size_t i = 0; i < logits.size(); ++i) {
        exps[i] = std::exp(logits[i] - maxLogit);
        sum += exps[i];
    }
    for (auto& e : exps) {
        e /= sum;
    }
    return exps;
}

RiskClass ToRisk(int klass) {
    switch (klass) {
        case 0:
            return RiskClass::HEALTHY;
        case 2:
            return RiskClass::HIGH_STRESS;
        case 1:
        default:
            return RiskClass::MODERATE_STRESS;
    }
}

} // namespace

MLLayer::MLLayer(MLBackend backend) : backend_(backend) {}

MLResult MLLayer::Predict(const FeatureVector& features) const {
#if defined(POF02_ENABLE_EDGE_IMPULSE)
    if (backend_ == MLBackend::EDGE_IMPULSE) {
        return PredictRuleBased(features);
    }
#elif defined(POF02_ENABLE_TINYML_TFLM)
    if (backend_ == MLBackend::TINYML_TFLM) {
        return PredictEmbeddedMLP(features);
    }
#endif
    return backend_ == MLBackend::RULE_BASED ? PredictRuleBased(features) : PredictEmbeddedMLP(features);
}

MLResult MLLayer::PredictRuleBased(const FeatureVector& features) const {
    MLResult out{};
    const float soil = features.values[0];
    const float dryness = features.values[4];

    if (soil < 30.0f || dryness > 6.0f) {
        out.risk = RiskClass::HIGH_STRESS;
        out.probabilities = {0.05f, 0.15f, 0.80f};
    } else if (soil < 40.0f || dryness > 2.0f) {
        out.risk = RiskClass::MODERATE_STRESS;
        out.probabilities = {0.10f, 0.78f, 0.12f};
    } else {
        out.risk = RiskClass::HEALTHY;
        out.probabilities = {0.85f, 0.12f, 0.03f};
    }

    out.confidence = *std::max_element(out.probabilities.begin(), out.probabilities.end());
    return out;
}

MLResult MLLayer::PredictEmbeddedMLP(const FeatureVector& features) const {
    using namespace modelexport;

    std::array<float, kFeatureCount> x{};
    for (std::size_t i = 0; i < kFeatureCount; ++i) {
        const float denom = kScalerStd[i] == 0.0f ? 1.0f : kScalerStd[i];
        x[i] = (features.values[i] - kScalerMean[i]) / denom;
    }

    std::array<float, kHiddenCount> hidden{};
    for (std::size_t j = 0; j < kHiddenCount; ++j) {
        float z = kB1[j];
        for (std::size_t i = 0; i < kFeatureCount; ++i) {
            z += x[i] * kW1[i][j];
        }
        hidden[j] = std::max(0.0f, z);
    }

    std::array<float, kClassCount> logits{};
    for (std::size_t k = 0; k < kClassCount; ++k) {
        float z = kB2[k];
        for (std::size_t j = 0; j < kHiddenCount; ++j) {
            z += hidden[j] * kW2[j][k];
        }
        logits[k] = z;
    }

    const auto probs = Softmax(logits);
    const auto maxIt = std::max_element(probs.begin(), probs.end());
    const std::size_t argMax = static_cast<std::size_t>(std::distance(probs.begin(), maxIt));

    MLResult out{};
    out.risk = ToRisk(kClasses[argMax]);
    out.probabilities = probs;
    out.confidence = *maxIt;
    return out;
}

} // namespace pof02
