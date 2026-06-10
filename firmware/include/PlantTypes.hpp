/**
 * @file PlantTypes.hpp
 * @brief Shared data types: sensor snapshots, ML results, recommendations, and plant profiles.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <array>
#include <cstdint>
#include <cstring>

/**
 * @brief Enumerates the levels for sensor readings.
 * Used for both user preferences and threshold-based classifications.
 */
enum class Level : uint8_t
{
    kLow = 0,  /**< Below the lower threshold. */
    kOk = 1,   /**< Within the acceptable range. */
    kHigh = 2, /**< Above the upper threshold. */
};

/**
 * @brief Enumerates the overall health risk classes for a plant.
 * Used as the output of the ML classifier.
 */
enum class RiskClass : uint8_t
{
    HEALTHY = 0,         /**< Plant is healthy, no action required. */
    MODERATE_STRESS = 1, /**< One or more metrics approaching a threshold. */
    HIGH_STRESS = 2,     /**< Immediate action recommended. */
};

/**
 * @brief Aggregated sensor reading at a single point in time.
 */
struct SensorSnapshot
{
    float soilMoisturePct = 0.0f; /**< Soil moisture (0–100 %). */
    float temperatureC = 0.0f;    /**< Air temperature (°C). */
    float humidityPct = 0.0f;     /**< Relative humidity (0–100 %). */
    float lightLevelPct = 0.0f;   /**< Light level (0–100 %). */
    std::int64_t unixTime = 0;    /**< UTC Unix timestamp of the reading. */
};

/**
 * @brief Engineered feature vector passed to the ML models.
 */
struct FeatureVector
{
    static constexpr std::size_t kCount = 13; /**< Number of features. */
    std::array<float, kCount> values{};
};

/**
 * @brief Output of the health-risk classifier.
 */
struct MLResult
{
    RiskClass risk = RiskClass::MODERATE_STRESS;
    std::array<float, 3> probabilities = {0.0f, 0.0f, 0.0f}; /**< Per-class probabilities. */
    float confidence = 0.0f;                                 /**< Max probability. */
};

/**
 * @brief Actionable care recommendation for a plant.
 */
struct Recommendation
{
    bool water = false;                   /**< Plant needs watering. */
    bool reduceTemp = false;              /**< Temperature is too high. */
    bool increaseLight = false;           /**< Light level is too low. */
    float predictedMinutesToWater = 0.0f; /**< Regression model output (minutes). */
    float optimizedCycleMinutes = 120.0f; /**< Recommended watering cycle duration. */
    float baselineCycleMinutes = 30.0f;   /**< Baseline watering cycle duration. */
    float estimatedPowerSavingPct = 0.0f; /**< Estimated power saving percentage. */
    char summary[128] = {};               /**< Human-readable summary string. */
};

/** @brief User preference band for a single sensor metric. */
enum class PreferenceBand : uint8_t
{
    pLow = 0,  /**< Prefers low values for this metric. */
    pMid = 1,  /**< Prefers mid-range values. */
    pHigh = 2, /**< Prefers high values. */
};

/**
 * @brief Low/mid/high threshold boundaries for a single sensor metric.
 */
struct MetricThresholds
{
    float lowMax;  /**< Upper edge of the "low" band. */
    float midMin;  /**< Lower edge of the "mid" band. */
    float midMax;  /**< Upper edge of the "mid" band. */
    float highMin; /**< Lower edge of the "high" band. */
    float highMax; /**< Upper edge of the "high" band. */
};

/**
 * @brief Per-metric preference bands for a plant. */
struct UserPreferences
{
    PreferenceBand soilMoisture = PreferenceBand::pMid;
    PreferenceBand temperature = PreferenceBand::pMid;
    PreferenceBand humidity = PreferenceBand::pMid;
    PreferenceBand light = PreferenceBand::pMid;
};

/**
 * @brief Complete profile for a paired plant, including thresholds and preferences.
 * */
struct PlantRuleProfile
{
    char plantName[32] = "unnamed";
    char deviceId[40] = "unknown-device"; ///< 40 bytes holds a UUID (36 chars + null).
    char deviceName[32] = "unknown";

    MetricThresholds soilMoistureThresholds{28.0f, 33.0f, 55.0f, 60.0f, 90.0f};
    MetricThresholds temperatureThresholds{16.0f, 18.0f, 26.0f, 28.0f, 35.0f};
    MetricThresholds humidityThresholds{45.0f, 50.0f, 70.0f, 75.0f, 95.0f};
    MetricThresholds lightThresholds{20.0f, 25.0f, 65.0f, 70.0f, 95.0f};

    UserPreferences preferences{};
};

/**
 * @brief Aggregated result of one full monitoring cycle.
 * */
struct MonitoringCycleResult
{
    SensorSnapshot snapshot;
    FeatureVector features;
    MLResult mlResult;
    Recommendation recommendation;
};
