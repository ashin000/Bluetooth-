import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE GATT bridge to a MeshMessage LoRa accessory.
/// The accessory UUIDs must match firmware/src/main.cpp.
class LoraAccessoryService {
  static final Guid serviceUuid =
      Guid('7b100001-7b10-4d2a-9f31-112233445566');
  static final Guid rxUuid =
      Guid('7b100002-7b10-4d2a-9f31-112233445566');
  static final Guid txUuid =
      Guid('7b100003-7b10-4d2a-9f31-112233445566');

  final StreamController<String> _events =
      StreamController<String>.broadcast();
  final StreamController<String> _received =
      StreamController<String>.broadcast();

  Stream<String> get events => _events.stream;
  Stream<String> get received => _received.stream;
  final List<ScanResult> scanResults = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;

  bool get isConnected => _device != null && _rx != null;

  Future<void> scan() async {
    scanResults.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertised = result.advertisementData.serviceUuids;
        if (advertised.any((id) => id == serviceUuid) ||
            result.device.platformName.toLowerCase().contains('mesh')) {
          if (!scanResults.any((r) => r.device.remoteId == result.device.remoteId)) {
            scanResults.add(result);
          }
        }
      }
      _events.add('Scan updated: ${scanResults.length} device(s)');
    });
    await FlutterBluePlus.startScan(
      withServices: [serviceUuid],
      timeout: const Duration(seconds: 12),
    );
    _events.add('Scanning for MeshMessage LoRa accessories...');
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;
    await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    final services = await device.discoverServices();
    final matches = services.where((s) => s.uuid == serviceUuid).toList();
    if (matches.isEmpty) {
      throw Exception('MeshMessage radio service not found');
    }
    final service = matches.first;
    final rxMatches = service.characteristics.where((c) => c.uuid == rxUuid).toList();
    final txMatches = service.characteristics.where((c) => c.uuid == txUuid).toList();
    _rx = rxMatches.isEmpty ? null : rxMatches.first;
    _tx = txMatches.isEmpty ? null : txMatches.first;
    if (_rx == null || _tx == null) {
      throw Exception('Radio RX/TX characteristics not found');
    }
    await _tx!.setNotifyValue(true);
    _notifySub = _tx!.onValueReceived.listen((bytes) {
      final text = utf8.decode(bytes, allowMalformed: true);
      _received.add(text);
      _events.add('Radio received: $text');
    });
    _events.add('Connected to LoRa accessory: ${device.platformName}');
  }

  Future<void> sendText(String text) async {
    if (_rx == null) throw Exception('Connect a LoRa accessory first');
    final bytes = utf8.encode(text);
    if (bytes.length > 180) {
      throw Exception('Prototype packet limit is 180 bytes');
    }
    await _rx!.write(bytes, withoutResponse: false);
    _events.add('Submitted ${bytes.length} bytes to radio accessory');
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    final old = _device;
    _device = null;
    _rx = null;
    _tx = null;
    if (old != null) {
      try { await old.disconnect(); } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await disconnect();
    await _events.close();
    await _received.close();
  }
}
