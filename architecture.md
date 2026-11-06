# MeshMessage v0.2 architecture

## Transports
- Phone BLE: existing custom Android GATT central/peripheral path.
- Accessory BLE: Flutter central connects to ESP32-S3 peripheral.
- LoRa: SX1262 radio-to-radio link; TX disabled in this starter pending legal profile.
- Future phone Wi-Fi Aware / Wi-Fi Direct: optional higher-throughput transport.

## Routing interface (next step)
Define a common transport contract: discover(), connect(peer), send(packet),
incomingPackets and transportStatus.

Route policy:
1. Try an active direct transport to recipient.
2. Otherwise enqueue encrypted packet.
3. Forward only if TTL > 0 and message ID is not in duplicate cache.
4. Decrement hop count and set expiry on forwarding.
5. Mark delivered only after recipient acknowledgement.

## Security
This version is a transport prototype, not a secure messenger.
Implement authenticated key agreement (X25519), per-session keys,
authenticated encryption (AES-GCM or ChaCha20-Poly1305), unique nonces,
replay protection and signed identity fingerprints. Relays must only see
ciphertext.
