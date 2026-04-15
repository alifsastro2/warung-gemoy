import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../orders/admin_orders_screen.dart';
import '../settings/admin_customer_accounts_screen.dart';
import '../settings/admin_audit_log_screen.dart';
import '../admin_profile_screen.dart';
import '../chat/admin_chats_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  bool _settingsExpanded = false;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _chatsChannel;
  int _totalOrdersToday = 0;
  int _pendingPayments = 0;
  int _processingOrders = 0;
  int _totalRevenueToday = 0;
  int _openChats = 0;
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _subscribeToNewOrders();
    _subscribeToChats();
  }

  @override
  void dispose() {
    _ordersChannel?.unsubscribe();
    _chatsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToNewOrders() {
    _ordersChannel = Supabase.instance.client
        .channel('public:orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            _loadDashboard();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('Pesanan baru masuk!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Lihat',
                  textColor: Colors.white,
                  onPressed: () => Navigator.pushNamed(context, '/admin-orders'),
                ),
              ),
            );
          },
        )
        .subscribe();
    debugPrint('Realtime orders channel subscribed');
  }

  void _subscribeToChats() {
    _chatsChannel = Supabase.instance.client
        .channel('dashboard:chat_sessions')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_sessions',
          callback: (_) => _loadDashboard(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_sessions',
          callback: (_) => _loadDashboard(),
        )
        .subscribe();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Total orders hari ini
      final todayOrders = await Supabase.instance.client
          .from('orders')
          .select('id, status, total, created_at, delivery_method, payments(method, status)')
          .gte('created_at', '${today}T00:00:00')
          .lte('created_at', '${today}T23:59:59')
          .order('created_at', ascending: false);

      final orders = List<Map<String, dynamic>>.from(todayOrders);

      setState(() {
        _totalOrdersToday = orders.length;
        _pendingPayments = orders
            .where((o) =>
        o['status'] == 'pending' ||
            o['status'] == 'waiting_verification')
            .length;
        _processingOrders = orders
            .where((o) => o['status'] == 'processing')
            .length;
        _totalRevenueToday = orders.fold(0, (sum, o) {
          final payments = o['payments'] as List;
          final isCod = payments.isNotEmpty && payments.first['method'] == 'cod';
          final status = o['status'] as String;

          if (isCod && status == 'completed') {
            return sum + (o['total'] as int);
          } else if (!isCod && ['processing', 'delivered', 'completed'].contains(status)) {
            return sum + (o['total'] as int);
          }
          return sum;
        });
        _recentOrders = orders.take(5).toList();
        _isLoading = false;
      });

      // Hitung sesi chat aktif
      final openSessions = await Supabase.instance.client
          .from('chat_sessions')
          .select('id')
          .eq('status', 'open');
      setState(() => _openChats = (openSessions as List).length);
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
      case 'processing': return Colors.purple;
      case 'delivered': return Colors.teal;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Menunggu Bayar';
      case 'waiting_verification': return 'Verifikasi';
      case 'processing': return 'Dimasak';
      case 'delivered': return 'Dikirim';
      case 'completed': return 'Selesai';
      case 'cancelled': return 'Dibatalkan';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_gemoy_kitchen.png',
              height: 32,
              width: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text(
              'Warung Gemoy',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDashboard,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            offset: const Offset(0, 48),
            onSelected: (value) async {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminProfileScreen()),
                );
              } else if (value == 'logout') {
                await Supabase.instance.client.auth.signOut();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/admin-login');
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.orange),
                    SizedBox(width: 12),
                    Text('Edit Profil'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Keluar', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
        onRefresh: _loadDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Selamat datang, Admin! 👋',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ringkasan hari ini',
                style: TextStyle(color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),

              // Stats Cards
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _statCard(
                    title: 'Total Pesanan',
                    value: '$_totalOrdersToday',
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                  _statCard(
                    title: 'Perlu Diproses',
                    value: '$_pendingPayments',
                    icon: Icons.pending_actions,
                    color: Colors.orange,
                  ),
                  _statCard(
                    title: 'Sedang Dimasak',
                    value: '$_processingOrders',
                    icon: Icons.restaurant,
                    color: Colors.purple,
                  ),
                  _statCard(
                    title: 'Pendapatan',
                    value: _formatPrice(_totalRevenueToday),
                    icon: Icons.attach_money,
                    color: Colors.green,
                    smallText: true,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Menu Utama
              const Text(
                'Menu Utama',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Column(
                children: [
                  // Kelola Pesanan dengan badge
                  _menuCard(
                    title: 'Kelola Pesanan',
                    icon: Icons.list_alt,
                    color: Colors.orange,
                    badge: _pendingPayments > 0 ? '$_pendingPayments' : null,
                    onTap: () => Navigator.pushNamed(
                        context, '/admin-orders'),
                  ),
                  const SizedBox(height: 10),
                  _menuCard(
                    title: 'Kelola Menu',
                    icon: Icons.restaurant_menu,
                    color: Colors.green,
                    onTap: () => Navigator.pushNamed(
                        context, '/admin-menus'),
                  ),
                  const SizedBox(height: 10),
                  _menuCard(
                    title: 'Laporan & History',
                    icon: Icons.bar_chart,
                    color: Colors.teal,
                    onTap: () => Navigator.pushNamed(
                        context, '/admin-reports'),
                  ),
                  const SizedBox(height: 10),
                  _menuCard(
                    title: 'Broadcast Pesan',
                    icon: Icons.campaign,
                    color: Colors.purple,
                    onTap: () => Navigator.pushNamed(
                        context, '/admin-broadcast'),
                  ),
                  const SizedBox(height: 10),
                  _menuCard(
                    title: 'Chat',
                    icon: Icons.chat_bubble_outline,
                    color: Colors.indigo,
                    badge: _openChats > 0 ? '$_openChats' : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminChatsScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _menuCard(
                    title: 'Pengaturan',
                    icon: Icons.settings,
                    color: Colors.blue,
                    expandable: true,
                    isExpanded: _settingsExpanded,
                    onTap: () => setState(
                        () => _settingsExpanded = !_settingsExpanded),
                  ),
                  if (_settingsExpanded) ...[
                    const SizedBox(height: 6),
                    _subMenuCard(
                      title: 'Pengaturan Toko',
                      icon: Icons.store_outlined,
                      onTap: () => Navigator.pushNamed(
                          context, '/admin-settings'),
                    ),
                    const SizedBox(height: 6),
                    _subMenuCard(
                      title: 'Akun Pelanggan',
                      icon: Icons.people_outline,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const AdminCustomerAccountsScreen()),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _subMenuCard(
                      title: 'Riwayat Aktivitas',
                      icon: Icons.history,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminAuditLogScreen()),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // Recent Orders
              const Text(
                'Pesanan Terbaru',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _recentOrders.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'Belum ada pesanan hari ini',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentOrders.length,
                itemBuilder: (context, index) {
                  final order = _recentOrders[index];
                  final payments =
                  order['payments'] as List;
                  final paymentMethod = payments.isNotEmpty
                      ? payments.first['method']
                      : '-';
                  return GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/admin-orders'),
                    child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                                order['status'])
                                .withOpacity(0.1),
                            borderRadius:
                            BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.receipt,
                            color: _getStatusColor(
                                order['status']),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${(order['id'] as String).substring(0, 8).toUpperCase()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_getPaymentLabel(paymentMethod)} • ${order['delivery_method'] == 'delivery' ? 'Diantar' : 'Ambil'}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatPrice(
                                  order['total'] as int),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            Container(
                              padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                    order['status'])
                                    .withOpacity(0.1),
                                borderRadius:
                                BorderRadius.circular(20),
                              ),
                              child: Text(
                                _getStatusLabel(
                                    order['status']),
                                style: TextStyle(
                                  color: _getStatusColor(
                                      order['status']),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ));
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool smallText = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: smallText ? 14 : 24,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: Colors.blue.shade200, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue.shade400, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _menuCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badge,
    bool expandable = false,
    bool isExpanded = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (expandable)
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: isExpanded ? Colors.blue : Colors.grey.shade400,
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  String _getPaymentLabel(String method) {
    switch (method) {
      case 'transfer': return 'Transfer';
      case 'qris': return 'QRIS';
      case 'cod': return 'Cash/Tunai';
      default: return method;
    }
  }
}