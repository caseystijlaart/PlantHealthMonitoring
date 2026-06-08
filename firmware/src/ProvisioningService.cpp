#include "ProvisioningService.hpp"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLECharacteristic.h>
#include <esp_random.h>

#include "NvsStorage.hpp"

// ── BLE protocol UUIDs (fixed — identify the PHM provisioning service type) ──
#define SERVICE_UUID   "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define PASSWORD_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define DEVICEID_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// ── Static members ────────────────────────────────────────────────────────────
String ProvisioningService::ssid_;
String ProvisioningService::password_;
String ProvisioningService::deviceId_;
bool   ProvisioningService::ssidSet_      = false;
bool   ProvisioningService::passwordSet_  = false;

// ── UUID generation ───────────────────────────────────────────────────────────

String ProvisioningService::getOrCreateDeviceId()
{
    // Re-use existing UUID if already stored in NVS
    const String existing = NvsStorage::readString("device_id");
    if (!existing.isEmpty())
        return existing;

    // Generate UUID v4 using the ESP32 hardware RNG
    uint8_t b[16];
    esp_fill_random(b, sizeof(b));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant RFC 4122

    char uuid[37];
    snprintf(uuid, sizeof(uuid),
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x"
        "-%02x%02x%02x%02x%02x%02x",
        b[0],  b[1],  b[2],  b[3],
        b[4],  b[5],  b[6],  b[7],
        b[8],  b[9],
        b[10], b[11], b[12], b[13], b[14], b[15]);

    const String id(uuid);
    NvsStorage::writeString("device_id", id);
    Serial.printf("[Prov] Generated device UUID: %s\n", uuid);
    return id;
}

// ── BLE write callbacks ───────────────────────────────────────────────────────

class SsidCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onSsidWritten(
            String(pChar->getValue().c_str()));
    }
};

class PasswordCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) override {
        ProvisioningService::_onPasswordWritten(
            String(pChar->getValue().c_str()));
    }
};

// ── Public API ────────────────────────────────────────────────────────────────

void ProvisioningService::begin(const char *deviceName, const String &deviceId)
{
    ssid_         = "";
    password_     = "";
    deviceId_     = deviceId;
    ssidSet_      = false;
    passwordSet_  = false;

    BLEDevice::init(deviceName);
    BLEServer  *pServer  = BLEDevice::createServer();
    BLEService *pService = pServer->createService(SERVICE_UUID);

    // SSID — write-only
    BLECharacteristic *ssidChar = pService->createCharacteristic(
        SSID_UUID, BLECharacteristic::PROPERTY_WRITE);
    ssidChar->setCallbacks(new SsidCallback());

    // Password — write-only (no read; keeps password off the wire in both directions)
    BLECharacteristic *passChar = pService->createCharacteristic(
        PASSWORD_UUID, BLECharacteristic::PROPERTY_WRITE);
    passChar->setCallbacks(new PasswordCallback());

    // Device ID — read-only (app reads the UUID that was generated on-device)
    BLECharacteristic *devIdChar = pService->createCharacteristic(
        DEVICEID_UUID, BLECharacteristic::PROPERTY_READ);
    devIdChar->setValue(deviceId.c_str());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // helps iPhone connections
    BLEDevice::startAdvertising();

    Serial.printf("[BLE] Advertising as '%s' — device_id: %s\n",
                  deviceName, deviceId.c_str());
}

void ProvisioningService::stop()
{
    BLEDevice::stopAdvertising();
    BLEDevice::deinit(/*release_memory=*/true);
    Serial.println(F("[BLE] Provisioning stopped"));
}

bool ProvisioningService::isProvisioned()
{
    return ssidSet_ && passwordSet_;
}

const String &ProvisioningService::getSsid()     { return ssid_;     }
const String &ProvisioningService::getPassword() { return password_; }
const String &ProvisioningService::getDeviceId() { return deviceId_; }

// ── Write callbacks ───────────────────────────────────────────────────────────

void ProvisioningService::_onSsidWritten(const String &v)
{
    ssid_    = v;
    ssidSet_ = true;
    Serial.printf("[BLE] SSID received (%u chars)\n", v.length());
}

void ProvisioningService::_onPasswordWritten(const String &v)
{
    password_    = v;
    passwordSet_ = true;
    Serial.println(F("[BLE] Password received"));
}
