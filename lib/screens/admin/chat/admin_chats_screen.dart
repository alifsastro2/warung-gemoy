import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_chat_detail_screen.dart';

class AdminChatsScreen extends StatefulWidget {
  const AdminChatsScreen({super.key});

  @override
  State<AdminChatsScreen> createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('chats')
          .select('*, users(name, phone), chat_sessions(id, status, opened_at, chat_messages(message, sender_type, created_at))')
          .order('created_at', ascending: false);

      setState(() {
        _chats = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('admin:chats')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  bool _hasOpenSession(Map<String, dynamic> chat) {
    final sessions = chat['chat_sessions'] as List;
    return sessions.any((s) => s['status'] == 'open');
  }

  Map<String, dynamic>? _latestMessage(Map<String, dynamic> chat) {
    final sessions = chat['chat_sessions'] as List;
    List<Map<String, dynamic>> allMessages = [];
    for (final s in sessions) {
      final msgs = s['chat_messages'] as List;
      allMessages.addAll(List<Map<String, dynamic>>.from(msgs));
    }
    if (allMessages.isEmpty) return null;
    allMessages.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));
    return allMessages.first;
  }

  @override
  Widget build(BuildContext context) {
    final activeChats =
        _chats.where((c) => _hasOpenSession(c)).toList();
    final inactiveChats =
        _chats.where((c) => !_hasOpenSession(c)).toList();
    final sorted = [...activeChats, ...inactiveChats];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('Chat Pelanggan',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange))
          : sorted.isEmpty
              ? const Center(
                  child: Text('Belum ada chat',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: sorted.length,
                    itemBuilder: (ctx, i) => _chatCard(sorted[i]),
                  ),
                ),
    );
  }

  Widget _chatCard(Map<String, dynamic> chat) {
    final user = chat['users'] as Map<String, dynamic>?;
    final name = user?['name'] ?? 'Pelanggan';
    final phone = user?['phone'] ?? '-';
    final hasOpen = _hasOpenSession(chat);
    final lastMsg = _latestMessage(chat);
    final lastMsgText = lastMsg?['message'] ?? '-';
    final lastMsgTime = lastMsg != null
        ? DateTime.tryParse(lastMsg['created_at'])?.toLocal()
        : null;
    final timeStr = lastMsgTime != null
        ? DateFormat('d MMM, HH:mm').format(lastMsgTime)
        : '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminChatDetailScreen(chat: chat),
        ),
      ).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: hasOpen
              ? Border.all(color: Colors.orange.withOpacity(0.4))
              : null,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  hasOpen ? Colors.orange.shade100 : Colors.grey.shade200,
              child: Icon(Icons.person,
                  color: hasOpen ? Colors.orange : Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                      Text(timeStr,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(phone,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    lastMsgText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (hasOpen) ...[
              const SizedBox(width: 8),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: Colors.orange, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
