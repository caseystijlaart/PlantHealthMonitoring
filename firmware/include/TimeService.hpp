/**
 * @file TimeService.hpp
 * @brief NTP time synchronization and timestamp formatting.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>

/**
 * @brief A class for managing time-related operations, including NTP synchronization and timestamp formatting.
 */
class TimeService
{
public:
    /**
     * @brief Constructs a new time service instance.
     */
    TimeService();

    /**
     * @brief Gets the current UTC Unix timestamp.
     * @return The current UTC Unix timestamp.
     */
    std::int64_t GetCurrentUnixTimeUtc() const;

    /**
     * @brief Formats a Unix timestamp as a local date/time string.
     * @param unixTime The Unix timestamp to format.
     * @return The formatted date/time string.
     */
    String FormatTimestampLocal(std::int64_t unixTime) const;

    /**
     * @brief Synchronizes the system time with an NTP server.
     * @param timeoutMs The maximum time to wait for synchronization, in milliseconds.
     * @return True if synchronization was successful, false otherwise.
     */
    bool SyncTimeWithNtp(unsigned long timeoutMs = 20000);

    /**
     * @brief Checks if the system time is synchronized.
     * @return True if the time is synchronized, false otherwise.
     */
    bool IsSynced() const;

private:
    bool synced_;
};
