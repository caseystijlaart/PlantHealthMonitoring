/**
 * @file NvsStorage.hpp
 * @brief Thin wrapper around the Arduino Preferences (NVS) library.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#pragma once

#include <Arduino.h>

/**
 * @brief Provides simple key-value string storage backed by ESP32 NVS.
 *
 * All keys are stored under the @c "phm_prov" namespace.
 */
class NvsStorage
{
public:
    /**
     * @brief Writes a string value to NVS.
     * @param key   Key name.
     * @param value Value to store.
     * @return @c true on success.
     */
    static bool writeString(const char *key, const String &value);

    /**
     * @brief Reads a string value from NVS.
     * @param key          Key name.
     * @param defaultValue Returned when the key does not exist.
     * @return Stored value, or @p defaultValue if the key is absent.
     */
    static String readString(const char *key, const String &defaultValue = "");

    /**
     * @brief Returns @c true if the given key exists in NVS.
     * @param key Key name.
     */
    static bool hasKey(const char *key);

    /**
     * @brief Removes a single key from NVS.
     * @param key Key name.
     * @return @c true on success.
     */
    static bool remove(const char *key);

    /**
     * @brief Erases all keys in the @c "phm_prov" namespace.
     */
    static void clearAll();

private:
    static constexpr const char *kNamespace = "phm_prov";
};
