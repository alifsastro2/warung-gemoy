import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _tabs = [
    {'label': 'Perlu Aksi', 'statuses': ['pending', 'waiting_verification']},
    {'label': 'Diproses', 'statuses': ['processing']},
    {'label': 'Siap', 'statuses': ['delivered']},
    {'label': 'Konfirmasi', 'statuses': ['completed'], 'unconfirmed': true},
    {'label': 'Selesai', 'statuses': ['completed'], 'confirmed': true},
    {'label': 'Dibatalkan', 'statuses': ['cancelled']},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('orders')
          .select('*, payments(*), users(name, phone)')
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
    final isUnconfirmed = tab['unconfirmed'] == true;
    final isConfirmed = tab['confirmed'] == true;

    return _orders.where((o) {
      if (!statuses.contains(o['status'])) return false;
      if (isUnconfirmed && o['customer_confirmed'] == true) return false;
      if (isConfirmed && o['customer_confirmed'] != true) return false;

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final orderId = (o['id'] as String).substring(0, 8).toLowerCase();
        final user = o['users'] as Map<String, dynamic>?;
        final name = (user?['name'] ?? '').toLowerCase();
        final phone = (user?['phone'] ?? '').toLowerCase();
        if (!orderId.contains(query) && !name.contains(query) && !phone.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.parse(dateStr).toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
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
      case 'pending': return isCod ? 'Menunggu Konfirmasi' : 'Menunggu Bayar';
      case 'waiting_verification': return 'Verifikasi Pembayaran';
      case 'processing': return 'Sedang Dimasak';
      case 'delivered': return deliveryMethod == 'pickup' ? 'Siap Diambil' : 'Sedang Dikirim';
      case 'completed': return 'Selesai';
      case 'cancelled': return 'Dibatalkan';
      default: return status;
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      // Ambil user_id dari order
      final orderData = await Supabase.instance.client
          .from('orders')
          .select('user_id')
          .eq('id', orderId)
          .single();
      final userId = orderData['user_id'] as String;

      await Supabase.instance.client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      if (newStatus == 'processing') {
        await Supabase.instance.client
            .from('payments')
            .update({'status': 'verified', 'verified_at': DateTime.now().toIso8601String()})
            .eq('order_id', orderId);

        // Notif pembayaran dikonfirmasi
        await NotificationService.paymentConfirmed(
          userId: userId,
          orderId: orderId,
        );
      } else if (newStatus == 'cancelled') {
        // Cek apakah ini penolakan pembayaran
        final payments = await Supabase.instance.client
            .from('payments')
            .select('status')
            .eq('order_id', orderId)
            .maybeSingle();
        if (payments != null && payments['status'] == 'pending') {
          await NotificationService.paymentRejected(
            userId: userId,
            orderId: orderId,
          );
        } else {
          await NotificationService.orderStatusChanged(
            userId: userId,
            orderId: orderId,
            newStatus: newStatus,
          );
        }
      } else {
        // Notif status lainnya
        await NotificationService.orderStatusChanged(
          userId: userId,
          orderId: orderId,
          newStatus: newStatus,
        );
      }

      _loadOrders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status pesanan diupdate ke: ${_getStatusLabel(newStatus)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal update: ${e.toString()}')),
        );
      }
    }
  }

  String _normalizePhone(String phone) {
    phone = phone.trim().replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+')) phone = phone.substring(1);
    if (phone.startsWith('62')) return phone;
    if (phone.startsWith('0')) return '62${phone.substring(1)}';
    return '62$phone';
  }

  Future<void> _confirmCancelOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: const Text('Pesanan akan dibatalkan dan stok akan dikembalikan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final orderData = await Supabase.instance.client
            .from('orders')
            .select('created_at')
            .eq('id', orderId)
            .single();
        final orderDate = (orderData['created_at'] as String).split('T')[0];

        final items = await Supabase.instance.client
            .from('order_items')
            .select('menu_id, qty')
            .eq('order_id', orderId);

        for (final item in items as List) {
          try {
            await Supabase.instance.client.rpc('decrement_used_qty', params: {
              'p_menu_id': item['menu_id'],
              'p_date': orderDate,
              'p_qty': item['qty'],
            });
          } catch (e) {
            debugPrint('Rollback stok gagal untuk ${item['menu_id']}: $e');
          }
        }

        await _updateOrderStatus(orderId, 'cancelled');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal batalkan: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _openWhatsApp(String phone, String orderId) async {
    final message = Uri.encodeComponent(
      'Halo kak, pesanan Warung Gemoy kamu dengan Order ID: ${orderId.substring(0, 8).toUpperCase()} sudah kami terima dan sedang diproses ya! 🍱',
    );
    final url = Uri.parse('https://wa.me/${_normalizePhone(phone)}?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showOrderDetail(Map<String, dynamic> order) {
    final payments = order['payments'] as List;
    final payment = payments.isNotEmpty ? payments.first : null;
    final user = order['users'] as Map<String, dynamic>?;
    final status = order['status'] as String;
    final isCod = payment?['method'] == 'cod';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #${(order['id'] as String).substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getStatusLabel(status, isCod: isCod, deliveryMethod: order['delivery_method']),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Info Pelanggan
              _detailRow('Pelanggan', user?['name'] ?? '-'),
              _detailRow('No. HP', user?['phone'] ?? '-'),
              _detailRow('Pengiriman',
                  order['delivery_method'] == 'delivery' ? 'Diantar' : 'Ambil Sendiri'),
              if (order['delivery_address'] != null &&
                  order['delivery_address'].toString().isNotEmpty)
                _detailRow('Alamat', order['delivery_address']),
              if (order['notes'] != null &&
                  order['notes'].toString().isNotEmpty)
                _detailRow('Catatan', order['notes']),
              _detailRow('Pembayaran',
                  isCod ? 'Cash/Tunai' : payment?['method'] == 'qris' ? 'QRIS' : 'Transfer Bank'),
              _detailRow('Total', _formatPrice(order['total'] as int)),

              const SizedBox(height: 16),

              // Bukti Bayar
              if (payment?['proof_url'] != null) ...[
                const Text(
                  'Bukti Pembayaran:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    payment!['proof_url'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 100,
                      color: Colors.grey.shade100,
                      child: const Center(child: Text('Gagal load gambar')),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Timeline riwayat status
              const Divider(height: 24),
              const Text(
                'Riwayat Status:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client
                    .from('order_status_history')
                    .select('status, created_at')
                    .eq('order_id', order['id'])
                    .order('created_at', ascending: false)
                    .then((res) => List<Map<String, dynamic>>.from(res)),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2));
                  }
                  final history = snapshot.data!;
                  if (history.isEmpty) return const Text('Belum ada riwayat', style: TextStyle(color: Colors.grey, fontSize: 13));
                  return Column(
                    children: List.generate(history.length, (i) {
                      final item = history[i];
                      final s = item['status'] as String;
                      final isFirst = i == 0;
                      final color = _getStatusColor(s);
                      final dt = DateTime.parse(item['created_at']).toLocal();
                      final months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
                      final timeStr = '${dt.day} ${months[dt.month-1]} ${dt.year}, ${dt.hour.toString().padLeft(2,'0')}.${dt.minute.toString().padLeft(2,'0')}';
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 20,
                            child: Column(
                              children: [
                                if (i > 0) Container(width: 2, height: 10, color: Colors.grey.shade300),
                                Container(
                                  width: 14, height: 14,
                                  decoration: BoxDecoration(
                                    color: isFirst ? color : Colors.grey.shade300,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isFirst ? color : Colors.grey.shade400, width: 2),
                                  ),
                                ),
                                if (i < history.length - 1) Container(width: 2, height: 28, color: Colors.grey.shade300),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1, bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_getStatusLabel(s), style: TextStyle(fontSize: 13, fontWeight: isFirst ? FontWeight.bold : FontWeight.normal, color: isFirst ? color : Colors.grey.shade700)),
                                  Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  );
                },
              ),
              const Divider(height: 24),

              // Action Buttons
              const Text(
                'Update Status:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (status == 'waiting_verification') ...[
                _actionButton(
                  label: '✅ Verifikasi & Mulai Masak',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'processing');
                  },
                ),
                const SizedBox(height: 8),
                _actionButton(
                  label: '❌ Tolak Pembayaran',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'cancelled');
                  },
                ),
              ],

              if (status == 'pending' && isCod) ...[
                _actionButton(
                  label: '✅ Konfirmasi Pesanan Cash/Tunai',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'processing');
                  },
                ),
                const SizedBox(height: 8),
                _actionButton(
                  label: '❌ Tolak Pesanan',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'cancelled');
                  },
                ),
              ],

              if (status == 'processing') ...[
                _actionButton(
                  label: order['delivery_method'] == 'pickup'
                      ? '✅ Tandai Siap Diambil'
                      : '🛵 Tandai Sedang Dikirim',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'delivered');
                  },
                ),
                const SizedBox(height: 8),
                _actionButton(
                  label: '❌ Batalkan Pesanan',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmCancelOrder(order['id']);
                  },
                ),
              ],

              if (status == 'delivered') ...[
                _actionButton(
                  label: '✅ Tandai Selesai',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], 'completed');
                  },
                ),
                const SizedBox(height: 8),
                _actionButton(
                  label: '❌ Batalkan Pesanan',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmCancelOrder(order['id']);
                  },
                ),
              ],

              const SizedBox(height: 8),

              // Rating
              FutureBuilder(
                future: Supabase.instance.client
                    .from('ratings')
                    .select()
                    .eq('order_id', order['id'])
                    .maybeSingle(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data == null) {
                    return const SizedBox();
                  }
                  final rating = snapshot.data as Map<String, dynamic>;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const Text(
                        'Rating Pelanggan:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(
                          5,
                              (i) => Icon(
                                i < (rating['score'] as int)
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.orange,
                            size: 24,
                          ),
                        ),
                      ),
                      if (rating['review'] != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '"${rating['review']}"',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              // Tombol WA
              if (user?['phone'] != null)
                _actionButton(
                  label: '💬 Hubungi via WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openWhatsApp(user!['phone'], order['id']);
                  },
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Kelola Pesanan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOrders,
          ),
        ],
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
            final isHistory = tab['label'] == 'Selesai' || tab['label'] == 'Dibatalkan';
            final count = isHistory ? 0 : _getFilteredOrders(tab).length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tab['label'] as String),
                  if (!isHistory && count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Cari Order ID, nama, atau nomor HP...',
                prefixIcon: const Icon(Icons.search, color: Colors.orange, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orange)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : RefreshIndicator(
              onRefresh: _loadOrders,
              child: TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final orders =
            _getFilteredOrders(tab);
            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined,
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
                final user =
                order['users'] as Map<String, dynamic>?;
                final payments = order['payments'] as List;
                final payment =
                payments.isNotEmpty ? payments.first : null;
                final isCod = payment?['method'] == 'cod';
                final status = order['status'] as String;

                return GestureDetector(
                  onTap: () => _showOrderDetail(order),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: status == 'waiting_verification' ||
                          (status == 'pending' && isCod)
                          ? Border.all(
                          color: Colors.orange, width: 2)
                          : null,
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
                                  borderRadius:
                                  BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getStatusLabel(status, isCod: isCod, deliveryMethod: order['delivery_method']),
                                  style: TextStyle(
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
                            children: [
                              Icon(Icons.person_outline,
                                  size: 14,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                user?['name'] ?? '-',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.payment,
                                  size: 14,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                isCod
                                    ? 'Cash/Tunai'
                                    : payment?['method'] == 'qris'
                                    ? 'QRIS'
                                    : 'Transfer',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
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
                                order['delivery_method'] ==
                                    'delivery'
                                    ? '🛵 Diantar'
                                    : '🏪 Ambil Sendiri',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 12,
                                color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(order['created_at']),
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                          if (status == 'waiting_verification' ||
                              (status == 'pending' && isCod)) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                Colors.orange.withOpacity(0.1),
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '👆 Tap untuk lihat detail & aksi',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
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
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}