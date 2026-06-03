#pragma once

#include <array>
#include <cstdint>
#include <cstring>

namespace pof02 {

enum class Level : uint8_t {
    kLow  = 0,
    kOk   = 1,
    kHigh = 2,
};

enum class RiskClass : uint8_t {
    HEALTHY = 0,
    MODERATE_STRESS = 1,
    HIGH_STRESS = 2,
};

struct SensorSnapshot {
    float soilMoisturePct = 0.0f;
    float temperatureC = 0.0f;
    float humidityPct = 0.0f;
    float lightLevelPct = 0.0f;
    std::int64_t unixTime = 0;
};

struct FeatureVector {
    static constexpr std::size_t kCount = 13;
    std::array<float, kCount> values{};
};

struct MLResult {
    RiskClass risk = RiskClass::MODERATE_STRESS;
    std::array<float, 3> probabilities{0.0f, 0.0f, 0.0f};
    float confidence = 0.0f;
};

struct Recommendation {
    bool water = false;
    bool reduceTemp = false;
    bool increaseLight = false;
    float predictedMinutesToWater = 0.0f;
    float optimizedCycleMinutes = 120.0f;
    float baselineCycleMinutes = 30.0f;
    float estimatedPowerSavingPct = 0.0f;
    char summary[128] = {};
};

enum class PreferenceBand : uint8_t {
    pLow = 0,
    pMid = 1,
    pHigh = 2,
};

struct MetricThresholds {
    float lowMax;
    float midMin;
    float midMax;
    float highMin;
    float highMax;
};

struct UserPreferences {
    PreferenceBand soilMoisture = PreferenceBand::pMid;
    PreferenceBand temperature = PreferenceBand::pMid;
    PreferenceBand humidity = PreferenceBand::pMid;
    PreferenceBand light = PreferenceBand::pMid;
};

struct PlantRuleProfile {
    char plantName[32] = "unnamed";
    char deviceId[32] = "unknown-device";
    char deviceName[32] = "unknown";
    // Tuned for airy/chunky soil mixes: moisture drops slower and sensor reads lower.
    MetricThresholds soilMoistureThresholds{28.0f, 33.0f, 55.0f, 60.0f, 90.0f};
    MetricThresholds temperatureThresholds{16.0f, 18.0f, 26.0f, 28.0f, 35.0f};
    MetricThresholds humidityThresholds{45.0f, 50.0f, 70.0f, 75.0f, 95.0f};
    MetricThresholds lightThresholds{20.0f, 25.0f, 65.0f, 70.0f, 95.0f};
    UserPreferences preferences{};
};

struct MonitoringCycleResult {
    SensorSnapshot snapshot;
    FeatureVector features;
    MLResult mlResult;
    Recommendation recommendation;
};

} // namespace pof02
