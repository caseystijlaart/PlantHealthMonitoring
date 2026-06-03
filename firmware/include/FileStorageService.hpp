#pragma once

#include <Arduino.h>
#include <vector>

#include "PlantTypes.hpp"

class TimeService;

class FileStorageService
{
public:
    explicit FileStorageService(TimeService &timeService);

    std::vector<pof02::SensorSnapshot> LoadHistoryFile(const char *filePath, std::size_t maxEntries, std::size_t &outTotalCount) const;
    bool AppendToHistoryFile(const char *filePath, const pof02::MonitoringCycleResult &result, const char *plantLabel, int deviceId, std::size_t maxEntries);

private:
    TimeService &timeService_;
    String CsvEscape(const String &input) const;
};
