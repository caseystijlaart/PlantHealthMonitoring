/**
 * @file TimeService.cpp
 * @brief Implementation of TimeService. NTP time synchronization and timestamp formatting.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "TimeService.hpp"
#include "CloudLogger.hpp"

#include <WiFi.h>

#include <ctime>

TimeService::TimeService() : synced_(false)
{
}

std::int64_t TimeService::GetCurrentUnixTimeUtc() const
{
    time_t now;
    time(&now);
    if (now < 1700000000)
    {
        return 0;
    }

    return static_cast<std::int64_t>(now);
}

String TimeService::FormatTimestampLocal(std::int64_t unixTime) const
{
    const std::time_t ts = static_cast<std::time_t>(unixTime);
    std::tm timeInfo{};
    localtime_r(&ts, &timeInfo);

    char buffer[24];
    const std::size_t len = std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &timeInfo);
    if (len == 0)
    {
        return "1970-01-01 00:00:00";
    }

    return String(buffer);
}

bool TimeService::SyncTimeWithNtp(unsigned long timeoutMs)
{
    if (WiFi.status() != WL_CONNECTED)
    {
        Log.log("Cannot sync time: WiFi not connected");
        synced_ = false;
        return false;
    }

    configTzTime("CET-1CEST,M3.5.0/2,M10.5.0/3", "pool.ntp.org", "time.nist.gov", "time.google.com");

    struct tm timeInfo{};
    const unsigned long start = millis();

    while (millis() - start < timeoutMs)
    {
        if (getLocalTime(&timeInfo, 1000))
        {
            char buffer[32];
            strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &timeInfo);

            Log.logf("NTP time synced. Local time: %s", buffer);

            synced_ = true;
            return true;
        }

        delay(500);
    }

    Log.log("NTP time sync failed");
    synced_ = false;
    return false;
}

bool TimeService::IsSynced() const
{
    return synced_;
}
