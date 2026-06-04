#pragma once

#include <Arduino.h>

class TimeService
{
public:
    TimeService();

    std::int64_t GetCurrentUnixTimeUtc() const;
    String FormatTimestampLocal(std::int64_t unixTime) const;

    bool SyncTimeWithNtp(unsigned long timeoutMs = 20000);
    bool IsSynced() const;

private:
    bool synced_;
};
