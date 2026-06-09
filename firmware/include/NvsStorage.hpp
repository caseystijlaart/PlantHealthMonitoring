#pragma once

#include <Arduino.h>

// Thin wrapper around the Arduino Preferences (NVS) library.
// All keys are stored under the "phm_prov" namespace.
class NvsStorage
{
public:
    static bool   writeString(const char *key, const String &value);
    static String readString (const char *key, const String &defaultValue = "");
    static bool   hasKey     (const char *key);
    static bool   remove     (const char *key);
    static void   clearAll   ();

private:
    static constexpr const char *kNamespace = "phm_prov";
};
