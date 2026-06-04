#pragma once

#include <cstdint>

#include "LightSensor.hpp"
#include "MLLayer.hpp"
#include "PredictiveIrrigationModel.hpp"
#include "RecommendationEngine.hpp"
#include "SensorHistory.hpp"
#include "SoilMoistureSensor.hpp"
#include "TempHumiditySensor.hpp"

namespace pof02
{

    constexpr std::int64_t kDefaultDatasetStartUnixTime = 1776466884; // 2026-03-04 12:10:00 UTC

    class MonitoringSystem
    {
    public:
        MonitoringSystem(SoilMoistureSensor soilSensor,
                         TempHumiditySensor tempHumiditySensor,
                         LightSensor lightSensor,
                         MLLayer mlLayer,
                         RecommendationEngine recommendationEngine,
                         PlantRuleProfile plantProfile = PlantRuleProfile{},
                         std::size_t historySize = 24,
                         std::int64_t startUnixTime = kDefaultDatasetStartUnixTime);

        bool Init();
        MonitoringCycleResult RunCycleDetailed();
        void SetPlantProfile(const PlantRuleProfile &plantProfile);
        const PlantRuleProfile &GetPlantProfile() const;
        void LoadHistoricalSnapshots(const std::vector<SensorSnapshot> &snapshots);
        void SetStartUnixTime(std::int64_t unixTime);

    private:
        SoilMoistureSensor soilSensor_;
        TempHumiditySensor tempHumiditySensor_;
        LightSensor lightSensor_;
        MLLayer mlLayer_;
        RecommendationEngine recommendationEngine_;
        PredictiveIrrigationModel predictiveIrrigationModel_;
        PlantRuleProfile plantProfile_;
        SensorHistory history_;
        std::int64_t startUnixTime_;
        unsigned long startMillis_;
    };

} // namespace pof02
