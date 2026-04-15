import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Map<String, dynamic>? _chat;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  bool _isSending = false;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;
  bool _initialized = false;

  // Data pesanan yang dilampirkan (dari tap Chat di pesanan)
  String? _pendingOrderId;
  Map<String, dynamic>? _pendingOrderData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['order_id'] != null) {
      _pendingOrderId = args['order_id'] as String;
      _pendingOrderData = args['order_data'] as Map<String, dynamic>?;
    }
    _load();
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
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      Map<String, dynamic>? chat = await Supabase.instance.client
          .from('chats')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      chat ??= await Supabase.instance.client
          .from('chats')
          .insert({'user_id': userId})
          .select()
          .single();

      await _reloadSessions(chat['id']);
      setState(() {
        _chat = chat;
        _isLoading = false;
      });
      _subscribeRealtime(chat['id']);
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadSessions(String chatId) async {
    final sessions = await Supabase.instance.client
        .from('chat_sessions')
        .select('*, chat_messages(*)')
        .eq('chat_id', chatId)
        .order('opened_at');

    final sessionList =
        List<Map<String, dynamic>>.from(sessions).map((s) {
      final msgs =
          List<Map<String, dynamic>>.from(s['chat_messages'] as List)
            ..sort((a, b) => (a['created_at'] as String)
                .compareTo(b['created_at'] as String));
      return {...s, 'chat_messages': msgs};
    }).toList();

    setState(() => _sessions = sessionList);
  }

  void _subscribeRealtime(String chatId) {
    _channel = Supabase.instance.client
        .channel('chat_$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) async {
            await _reloadSessions(chatId);
            _scrollToBottom();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_sessions',
          callback: (_) async => await _reloadSessions(chatId),
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

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _chat == null) return;

    setState(() => _isSending = true);
    try {
      // Cari sesi open, kalau tidak ada buat baru
      var openSession =
          _sessions.where((s) => s['status'] == 'open').firstOrNull;

      if (openSession == null) {
        final session = await Supabase.instance.client
            .from('chat_sessions')
            .insert({
              'chat_id': _chat!['id'],
              'order_id': _pendingOrderId,
              'status': 'open',
            })
            .select()
            .single();
        openSession = session;
      }

      await Supabase.instance.client.from('chat_messages').insert({
        'session_id': openSession['id'],
        'sender_type': 'customer',
        'message': message,
        if (_pendingOrderId != null) 'order_id': _pendingOrderId,
      });

      _messageController.clear();
      // Hapus pending order setelah pesan terkirim
      setState(() {
        _pendingOrderId = null;
        _pendingOrderData = null;
      });

      await _reloadSessions(_chat!['id']);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal kirim: $e')));
      }
    } finally {
      setState(() => _isSending = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            Text('Admin Warung Gemoy',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange))
          : Column(
              children: [
                Expanded(
                  child: _sessions.isEmpty && _pendingOrderId == null
                      ? const Center(
                          child: Text(
                            'Belum ada pesan.\nKetik pesan untuk memulai chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _sessions.length,
                          itemBuilder: (ctx, i) =>
                              _buildSession(_sessions[i], i),
                        ),
                ),
                // Card referensi pesanan (muncul sebelum pesan pertama dikirim)
                if (_pendingOrderId != null && _pendingOrderData != null)
                  _buildPendingOrderCard(),
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildPendingOrderCard() {
    final order = _pendingOrderData!;
    final shortId =
        (_pendingOrderId!).substring(0, 8).toUpperCase();
    final status = order['status'] as String? ?? '';
    final total = order['total'] as int? ?? 0;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/order-status',
        arguments: {'order_id': _pendingOrderId},
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05), blurRadius: 4)
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long,
                  color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #$shortId',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Row(
                    children: [
                      Text(_formatPrice(total),
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _getStatusLabel(status),
                          style: TextStyle(
                              color: _getStatusColor(status),
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(String orderId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('orders')
          .select('id, total, status')
          .eq('id', orderId)
          .maybeSingle(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox();
        }
        final order = snapshot.data!;
        final shortId = orderId.substring(0, 8).toUpperCase();
        final status = order['status'] as String? ?? '';
        final total = order['total'] as int? ?? 0;

        return GestureDetector(
          onTap: () => Navigator.pushNamed(
            context,
            '/order-status',
            arguments: {'order_id': orderId},
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #$shortId',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
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
                const Icon(Icons.chevron_right,
                    color: Colors.orange, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSession(Map<String, dynamic> session, int index) {
    final isClosed = session['status'] == 'closed';
    final messages =
        session['chat_messages'] as List<Map<String, dynamic>>;
    final openedAt =
        DateTime.tryParse(session['opened_at'] ?? '')?.toLocal();
    final dateStr = openedAt != null
        ? DateFormat('d MMM yyyy').format(openedAt)
        : '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              const SizedBox(width: 8),
              Text('Sesi ${index + 1} · $dateStr',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 11)),
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
                  style: const TextStyle(
                      color: Colors.green, fontSize: 11),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Divider(color: Colors.green)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final isCustomer = msg['sender_type'] == 'customer';
    final dt = DateTime.tryParse(msg['created_at'] ?? '')?.toLocal();
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt) : '';
    final msgOrderId = msg['order_id'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isCustomer ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCustomer) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.orange.shade100,
              child: const Icon(Icons.support_agent,
                  color: Colors.orange, size: 16),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isCustomer
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Card pesanan di atas bubble (hanya jika ada order_id)
                if (msgOrderId != null)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.72,
                    child: _buildOrderCard(msgOrderId),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCustomer ? Colors.orange : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isCustomer ? 16 : 4),
                      bottomRight:
                          Radius.circular(isCustomer ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isCustomer
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(msg['message'] ?? '',
                          style: TextStyle(
                              color: isCustomer
                                  ? Colors.white
                                  : Colors.black87)),
                      const SizedBox(height: 4),
                      Text(timeStr,
                          style: TextStyle(
                              color: isCustomer
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                              fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isCustomer) const SizedBox(width: 6),
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
                hintText: 'Ada yang bisa kami bantu?',
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
