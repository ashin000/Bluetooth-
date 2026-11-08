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
  final Map<String, List<_ChatMessage>> conversations = {};
  final Map<String, String> contacts = {};
  final Map<String, String> peerNames = {};
  final Map<String, String> addressPeerNames = {};
  final Map<String, String> addressPeerIds = {};
  final Map<String, String> peerAddresses = {};
  final Set<String> customContactIds = {};
  String? activeChatAddress;
  bool historyLoaded = false;
  StreamSubscription<Map<String, dynamic>>? events;
  int tab = 0;
  bool connected = false;
  bool sending = false;
  String status = 'Bluetooth idle';
  String localId = '';
  String localName = 'Mesh User';
  final profileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadLocalId();
    loadLocalName();
    loadChatData();
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

  Future<void> loadLocalName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('mesh_local_name') ?? 'Mesh User';
    if (!mounted) return;
    setState(() {
      localName = saved;
      profileNameController.text = saved;
    });
  }

  Future<void> saveLocalName() async {
    final value = profileNameController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }
    if (value.length > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be 24 characters or fewer')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh_local_name', value);
    if (!mounted) return;
    setState(() => localName = value);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local name saved')),
    );
  }

  Future<void> loadChatData() async {
    final prefs = await SharedPreferences.getInstance();
    final rawContacts = prefs.getString('mesh_contacts');
    final rawCustom = prefs.getString('mesh_custom_contact_ids');
    if (rawCustom != null) {
      customContactIds.addAll((jsonDecode(rawCustom) as List).map((e) => e.toString()));
    }
    final rawMessages = prefs.getString('mesh_conversations');
    if (rawContacts != null) {
      final decoded = jsonDecode(rawContacts) as Map<String, dynamic>;
      contacts.addAll(decoded.map((key, value) => MapEntry(key, value.toString())));
    }
    if (rawMessages != null) {
      final decoded = jsonDecode(rawMessages) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final items = (entry.value as List).cast<Map>();
        conversations[entry.key] = items.map((item) => _ChatMessage(
          item['text'].toString(), item['mine'] == true,
          DateTime.tryParse(item['time'].toString()) ?? DateTime.now(),
        )).toList();
      }
    }
    if (mounted) setState(() => historyLoaded = true);
  }

  Future<void> persistChatData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh_contacts', jsonEncode(contacts));
    await prefs.setString('mesh_custom_contact_ids', jsonEncode(customContactIds.toList()));
    final encoded = conversations.map((key, value) => MapEntry(key, value.map((m) => {
      'text': m.text, 'mine': m.mine, 'time': m.time.toIso8601String(),
    }).toList()));
    await prefs.setString('mesh_conversations', jsonEncode(encoded));
  }

  String contactName(String address) => contacts[address] ?? peerNames[address] ?? 'Unknown contact';

  Future<void> addContact(String address, {String? suggestedName}) async {
    final fallback = suggestedName?.trim().isNotEmpty == true
        ? suggestedName!.trim() : 'MeshMessage contact';
    contacts.putIfAbsent(address, () => fallback);
    conversations.putIfAbsent(address, () => <_ChatMessage>[]);
    await persistChatData();
    if (mounted) {
      setState(() {
        activeChatAddress = null;
        tab = 0;
      });
    }
  }

  Future<void> renameContact(String address) async {
    final controller = TextEditingController(text: contactName(address));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit contact name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Contact name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    contacts[address] = value;
    customContactIds.add(address);
    await persistChatData();
    if (mounted) setState(() {});
  }

  void onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e['event']?.toString();
    final data = e['data'];

    if (type == 'peerIdentity') {
      final info = Map<String, dynamic>.from(data as Map);
      final address = info['address'].toString();
      final peerId = info['peerId'].toString();
      if (peerId.isNotEmpty && peerId != localId) {
        final previousId = addressPeerIds[address];
        if (previousId != null && previousId != peerId) {
          contacts.remove(previousId);
          conversations.remove(previousId);
          customContactIds.remove(previousId);
        }
        addressPeerIds[address] = peerId;
        peerAddresses[peerId] = address;
        contacts.putIfAbsent(peerId, () => peerNames[peerId] ?? 'MeshMessage contact');
        conversations.putIfAbsent(peerId, () => <_ChatMessage>[]);
        persistChatData();
        if (mounted) setState(() {});
      }
      return;
    }
    if (type == 'peerName') {
      final info = Map<String, dynamic>.from(data as Map);
      final address = info['address'].toString();
      final name = info['name'].toString().trim();
      final peerId = addressPeerIds[address];
      if (peerId != null && name.isNotEmpty) {
        peerNames[peerId] = name;
        addressPeerNames[address] = name;
        for (final device in devices) {
          if (device['address']?.toString() == address) device['name'] = name;
        }
        if (!customContactIds.contains(peerId)) contacts[peerId] = name;
        persistChatData();
        if (mounted) setState(() {});
      }
      return;
    }
    if (type == 'message') {
      final address = data is Map ? (data['from'] ?? '').toString() : '';
      final messageText = data is Map ? (data['text'] ?? '').toString() : data.toString();
      final peerId = addressPeerIds[address] ?? address;
      if (address.isNotEmpty) {
        setState(() {
          conversations.putIfAbsent(peerId, () => <_ChatMessage>[])
              .add(_ChatMessage(messageText, false, DateTime.now()));
          contacts.putIfAbsent(peerId, () => peerNames[peerId] ?? 'MeshMessage contact');
        });
        persistChatData();
      }
      return;
    }

    setState(() {
      if (type == 'status') {
        status = data.toString();
      } else if (type == 'device') {
        final device = Map<String, dynamic>.from(data as Map);
        final address = device['address']?.toString() ?? '';
        device['name'] = addressPeerNames[address] ?? device['name'] ?? 'MeshMessage Device';
        final existingIndex = devices.indexWhere((item) => item['address'] == address);
        if (existingIndex == -1) {
          devices.add(device);
        } else {
          devices[existingIndex] = device;
        }
      } else if (type == 'connected') {
        connected = true;
        status = 'Connected: $data';
        // The peer identity and profile name arrive in handshake events.
      } else if (type == 'disconnected') {
        connected = false;
        status = 'Disconnected: $data';
      } else if (type == 'error') {
        status = 'Error: $data';
      }
      // Transport acknowledgements are intentionally not displayed as messages.
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
      await radio.startServer(localId, localName);
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
      await radio.connect(address, localId, localName);
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  Future<void> send() async {
    final value = composer.text.trim();
    if (value.isEmpty || sending || activeChatAddress == null) return;
    if (utf8.encode(value).length > 20) {
      setState(() => status = 'Bluetooth limit is 20 UTF-8 bytes');
      return;
    }
    setState(() => sending = true);
    try {
      final peerAddress = peerAddresses[activeChatAddress!] ?? activeChatAddress!;
      await radio.send(value, peerAddress);
      if (mounted) {
        setState(() => conversations.putIfAbsent(activeChatAddress!, () => <_ChatMessage>[]).add(_ChatMessage(value, true, DateTime.now())));
        await persistChatData();
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
    profileNameController.dispose();
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
        onDestinationSelected: (v) => setState(() {
          tab = v;
          if (v == 0) activeChatAddress = null;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.devices_other), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget chatTab() {
    if (activeChatAddress == null) {
      final addresses = contacts.keys.toList()
        ..sort((a, b) {
          final aItems = conversations[a] ?? [];
          final bItems = conversations[b] ?? [];
          final aTime = aItems.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : aItems.last.time;
          final bTime = bItems.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : bItems.last.time;
          return bTime.compareTo(aTime);
        });
      if (!historyLoaded) {
        return const Center(child: CircularProgressIndicator());
      }
      if (addresses.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 64, color: Colors.white.withValues(alpha: 0.45)),
                const SizedBox(height: 16),
                const Text('Your chats will appear here',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Connect to a nearby MeshMessage device to add it to your contacts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => setState(() => tab = 1),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Find nearby devices'),
                ),
              ],
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: addresses.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 82, endIndent: 16),
        itemBuilder: (context, index) {
          final address = addresses[index];
          final items = conversations[address] ?? [];
          final last = items.isEmpty ? 'No messages yet' : items.last.text;
          final initial = contactName(address).trim().isEmpty
              ? '?' : contactName(address).trim().substring(0, 1).toUpperCase();
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF285A55),
              child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            ),
            title: Text(contactName(address),
              style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: items.isEmpty ? Colors.white54 : Colors.white70)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) { if (v == 'rename') renameContact(address); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Edit contact name')),
              ],
            ),
            onTap: () => setState(() => activeChatAddress = address),
          );
        },
      );
    }
    final address = activeChatAddress!;
    final items = conversations[address] ?? [];
    return Column(children: [
      Material(
        color: const Color(0xFF1B2B2A),
        child: ListTile(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => activeChatAddress = null)),
          title: Text(contactName(address), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(peerAddresses[address] ?? 'MeshMessage contact'),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => renameContact(address)),
        ),
      ),
      Expanded(
        child: items.isEmpty
          ? const Center(child: Text('No messages with this contact yet.'))
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final m = items[items.length - 1 - index];
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
                  hintText: connected ? 'Message (20-byte limit)' : 'Connect this contact to send',
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
    ]);
  }

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
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                CircleAvatar(child: Icon(Icons.person)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your profile', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Local profile · No account required',
                        style: TextStyle(fontSize: 12, color: Colors.white60)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: profileNameController,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Enter your local name',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => saveLocalName(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saveLocalName,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Current name: $localName',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    ),
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
