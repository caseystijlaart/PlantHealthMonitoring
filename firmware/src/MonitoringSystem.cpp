#include "MonitoringSystem.hpp"

#include <Arduino.h>

#include "FeatureEngineering.hpp"

namespace pof02 {

MonitoringSystem::MonitoringSystem(SoilMoistureSensor soilSensor,
                                   TempHumiditySensor tempHumiditySensor,
                                   LightSensor lightSensor,
                                   MLLayer mlLayer,
                                   RecommendationEngine recommendationEngine,
                                   PlantRuleProfile plantProfile,
                                   std::size_t historySize,
                                   std::int64_t startUnixTime)
    : soilSensor_(soilSensor),
      tempHumiditySensor_(tempHumiditySensor),
      lightSensor_(lightSensor),
      mlLayer_(mlLayer),
      recommendationEngine_(recommendationEngine),
      plantProfile_(plantProfile),
      history_(historySize),
      startUnixTime_(startUnixTime),
      startMillis_(0) {}

bool MonitoringSystem::Init() {
    startMillis_ = millis();
    return tempHumiditySensor_.Init();
}

MonitoringCycleResult MonitoringSystem::RunCycleDetailed() {
    const auto [temperature, humidity] = tempHumiditySensor_.Read();

    SensorSnapshot snapshot{};
    snapshot.soilMoisturePct = soilSensor_.ReadPercent();
    snapshot.temperatureC = temperature;
    snapshot.humidityPct = humidity;
    snapshot.lightLevelPct = lightSensor_.ReadLightLevelPct();

    const unsigned long elapsedMs = millis() - startMillis_;
    snapshot.unixTime = startUnixTime_ + static_cast<std::int64_t>(elapsedMs / 1000UL);

    // Skip cycle if soil sensor read is invalid (disconnected / shorted)
    if (snapshot.soilMoisturePct < 0.0f) {
        Serial.println("[MonitoringSystem] Soil sensor returned invalid reading — skipping cycle");
        return MonitoringCycleResult{};
    }

    history_.Add(snapshot);

    const FeatureVector features = FeatureEngineering::Build(history_);
    const MLResult mlResult = mlLayer_.Predict(features);
    const float predictedMinutesToWater = predictiveIrrigationModel_.PredictMinutesUntilWatering(features, plantProfile_);
    const Recommendation recommendation = recommendationEngine_.Build(snapshot, mlResult, plantProfile_, predictedMinutesToWater);

    return MonitoringCycleResult{snapshot, features, mlResult, recommendation};
}

void MonitoringSystem::SetPlantProfile(const PlantRuleProfile& plantProfile) {
    plantProfile_ = plantProfile;
}

const PlantRuleProfile& MonitoringSystem::GetPlantProfile() const {
    return plantProfile_;
}

void MonitoringSystem::LoadHistoricalSnapshots(const std::vector<SensorSnapshot>& snapshots) {
    for (const auto& snapshot : snapshots) {
        history_.Add(snapshot);
    }
}

void MonitoringSystem::SetStartUnixTime(std::int64_t unixTime) {
    startUnixTime_ = unixTime;
    startMillis_ = millis();
}

} // namespace pof02
