import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MeshChatService {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  String get myUid => FirebaseAuth.instance.currentUser!.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> conversations() => db.collection('chats')
      .where('members', arrayContains: myUid).snapshots();

  Future<Map<String, dynamic>> findProfile(String uid) async {
    final doc = await db.collection('profiles').doc(uid.trim()).get();
    if (!doc.exists) throw Exception('No MeshMessage user found with that UID.');
    return {'uid': doc.id, ...doc.data()!};
  }

  Future<String> openConversation(String otherUid) async {
    if (otherUid == myUid) throw Exception('You cannot start a chat with yourself.');
    final profile = await findProfile(otherUid);
    final members = [myUid, otherUid]..sort();
    final chatId = members.join('_');
    final ref = db.collection('chats').doc(chatId);
    await db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (!existing.exists) {
        tx.set(ref, {
          'members': members,
          'memberNames': {myUid: FirebaseAuth.instance.currentUser?.displayName ?? 'Me', otherUid: profile['username'] ?? 'User'},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastSenderUid': '',
        });
      }
    });
    return chatId;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String chatId) =>
      db.collection('chats').doc(chatId).collection('messages').orderBy('createdAt').snapshots();

  Future<void> sendMessage(String chatId, String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    final chat = db.collection('chats').doc(chatId);
    final message = chat.collection('messages').doc();
    final batch = db.batch();
    batch.set(message, {'senderUid': myUid, 'text': value, 'createdAt': FieldValue.serverTimestamp()});
    batch.update(chat, {'lastMessage': value, 'lastSenderUid': myUid, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}

class ChatListPage extends StatelessWidget {
  ChatListPage({super.key});
  final MeshChatService service = MeshChatService();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder(
      stream: service.conversations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load chats: ' + snapshot.error.toString()));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No conversations yet. Tap + to find someone by UID.'));
        return ListView.separated(
          itemCount: docs.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final members = List<String>.from(data['members'] ?? []);
            final other = members.firstWhere((id) => id != service.myUid, orElse: () => '');
            final names = Map<String, dynamic>.from(data['memberNames'] ?? {});
            final name = names[other]?.toString() ?? 'MeshMessage user';
            final last = data['lastMessage']?.toString() ?? '';
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(last.isEmpty ? 'Start a conversation' : last, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(chatId: docs[index].id, title: name))),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        final controller = TextEditingController();
        final uid = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
          title: const Text('Start a new chat'),
          content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Enter recipient UID')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Continue')),
          ],
        ));
        controller.dispose();
        if (uid == null || uid.isEmpty || !context.mounted) return;
        try {
          final id = await service.openConversation(uid);
          final profile = await service.findProfile(uid);
          if (!context.mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(chatId: id, title: profile['username']?.toString() ?? 'User')));
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
        }
      },
      child: const Icon(Icons.person_add_alt_1),
    ),
  );
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.chatId, required this.title});
  final String chatId;
  final String title;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final service = MeshChatService();
  final controller = TextEditingController();
  bool sending = false;
  @override
  void dispose() { controller.dispose(); super.dispose(); }

  Future<void> send() async {
    if (sending || controller.text.trim().isEmpty) return;
    final text = controller.text.trim();
    setState(() => sending = true);
    try {
      await service.sendMessage(widget.chatId, text);
      controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message failed: ' + e.toString())));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: const [Padding(padding: EdgeInsets.only(right: 14), child: Icon(Icons.cloud_done_outlined))]),
    body: Column(children: [
      Expanded(child: StreamBuilder(
        stream: service.messages(widget.chatId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not load messages: ' + snapshot.error.toString()));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Say hello 👋'));
          return ListView.builder(
            reverse: true, padding: const EdgeInsets.all(14), itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[docs.length - 1 - index].data();
              final mine = data['senderUid'] == service.myUid;
              final stamp = data['createdAt'];
              final time = stamp is Timestamp ? stamp.toDate() : null;
              final timeText = time == null ? '' : time.hour.toString().padLeft(2, '0') + ':' + time.minute.toString().padLeft(2, '0');
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300), margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(color: mine ? const Color(0xFF075E54) : const Color(0xFF25343B), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Align(alignment: Alignment.centerLeft, child: Text(data['text']?.toString() ?? '')),
                    Text(timeText, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ]),
                ),
              );
            },
          );
        },
      )),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(children: [
          Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 4,
            decoration: InputDecoration(hintText: 'Message', filled: true, fillColor: const Color(0xFF26363D),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            onSubmitted: (_) => send())),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send),
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF128C7E))),
        ]),
      )),
    ]),
  );
}
