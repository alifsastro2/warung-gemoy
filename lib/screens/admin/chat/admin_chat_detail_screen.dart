import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminChatDetailScreen extends StatefulWidget {
  final Map<String, dynamic> chat;
  const AdminChatDetailScreen({super.key, required this.chat});

  @override
  State<AdminChatDetailScreen> createState() =>
      _AdminChatDetailScreenState();
}

class _AdminChatDetailScreenState extends State<AdminChatDetailScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  bool _isSending = false;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
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
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await Supabase.instance.client
          .from('chat_sessions')
          .select('*, chat_messages(*)')
          .eq('chat_id', widget.chat['id'])
          .order('opened_at');

      final sessionList =
          List<Map<String, dynamic>>.from(sessions).map((s) {
        final msgs =
            List<Map<String, dynamic>>.from(s['chat_messages'] as List)
              ..sort((a, b) => (a['created_at'] as String)
                  .compareTo(b['created_at'] as String));
        return {...s, 'chat_messages': msgs};
      }).toList();

      setState(() {
        _sessions = sessionList;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('admin_chat_${widget.chat['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_sessions',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Map<String, dynamic>? get _openSession =>
      _sessions.where((s) => s['status'] == 'open').firstOrNull;

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final session = _openSession;
    if (session == null) return;

    setState(() => _isSending = true);
    try {
      await Supabase.instance.client.from('chat_messages').insert({
        'session_id': session['id'],
        'sender_type': 'admin',
        'message': message,
      });
      _messageController.clear();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal kirim: $e')));
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _closeSession() async {
    final session = _openSession;
    if (session == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selesaikan Sesi?'),
        content: const Text(
            'Tandai sesi ini selesai? Pelanggan bisa memulai sesi baru kapan saja.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Selesaikan',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await Supabase.instance.client.from('chat_sessions').update({
        'status': 'closed',
        'closed_at': DateTime.now().toIso8601String(),
      }).eq('id', session['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sesi diselesaikan'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.chat['users'] as Map<String, dynamic>?;
    final name = user?['name'] ?? 'Pelanggan';
    final hasOpen = _openSession != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            Text(hasOpen ? 'Sesi aktif' : 'Tidak ada sesi aktif',
                style: TextStyle(
                    color:
                        hasOpen ? Colors.white70 : Colors.white54,
                    fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (hasOpen)
            TextButton(
              onPressed: _closeSession,
              child: const Text('Selesaikan',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange))
          : Column(
              children: [
                Expanded(
                  child: _sessions.isEmpty
                      ? const Center(
                          child: Text('Belum ada pesan',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _sessions.length,
                          itemBuilder: (ctx, i) =>
                              _buildSession(_sessions[i], i),
                        ),
                ),
                if (hasOpen) _buildInputBar(),
                if (!hasOpen)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey.shade100,
                    child: const Text(
                      'Tidak ada sesi aktif. Tunggu pelanggan memulai chat baru.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSession(Map<String, dynamic> session, int index) {
    final isClosed = session['status'] == 'closed';
    final messages =
        session['chat_messages'] as List<Map<String, dynamic>>;
    final openedAt =
        DateTime.tryParse(session['opened_at'] ?? '')?.toLocal();
    final dateStr =
        openedAt != null ? DateFormat('d MMM yyyy').format(openedAt) : '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              const SizedBox(width: 8),
              Text('Sesi ${index + 1} · $dateStr',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(width: 8),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        ...messages.map((msg) => _messageBubble(msg)),
        if (isClosed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Expanded(child: Divider(color: Colors.green)),
                const SizedBox(width: 8),
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Diselesaikan · ${session['closed_at'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(session['closed_at']).toLocal()) : ''}',
                  style: const TextStyle(color: Colors.green, fontSize: 11),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Divider(color: Colors.green)),
              ],
            ),
          ),
      ],
    );
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Menunggu Pembayaran';
      case 'waiting_verification': return 'Verifikasi Pembayaran';
      case 'processing': return 'Sedang Dimasak';
      case 'delivered': return 'Sedang Dikirim';
      case 'completed': return 'Selesai';
      case 'cancelled': return 'Dibatalkan';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'waiting_verification': return Colors.blue;
      case 'processing': return Colors.purple;
      case 'delivered': return Colors.teal;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildOrderCard(String orderId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('orders')
          .select('id, total, status')
          .eq('id', orderId)
          .maybeSingle(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox();
        final order = snapshot.data!;
        final shortId = orderId.substring(0, 8).toUpperCase();
        final status = order['status'] as String? ?? '';
        final total = order['total'] as int? ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$shortId',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    Row(
                      children: [
                        Text(_formatPrice(total),
                            style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text(_getStatusLabel(status),
                            style: TextStyle(
                                color: _getStatusColor(status),
                                fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final isAdmin = msg['sender_type'] == 'admin';
    final dt = DateTime.tryParse(msg['created_at'] ?? '')?.toLocal();
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt) : '';
    final msgOrderId = msg['order_id'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isAdmin) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade200,
              child: const Icon(Icons.person, color: Colors.grey, size: 16),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (msgOrderId != null)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.72,
                    child: _buildOrderCard(msgOrderId),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAdmin ? Colors.orange : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isAdmin ? 16 : 4),
                      bottomRight: Radius.circular(isAdmin ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05), blurRadius: 4)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isAdmin
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(msg['message'] ?? '',
                          style: TextStyle(
                              color: isAdmin ? Colors.white : Colors.black87)),
                      const SizedBox(height: 4),
                      Text(timeStr,
                          style: TextStyle(
                              color: isAdmin
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                              fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Balas pelanggan...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isSending ? null : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: Colors.orange, shape: BoxShape.circle),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
