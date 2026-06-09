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
    // Print interface — mirror to Serial and buffer a line for upload.
    size_t write(uint8_t c) override;
    size_t write(const uint8_t *buffer, size_t size) override;

    // Supabase REST endpoint + credentials used for uploads.
    // baseUrl is e.g. "https://<proj>.supabase.co/rest/v1"; "/logs" is appended.
    void configure(const char *baseUrl, const char *apiKey, const char *caCert);

    // Upload all queued lines as a single batched insert into `logs`.
    // No-op when the queue is empty, WiFi is down, or deviceId is empty.
    void uploadPending(const String &deviceId, const String &deviceName);

private:
    struct Entry { const char *status; String message; };

    void               finishLine();
    static const char *classify(const String &line);
    static String      jsonEscape(const String &s);

    String             line_;
    std::vector<Entry> queue_;
    const char        *baseUrl_ = nullptr;
    const char        *apiKey_  = nullptr;
    const char        *caCert_  = nullptr;

    static constexpr size_t kMaxLine   = 240; // per-line cap (chars)
    static constexpr size_t kMaxQueued = 60;  // ring-buffer cap (lines)
};

// Single global instance, defined in CloudLogger.cpp.
extern CloudLogger Log;
