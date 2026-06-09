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

    // Source of the current UTC time (Unix seconds), used to stamp each log
    // line.  Returns <= 0 until the clock is set (e.g. before NTP sync); uploads
    // wait for a valid time so every row gets a real timestamp.
    void setTimeProvider(int64_t (*nowUnixUtc)());

    // Upload all queued lines as a single batched insert into `logs`.
    // No-op when the queue is empty, WiFi is down, deviceId is empty, or the
    // clock has not been set yet.
    void uploadPending(const String &deviceId, const String &deviceName);

private:
    // millisAt records millis() at line creation so the real wall-clock time
    // can be back-computed at upload, even for lines emitted before NTP sync.
    struct Entry { const char *status; String message; uint32_t millisAt; };

    void               finishLine();
    static const char *classify(const String &line);
    static String      jsonEscape(const String &s);
    static String      toIso8601(int64_t unixUtc);

    String             line_;
    std::vector<Entry> queue_;
    const char        *baseUrl_ = nullptr;
    const char        *apiKey_  = nullptr;
    const char        *caCert_  = nullptr;
    int64_t          (*nowUnixUtc_)() = nullptr;

    static constexpr size_t kMaxLine   = 240; // per-line cap (chars)
    static constexpr size_t kMaxQueued = 60;  // ring-buffer cap (lines)
};

// Single global instance, defined in CloudLogger.cpp.
extern CloudLogger Log;
