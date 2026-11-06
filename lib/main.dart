import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'services/bluetooth_service.dart';
import 'screens/radio_accessory_page.dart';
import 'services/chat_service.dart';

bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (_) {
    // Guest mode must remain available when Firebase or the internet is unavailable.
  }
  runApp(const MeshMessageApp());
}

class MeshMessageApp extends StatelessWidget {
  const MeshMessageApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MeshMessage', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF128C7E), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101B20)),
    home: const AuthGate());
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool loading = true;
  bool guest = false;
  String guestId = '';

  String makeGuestId() => 'guest-' + DateTime.now().microsecondsSinceEpoch.toRadixString(36) + '-' + Random.secure().nextInt(0xFFFFFF).toRadixString(16);

  @override
  void initState() {
    super.initState();
    loadSession();
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final activeGuest = prefs.getBool('mesh_guest_mode') ?? false;
    var id = prefs.getString('mesh_guest_id') ?? '';
    if (activeGuest && id.isEmpty) { id = makeGuestId(); await prefs.setString('mesh_guest_id', id); }
    setState(() { guest = activeGuest; guestId = id; loading = false; });
  }

  Future<void> enterGuest() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('mesh_guest_id') ?? makeGuestId();
    await prefs.setString('mesh_guest_id', id);
    await prefs.setBool('mesh_guest_mode', true);
    if (mounted) setState(() { guest = true; guestId = id; });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (guest || !firebaseReady) return MeshHomePage(guest: true, guestId: guestId, onExitGuest: () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('mesh_guest_mode');
      if (mounted) setState(() => guest = false);
    });
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return snap.data == null ? AuthPage(onGuest: enterGuest) : const MeshHomePage();
      });
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.onGuest});
  final VoidCallback? onGuest;
  @override
  State<AuthPage> createState() => _AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(), email = TextEditingController(), password = TextEditingController();
  bool registering = true, busy = false, hide = true;
  String? error;
  @override
  void dispose() { username.dispose(); email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() { busy = true; error = null; });
    try {
      if (!registering) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      } else {
        final name = username.text.trim();
        final user = (await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text)).user!;
        final db = FirebaseFirestore.instance;
        final profile = db.collection('profiles').doc(user.uid);
        final handle = db.collection('usernames').doc(name.toLowerCase());
        try {
          await db.runTransaction((tx) async {
            final found = await tx.get(handle);
            if (found.exists) throw StateError('Username is already taken.');
            tx.set(handle, {'authUid': user.uid, 'username': name, 'createdAt': FieldValue.serverTimestamp()});
            tx.set(profile, {'authUid': user.uid, 'uid': user.uid, 'username': name, 'usernameLower': name.toLowerCase(), 'createdAt': FieldValue.serverTimestamp()});
          });
          await user.updateDisplayName(name);
        } catch (_) { await user.delete(); rethrow; }
      }
    } on FirebaseAuthException catch (e) { setState(() => error = e.message ?? e.code); }
      catch (e) { setState(() => error = e.toString().replaceFirst('Bad state: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
    child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.forum_rounded, size: 64, color: Color(0xFF25D366)),
      const SizedBox(height: 14),
      const Text('MeshMessage', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(registering ? 'Create your account' : 'Welcome back', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 30),
      if (registering) ...[
        TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email), border: OutlineInputBorder()),
          validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch((v ?? '').trim()) ? null : '3–20 letters, numbers or underscores'),
        const SizedBox(height: 14)],
      TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
        validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email'),
      const SizedBox(height: 14),
      TextFormField(controller: password, obscureText: hide, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => hide = !hide), icon: Icon(hide ? Icons.visibility : Icons.visibility_off))),
        validator: (v) => (v ?? '').length >= 6 ? null : 'Minimum 6 characters'),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      const SizedBox(height: 20),
      FilledButton(onPressed: busy ? null : submit, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(registering ? 'Create account' : 'Log in')),
      TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = null; }), child: Text(registering ? 'Already registered? Log in' : 'Create a new account')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : widget.onGuest, icon: const Icon(Icons.wifi_off), label: const Text('Continue as Guest')),
      const Text('Guest mode works without an account. Account registration and login need internet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white54)),
      const Text('Your unique MeshMessage UID is generated automatically.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white54))
    ])))))));

class MeshHomePage extends StatefulWidget {
  const MeshHomePage({super.key, this.guest = false, this.guestId = '', this.onExitGuest});
  final bool guest;
  final String guestId;
  final VoidCallback? onExitGuest;
  @override
  State<MeshHomePage> createState() => _MeshHomePageState();
}
class _ChatMessage { _ChatMessage(this.text, this.mine, this.time); final String text; final bool mine; final DateTime time; }

class _MeshHomePageState extends State<MeshHomePage> {
  final radio = BluetoothService(), composer = TextEditingController();
  final devices = <Map<String, dynamic>>[], messages = <_ChatMessage>[];
  StreamSubscription<Map<String, dynamic>>? events;
  int tab = 0; bool connected = false, sending = false;
  String status = 'Bluetooth idle';

  @override
  void initState() { super.initState(); events = radio.events.listen(onEvent, onError: (Object e) { if (mounted) setState(() => status = e.toString()); }); }
  void onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final type = e['event']?.toString(), data = e['data'];
    setState(() {
      if (type == 'status') status = data.toString();
      if (type == 'device') { final d = Map<String, dynamic>.from(data as Map); if (!devices.any((x) => x['address'] == d['address'])) devices.add(d); }
      if (type == 'connected') { connected = true; status = 'Connected: ' + data.toString(); }
      if (type == 'disconnected') { connected = false; status = 'Disconnected: ' + data.toString(); }
      if (type == 'message') messages.add(_ChatMessage(data is Map ? (data['text'] ?? '').toString() : data.toString(), false, DateTime.now()));
      if (type == 'sent') messages.add(_ChatMessage(data.toString(), true, DateTime.now()));
      if (type == 'error') status = 'Error: ' + data.toString();
    });
  }
  Future<bool> prepare() async { try { final ok = await radio.requestPermissions(); if (!ok && mounted) setState(() => status = 'Bluetooth permission denied'); return ok; } catch (e) { if (mounted) setState(() => status = e.toString()); return false; } }
  Future<void> server() async { if (!await prepare()) return; try { await radio.startServer(); setState(() { devices.clear(); status = 'Bluetooth server started'; }); } catch (e) { setState(() => status = e.toString()); } }
  Future<void> scan() async { if (!await prepare()) return; try { await radio.startScan(); setState(() { devices.clear(); status = 'Scanning nearby devices'; }); } catch (e) { setState(() => status = e.toString()); } }
  Future<void> connect(String address) async { try { await radio.stopScan(); await radio.connect(address); } catch (e) { if (mounted) setState(() => status = e.toString()); } }
  Future<void> send() async {
    final value = composer.text.trim(); if (value.isEmpty || sending) return;
    if (utf8.encode(value).length > 20) { setState(() => status = 'Bluetooth limit is 20 UTF-8 bytes'); return; }
    setState(() => sending = true);
    try { await radio.send(value); if (mounted) { setState(() => messages.add(_ChatMessage(value, true, DateTime.now()))); composer.clear(); } }
    catch (e) { if (mounted) setState(() => status = e.toString()); }
    finally { if (mounted) setState(() => sending = false); }
  }
  Future<void> stop() async { try { await radio.stopScan(); await radio.stopServer(); await radio.disconnect(); if (mounted) setState(() { connected = false; devices.clear(); status = 'Bluetooth stopped'; }); } catch (e) { if (mounted) setState(() => status = e.toString()); } }
  @override
  void dispose() { events?.cancel(); composer.dispose(); radio.stopScan(); radio.stopServer(); radio.disconnect(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final pages = [chatTab(), deviceTab(), settingsTab()];
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('MeshMessage', style: TextStyle(fontWeight: FontWeight.bold)), Text(['Chats', 'Nearby devices', 'Settings'][tab], style: const TextStyle(fontSize: 11, color: Colors.white60))]),
        actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth, color: connected ? Colors.lightGreenAccent : null))]),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'Chats'),
        NavigationDestination(icon: Icon(Icons.devices_other), label: 'Devices'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings')]));
  }

  Widget chatTab() => widget.guest ? const GuestChatInfoPage() : ChatListPage();

  Widget deviceTab() => Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Card(child: ListTile(leading: Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_searching), title: const Text('Bluetooth status'), subtitle: Text(status))),
    Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(onPressed: server, icon: const Icon(Icons.cell_tower), label: const Text('Start server')),
      FilledButton.tonalIcon(onPressed: scan, icon: const Icon(Icons.search), label: const Text('Scan devices')),
      OutlinedButton.icon(onPressed: stop, icon: const Icon(Icons.stop), label: const Text('Stop'))]),
    const SizedBox(height: 18), const Text('Nearby MeshMessage devices', style: TextStyle(fontWeight: FontWeight.bold)),
    Expanded(child: devices.isEmpty ? const Center(child: Text('No devices found. Start scanning.')) : ListView.builder(itemCount: devices.length, itemBuilder: (context, i) {
      final d = devices[i]; return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.smartphone)), title: Text((d['name'] ?? 'Unknown device').toString()), subtitle: Text(d['address'].toString() + ' · RSSI ' + d['rssi'].toString()), trailing: IconButton(icon: const Icon(Icons.link), onPressed: () => connect(d['address'].toString()))));
    }))]));

  Widget settingsTab() {
    if (widget.guest) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: ListTile(leading: Icon(Icons.person_outline), title: Text('Guest mode'), subtitle: Text('No account or internet required for this local session.'))),
        Card(child: ListTile(leading: const Icon(Icons.wifi_off), title: const Text('Local guest ID'), subtitle: SelectableText(widget.guestId.isEmpty ? 'Creating local ID…' : widget.guestId), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: widget.guestId.isEmpty ? null : () async { await Clipboard.setData(ClipboardData(text: widget.guestId)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local ID copied'))); }))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Bluetooth and LoRa device controls are available in the Devices tab. LoRa transmission remains disabled until the radio profile is verified.', style: TextStyle(fontSize: 11, color: Colors.orangeAccent))),
        OutlinedButton.icon(onPressed: widget.onExitGuest, icon: const Icon(Icons.logout), label: const Text('Exit guest mode'))
      ]);
    }
    final user = FirebaseAuth.instance.currentUser!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ACCOUNT', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.2)),
        const SizedBox(height: 12), Row(children: [const CircleAvatar(child: Icon(Icons.person)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.displayName ?? 'MeshMessage user', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), Text(user.email ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12))]))]),
        const Divider(height: 24), const Text('Your MeshMessage UID', style: TextStyle(fontSize: 12, color: Colors.white60)),
        SelectableText(user.uid, style: const TextStyle(fontSize: 12)),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: user.uid)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UID copied'))); }, icon: const Icon(Icons.copy, size: 16), label: const Text('Copy UID')))
      ]))),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('BLUETOOTH CONFIGURATION', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.1))),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.bluetooth), title: const Text('Phone-to-phone Bluetooth'), subtitle: Text(status)),
        ListTile(leading: const Icon(Icons.cell_tower), title: const Text('Start Bluetooth server'), onTap: server),
        ListTile(leading: const Icon(Icons.search), title: const Text('Scan nearby devices'), onTap: scan),
        ListTile(leading: const Icon(Icons.stop_circle_outlined), title: const Text('Stop / disconnect'), onTap: stop)])),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('LORA CONFIGURATION', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.1))),
      Card(child: ListTile(leading: const Icon(Icons.settings_input_antenna), title: const Text('LoRa radio accessory'), subtitle: const Text('Scan, connect and inspect your BLE-to-LoRa accessory'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RadioAccessoryPage())))),
      const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Prototype note: Bluetooth messages are plaintext and limited to 20 UTF-8 bytes. The supplied LoRa firmware keeps radio transmission disabled pending confirmation of the compliant Indian radio profile.', style: TextStyle(fontSize: 11, color: Colors.orangeAccent))),
      OutlinedButton.icon(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: const Text('Log out'), style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent))
    ]);
  }

  Future<void> findUid() async {
    final c = TextEditingController();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Find a MeshMessage user'),
      content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Enter exact user UID')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final id = c.text.trim(); Navigator.pop(dialogContext); if (id.isEmpty) return;
          try {
            final doc = await FirebaseFirestore.instance.collection('profiles').doc(id).get();
            if (!mounted) return;
            final handle = doc.data()?['username']?.toString();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doc.exists ? 'Found @' + (handle ?? 'user') : 'No profile found for this UID')));
          } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lookup failed: ' + e.toString()))); }
        }, child: const Text('Search'))
      ]));
    c.dispose();
  }
}


class GuestChatInfoPage extends StatelessWidget {
  const GuestChatInfoPage({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline, size: 54, color: Colors.white54),
        SizedBox(height: 16),
        Text('Offline guest session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Your guest session does not use Firebase. Connect to another MeshMessage device from the Devices tab. Local chat history and peer-to-peer message routing are the next implementation step.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))
      ]),
    ),
  );
}
