# MeshMessage Hybrid v0.2 (starter build)

This bundle extends the supplied v0.1 Android BLE prototype with a BLE GATT
client screen for a LoRa accessory and starter firmware for **Heltec WiFi
LoRa 32 V3 (ESP32-S3 + SX1262)**.

## Included
- Existing v0.1 phone-to-phone BLE GATT prototype.
- Flutter LoRa accessory page and BLE GATT client.
- Shared GATT UUIDs for Flutter and ESP32 firmware.
- PlatformIO firmware starter for Heltec WiFi LoRa 32 V3.
- Receiver-only SX1262 bench initialization.
- LoRa transmit deliberately disabled pending Indian WPC review.

## Important: not a finished mesh messenger
This is a development starter, not a verified production build. It has not
been compiled on your laptop or tested with physical Heltec boards. The
existing phone-to-phone BLE path remains plaintext, one-hop and limited to
20 UTF-8 bytes. The new LoRa page tests the phone-to-accessory BLE bridge;
firmware reports TX disabled. No end-to-end encryption, recipient addressing,
multi-hop routing, acknowledgements, persistent queue, background relay or
verified 1 km range is implemented yet. Do not use for private messages.

## Hardware
For the first pair, use **two matching Heltec WiFi LoRa 32 V3 boards** with
the correct regional RF variant and matching LoRa antennas. Confirm each
board is V3 with ESP32-S3 + SX1262. Do not mix V2, V3 and V4 firmware/pin maps.
Each phone connects to its own board over BLE.

Also required: two Android phones, USB-C data cables, suitable power sources,
and the correct antenna fitted before any radio operation.

## Indian radio compliance gate
The WPC 865–868 MHz SRD rules (G.S.R. 853(E), 10 Dec 2021) contain
different technical categories and limits. A general-purpose encrypted chat
radio must not assume it qualifies for a particular category. LoRa 125 kHz
chirp modulation is not automatically authorised just because a module
supports 865–868 MHz. Do not enable radio transmission until WPC or a
qualified Indian RF compliance professional confirms the exact frequency,
waveform, bandwidth, ERP, channel access/hopping, duty cycle and equipment
approval. TX is intentionally disabled in this firmware.

Official starting points:
- DoT/WPC: https://www.dot.gov.in/
- WPC ETA portal: https://www.eservices.dot.gov.in/equipment-type-approval-eta
- Heltec V3 docs: https://wiki.heltec.org/
- Android BLE permissions: https://developer.android.com/develop/connectivity/bluetooth/bt-permissions

## Flutter setup (Windows PowerShell)
1. Install Flutter, Android Studio/Android SDK and VS Code.
2. Extract this folder and open it in VS Code.
3. If Android scaffold is not present, run:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\setup_android.ps1
   ```
4. Run:
   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   flutter devices
   flutter run
   ```
5. The main screen retains the original phone-to-phone BLE test.
   Tap the antenna icon to open **LoRa accessory**.
6. Flash one Heltec V3 board and scan for `MeshMessage-Radio`.

## Firmware
Install PlatformIO in VS Code and open:
`firmware/heltec_wifi_lora32_v3`

Build and upload to Heltec WiFi LoRa 32 V3. Open PlatformIO Serial Monitor
at 115200 baud. If the board ID is unavailable, select the exact V3 board
from PlatformIO's registry and update platformio.ini.

## BLE accessory protocol
Service UUID: `7b100001-7b10-4d2a-9f31-112233445566`
- RX (phone writes): `7b100002-7b10-4d2a-9f31-112233445566`
- TX (accessory notifies): `7b100003-7b10-4d2a-9f31-112233445566`

Temporary Flutter packet limit: 180 UTF-8 bytes. This is not yet a
fragmentation/reassembly protocol.

## Next milestones
1. Compile and verify phone-to-accessory BLE.
2. Confirm WPC-compliant radio profile before enabling TX.
3. Implement packet framing, CRC, fragmentation and acknowledgements.
4. Implement phone-side end-to-end encryption and authenticated identities.
5. Add radio-node store-and-forward, duplicate suppression, hop count and TTL.
6. Add Wi-Fi Aware / Wi-Fi Direct phone-to-phone transport.
7. Field-test direct 1 km and multi-hop links; report measured results.

## Build APK
After Android setup:
```powershell
flutter build apk --release
```
APK: `build\app\outputs\flutter-apk\app-release.apk`
