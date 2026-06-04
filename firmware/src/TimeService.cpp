#include "TimeService.hpp"

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
        Serial.println("Cannot sync time: WiFi not connected");
        synced_ = false;
        return false;
    }

    configTzTime("CET-1CEST,M3.5.0/2,M10.5.0/3", "pool.ntp.org", "time.nist.gov", "time.google.com");

    Serial.println("Syncing time with NTP...");
    struct tm timeInfo{};
    const unsigned long start = millis();

    while (millis() - start < timeoutMs)
    {
        if (getLocalTime(&timeInfo, 1000))
        {
            char buffer[32];
            strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &timeInfo);

            Serial.print("NTP time synced. Local time: ");
            Serial.println(buffer);

            synced_ = true;
            return true;
        }

        Serial.println("Waiting for NTP time...");
        delay(500);
    }

    Serial.println("NTP time sync failed");
    synced_ = false;
    return false;
}

bool TimeService::IsSynced() const
{
    return synced_;
}
