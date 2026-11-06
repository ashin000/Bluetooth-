import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/bluetooth_service.dart';
import 'screens/radio_accessory_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MeshMessageApp());
}

class MeshMessageApp extends StatelessWidget {
  const MeshMessageApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MeshMessage',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF128C7E),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF101B20),
    ),
    home: const MeshHomePage(),
  );
}


class MeshHomePage extends StatefulWidget {
  const MeshHomePage({super.key});

  @override
  State<MeshHomePage> createState() => _MeshHomePageState();
}

class _ChatMessage {
  _ChatMessage(this.text, this.mine, this.time);
  final String text;
  final bool mine;
  final DateTime time;
}

class _MeshHomePageState extends State<MeshHomePage> {
  final radio = BluetoothService();
  final composer = TextEditingController();
  final devices = <Map<String, dynamic>>[];
  final messages = <_ChatMessage>[];
  StreamSubscription<Map<String, dynamic>>? events;
  int tab = 0;
  bool connected = false;
  bool sending = false;
  String status = 'Bluetooth idle';
  String localId = '';

  @override
  void initState() {
    super.initState();
    loadLocalId();
    events = radio.events.listen(onEvent, onError: (Object e) {
      if (mounted) setState(() => status = e.toString());
    });
  }

  Future<void> loadLocalId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('mesh_local_id') ?? '';
    if (id.isEmpty) {
      id = 'mesh-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await prefs.setString('mesh_local_id', id);
    }
    if (mounted) setState(() => localId = id);
  }

  void onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e['event']?.toString();
    final data = e['data'];
    setState(() {
      if (type == 'status') status = data.toString();
      if (type == 'device') {
        final d = Map<String, dynamic>.from(data as Map);
        if (!devices.any((x) => x['address'] == d['address'])) devices.add(d);
      }
      if (type == 'connected') {
        connected = true;
        status = 'Connected: $data';
      }
      if (type == 'disconnected') {
        connected = false;
        status = 'Disconnected: $data';
      }
      if (type == 'message') {
        messages.add(_ChatMessage(
          data is Map ? (data['text'] ?? '').toString() : data.toString(),
          false,
          DateTime.now(),
        ));
      }
      if (type == 'sent') {
        messages.add(_ChatMessage(data.toString(), true, DateTime.now()));
      }
      if (type == 'error') { status = 'Error: $data'; }
    });
  }

  Future<bool> prepare() async {
    try {
      final ok = await radio.requestPermissions();
      if (!ok && mounted) setState(() => status = 'Bluetooth permission denied');
      return ok;
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
      return false;
    }
  }

  Future<void> server() async {
    if (!await prepare()) return;
    try {
      await radio.startServer();
      if (mounted) setState(() { devices.clear(); status = 'Bluetooth server started'; });
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  Future<void> scan() async {
    if (!await prepare()) return;
    try {
      await radio.startScan();
      if (mounted) setState(() { devices.clear(); status = 'Scanning nearby devices'; });
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  Future<void> connect(String address) async {
    try {
      await radio.stopScan();
      await radio.connect(address);
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  Future<void> send() async {
    final value = composer.text.trim();
    if (value.isEmpty || sending) return;
    if (utf8.encode(value).length > 20) {
      setState(() => status = 'Bluetooth limit is 20 UTF-8 bytes');
      return;
    }
    setState(() => sending = true);
    try {
      await radio.send(value);
      if (mounted) {
        setState(() => messages.add(_ChatMessage(value, true, DateTime.now())));
        composer.clear();
      }
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> stop() async {
    try {
      await radio.stopScan();
      await radio.stopServer();
      await radio.disconnect();
      if (mounted) {
        setState(() {
        connected = false;
        devices.clear();
        status = 'Bluetooth stopped';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  @override
  void dispose() {
    events?.cancel();
    composer.dispose();
    radio.stopScan();
    radio.stopServer();
    radio.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [chatTab(), deviceTab(), settingsTab()];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MeshMessage', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(['Chats', 'Nearby devices', 'Settings'][tab],
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: connected ? Colors.lightGreenAccent : null),
          ),
        ],
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.devices_other), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget chatTab() => Column(
    children: [
      if (!connected)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Connect to a nearby MeshMessage device to start chatting.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        ),
      Expanded(
        child: messages.isEmpty
          ? const Center(child: Text('No messages yet. Connect a device to begin.'))
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(14),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final m = messages[messages.length - 1 - index];
                return Align(
                  alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: m.mine ? const Color(0xFF075E54) : const Color(0xFF25343B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Align(alignment: Alignment.centerLeft, child: Text(m.text)),
                      Text('${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 10, color: Colors.white54)),
                    ]),
                  ),
                );
              },
            ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: composer,
                minLines: 1,
                maxLines: 3,
                maxLength: 20,
                decoration: InputDecoration(
                  hintText: connected ? 'Message (20-byte limit)' : 'Connect a device first',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF26363D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: connected && !sending ? send : null,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
            ),
          ]),
        ),
      ),
    ],
  );

  Widget deviceTab() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: ListTile(
        leading: Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_searching),
        title: const Text('Bluetooth status'),
        subtitle: Text(status),
      )),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: server, icon: const Icon(Icons.cell_tower), label: const Text('Start server')),
        FilledButton.tonalIcon(onPressed: scan, icon: const Icon(Icons.search), label: const Text('Scan devices')),
        OutlinedButton.icon(onPressed: stop, icon: const Icon(Icons.stop), label: const Text('Stop')),
      ]),
      const SizedBox(height: 18),
      const Text('Nearby MeshMessage devices', style: TextStyle(fontWeight: FontWeight.bold)),
      Expanded(
        child: devices.isEmpty
          ? const Center(child: Text('No devices found. Start scanning.'))
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, i) {
                final d = devices[i];
                return Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.smartphone)),
                  title: Text((d['name'] ?? 'Unknown device').toString()),
                  subtitle: Text('${d['address']} · RSSI ${d['rssi']}'),
                  trailing: IconButton(icon: const Icon(Icons.link), onPressed: () => connect(d['address'].toString())),
                ));
              },
            ),
      ),
    ]),
  );

  Widget settingsTab() => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(
      leading: const Icon(Icons.person_outline),
      title: const Text('Local device identity'),
      subtitle: SelectableText(localId.isEmpty ? 'Generating local ID...' : localId),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: localId.isEmpty ? null : () async {
          await Clipboard.setData(ClipboardData(text: localId));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copied')));
        },
      ),
    )),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text('BLUETOOTH', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.2)),
    ),
    Card(child: Column(children: [
      ListTile(leading: const Icon(Icons.bluetooth), title: const Text('Phone-to-phone Bluetooth'), subtitle: Text(status)),
      ListTile(leading: const Icon(Icons.cell_tower), title: const Text('Start Bluetooth server'), onTap: server),
      ListTile(leading: const Icon(Icons.search), title: const Text('Scan nearby devices'), onTap: scan),
      ListTile(leading: const Icon(Icons.stop_circle_outlined), title: const Text('Stop / disconnect'), onTap: stop),
    ])),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text('LORA', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.2)),
    ),
    Card(child: ListTile(
      leading: const Icon(Icons.settings_input_antenna),
      title: const Text('LoRa radio accessory'),
      subtitle: const Text('Scan and connect to your BLE-to-LoRa accessory'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RadioAccessoryPage())),
    )),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Text('Prototype: Bluetooth messages are limited to 20 UTF-8 bytes. LoRa radio transmission remains disabled until the compliant regional radio profile is confirmed.',
        style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
    ),
  ]);
}
