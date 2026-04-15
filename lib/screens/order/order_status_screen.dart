import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _statusHistory = [];
  bool _isLoading = true;
  late String _orderId;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _orderId = args['order_id'];
      _loadOrder();
      _subscribeRealtime();
    });
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('order_status_$_orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _orderId,
          ),
          callback: (_) => _loadOrder(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('orders')
            .select('*, order_items(*, menus(name, price))')
            .eq('id', _orderId)
            .single(),
        Supabase.instance.client
            .from('order_status_history')
            .select('status, created_at')
            .eq('order_id', _orderId)
            .order('created_at', ascending: true),
      ]);
      setState(() {
        _order = results[0] as Map<String, dynamic>;
        _statusHistory = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(String raw) {
    final dt = DateTime.parse(raw).toLocal();
    final months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${dt.hour.toString().padLeft(2,'0')}.${dt.minute.toString().padLeft(2,'0')}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'Pesanan Dibuat';
      case 'waiting_verification': return 'Menunggu Verifikasi';
      case 'processing': return 'Sedang Dimasak';
      case 'delivered': return _order?['delivery_method'] == 'pickup' ? 'Siap Diambil' : 'Sedang Diantar';
      case 'completed': return 'Pesanan Selesai';
      case 'cancelled': return 'Dibatalkan';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.grey;
      case 'waiting_verification': return Colors.orange;
      case 'processing': return Colors.blue;
      case 'delivered': return Colors.teal;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.receipt_long;
      case 'waiting_verification': return Icons.hourglass_top;
      case 'processing': return Icons.restaurant;
      case 'delivered': return _order?['delivery_method'] == 'pickup' ? Icons.store : Icons.delivery_dining;
      case 'completed': return Icons.done_all;
      case 'cancelled': return Icons.cancel;
      default: return Icons.circle;
    }
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'waiting_verification':
        return {
          'icon': Icons.hourglass_top,
          'color': Colors.orange,
          'title': 'Menunggu Verifikasi',
          'desc': 'Admin sedang memverifikasi pembayaran kamu',
        };
      case 'processing':
        return {
          'icon': Icons.restaurant,
          'color': Colors.blue,
          'title': 'Sedang Dimasak',
          'desc': 'Pesanan kamu sedang disiapkan',
        };
      case 'delivered':
        final isPickup = _order?['delivery_method'] == 'pickup';
        return {
          'icon': isPickup ? Icons.store : Icons.delivery_dining,
          'color': Colors.teal,
          'title': isPickup ? 'Pesanan Siap Diambil!' : 'Sedang Diantar',
          'desc': isPickup
              ? 'Silakan datang ke toko untuk mengambil pesanan kamu'
              : 'Pesanan kamu sedang dalam perjalanan menuju lokasi kamu',
        };
      case 'completed':
        return {
          'icon': Icons.done_all,
          'color': Colors.green,
          'title': 'Pesanan Selesai',
          'desc': 'Terima kasih sudah memesan!',
        };
      case 'cancelled':
        return {
          'icon': Icons.cancel,
          'color': Colors.red,
          'title': 'Pesanan Dibatalkan',
          'desc': 'Pesanan kamu telah dibatalkan',
        };
      default:
        return {
          'icon': Icons.pending,
          'color': Colors.grey,
          'title': 'Menunggu',
          'desc': 'Pesanan kamu sedang diproses',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Status Pesanan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _order == null
          ? const Center(child: Text('Pesanan tidak ditemukan'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status Card
            Builder(builder: (context) {
              final statusInfo = _getStatusInfo(_order!['status']);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      statusInfo['icon'] as IconData,
                      size: 80,
                      color: statusInfo['color'] as Color,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      statusInfo['title'] as String,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusInfo['desc'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            // Timeline Riwayat Status
            if (_statusHistory.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Riwayat Pesanan',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(_statusHistory.length, (index) {
                      final item = _statusHistory[_statusHistory.length - 1 - index];
                      final status = item['status'] as String;
                      final isFirst = index == 0;
                      final isLast = index == _statusHistory.length - 1;
                      final color = _statusColor(status);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Garis + Dot
                          SizedBox(
                            width: 24,
                            child: Column(
                              children: [
                                if (!isFirst)
                                  Container(width: 2, height: 12, color: Colors.grey.shade300),
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: isFirst ? color : Colors.grey.shade300,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isFirst ? color : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child: isFirst
                                      ? Icon(
                                          _statusIcon(status),
                                          size: 8,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                if (!isLast)
                                  Container(width: 2, height: 32, color: Colors.grey.shade300),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Label + Waktu
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 14,
                                      color: isFirst ? color : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDateTime(item['created_at'] as String),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

            if (_statusHistory.isNotEmpty) const SizedBox(height: 16),

            // Order Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Info Pesanan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _infoRow('Order ID',
                      _orderId.substring(0, 8).toUpperCase()),
                  _infoRow('Pengiriman',
                      _order!['delivery_method'] == 'delivery'
                          ? '🛵 Diantar'
                          : '🏪 Ambil Sendiri'),
                  const Divider(height: 20),

                  // Ringkasan item
                  ...(_order!['order_items'] as List? ?? []).map((item) {
                    final menu = item['menus'] as Map<String, dynamic>?;
                    final name = menu?['name'] ?? '-';
                    final qty = item['qty'] as int? ?? 0;
                    final price = item['price'] as int? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$name x$qty',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            _formatPrice(price * qty),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const Divider(height: 16),

                  // Ongkir
                  if (_order!['delivery_method'] == 'delivery') ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ongkir',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            (_order!['delivery_fee'] as int? ?? 0) == 0
                                ? 'Gratis'
                                : _formatPrice(
                                _order!['delivery_fee'] as int),
                            style: TextStyle(
                              fontSize: 13,
                              color:
                              (_order!['delivery_fee'] as int? ?? 0) == 0
                                  ? Colors.green
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _formatPrice(_order!['total'] as int),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Refresh Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loadOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Refresh Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Kembali ke Home
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                      (route) => false,
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Kembali ke Beranda',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}