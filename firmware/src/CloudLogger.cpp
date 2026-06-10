/**
 * @file CloudLogger.cpp
 * @brief Implementation of CloudLogger. Line-based logger that queues log messages and batch-uploads them to the cloud logs table.
 * @version 1.2.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "CloudLogger.hpp"

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

#include <cstdarg>
#include <cstdio>

CloudLogger Log;

void CloudLogger::log(const String &message)
{
    enqueue(message);
}

void CloudLogger::logf(const char *format, ...)
{
    char buf[kMaxLine + 1];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    enqueue(String(buf));
}

void CloudLogger::enqueue(const String &message)
{
    if (message.isEmpty())
        return;
    String line = message;
    if (line.length() > kMaxLine)
        line = line.substring(0, kMaxLine);
    if (queue_.size() >= kMaxQueued)
        queue_.erase(queue_.begin());
    queue_.push_back({classify(line), line});
}

const char *CloudLogger::classify(const String &line)
{
    String l = line;
    l.toLowerCase();
    if (l.indexOf("fail") >= 0 || l.indexOf("error") >= 0 ||
        l.indexOf("timed out") >= 0 || l.indexOf("timeout") >= 0 ||
        l.indexOf("could not") >= 0 || l.indexOf("unable") >= 0)
        return "ERROR";
    return "OK";
}

void CloudLogger::configure(const String &baseUrl, const String &apiKey, const char *caCert)
{
    baseUrl_ = baseUrl;
    apiKey_ = apiKey;
    caCert_ = caCert;
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
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
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
    if (queue_.empty())
        return;
    if (baseUrl_.isEmpty())
        return;
    if (deviceId.isEmpty())
        return;
    if (WiFi.status() != WL_CONNECTED)
        return;

    const String dId = jsonEscape(deviceId);
    const String dName = jsonEscape(deviceName);

    String body;
    body.reserve(64 * queue_.size());
    body = "[";
    for (unsigned i = 0; i < queue_.size(); ++i)
    {
        if (i)
            body += ",";
        body += "{\"device_id\":\"";
        body += dId;
        body += "\",\"device_name\":\"";
        body += dName;
        body += "\",\"status\":\"";
        body += queue_[i].status;
        body += "\",\"message\":\"";
        body += jsonEscape(queue_[i].message);
        body += "\"}";
    }
    body += "]";

    const String url = String(baseUrl_) + "/logs";

    WiFiClientSecure client;
    client.setCACert(caCert_);
    HTTPClient https;
    if (!https.begin(client, url))
        return;

    https.addHeader("Content-Type", "application/json");
    https.addHeader("apikey", apiKey_);
    https.addHeader("Authorization", String("Bearer ") + apiKey_);
    https.addHeader("Prefer", "return=minimal");

    const int code = https.POST(body);
    https.end();

    if (code >= 200 && code < 300)
        queue_.clear();
}
