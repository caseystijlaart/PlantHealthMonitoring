/**
 * @file ProvisioningService.cpp
 * @brief Implementation of ProvisioningService. BLE provisioning service receiving WiFi and Supabase credentials from the app.
 * @version 1.1.0
 * @date 2026-06-10
 * @author C. Stijlaart
 * @copyright Copyright (c) 2026 C. Stijlaart. Released under the MIT License.
 */
#include "ProvisioningService.hpp"
#include "CloudLogger.hpp"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLECharacteristic.h>
#include <BLEAdvertising.h>
#include <esp_random.h>

#include "NvsStorage.hpp"

String ProvisioningService::ssid_;
String ProvisioningService::password_;
String ProvisioningService::deviceId_;
String ProvisioningService::apiKey_;
String ProvisioningService::supabaseUrl_;
bool   ProvisioningService::ssidSet_         = false;
bool   ProvisioningService::passwordSet_     = false;
bool   ProvisioningService::apiKeySet_       = false;
bool   ProvisioningService::supabaseUrlSet_  = false;
volatile bool ProvisioningService::reAdvertise_ = false;

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SSID_UUID           "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define PASSWORD_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define DEVICEID_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define APIKEY_UUID         "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define SUPABASE_URL_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26ac"

/// @cond INTERNAL

class SsidCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onSsidWritten(String(pChar->getValue().c_str()));
    }
};

class PasswordCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onPasswordWritten(String(pChar->getValue().c_str()));
    }
};

class ApiKeyCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onApiKeyWritten(String(pChar->getValue().c_str()));
    }
};

class SupabaseUrlCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onSupabaseUrlWritten(String(pChar->getValue().c_str()));
    }
};

class ProvServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *) override {
        ProvisioningService::_onClientConnected();
    }
    void onDisconnect(BLEServer *) override {
        ProvisioningService::_onClientDisconnected();
    }
};

/// @endcond

String ProvisioningService::getOrCreateDeviceId()
{
    const String existing = NvsStorage::readString("device_id");
    if (!existing.isEmpty()) return existing;

    uint8_t b[16];
    esp_fill_random(b, sizeof(b));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;

    char uuid[37];
    snprintf(uuid, sizeof(uuid),
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[0],  b[1],  b[2],  b[3],  b[4],  b[5],  b[6],  b[7],
        b[8],  b[9],  b[10], b[11], b[12], b[13], b[14], b[15]);

    const String id(uuid);
    NvsStorage::writeString("device_id", id);
    return id;
}

void ProvisioningService::begin(const char *deviceName, const String &deviceId)
{
    ssid_ = password_ = apiKey_ = supabaseUrl_ = "";
    deviceId_       = deviceId;
    ssidSet_        = passwordSet_ = apiKeySet_ = supabaseUrlSet_ = false;

    reAdvertise_ = false;

    BLEDevice::init(deviceName);
    BLEServer  *pServer  = BLEDevice::createServer();
    pServer->setCallbacks(new ProvServerCallbacks());
    BLEService *pService = pServer->createService(SERVICE_UUID);

    auto *ssidChar = pService->createCharacteristic(SSID_UUID, BLECharacteristic::PROPERTY_WRITE);
    ssidChar->setCallbacks(new SsidCallback());

    auto *passChar = pService->createCharacteristic(PASSWORD_UUID, BLECharacteristic::PROPERTY_WRITE);
    passChar->setCallbacks(new PasswordCallback());

    auto *devIdChar = pService->createCharacteristic(DEVICEID_UUID, BLECharacteristic::PROPERTY_READ);
    devIdChar->setValue(deviceId.c_str());

    auto *apiKeyChar = pService->createCharacteristic(APIKEY_UUID, BLECharacteristic::PROPERTY_WRITE);
    apiKeyChar->setCallbacks(new ApiKeyCallback());

    auto *urlChar = pService->createCharacteristic(SUPABASE_URL_UUID, BLECharacteristic::PROPERTY_WRITE);
    urlChar->setCallbacks(new SupabaseUrlCallback());

    pService->start();

    BLEAdvertising *pAdv = BLEDevice::getAdvertising();
    pAdv->addServiceUUID(SERVICE_UUID);
    pAdv->setScanResponse(true);
    pAdv->setMinPreferred(0x06);
    BLEDevice::startAdvertising();

    Log.logf("[BLE] Advertising as '%s' — device_id: %s", deviceName, deviceId.c_str());
}

void ProvisioningService::stop()
{
    BLEDevice::stopAdvertising();
    BLEDevice::deinit(true);
    Log.log("[BLE] Provisioning stopped");
}

void ProvisioningService::maintainAdvertising()
{
    if (!reAdvertise_) return;
    reAdvertise_ = false;
    delay(500);                     
    BLEDevice::startAdvertising();
    Log.log("[BLE] Client disconnected before provisioning — re-advertising");
}

void ProvisioningService::_onClientConnected()
{
    Log.log("[BLE] Client connected");
}

void ProvisioningService::_onClientDisconnected()
{
    if (!isProvisioned())
        reAdvertise_ = true;
}

bool ProvisioningService::isProvisioned()
{
    return ssidSet_ && passwordSet_ && apiKeySet_ && supabaseUrlSet_;
}

const String &ProvisioningService::getSsid()         { return ssid_;         }
const String &ProvisioningService::getPassword()      { return password_;     }
const String &ProvisioningService::getDeviceId()      { return deviceId_;     }
const String &ProvisioningService::getApiKey()        { return apiKey_;       }
const String &ProvisioningService::getSupabaseUrl()   { return supabaseUrl_;  }

void ProvisioningService::_onSsidWritten(const String &v)
{
    ssid_    = v;
    ssidSet_ = true;
    Log.logf("[BLE] SSID received (%u chars)", v.length());
}

void ProvisioningService::_onPasswordWritten(const String &v)
{
    password_    = v;
    passwordSet_ = true;
    Log.log("[BLE] Password received");
}

void ProvisioningService::_onApiKeyWritten(const String &v)
{
    apiKey_    = v;
    apiKeySet_ = true;
    Log.log("[BLE] API key received");
}

void ProvisioningService::_onSupabaseUrlWritten(const String &v)
{
    supabaseUrl_    = v;
    supabaseUrlSet_ = true;
    Log.logf("[BLE] Supabase URL received (%u chars)", v.length());
}
