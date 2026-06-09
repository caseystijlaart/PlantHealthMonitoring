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
    explicit FileStorageService(TimeService &timeService);

    // ── Sensor history ─────────────────────────────────────────────────────────

    std::vector<SensorSnapshot> LoadHistoryFile(const char *filePath,
                                                std::size_t maxEntries,
                                                std::size_t &outTotalCount) const;

    bool AppendToHistoryFile(const char *filePath,
                             const MonitoringCycleResult &result,
                             const char *plantLabel,
                             const char *deviceId,
                             std::size_t maxEntries);

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
