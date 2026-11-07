import 'dart:async';
import 'package:flutter/services.dart';

class BluetoothService {
  static const MethodChannel _methods = MethodChannel('mesh/bluetooth');
  static const EventChannel _events = EventChannel('mesh/events');

  Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().map(
        (event) => Map<String, dynamic>.from(event as Map),
      );

  Future<bool> requestPermissions() async =>
      await _methods.invokeMethod<bool>('requestPermissions') ?? false;

  Future<void> startServer() => _methods.invokeMethod('startServer');
  Future<void> stopServer() => _methods.invokeMethod('stopServer');
  Future<void> startScan() => _methods.invokeMethod('startScan');
  Future<void> stopScan() => _methods.invokeMethod('stopScan');

  Future<void> connect(String address) =>
      _methods.invokeMethod('connect', {'address': address});

  Future<void> send(String message, String address) =>
      _methods.invokeMethod('send', {'message': message, 'address': address});

  Future<void> disconnect() => _methods.invokeMethod('disconnect');
}
