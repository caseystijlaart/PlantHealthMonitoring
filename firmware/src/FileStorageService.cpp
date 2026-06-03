#include "FileStorageService.hpp"

#include <LittleFS.h>

#include <algorithm>
#include <ctime>
#include <vector>

#include "TimeService.hpp"

using namespace pof02;

namespace
{

std::vector<String> ParseCsvLine(const String &line)
{
    std::vector<String> parts;
    int i = 0;
    const int len = static_cast<int>(line.length());

    while (i <= len)
    {
        if (i < len && line[i] == '"')
        {
            ++i;
            String field;
            while (i < len)
            {
                if (line[i] == '"')
                {
                    if (i + 1 < len && line[i + 1] == '"')
                    {
                        field += '"';
                        i += 2;
                    }
                    else
                    {
                        ++i;
                        break;
                    }
                }
                else
                {
                    field += line[i++];
                }
            }
            parts.push_back(field);
            if (i < len && line[i] == ',')
                ++i;
        }
        else
        {
            const int comma = line.indexOf(',', i);
            if (comma < 0)
            {
                parts.push_back(line.substring(i));
                break;
            }
            parts.push_back(line.substring(i, comma));
            i = comma + 1;
        }
    }

    return parts;
}

std::int64_t ParseTimestamp(const String &ts)
{
    int year, month, day, hour, min, sec;
    if (sscanf(ts.c_str(), "%d-%d-%d %d:%d:%d", &year, &month, &day, &hour, &min, &sec) != 6)
        return 0;

    std::tm t{};
    t.tm_year = year - 1900;
    t.tm_mon = month - 1;
    t.tm_mday = day;
    t.tm_hour = hour;
    t.tm_min = min;
    t.tm_sec = sec;
    t.tm_isdst = -1;

    const time_t result = mktime(&t);
    return result < 0 ? 0 : static_cast<std::int64_t>(result);
}

} // namespace

FileStorageService::FileStorageService(TimeService &timeService)
    : timeService_(timeService) {}

std::vector<SensorSnapshot> FileStorageService::LoadHistoryFile(const char *filePath, std::size_t maxEntries, std::size_t &outTotalCount) const
{
    outTotalCount = 0;

    File file = LittleFS.open(filePath, FILE_READ);
    if (!file)
        return {};

    std::vector<String> lines;
    while (file.available())
    {
        String line = file.readStringUntil('\n');
        line.trim();
        if (line.length() > 0)
            lines.push_back(line);
    }
    file.close();

    if (lines.size() <= 1)
        return {};

    const std::size_t dataRows = lines.size() - 1;
    outTotalCount = dataRows;

    const std::size_t startIdx = dataRows > maxEntries ? lines.size() - maxEntries : 1;

    std::vector<SensorSnapshot> snapshots;
    snapshots.reserve(std::min(dataRows, maxEntries));

    for (std::size_t i = startIdx; i < lines.size(); ++i)
    {
        const auto parts = ParseCsvLine(lines[i]);
        if (parts.size() < 7)
            continue;

        const std::int64_t ts = ParseTimestamp(parts[2]);
        if (ts <= 0)
            continue;

        SensorSnapshot s{};
        s.unixTime = ts;
        s.soilMoisturePct = parts[3].toFloat();
        s.temperatureC = parts[4].toFloat();
        s.humidityPct = parts[5].toFloat();
        s.lightLevelPct = parts[6].toFloat();
        snapshots.push_back(s);
    }

    return snapshots;
}

bool FileStorageService::AppendToHistoryFile(const char *filePath, const MonitoringCycleResult &result, const char *plantLabel, int deviceId, std::size_t maxEntries)
{
    const std::int64_t unixTime = timeService_.GetCurrentUnixTimeUtc() > 0
                                      ? timeService_.GetCurrentUnixTimeUtc()
                                      : result.snapshot.unixTime;
    const String timestamp = timeService_.FormatTimestampLocal(unixTime);

    if (!LittleFS.exists(filePath))
    {
        File f = LittleFS.open(filePath, FILE_WRITE);
        if (!f)
            return false;
        f.println(F("plant_label,device_id,timestamp_utc,soil_moisture_pct,temperature_c,humidity_pct,light_level_pct,action_water,action_reduce_temp,action_increase_light,recommendation_summary"));
        f.close();
    }

    File file = LittleFS.open(filePath, FILE_APPEND);
    if (!file)
        return false;

    const auto &s = result.snapshot;
    const auto &rec = result.recommendation;

    String line;
    line.reserve(200);
    line += CsvEscape(String(plantLabel)) + ',';
    line += String(deviceId) + ',';
    line += CsvEscape(timestamp) + ',';
    line += String(s.soilMoisturePct, 3) + ',';
    line += String(s.temperatureC, 3) + ',';
    line += String(s.humidityPct, 3) + ',';
    line += String(s.lightLevelPct, 3) + ',';
    line += String(rec.water ? 1 : 0) + ',';
    line += String(rec.reduceTemp ? 1 : 0) + ',';
    line += String(rec.increaseLight ? 1 : 0) + ',';
    line += CsvEscape(String(rec.summary));

    file.println(line);
    file.close();

    // Trim to maxEntries*2 to keep flash usage bounded
    File countFile = LittleFS.open(filePath, FILE_READ);
    std::size_t rowCount = 0;
    if (countFile)
    {
        while (countFile.available())
        {
            countFile.readStringUntil('\n');
            ++rowCount;
        }
        countFile.close();
        rowCount = rowCount > 1 ? rowCount - 1 : 0;
    }

    if (rowCount > maxEntries * 2)
    {
        std::size_t dummy = 0;
        const auto keep = LoadHistoryFile(filePath, maxEntries, dummy);

        File rewrite = LittleFS.open(filePath, FILE_WRITE);
        if (rewrite)
        {
            rewrite.println(F("plant_label,device_id,timestamp_utc,soil_moisture_pct,temperature_c,humidity_pct,light_level_pct,action_water,action_reduce_temp,action_increase_light,recommendation_summary"));
            for (const auto &snap : keep)
            {
                const String ts = timeService_.FormatTimestampLocal(snap.unixTime);
                String l;
                l += CsvEscape(String(plantLabel)) + ',';
                l += String(deviceId) + ',';
                l += CsvEscape(ts) + ',';
                l += String(snap.soilMoisturePct, 3) + ',';
                l += String(snap.temperatureC, 3) + ',';
                l += String(snap.humidityPct, 3) + ',';
                l += String(snap.lightLevelPct, 3) + F(",0,0,0,\"\"");
                rewrite.println(l);
            }
            rewrite.close();
            Serial.println(F("Trimmed sensor history file"));
        }
    }

    return true;
}

String FileStorageService::CsvEscape(const String &input) const
{
    String escaped = input;
    escaped.replace("\"", "\"\"");
    return '"' + escaped + '"';
}
