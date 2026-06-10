/**
 * @file MonitoringSystem.hpp
 * @brief Top-level monitoring system orchestrating sensors, ML, and recommendations.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <cstdint>

#include "LightSensor.hpp"
#include "MLLayer.hpp"
#include "PredictiveIrrigationModel.hpp"
#include "RecommendationEngine.hpp"
#include "SensorHistory.hpp"
#include "SoilMoistureSensor.hpp"
#include "TempHumiditySensor.hpp"

/**
 * @brief Default start time for the dataset (01-01-2026 00:00:00 CEST).
 */
constexpr std::int64_t kDefaultDatasetStartUnixTime = 1767222000;

/**
 * @brief Orchestrates the full sensor → ML → recommendation pipeline.
 */
class MonitoringSystem
{
public:
    /**
     * @brief Constructs a MonitoringSystem instance.
     * @param soilSensor The soil moisture sensor.
     * @param tempHumiditySensor The temperature and humidity sensor.
     * @param lightSensor The light sensor.
     * @param mlLayer The machine learning layer.
     * @param recommendationEngine The recommendation engine.
     */
    MonitoringSystem(SoilMoistureSensor soilSensor,
                     TempHumiditySensor tempHumiditySensor,
                     LightSensor lightSensor,
                     MLLayer mlLayer,
                     RecommendationEngine recommendationEngine,
                     PlantRuleProfile plantProfile = PlantRuleProfile{},
                     std::size_t historySize = 24,
                     std::int64_t startUnixTime = kDefaultDatasetStartUnixTime);

    /**
     * @brief Initializes the monitoring system.
     * @return True if initialization was successful, false otherwise.
     */
    bool Init();

    /**
     * @brief Runs a detailed monitoring cycle.
     * @return The result of the monitoring cycle.
     */
    MonitoringCycleResult RunCycleDetailed();

    /**
     * @brief Sets the plant profile.
     * @param plantProfile The plant rule profile.
     */
    void SetPlantProfile(const PlantRuleProfile &plantProfile);
    /**
     * @brief Gets the plant profile.
     * @return The plant rule profile.
     */
    const PlantRuleProfile &GetPlantProfile() const;

    /**
     * @brief Loads historical snapshots.
     * @param snapshots The vector of sensor snapshots.
     */
    void LoadHistoricalSnapshots(const std::vector<SensorSnapshot> &snapshots);

    /**
     * @brief Sets the start Unix time.
     * @param unixTime The Unix time.
     */
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
