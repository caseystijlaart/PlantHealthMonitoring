/**
 * @file MLLayer.hpp
 * @brief On-device ML inference layer producing the plant health risk classification.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include "PlantTypes.hpp"

/**
 * @brief Selects which inference backend the MLLayer uses.
 */
enum class MLBackend
{
    RULE_BASED,   /**< Threshold-based fallback rules, no model weights. */
    TINYML_TFLM,  /**< Embedded MLP with weights from ModelExport.hpp. */
    EDGE_IMPULSE, /**< Edge Impulse build (falls back to rules unless enabled). */
};

/**
 * @brief A class for managing machine learning inference.
 */
class MLLayer
{
public:
    /**
     * @brief Constructs a MLLayer instance.
     * @param backend The machine learning backend to use.
     */
    explicit MLLayer(MLBackend backend = MLBackend::TINYML_TFLM);

    /**
     * @brief Makes a prediction based on the input features.
     * @param features The feature vector.
     * @return The prediction result.
     */
    MLResult Predict(const FeatureVector &features) const;

private:
    MLBackend backend_;

    /**
     * @brief Makes a rule-based prediction.
     * @param features The feature vector.
     * @return The prediction result.
     */
    MLResult PredictRuleBased(const FeatureVector &features) const;

    /**
     * @brief Makes an embedded ML prediction.
     * @param features The feature vector.
     * @return The prediction result.
     */
    MLResult PredictEmbeddedMLP(const FeatureVector &features) const;
};
