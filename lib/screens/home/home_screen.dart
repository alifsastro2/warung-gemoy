import 'dart:async';
import 'package:flutter/material.dart';
import '../home/broadcast_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/menu_model.dart';
import 'package:provider/provider.dart';
import '../../services/cart_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MenuModel> _menus = [];
  bool _isLoading = true;
  final GlobalKey _cartIconKey = GlobalKey();
  Map<String, int> _maxQty = {};
  Map<String, int> _usedQty = {};
  bool _isStoreOpen = true;
  String _storeClosedReason = '';
  bool _allMenusSoldOut = false;
  int _unreadBroadcastCount = 0;

  Timer? _refreshTimer;
  RealtimeChannel? _broadcastChannel;

  @override
  void initState() {
    super.initState();
    _loadTodayMenus();
    _loadUnreadBroadcastCount();
    _subscribeToBroadcasts();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _loadTodayMenus();
      _loadUnreadBroadcastCount();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _broadcastChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToBroadcasts() {
    _broadcastChannel = Supabase.instance.client
        .channel('public:broadcast_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'broadcast_messages',
          callback: (payload) {
            _loadUnreadBroadcastCount();
            if (!mounted) return;
            final title = payload.newRecord['title'] as String? ?? 'Pesan Baru';
            final body = payload.newRecord['body'] as String? ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          if (body.isNotEmpty)
                            Text(
                              body,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Lihat',
                  textColor: Colors.white,
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BroadcastScreen()),
                    );
                    _loadUnreadBroadcastCount();
                  },
                ),
              ),
            );
          },
        )
        .subscribe();
  }

  Future<void> _loadTodayMenus() async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final storeSettings = await Supabase.instance.client
          .from('store_settings')
          .select()
          .single();

      bool isStoreOpen = storeSettings['is_open'] ?? true;
      String closedReason = '';
      final manuallyOpened = storeSettings['manually_opened'] ?? false;
      final manuallyClosedDate = storeSettings['manually_closed_date'];

      if (isStoreOpen) {
        if (manuallyOpened) {
          // Admin buka manual → ikut toggle admin sepenuhnya
          // Auto-tutup saat jam tutup dihandle oleh admin_settings_screen
          isStoreOpen = true;
        } else {
          // Ikut jadwal jam operasional
          final openTimeParts =
          storeSettings['open_time'].toString().split(':');
          final closeTimeParts =
          storeSettings['close_time'].toString().split(':');
          final openTime = TimeOfDay(
            hour: int.parse(openTimeParts[0]),
            minute: int.parse(openTimeParts[1]),
          );
          final closeTime = TimeOfDay(
            hour: int.parse(closeTimeParts[0]),
            minute: int.parse(closeTimeParts[1]),
          );
          final nowMinutes = now.hour * 60 + now.minute;
          final openMinutes = openTime.hour * 60 + openTime.minute;
          final closeMinutes = closeTime.hour * 60 + closeTime.minute;

          if (nowMinutes < openMinutes) {
            isStoreOpen = false;
            closedReason =
            'Toko buka pukul ${storeSettings['open_time'].toString().substring(0, 5)}';
          } else if (nowMinutes > closeMinutes) {
            isStoreOpen = false;
            closedReason = 'Toko sudah tutup hari ini';
          }
        }
      } else {
        if (manuallyOpened) {
          // Admin buka manual → ikut toggle admin sepenuhnya
          isStoreOpen = true;
        } else if (manuallyClosedDate != null &&
            manuallyClosedDate != today) {
          // Hari baru → tampilkan buka (reset dilakukan admin panel)
          isStoreOpen = true;
        } else {
          // Tutup manual hari ini
          isStoreOpen = false;
          closedReason = 'Toko sedang tutup sementara';
        }
      }

      final response = await Supabase.instance.client
          .from('menu_schedules')
          .select('menu_id, max_qty, used_qty, menus(*, menu_categories(id, name, sort_order))')
          .eq('scheduled_date', today);

      final Map<String, int> usedQty = {};
      final Map<String, int> maxQty = {};

      for (final item in response as List) {
        usedQty[item['menu_id'] as String] = item['used_qty'] as int? ?? 0;
        maxQty[item['menu_id'] as String] = item['max_qty'] as int;
      }

      final menus = (response as List)
          .map((item) => MenuModel.fromJson(item['menus']))
          .toList();

      bool allSoldOut = menus.isNotEmpty && menus.every((menu) {
        final remaining = (maxQty[menu.id] ?? 0) - (usedQty[menu.id] ?? 0);
        return remaining <= 0 || !menu.isAvailable;
      });

      if (!isStoreOpen && _isStoreOpen) {
        Provider.of<CartProvider>(context, listen: false).clearCart();
      }

      setState(() {
        _menus = menus;
        _maxQty = maxQty;
        _usedQty = usedQty;
        _isStoreOpen = isStoreOpen;
        _storeClosedReason = closedReason;
        _allMenusSoldOut = allSoldOut;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUnreadBroadcastCount() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final allBroadcasts = await Supabase.instance.client
          .from('broadcast_messages')
          .select('id');

      final readBroadcasts = await Supabase.instance.client
          .from('broadcast_reads')
          .select('broadcast_id')
          .eq('user_id', user.id);

      final readIds = Set<String>.from(
        (readBroadcasts as List).map((r) => r['broadcast_id'] as String),
      );

      setState(() {
        _unreadBroadcastCount = (allBroadcasts as List)
            .where((b) => !readIds.contains(b['id']))
            .length;
      });
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  int _getRemainingStock(String menuId) {
    final max = _maxQty[menuId] ?? 50;
    final used = _usedQty[menuId] ?? 0;
    return max - used;
  }

  void _showMenuDetail(MenuModel menu, int remaining) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer<CartProvider>(
        builder: (ctx, cart, _) {
          final cartQty = cart.getQuantity(menu.id);
          final availableToOrder = remaining - cartQty;
          final canOrder = availableToOrder > 0 && menu.isAvailable && _isStoreOpen;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Foto
                if (menu.imageUrl != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(
                      menu.imageUrl!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Container(
                        height: 120,
                        color: Colors.orange.withOpacity(0.1),
                        child: const Center(
                          child: Icon(Icons.restaurant, color: Colors.orange, size: 60),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 120,
                    width: double.infinity,
                    color: Colors.orange.withOpacity(0.1),
                    child: const Center(
                      child: Icon(Icons.restaurant, color: Colors.orange, size: 60),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nama + harga
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              menu.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatPrice(menu.price),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Stok
                      Row(
                        children: [
                          Icon(
                            remaining > 5 ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                            size: 14,
                            color: remaining > 5 ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            remaining > 0
                                ? (remaining <= 5 ? 'Sisa $remaining porsi lagi!' : 'Tersedia $remaining porsi')
                                : 'Stok habis',
                            style: TextStyle(
                              fontSize: 12,
                              color: remaining > 5 ? Colors.green : (remaining > 0 ? Colors.red : Colors.grey),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      // Deskripsi
                      if (menu.description != null && menu.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          menu.description!,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Tombol pesan
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: canOrder
                              ? () {
                                  Navigator.pop(ctx);
                                  cart.addItem(menu);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${menu.name} ditambahkan!'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canOrder ? Colors.orange : Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            canOrder ? '+ Tambah ke Keranjang' : (remaining <= 0 ? 'Stok Habis' : 'Tidak Tersedia'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _animateToCart(BuildContext itemContext, MenuModel menu) {
    final cartBox = _cartIconKey.currentContext?.findRenderObject() as RenderBox?;
    final itemBox = itemContext.findRenderObject() as RenderBox?;

    if (cartBox == null || itemBox == null) return;

    final cartPos = cartBox.localToGlobal(Offset(
      cartBox.size.width / 2,
      cartBox.size.height / 2,
    ));
    final itemPos = itemBox.localToGlobal(Offset(
      itemBox.size.width / 2,
      itemBox.size.height / 2,
    ));

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _FlyingCartItem(
        startPosition: itemPos,
        endPosition: cartPos,
        onComplete: () {
          entry.remove();
          Provider.of<CartProvider>(context, listen: false).addItem(menu);
        },
      ),
    );

    overlay.insert(entry);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${menu.name} ditambahkan!'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  bool get _showCategoryHeaders => _menus.any((m) => m.categoryId != null);

  List<Map<String, dynamic>> _buildGroups() {
    final Map<String?, List<MenuModel>> byCategory = {};
    final Map<String?, String> categoryNames = {};
    final Map<String?, int> categorySortOrders = {};

    for (final menu in _menus) {
      byCategory.putIfAbsent(menu.categoryId, () => []).add(menu);
      if (menu.categoryId != null) {
        categoryNames[menu.categoryId] = menu.categoryName ?? '';
        categorySortOrders[menu.categoryId] = menu.categorySortOrder;
      }
    }

    final groups = <Map<String, dynamic>>[];
    for (final id in byCategory.keys.where((k) => k != null)) {
      groups.add({
        'id': id,
        'name': categoryNames[id] ?? '',
        'sortOrder': categorySortOrders[id] ?? 999,
        'menus': byCategory[id]!,
      });
    }
    groups.sort((a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int));

    if (byCategory.containsKey(null)) {
      groups.add({
        'id': null,
        'name': 'Lainnya',
        'sortOrder': 999,
        'menus': byCategory[null]!,
      });
    }
    return groups;
  }

  Widget _buildMenuCard(MenuModel menu) {
    final remaining = _getRemainingStock(menu.id);
    return GestureDetector(
      onTap: () => _showMenuDetail(menu, remaining),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: menu.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              menu.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) =>
                                  const Icon(Icons.restaurant, color: Colors.orange, size: 30),
                            ),
                          )
                        : const Icon(Icons.restaurant, color: Colors.orange, size: 30),
                  ),
                  if (menu.imageUrl != null)
                    Positioned(
                      right: 2, bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(menu.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (menu.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        menu.description!,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatPrice(menu.price),
                      style: const TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (buttonContext) {
                  final cartQty =
                      Provider.of<CartProvider>(context, listen: true).getQuantity(menu.id);
                  final availableToOrder = remaining - cartQty;
                  final canOrder =
                      availableToOrder > 0 && menu.isAvailable && _isStoreOpen;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: canOrder ? () => _animateToCart(buttonContext, menu) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canOrder ? Colors.orange : Colors.grey.shade400,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: Text(
                          canOrder ? '+ Pesan' : 'Habis',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      if (remaining <= 5 && canOrder) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Sisa $remaining porsi',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    final slivers = <Widget>[];

    // Banner atas
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Menu Hari Ini 🍽️',
                      style: TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Pesan sekarang sebelum habis!',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!_isStoreOpen)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_mall_directory_outlined, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Toko Sedang Tutup',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15)),
                          Text(_storeClosedReason,
                              style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_isStoreOpen && _allMenusSoldOut && _menus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Text('🍱', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Menu Hari Ini Sudah Habis!',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                  fontSize: 15)),
                          Text('Pantau terus untuk menu besok ya 😊',
                              style: TextStyle(color: Colors.orange, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ));

    if (_isLoading) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: Colors.orange)),
        ),
      ));
    } else if (_menus.isEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('Belum ada menu hari ini 😴', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ));
    } else if (!_showCategoryHeaders) {
      // Flat list — tidak ada kategori
      slivers.add(SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildMenuCard(_menus[i]),
            childCount: _menus.length,
          ),
        ),
      ));
    } else {
      // Grouped dengan sticky header per kategori
      for (final group in _buildGroups()) {
        slivers.add(SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryHeaderDelegate(group['name'] as String),
        ));
        final groupMenus = group['menus'] as List<MenuModel>;
        slivers.add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _buildMenuCard(groupMenus[i]),
              childCount: groupMenus.length,
            ),
          ),
        ));
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_gemoy_kitchen.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text(
              'Warung Gemoy',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.campaign_outlined, color: Colors.white),
                if (_unreadBroadcastCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        '$_unreadBroadcastCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BroadcastScreen()),
              );
              // Reload unread count setelah kembali dari broadcast screen
              _loadUnreadBroadcastCount();
            },
          ),
          IconButton(
            key: _cartIconKey,
            icon: Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                    if (cart.totalItems > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '${cart.totalItems}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/cart');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTodayMenus,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(),
        ),
      ),
    );
  }
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  const _CategoryHeaderDelegate(this.title);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFFFF8F0),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 3, height: 16,
            color: Colors.orange,
            margin: const EdgeInsets.only(right: 8),
          ),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 40;

  @override
  double get minExtent => 40;

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate oldDelegate) =>
      title != oldDelegate.title;
}

class _FlyingCartItem extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final VoidCallback onComplete;

  const _FlyingCartItem({
    required this.startPosition,
    required this.endPosition,
    required this.onComplete,
  });

  @override
  State<_FlyingCartItem> createState() => _FlyingCartItemState();
}

class _FlyingCartItemState extends State<_FlyingCartItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _positionAnimation = Tween<Offset>(
      begin: widget.startPosition,
      end: widget.endPosition,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0),
      ),
    );

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx - 20,
          top: _positionAnimation.value.dy - 20,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.restaurant,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}