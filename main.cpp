/*
  MeshMessage radio accessory firmware
  Target: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262)

  SAFETY / REGULATORY:
  - This starter intentionally has TX disabled (MESH_TX_ENABLED=0).
  - Do not enable TX or select a LoRa profile until WPC confirms that
    the exact modulation, bandwidth, channel, ERP, duty cycle, hopping/
    channel access and equipment approval are lawful for this use in India.
  - RX test frequency below is only a local bench receiver setting.
  - Confirm the exact board revision and pin map before flashing.
*/

#include <Arduino.h>
#include <SPI.h>
#include <RadioLib.h>
#include <NimBLEDevice.h>

#ifndef MESH_TX_ENABLED
#define MESH_TX_ENABLED 0
#endif

// Heltec WiFi LoRa 32 V3 pin mapping. V2/V4 boards differ.
static constexpr int PIN_LORA_SCK  = 9;
static constexpr int PIN_LORA_MISO = 11;
static constexpr int PIN_LORA_MOSI = 10;
static constexpr int PIN_LORA_CS   = 8;
static constexpr int PIN_LORA_RST  = 12;
static constexpr int PIN_LORA_DIO1 = 14;
static constexpr int PIN_LORA_BUSY = 13;

// BLE GATT UUIDs must match lib/services/lora_accessory_service.dart.
static const char* SERVICE_UUID = "7b100001-7b10-4d2a-9f31-112233445566";
static const char* RX_UUID      = "7b100002-7b10-4d2a-9f31-112233445566";
static const char* TX_UUID      = "7b100003-7b10-4d2a-9f31-112233445566";

// Receiver-only bench setting. Do not use this as a transmit configuration.
static constexpr float RX_BENCH_FREQ_MHZ = 866.0f;

SX1262 radio = new Module(PIN_LORA_CS, PIN_LORA_DIO1, PIN_LORA_RST, PIN_LORA_BUSY);
NimBLECharacteristic* txCharacteristic = nullptr;
volatile bool radioPacketReceived = false;

void setRadioFlag() { radioPacketReceived = true; }

void notifyPhone(const String& text) {
  if (txCharacteristic == nullptr) return;
  txCharacteristic->setValue(text.c_str());
  txCharacteristic->notify();
}

class RxCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& connInfo) override {
    std::string value = characteristic->getValue();
    if (value.empty()) return;
#if MESH_TX_ENABLED
    // TX intentionally remains unimplemented until the approved profile,
    // packet framing, duty-cycle limiter and security review are completed.
    notifyPhone("TX_NOT_IMPLEMENTED");
#else
    notifyPhone("TX_DISABLED_WPC_PROFILE_REQUIRED");
#endif
  }
};

void setupBle() {
  NimBLEDevice::init("MeshMessage-Radio");
  NimBLEDevice::setMTU(247);
  NimBLEServer* server = NimBLEDevice::createServer();
  NimBLEService* service = server->createService(SERVICE_UUID);

  NimBLECharacteristic* rx = service->createCharacteristic(
    RX_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  rx->setCallbacks(new RxCallbacks());

  txCharacteristic = service->createCharacteristic(
    TX_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  txCharacteristic->setValue("RADIO_BOOTING");

  service->start();
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->start();
}

void setupRadioReceiver() {
  SPI.begin(PIN_LORA_SCK, PIN_LORA_MISO, PIN_LORA_MOSI, PIN_LORA_CS);
  // Receiver-only bench initialization. No transmit call is made here.
  int state = radio.begin(RX_BENCH_FREQ_MHZ, 125.0, 9, 7, 0x12, 10, 8, 1.8, false);
  if (state == RADIOLIB_ERR_NONE) {
    radio.setDio1Action(setRadioFlag);
    radio.startReceive();
    notifyPhone("RADIO_RX_READY_TX_DISABLED");
  } else {
    notifyPhone(String("RADIO_INIT_ERROR_") + state);
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  setupBle();
  setupRadioReceiver();
  Serial.println("MeshMessage radio accessory ready; TX disabled.");
}

void loop() {
  if (radioPacketReceived) {
    radioPacketReceived = false;
    String incoming;
    int state = radio.readData(incoming);
    if (state == RADIOLIB_ERR_NONE) {
      notifyPhone(String("RX:") + incoming);
      Serial.println(String("RX: ") + incoming);
    }
    radio.startReceive();
  }
  delay(5);
}
