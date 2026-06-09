#pragma once

#include <Arduino.h>
#include <vector>

#include "PlantTypes.hpp"

/**
 * @brief A class for managing file storage operations.
 */
class TimeService;

/**
 * @brief A class for managing file storage operations.
 */
class FileStorageService
{
public:
    /**
     * @brief Constructs a FileStorageService instance.
     * @param timeService A reference to the time service.
     */
    explicit FileStorageService(TimeService &timeService);

    /**
     * @brief Loads sensor history data from a file.
     * @param filePath The path to the history file.
     * @param maxEntries The maximum number of entries to load.
     * @param outTotalCount Output parameter for the total count of entries in the file.
     * @return A vector of SensorSnapshot objects loaded from the file.
     */
    std::vector<SensorSnapshot> LoadHistoryFile(const char *filePath, std::size_t maxEntries, std::size_t &outTotalCount) const;
    
    /**
     * @brief Appends a monitoring cycle result to a history file.
     * @param filePath The path to the history file.
     * @param result The monitoring cycle result to append.
     * @param plantLabel The label of the plant.
     * @param deviceId The ID of the device.
     * @param maxEntries The maximum number of entries to keep in the file.
     * @return True if the operation was successful, false otherwise.
     */
    bool AppendToHistoryFile(const char *filePath, const MonitoringCycleResult &result, const char *plantLabel, const char *deviceId, std::size_t maxEntries);

private:
    TimeService &timeService_;
    String CsvEscape(const String &input) const;
};
