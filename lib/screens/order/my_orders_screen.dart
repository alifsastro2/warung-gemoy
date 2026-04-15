import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../chat/chat_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;

  final List<Map<String, dynamic>> _tabs = [
    {'label': 'Pembayaran', 'statuses': ['pending']},
    {'label': 'Diproses', 'statuses': ['waiting_verification', 'processing']},
    {'label': 'Siap', 'statuses': ['delivered']},
    {'label': 'Diterima', 'statuses': ['completed'], 'unrated': true},
    {'label': 'History', 'statuses': ['completed', 'cancelled'], 'rated': true},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrders();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = Supabase.instance.client
        .channel('my_orders_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: (_) => _loadOrders(),
        )
        .subscribe();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final response = await Supabase.instance.client
          .from('orders')
          .select('*, payments(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _orders = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getFilteredOrders(Map<String, dynamic> tab) {
    final statuses = tab['statuses'] as List<String>;
    final isUnrated = tab['unrated'] == true;
    final isRated = tab['rated'] == true;

    return _orders.where((o) {
      final status = o['status'] as String;
      if (!statuses.contains(status)) return false;

      if (isUnrated) {
        // Tab Diterima: completed yang BELUM dikonfirmasi pelanggan
        return o['customer_confirmed'] != true;
      }

      if (isRated) {
        // Tab History: cancelled ATAU completed yang SUDAH dikonfirmasi pelanggan
        if (status == 'cancelled') return true;
        return o['customer_confirmed'] == true;
      }

      return true;
    }).toList();
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'waiting_verification': return Colors.blue;
      case 'processing': return Colors.blue;
      case 'delivered': return Colors.teal;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status, {bool isCod = false, String? deliveryMethod}) {
    switch (status) {
      case 'pending': return isCod ? 'Menunggu Konfirmasi' : 'Menunggu Pembayaran';
      case 'waiting_verification': return 'Verifikasi Pembayaran';
      case 'processing': return 'Sedang Dimasak';
      case 'delivered': return deliveryMethod == 'pickup' ? 'Siap Diambil' : 'Sedang Dikirim';
      case 'completed': return 'Selesai';
      case 'cancelled': return 'Dibatalkan';
      default: return status;
    }
  }

  Future<Map<String, dynamic>?> _getRating(String orderId) async {
    try {
      final response = await Supabase.instance.client
          .from('ratings')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<void> _showRatingDialog(String orderId) async {
    int selectedRating = 0;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Beri Rating Pesanan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Bintang
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () =>
                          setModalState(() => selectedRating = index + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          index < selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.orange,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 8),
                Text(
                  selectedRating == 0
                      ? 'Tap bintang untuk memberi rating'
                      : selectedRating == 1
                      ? '😞 Sangat Buruk'
                      : selectedRating == 2
                      ? '😕 Buruk'
                      : selectedRating == 3
                      ? '😊 Cukup'
                      : selectedRating == 4
                      ? '😄 Bagus'
                      : '🤩 Sangat Bagus!',
                  style: TextStyle(
                    color: selectedRating == 0
                        ? Colors.grey
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // Komentar
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Tulis komentar (opsional)...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selectedRating == 0 || isSubmitting
                        ? null
                        : () async {
                      setModalState(() => isSubmitting = true);
                      try {
                        final user = Supabase.instance.client.auth
                            .currentUser!;
                        await Supabase.instance.client
                            .from('ratings')
                            .insert({
                          'order_id': orderId,
                          'user_id': user.id,
                          'score': selectedRating,
                          'review':
                          commentController.text.trim().isEmpty
                              ? null
                              : commentController.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadOrders();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                              Text('Rating berhasil dikirim! 🌟'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setModalState(() => isSubmitting = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Kirim Rating',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: const Text('Pesanan yang dibatalkan tidak bisa dikembalikan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Ambil tanggal order dibuat (bukan hari ini!) untuk kembalikan stok ke slot yang benar
      final orderData = await Supabase.instance.client
          .from('orders')
          .select('created_at')
          .eq('id', orderId)
          .single();
      final orderDate = (orderData['created_at'] as String).split('T')[0];

      // Ambil order items untuk kembalikan stok
      final items = await Supabase.instance.client
          .from('order_items')
          .select('menu_id, qty')
          .eq('order_id', orderId);

      // Kembalikan stok ke tanggal order dibuat
      for (final item in items as List) {
        try {
          await Supabase.instance.client.rpc('decrement_used_qty', params: {
            'p_menu_id': item['menu_id'],
            'p_date': orderDate,
            'p_qty': item['qty'],
          });
        } catch (e) {
          debugPrint('Gagal kembalikan stok untuk menu ${item['menu_id']}: $e');
        }
      }

      await Supabase.instance.client
          .from('orders')
          .update({'status': 'cancelled'})
          .eq('id', orderId);
      await Supabase.instance.client
          .from('payments')
          .update({'status': 'cancelled'})
          .eq('order_id', orderId);

      // Notif ke admin bahwa pelanggan membatalkan pesanan
      try {
        final user = Supabase.instance.client.auth.currentUser;
        final adminData = await Supabase.instance.client
            .from('admins').select('id').limit(1).single();
        final userData = await Supabase.instance.client
            .from('users').select('name').eq('id', user!.id).maybeSingle();
        await NotificationService.orderCancelledByCustomer(
          adminUserId: adminData['id'],
          orderId: orderId,
          customerName: userData?['name'] ?? 'Pelanggan',
        );
      } catch (e) {
        debugPrint('Notif cancel order error: $e');
      }

      _loadOrders();
    }
  }

  Future<void> _confirmReceived(String orderId) async {
    // Step 1: Dialog konfirmasi penerimaan
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Penerimaan?'),
        content: const Text('Pastikan pesanan sudah kamu terima dengan baik.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Belum'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Ya, Sudah Terima',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Step 2: Tandai pesanan sudah dikonfirmasi pelanggan
    try {
      await Supabase.instance.client
          .from('orders')
          .update({
            'customer_confirmed': true,
            'customer_confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal konfirmasi: $e')),
        );
      }
      return;
    }

    // Step 3: Langsung munculkan bottom sheet rating
    // Rating opsional — tap "Lewati" atau tap di luar untuk skip
    if (mounted) await _showRatingAfterConfirm(orderId);

    _loadOrders();
  }

  Future<void> _showRatingAfterConfirm(String orderId) async {
    int selectedRating = 0;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true, // tap di luar = skip rating, konfirmasi tetap tersimpan
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Icon & judul
                const Icon(Icons.favorite, color: Colors.orange, size: 36),
                const SizedBox(height: 8),
                const Text(
                  'Bagaimana Pesananmu?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pendapatmu sangat berarti bagi kami untuk\nterus meningkatkan kualitas Warung Gemoy 🙏',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // Bintang
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () =>
                          setModalState(() => selectedRating = index + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          index < selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.orange,
                          size: 44,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedRating == 0
                      ? 'Tap bintang untuk memberi rating'
                      : selectedRating == 1
                          ? '😞 Sangat Buruk'
                          : selectedRating == 2
                              ? '😕 Buruk'
                              : selectedRating == 3
                                  ? '😊 Cukup'
                                  : selectedRating == 4
                                      ? '😄 Bagus'
                                      : '🤩 Sangat Bagus!',
                  style: TextStyle(
                    color: selectedRating == 0 ? Colors.grey : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),

                // Komentar
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Ceritakan pengalamanmu (opsional)...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Tombol Kirim
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selectedRating == 0 || isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            try {
                              final user =
                                  Supabase.instance.client.auth.currentUser!;
                              await Supabase.instance.client
                                  .from('ratings')
                                  .insert({
                                'order_id': orderId,
                                'user_id': user.id,
                                'score': selectedRating,
                                'review': commentController.text.trim().isEmpty
                                    ? null
                                    : commentController.text.trim(),
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Terima kasih atas penilaianmu! 🌟'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isSubmitting = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Kirim Rating',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Tombol Lewati
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Lewati',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleOrderTap(Map<String, dynamic> order) {
    final status = order['status'];
    final payments = order['payments'] as List;
    final payment = payments.isNotEmpty ? payments.first : null;

    if (status == 'pending' && payment != null) {
      // Belum bayar → ke payment screen (non-COD), atau order status (COD)
      final expiredAt = payment['expired_at'];
      if (payment['method'] != 'cod' && expiredAt != null) {
        Navigator.pushNamed(
          context,
          '/payment',
          arguments: {
            'order_id': order['id'],
            'payment_method': payment['method'],
            'total': order['total'],
            'expired_at': expiredAt,
          },
        );
      } else if (payment['method'] == 'cod') {
        Navigator.pushNamed(
          context,
          '/order-status',
          arguments: {'order_id': order['id']},
        );
      }
    } else {
      // Sudah bayar → ke order status
      Navigator.pushNamed(
        context,
        '/order-status',
        arguments: {'order_id': order['id']},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Pesanan Saya',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          tabs: _tabs.map((tab) {
            final isHistory = tab['rated'] == true;
            final count = isHistory ? 0 : _getFilteredOrders(tab).length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tab['label'] as String),
                  if (!isHistory && count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
        onRefresh: _loadOrders,
        child: TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final orders = _getFilteredOrders(tab);
            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 60, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'Tidak ada pesanan',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final status = order['status'] as String;
                final isPending = status == 'pending';
                return GestureDetector(
                  onTap: () => _handleOrderTap(order),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order #${(order['id'] as String).substring(0, 8).toUpperCase()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getStatusLabel(status, isCod: (order['payments'] as List).isNotEmpty && (order['payments'] as List).first['method'] == 'cod', deliveryMethod: order['delivery_method']),                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatPrice(order['total'] as int),
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                order['delivery_method'] == 'delivery'
                                    ? 'Diantar'
                                    : 'Ambil Sendiri',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (status != 'pending') ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ChatScreen(),
                                    settings: RouteSettings(
                                      arguments: {
                                        'order_id': order['id'],
                                        'order_data': {
                                          'id': order['id'],
                                          'total': order['total'],
                                          'status': order['status'],
                                        },
                                      },
                                    ),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.orange.shade200),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.chat_bubble_outline,
                                          color: Colors.orange, size: 14),
                                      SizedBox(width: 4),
                                      Text('Chat',
                                          style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (status == 'delivered') ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.teal.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    order['delivery_method'] == 'pickup'
                                        ? Icons.store
                                        : Icons.delivery_dining,
                                    color: Colors.teal,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      order['delivery_method'] == 'pickup'
                                          ? '✅ Pesanan siap diambil! Silakan datang ke toko.'
                                          : '🛵 Pesanan sedang dalam perjalanan menuju lokasi kamu.',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (status == 'completed') ...[
                            const SizedBox(height: 12),
                            if (order['customer_confirmed'] != true)
                              // Belum dikonfirmasi → tampil tombol Konfirmasi Terima
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _confirmReceived(order['id']),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Colors.white, size: 18),
                                  label: const Text(
                                    'Konfirmasi Terima',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              )
                            else
                              // Sudah dikonfirmasi → tampil rating jika ada, atau tombol "Beri Rating" jika skip
                              FutureBuilder<Map<String, dynamic>?>(
                                future: _getRating(order['id']),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const SizedBox();
                                  }
                                  final rating = snapshot.data;
                                  if (rating != null) {
                                    // Sudah ada rating — tampilkan bintang & review
                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.orange.withOpacity(0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          Row(
                                            children: List.generate(
                                              5,
                                              (i) => Icon(
                                                i < (rating['score'] as int)
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: Colors.orange,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              rating['review'] ?? 'Sudah diberi rating',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  // Belum ada rating (user skip) — masih bisa beri rating
                                  return OutlinedButton.icon(
                                    onPressed: () => _showRatingDialog(order['id']),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.orange),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: const Icon(Icons.star_border,
                                        color: Colors.orange, size: 18),
                                    label: const Text(
                                      'Beri Rating',
                                      style: TextStyle(
                                          color: Colors.orange, fontSize: 13),
                                    ),
                                  );
                                },
                              ),
                          ],
                          if (isPending) ...[
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final payments = order['payments'] as List;
                              final isCod = payments.isNotEmpty &&
                                  payments.first['method'] == 'cod';
                              return Row(
                                children: [
                                  if (!isCod)
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _handleOrderTap(order),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Text(
                                          'Bayar Sekarang',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _cancelOrder(order['id']),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.red),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text(
                                        'Batalkan',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}