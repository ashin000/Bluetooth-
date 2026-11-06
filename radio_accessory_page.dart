import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'lora_accessory_service.dart';

class RadioAccessoryPage extends StatefulWidget {
  const RadioAccessoryPage({super.key});
  @override
  State<RadioAccessoryPage> createState() => _RadioAccessoryPageState();
}

class _RadioAccessoryPageState extends State<RadioAccessoryPage> {
  final _radio = LoraAccessoryService();
  final _message = TextEditingController();
  final _logs = <String>[];
  StreamSubscription<String>? _eventSub;
  StreamSubscription<String>? _receiveSub;
  bool _scanning = false;
  bool _connected = false;
  String _status = 'Not connected';

  @override
  void initState() {
    super.initState();
    _eventSub = _radio.events.listen((e) {
      if (!mounted) return;
      setState(() { _status = e; _logs.insert(0, e); });
    });
    _receiveSub = _radio.received.listen((e) {
      if (!mounted) return;
      setState(() => _logs.insert(0, 'RECEIVED: $e'));
    });
  }

  Future<void> _scan() async {
    try {
      setState(() { _scanning = true; _status = 'Scanning...'; });
      await _radio.scan();
      await Future<void>.delayed(const Duration(seconds: 12));
    } catch (e) {
      setState(() => _status = 'Scan error: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await _radio.connect(device);
      if (mounted) setState(() { _connected = true; _status = 'Radio connected'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Connection error: $e');
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    try {
      await _radio.sendText(text);
      if (mounted) {
        setState(() => _logs.insert(0, 'QUEUED TO RADIO: $text'));
        _message.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Send error: $e');
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _receiveSub?.cancel();
    _message.dispose();
    _radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LoRa accessory')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: ListTile(
            leading: Icon(_connected ? Icons.radio : Icons.bluetooth_searching),
            title: const Text('Accessory status'),
            subtitle: Text(_status),
          )),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.search),
            label: Text(_scanning ? 'Scanning...' : 'Scan LoRa accessories'),
          ),
          const SizedBox(height: 8),
          const Text('Discovered accessories', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 150,
            child: _radio.scanResults.isEmpty
              ? const Center(child: Text('No radio accessories found'))
              : ListView.builder(
                  itemCount: _radio.scanResults.length,
                  itemBuilder: (context, i) {
                    final r = _radio.scanResults[i];
                    return ListTile(
                      title: Text(r.device.platformName.isEmpty ? 'MeshMessage Radio' : r.device.platformName),
                      subtitle: Text('${r.device.remoteId} · RSSI ${r.rssi}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.link),
                        onPressed: () => _connect(r.device),
                      ),
                    );
                  },
                ),
          ),
          const Divider(),
          const Text('Radio message test', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: _message,
              maxLength: 180,
              decoration: const InputDecoration(
                hintText: 'Type a short test message',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _connected ? _send : null, icon: const Icon(Icons.send)),
          ]),
          const SizedBox(height: 8),
          const Text('Activity log', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: _logs.isEmpty
            ? const Center(child: Text('No radio activity yet'))
            : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(_logs[i], style: const TextStyle(fontSize: 12)),
                ),
              )),
          const Text(
            'Prototype warning: radio transmission is disabled in the supplied firmware until the correct Indian operating profile is confirmed. This screen tests the phone-to-accessory BLE bridge.',
            style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
          ),
        ]),
      ),
    );
  }
}
