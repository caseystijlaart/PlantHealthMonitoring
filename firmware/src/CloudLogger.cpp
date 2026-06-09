#include "CloudLogger.hpp"

#include <time.h>

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

CloudLogger Log;

size_t CloudLogger::write(uint8_t c)
{
    Serial.write(c);              // mirror to the serial monitor in real time

    if (c == '\r') return 1;      // ignore CR; the line ends on '\n'
    if (c == '\n') { finishLine(); return 1; }
    if (line_.length() < kMaxLine) line_ += static_cast<char>(c);
    return 1;
}

size_t CloudLogger::write(const uint8_t *buffer, size_t size)
{
    for (size_t i = 0; i < size; ++i) write(buffer[i]);
    return size;
}

void CloudLogger::finishLine()
{
    if (line_.isEmpty()) return;
    if (queue_.size() >= kMaxQueued)
        queue_.erase(queue_.begin());   // drop the oldest line if we overflow
    queue_.push_back({ classify(line_), line_, millis() });
    line_ = "";
}

const char *CloudLogger::classify(const String &line)
{
    String l = line;
    l.toLowerCase();
    if (l.indexOf("fail")      >= 0 || l.indexOf("error")  >= 0 ||
        l.indexOf("timed out") >= 0 || l.indexOf("timeout") >= 0 ||
        l.indexOf("could not") >= 0 || l.indexOf("unable")  >= 0)
        return "ERROR";
    return "OK";
}

void CloudLogger::configure(const char *baseUrl, const char *apiKey, const char *caCert)
{
    baseUrl_ = baseUrl;
    apiKey_  = apiKey;
    caCert_  = caCert;
}

void CloudLogger::setTimeProvider(int64_t (*nowUnixUtc)())
{
    nowUnixUtc_ = nowUnixUtc;
}

String CloudLogger::toIso8601(int64_t unixUtc)
{
    char buf[21];
    const time_t t = static_cast<time_t>(unixUtc);
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));
    return String(buf);
}

String CloudLogger::jsonEscape(const String &s)
{
    String out;
    out.reserve(s.length() + 8);
    for (unsigned i = 0; i < s.length(); ++i)
    {
        const char c = s[i];
        switch (c)
        {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:
                if (static_cast<unsigned char>(c) < 0x20)
                {
                    char buf[7];
                    snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    out += buf;
                }
                else
                {
                    out += c;
                }
        }
    }
    return out;
}

void CloudLogger::uploadPending(const String &deviceId, const String &deviceName)
{
    if (queue_.empty())                  return;
    if (baseUrl_ == nullptr)             return;
    if (deviceId.isEmpty())              return;
    if (WiFi.status() != WL_CONNECTED)   return;

    // Every row needs a timestamp, so wait for a valid clock.  Lines stay queued
    // and retry on the next flush until the time is known (usually right after
    // NTP sync, before the first upload).
    const int64_t uploadUnix = nowUnixUtc_ ? nowUnixUtc_() : 0;
    if (uploadUnix <= 0) return;
    const uint32_t uploadMillis = millis();

    // One JSON array → PostgREST inserts every queued line in a single request.
    const String dId   = jsonEscape(deviceId);
    const String dName = jsonEscape(deviceName);

    String body;
    body.reserve(80 * queue_.size());
    body = "[";
    for (unsigned i = 0; i < queue_.size(); ++i)
    {
        // Back-compute each line's creation time from how long ago it was logged.
        const uint32_t ageMs = uploadMillis - queue_[i].millisAt; // wraps cleanly
        const int64_t  ts    = uploadUnix - static_cast<int64_t>(ageMs / 1000UL);

        if (i) body += ",";
        body += "{\"device_id\":\"";      body += dId;
        body += "\",\"device_name\":\"";  body += dName;
        body += "\",\"status\":\"";       body += queue_[i].status;
        body += "\",\"timestamp\":\"";    body += toIso8601(ts);
        body += "\",\"message\":\"";      body += jsonEscape(queue_[i].message);
        body += "\"}";
    }
    body += "]";

    const String url = String(baseUrl_) + "/logs";

    WiFiClientSecure client;
    client.setCACert(caCert_);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader("Content-Type",  "application/json");
    https.addHeader("apikey",        apiKey_);
    https.addHeader("Authorization", String("Bearer ") + apiKey_);
    https.addHeader("Prefer",        "return=minimal");

    const int code = https.POST(body);
    https.end();

    // Use raw Serial here — never this logger — so uploading doesn't enqueue
    // more log lines and recurse.
    Serial.printf("[Log] Uploaded %u line(s) -> %d\n",
                  static_cast<unsigned>(queue_.size()), code);

    if (code >= 200 && code < 300)
        queue_.clear();   // keep the queue on failure so lines retry next time
}
