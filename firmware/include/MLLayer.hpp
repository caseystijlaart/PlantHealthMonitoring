#pragma once

#include "PlantTypes.hpp"

/**
 * @brief A class for managing machine learning inference.
 */
enum class MLBackend {
    RULE_BASED,
    TINYML_TFLM,
    EDGE_IMPULSE,
};

/**
 * @brief A class for managing machine learning inference.
 */
class MLLayer {
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
    MLResult Predict(const FeatureVector& features) const;

private:
    MLBackend backend_;

    /**
     * @brief Makes a rule-based prediction.
     * @param features The feature vector.
     * @return The prediction result.
     */
    MLResult PredictRuleBased(const FeatureVector& features) const;
    
    /**
     * @brief Makes an embedded ML prediction.
     * @param features The feature vector.
     * @return The prediction result.
     */
    MLResult PredictEmbeddedMLP(const FeatureVector& features) const;
};

