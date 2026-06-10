/**
 * @file FileStorageService.hpp
 * @brief LittleFS-backed storage for the sensor history CSV and the pairing document.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>
#include <vector>
#include <LittleFS.h>

#include "PlantTypes.hpp"

class TimeService;

/**
 * @brief Manages local file storage: sensor history CSV and the pairing document.
 */
class FileStorageService
{
public:
    /**
     * @brief Constructs the service.
     * @param timeService Used to timestamp appended history rows.
     */
    explicit FileStorageService(TimeService &timeService);

    // ── Sensor history ─────────────────────────────────────────────────────────

    /**
     * @brief Loads the most recent snapshots from the history CSV.
     * @param filePath      Path of the history file on LittleFS.
     * @param maxEntries    Maximum number of snapshots to return (newest kept).
     * @param outTotalCount Set to the total number of rows present in the file.
     * @return Snapshots in chronological order (oldest first).
     */
    std::vector<SensorSnapshot> LoadHistoryFile(const char *filePath,
                                                std::size_t maxEntries,
                                                std::size_t &outTotalCount) const;

    /**
     * @brief Appends one monitoring cycle result as a CSV row, trimming the
     *        file to @p maxEntries rows.
     * @param filePath   Path of the history file on LittleFS.
     * @param result     Cycle result to persist.
     * @param plantLabel Plant label stored with the row.
     * @param deviceId   Device id stored with the row.
     * @param maxEntries Maximum number of rows to retain.
     * @return @c true on success.
     */
    bool AppendToHistoryFile(const char *filePath,
                             const MonitoringCycleResult &result,
                             const char *plantLabel,
                             const char *deviceId,
                             std::size_t maxEntries);

    /**
     * @brief Deletes the history file.
     * @param filePath Path of the history file on LittleFS.
     */
    void ClearHistory(const char *filePath);

    // ── Pairing document ───────────────────────────────────────────────────────

    /**
     * @brief Writes a paired state with credentials and Supabase URL.
     */
    void WritePaired(const String &ssid,
                     const String &password,
                     const String &apiKey,
                     const String &supabaseUrl);

    /**
     * @brief Writes the unpaired state, erasing any stored credentials.
     */
    void WriteUnpaired();

    /**
     * @brief Reads the pairing document.
     * @return true if paired and all out-params are populated.
     */
    bool ReadPairing(String &ssidOut,
                     String &passwordOut,
                     String &apiKeyOut,
                     String &supabaseUrlOut);

private:
    TimeService &timeService_;
    String CsvEscape(const String &input) const;

    static constexpr const char *kPairingFile = "/pairing_state.txt";

    static void StripCr(String &s);
};
