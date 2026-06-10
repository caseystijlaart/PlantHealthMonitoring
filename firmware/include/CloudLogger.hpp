/**
 * @file CloudLogger.hpp
 * @brief Line-based logger that queues log messages and batch-uploads them to the cloud logs table.
 * @version 1.2.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <WString.h>
#include <vector>

// ── CloudLogger ───────────────────────────────────────────────────────────────
// A line-based cloud logger.  Each call to log()/logf() queues one complete
// message for upload to the Supabase `logs` table.  Nothing is written to
// Serial — this logger is independent of the Arduino Print/serial-monitor
// machinery.
//
// Each message is classified OK/ERROR by a keyword heuristic (failures →
// ERROR).
//
// Uploads are batched (one HTTPS request inserts all queued lines) and only
// happen when WiFi is up and a device_id is known; lines emitted before then —
// e.g. during early boot or BLE provisioning — stay queued and flush once the
// device is online.
//
// Usage:
//   Log.configure(kSupabaseBase, API_KEY, kSupabaseRootCA);  // once, in setup()
//   Log.log("hello");
//   Log.logf("value: %d", 42);
//   Log.uploadPending(gDeviceId, gDeviceName);               // flush when online
class CloudLogger
{
public:
    /**
     * @brief Queue one log message for upload.
     */
    void log(const String &message);

    /**
     * @brief Queue one printf-formatted log message for upload.
     */
    void logf(const char *format, ...) __attribute__((format(printf, 2, 3)));

    /**
     * @brief Configures the supabase rest endpoint
     * @param baseUrl the supabase base url
     * @param apiKey publishable key obtained from supabase
     * @param caCert certificate
     */
    void configure(const String &baseUrl, const String &apiKey, const char *caCert);

    /**
     * @brief Upload all queued lines as a single batched insert into `logs`.
     * @details No-op when the queue is empty, WiFi is down, deviceId is empty, or the logger has not been configured yet.
     * @param deviceId the given device
     * @param deviceName the given device name
     */
    void uploadPending(const String &deviceId, const String &deviceName);

private:
    struct Entry
    {
        const char *status;
        String message;
    };

    void enqueue(const String &message);
    static const char *classify(const String &line);
    static String jsonEscape(const String &s);

    std::vector<Entry> queue_;
    String baseUrl_;
    String apiKey_;
    const char *caCert_ = nullptr;

    static constexpr size_t kMaxLine = 240;  // per-line cap (chars)
    static constexpr size_t kMaxQueued = 60; // ring-buffer cap (lines)
};

// Single global instance, defined in CloudLogger.cpp.
extern CloudLogger Log;
