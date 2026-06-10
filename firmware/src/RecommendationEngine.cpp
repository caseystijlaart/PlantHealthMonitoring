/**
 * @file RecommendationEngine.cpp
 * @brief Implementation of RecommendationEngine. Builds actionable care recommendations from ML results and plant thresholds.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "RecommendationEngine.hpp"

#include <algorithm>
#include <Arduino.h>

bool IsBelowPreference(const float value, const MetricThresholds &thresholds, const PreferenceBand preference)
{
    switch (preference)
    {
    case PreferenceBand::pLow:
        return value > thresholds.lowMax;
    case PreferenceBand::pMid:
        return value < thresholds.midMin;
    case PreferenceBand::pHigh:
        return value < thresholds.highMin;
    default:
        return false;
    }
}

bool IsAbovePreference(const float value, const MetricThresholds &thresholds, const PreferenceBand preference)
{
    switch (preference)
    {
    case PreferenceBand::pLow:
        return false;
    case PreferenceBand::pMid:
        return value > thresholds.midMax;
    case PreferenceBand::pHigh:
        return value > thresholds.highMax;
    default:
        return false;
    }
}

Recommendation RecommendationEngine::Build(const SensorSnapshot &snapshot,
                                           const MLResult &mlResult,
                                           const PlantRuleProfile &profile,
                                           const float predictedMinutesToWater) const
{
    Recommendation rec{};

    rec.predictedMinutesToWater = predictedMinutesToWater;
    rec.water = predictedMinutesToWater <= 30.0f || IsBelowPreference(snapshot.soilMoisturePct, profile.soilMoistureThresholds, profile.preferences.soilMoisture) || mlResult.risk == RiskClass::HIGH_STRESS;
    rec.reduceTemp = IsAbovePreference(snapshot.temperatureC, profile.temperatureThresholds, profile.preferences.temperature);
    rec.increaseLight = IsBelowPreference(snapshot.lightLevelPct, profile.lightThresholds, profile.preferences.light);

    rec.baselineCycleMinutes = 30.0f;
    rec.optimizedCycleMinutes = std::clamp(predictedMinutesToWater * 0.5f, 15.0f, 240.0f);
    rec.estimatedPowerSavingPct = (1.0f - (rec.baselineCycleMinutes / rec.optimizedCycleMinutes)) * 100.0f;
    rec.estimatedPowerSavingPct = std::clamp(rec.estimatedPowerSavingPct, 0.0f, 95.0f);

    String summary;
    summary += "predWaterMin=";
    summary += String(rec.predictedMinutesToWater, 1);
    summary += " nextCycleMin=";
    summary += String(rec.optimizedCycleMinutes, 1);
    summary += " powerSavingPct=";
    summary += String(rec.estimatedPowerSavingPct, 1);
    summary += " actions:[";
    if (rec.water)
        summary += "water ";
    if (rec.reduceTemp)
        summary += "cool ";
    if (rec.increaseLight)
        summary += "light ";
    summary += "]";
    strncpy(rec.summary, summary.c_str(), sizeof(rec.summary) - 1);
    rec.summary[sizeof(rec.summary) - 1] = '\0';

    return rec;
}
