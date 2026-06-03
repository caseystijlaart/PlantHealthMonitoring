#include "FeatureEngineering.hpp"

#include <cmath>
#include <ctime>

namespace pof02 {

namespace {

constexpr double kPi = 3.14159265358979323846;

float ComputeSlope(const std::vector<SensorSnapshot>& data) {
    const auto n = data.size();
    if (n < 2) {
        return 0.0f;
    }

    const float dx = static_cast<float>(n - 1);
    return (data.back().soilMoisturePct - data.front().soilMoisturePct) / dx;
}

float ComputeDryDurationHours(const std::vector<SensorSnapshot>& data, float dryThreshold) {
    if (data.size() < 2) {
        return 0.0f;
    }

    std::size_t streak = 0;
    for (auto it = data.rbegin(); it != data.rend(); ++it) {
        if (it->soilMoisturePct < dryThreshold) {
            ++streak;
            continue;
        }
        break;
    }

    if (streak < 2) {
        return 0.0f;
    }

    const auto& newest = data.back();
    const auto& oldest = data[data.size() - streak];
    const auto seconds = static_cast<float>(newest.unixTime - oldest.unixTime);
    return seconds / 3600.0f;
}

} // namespace

FeatureVector FeatureEngineering::Build(const SensorHistory& history) {
    FeatureVector out{};
    if (history.Empty()) {
        return out;
    }

    const auto& data = history.Data();
    const auto& latest = history.Latest();

    float moistureSum = 0.0f;
    for (const auto& s : data) {
        moistureSum += s.soilMoisturePct;
    }

    const float moistureMean = moistureSum / static_cast<float>(data.size());
    const float moistureDelta = data.size() > 1 ? (latest.soilMoisturePct - data[data.size() - 2].soilMoisturePct) : 0.0f;
    const float moistureSlope = ComputeSlope(data);
    const float dryDuration = ComputeDryDurationHours(data, 35.0f);

    const std::time_t t = static_cast<std::time_t>(latest.unixTime);
    const std::tm* utc = std::gmtime(&t);
    const int hour = utc ? utc->tm_hour : 12;
    const int dow = utc ? utc->tm_wday : 0;

    // soil_x_slope: steep downward trend on already-dry soil is the strongest
    // signal for high stress — pre-computing it helps the small MLP distinguish
    // class 2 from class 1 without needing extra hidden units.
    const float soilXSlope = latest.soilMoisturePct * moistureSlope;

    out.values = {
        latest.soilMoisturePct,
        moistureMean,
        moistureDelta,
        moistureSlope,
        dryDuration,
        latest.temperatureC,
        latest.humidityPct,
        latest.lightLevelPct,
        static_cast<float>(std::sin(2.0 * kPi * hour / 24.0)),
        static_cast<float>(std::cos(2.0 * kPi * hour / 24.0)),
        static_cast<float>(std::sin(2.0 * kPi * dow / 7.0)),
        static_cast<float>(std::cos(2.0 * kPi * dow / 7.0)),
        soilXSlope,
    };

    return out;
}

} // namespace pof02
