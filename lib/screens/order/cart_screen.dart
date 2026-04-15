import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/cart_provider.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  Map<String, int> _stockData = {};
  RealtimeChannel? _stockChannel;
  bool _isCheckingOut = false;

  @override
  void initState() {
    super.initState();
    _loadStockData();
    _subscribeToStockChanges();
  }

  @override
  void dispose() {
    _stockChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadStockData() async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final response = await Supabase.instance.client
        .from('menu_schedules')
        .select('menu_id, max_qty, used_qty')
        .eq('scheduled_date', today);

    setState(() {
      _stockData = Map.fromEntries(
        (response as List).map((item) => MapEntry(
          item['menu_id'] as String,
          (item['max_qty'] as int) - (item['used_qty'] as int? ?? 0),
        )),
      );
    });
  }

  void _subscribeToStockChanges() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    _stockChannel = Supabase.instance.client
        .channel('menu_schedules_changes')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'menu_schedules',
      callback: (payload) {
        final newData = payload.newRecord;
        if (newData['scheduled_date'] == today) {
          setState(() {
            _stockData[newData['menu_id']] =
                (newData['max_qty'] as int) -
                    (newData['used_qty'] as int? ?? 0);
          });
        }
      },
    )
        .subscribe();
  }

  int _getRemainingStock(String menuId, int cartQty) {
    final remaining = _stockData[menuId] ?? 99;
    return remaining - cartQty;
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Keranjang',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: cart.items.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Keranjang masih kosong',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                final item = cart.items[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.restaurant, color: Colors.orange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.menu.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _formatPrice(item.menu.price),
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => cart.decreaseItem(item.menu.id),
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  final remaining = _getRemainingStock(item.menu.id, item.quantity);
                                  if (remaining > 0) {
                                    cart.addItem(item.menu);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${item.menu.name} sudah mencapai batas stok!'),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  color: _getRemainingStock(item.menu.id, item.quantity) > 0
                                      ? Colors.orange
                                      : Colors.grey,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) => cart.updateNotes(item.menu.id, value),
                        decoration: InputDecoration(
                          hintText: 'Catatan (contoh: paha ya...)',
                          hintStyle: const TextStyle(fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 16)),
                    Text(
                      _formatPrice(cart.totalPrice),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isCheckingOut ? null : () async {
                      setState(() => _isCheckingOut = true);
                      try {
                        final cart = Provider.of<CartProvider>(context, listen: false);
                        final today = DateTime.now().toIso8601String().split('T')[0];

                        for (final item in cart.items) {
                          final schedule = await Supabase.instance.client
                              .from('menu_schedules')
                              .select('max_qty, used_qty')
                              .eq('menu_id', item.menu.id)
                              .eq('scheduled_date', today)
                              .maybeSingle();

                          if (schedule != null) {
                            final maxQty = schedule['max_qty'] as int;
                            final usedQty = schedule['used_qty'] as int? ?? 0;
                            final remaining = maxQty - usedQty;

                            if (item.quantity > remaining) {
                              if (!mounted) return;
                              final pesan = remaining <= 0
                                  ? '"${item.menu.name}" sudah habis dan akan dihapus dari keranjang.'
                                  : '"${item.menu.name}" hanya tersisa $remaining porsi. Jumlah di keranjang akan disesuaikan.';

                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Stok Tidak Cukup'),
                                  content: Text('$pesan\n\nLanjutkan?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Batal'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Lanjutkan',
                                          style: TextStyle(color: Colors.orange)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm != true) return;
                              if (remaining <= 0) {
                                cart.removeItem(item.menu.id);
                              } else {
                                cart.setQuantity(item.menu.id, remaining);
                              }
                              return; // biarkan user review ulang keranjang
                            }
                          }
                        }

                        if (mounted) Navigator.pushNamed(context, '/checkout');
                      } finally {
                        if (mounted) setState(() => _isCheckingOut = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.orange.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isCheckingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                      'Lanjut ke Checkout',
                      style: TextStyle(
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
  }
}