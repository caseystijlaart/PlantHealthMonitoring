/**
 * @file NvsStorage.cpp
 * @brief Implementation of NvsStorage. Thin wrapper around the Arduino Preferences (NVS) library.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "NvsStorage.hpp"

#include <Preferences.h>

bool NvsStorage::writeString(const char *key, const String &value)
{
    Preferences prefs;
    if (!prefs.begin(kNamespace, /*readOnly=*/false))
        return false;
    prefs.putString(key, value);
    prefs.end();
    return true;
}

String NvsStorage::readString(const char *key, const String &defaultValue)
{
    Preferences prefs;
    if (!prefs.begin(kNamespace, /*readOnly=*/true))
        return defaultValue;
    const String val = prefs.getString(key, defaultValue);
    prefs.end();
    return val;
}

bool NvsStorage::hasKey(const char *key)
{
    Preferences prefs;
    if (!prefs.begin(kNamespace, /*readOnly=*/true))
        return false;
    const bool found = prefs.isKey(key);
    prefs.end();
    return found;
}

bool NvsStorage::remove(const char *key)
{
    Preferences prefs;
    if (!prefs.begin(kNamespace, /*readOnly=*/false))
        return false;
    const bool removed = prefs.remove(key);
    prefs.end();
    return removed;
}

void NvsStorage::clearAll()
{
    Preferences prefs;
    if (prefs.begin(kNamespace, /*readOnly=*/false))
    {
        prefs.clear();
        prefs.end();
    }
}
