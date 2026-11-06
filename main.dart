import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'services/bluetooth_service.dart';
import 'screens/radio_accessory_page.dart';

void main() => runApp(const MeshMessageApp());

class MeshMessageApp extends StatelessWidget {
  const MeshMessageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshMessage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16A36A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MeshHomePage(),
    );
  }
}

class MeshHomePage extends StatefulWidget {
  const MeshHomePage({super.key});

  @override
  State<MeshHomePage> createState() => _MeshHomePageState();
}

class _MeshHomePageState extends State<MeshHomePage> {
  final BluetoothService _bluetooth = BluetoothService();
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _devices = [];
  final List<String> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _subscription;

  String _status = 'Not started';
  bool _serverStarted = false;
  bool _connected = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _subscription = _bluetooth.events.listen(
      _handleEvent,
      onError: (Object error) {
        if (mounted) setState(() => _status = 'Event error: $error');
      },
    );
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['event']?.toString();
    final data = event['data'];

    setState(() {
      switch (type) {
        case 'status':
          _status = data.toString();
          break;
        case 'device':
          final device = Map<String, dynamic>.from(data as Map);
          if (!_devices.any((d) => d['address'] == device['address'])) {
            _devices.add(device);
          }
          break;
        case 'connected':
          _connected = true;
          _status = 'Connected: $data';
          break;
        case 'disconnected':
          _connected = false;
          _status = 'Disconnected: $data';
          break;
        case 'message':
          if (data is Map) {
            _messages.add('Received: ${data['text'] ?? ''}');
          } else {
            _messages.add('Received: $data');
          }
          break;
        case 'sent':
          _messages.add('Sent: $data');
          break;
        case 'error':
          _status = 'Error: $data';
          break;
      }
    });
  }

  Future<bool> _prepare() async {
    try {
      final granted = await _bluetooth.requestPermissions();
      if (!granted && mounted) {
        setState(() => _status = 'Bluetooth permissions denied');
      }
      return granted;
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
      return false;
    }
  }

  Future<void> _startServer() async {
    if (!await _prepare()) return;
    try {
      await _bluetooth.startServer();
      if (mounted) {
        setState(() {
          _serverStarted = true;
          _devices.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    }
  }

  Future<void> _startScan() async {
    if (!await _prepare()) return;
    try {
      await _bluetooth.startScan();
      if (mounted) {
        setState(() {
          _serverStarted = false;
          _devices.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    }
  }

  Future<void> _connect(String address) async {
    try {
      await _bluetooth.stopScan();
      await _bluetooth.connect(address);
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _working) return;

    // v0.1 deliberately limits payloads to 20 UTF-8 bytes.
    if (utf8.encode(text).length > 20) {
      setState(() => _status = 'Phone-to-phone BLE v0.1 limit is 20 UTF-8 bytes. Use short text.');
      return;
    }

    setState(() => _working = true);
    try {
      await _bluetooth.send(text);
      _messageController.clear();
      setState(() => _messages.add('You: $text'));
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    try {
      await _bluetooth.stopScan();
      await _bluetooth.stopServer();
      await _bluetooth.disconnect();
      if (mounted) {
        setState(() {
          _serverStarted = false;
          _connected = false;
          _status = 'Stopped';
          _devices.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _messageController.dispose();
    _bluetooth.stopScan();
    _bluetooth.stopServer();
    _bluetooth.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MeshMessage'),
            Text(
              'Hybrid Bluetooth + LoRa prototype v0.2',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'LoRa accessory',
            icon: const Icon(Icons.settings_input_antenna),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RadioAccessoryPage()),
            ),
          ),
          Icon(
            _connected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: _connected ? Colors.greenAccent : null,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.network_check),
                  title: const Text('Phone-to-phone Bluetooth status'),
                  subtitle: Text(_status),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _startServer,
                    icon: const Icon(Icons.cell_tower),
                    label: const Text('Start server'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Scan devices'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Nearby MeshMessage devices',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 150,
                child: _devices.isEmpty
                    ? const Center(
                        child: Text('No devices discovered yet'),
                      )
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.smartphone),
                              title: Text(device['name'].toString()),
                              subtitle: Text(
                                '${device['address']} · RSSI ${device['rssi']}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.link),
                                onPressed: () => _connect(
                                  device['address'].toString(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              const Text(
                'Messages',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _messages.isEmpty
                    ? const Center(child: Text('No messages yet'))
                    : ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => Align(
                          alignment: Alignment.centerLeft,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(_messages[index]),
                            ),
                          ),
                        ),
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLength: 20,
                      decoration: const InputDecoration(
                        hintText: 'Short test message',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _working ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Prototype note: phone-to-phone BLE is plaintext. LoRa firmware TX is disabled pending Indian radio-profile approval. Do not use for private messages.',
                style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
