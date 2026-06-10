/**
 * @file CloudLogger.hpp
 * @brief Tee logger that mirrors Serial output and batch-uploads log lines to the cloud logs table.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>
#include <vector>

// ── CloudLogger ───────────────────────────────────────────────────────────────
// A "tee" logger.  Everything written to it is:
//   1. mirrored byte-for-byte to Serial, so the serial monitor is unchanged, and
//   2. buffered one line per newline and queued for upload to the Supabase
//      `logs` table.
//
// Because it derives from Arduino's Print, it is a drop-in for Serial: print(),
// println() and printf() all work, including F() strings.  Each completed line
// is classified OK/ERROR by a keyword heuristic (failures → ERROR).
//
// Uploads are batched (one HTTPS request inserts all queued lines) and only
// happen when WiFi is up and a device_id is known; lines emitted before then —
// e.g. during early boot or BLE provisioning — stay queued and flush once the
// device is online.
//
// Usage:
//   Log.configure(kSupabaseBase, API_KEY, kSupabaseRootCA);  // once, in setup()
//   Log.println("hello");                                    // like Serial.*
//   Log.uploadPending(gDeviceId, gDeviceName);               // flush when online
class CloudLogger : public Print
{
public:
    /**
     * @brief Print interface — mirror to Serial and buffer a line for upload.
     */
    size_t write(uint8_t c) override;
    size_t write(const uint8_t *buffer, size_t size) override;

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
     * @param devideId the given device
     * @param deviceName the given device name
     */
    void uploadPending(const String &deviceId, const String &deviceName);

private:
    struct Entry
    {
        const char *status;
        String message;
    };

    void finishLine();
    static const char *classify(const String &line);
    static String jsonEscape(const String &s);

    String line_;
    std::vector<Entry> queue_;
    String baseUrl_;
    String apiKey_;
    const char *caCert_ = nullptr;

    static constexpr size_t kMaxLine = 240;  // per-line cap (chars)
    static constexpr size_t kMaxQueued = 60; // ring-buffer cap (lines)
};

// Single global instance, defined in CloudLogger.cpp.
extern CloudLogger Log;
