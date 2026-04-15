import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/cart_provider.dart';
import '../../services/notification_service.dart';
import 'location_picker_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _deliveryMethod = 'delivery';
  String _paymentMethod = 'transfer';
  final _notesController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;
  double? _selectedLat;
  double? _selectedLng;
  double? _selectedDistance;
  int _deliveryFee = 0;

  void _setDeliveryFee(int fee) {
    setState(() => _deliveryFee = fee);
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  Future<void> _placeOrder() async {
    final cart = Provider.of<CartProvider>(context, listen: false);

    if (_deliveryMethod == 'delivery' && _selectedLat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih lokasi pengiriman di Maps dulu!')),
      );
      return;
    }

    if (_deliveryMethod == 'delivery' && _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi detail alamat pengiriman!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;

      // Validasi status toko
      final storeSettings = await Supabase.instance.client
          .from('store_settings')
          .select()
          .single();

      final isOpen = storeSettings['is_open'] ?? true;
      final manuallyOpened = storeSettings['manually_opened'] ?? false;

      if (!isOpen && !manuallyOpened) {
        throw Exception('Toko sedang tutup. Silakan coba lagi nanti!');
      }

      if (!manuallyOpened && isOpen) {
        final now = DateTime.now();
        final openTimeParts = storeSettings['open_time'].toString().split(':');
        final closeTimeParts = storeSettings['close_time'].toString().split(':');
        final openMinutes = int.parse(openTimeParts[0]) * 60 + int.parse(openTimeParts[1]);
        final closeMinutes = int.parse(closeTimeParts[0]) * 60 + int.parse(closeTimeParts[1]);
        final nowMinutes = now.hour * 60 + now.minute;

        if (nowMinutes < openMinutes || nowMinutes > closeMinutes) {
          throw Exception(
              'Toko sedang tutup. Jam operasional ${storeSettings['open_time'].toString().substring(0, 5)} - ${storeSettings['close_time'].toString().substring(0, 5)}');
        }
      }

      final deliveryFee = _deliveryMethod == 'delivery' ? _deliveryFee : 0;
      final total = cart.totalPrice + deliveryFee;

      // Buat order
      final orderResponse = await Supabase.instance.client
          .from('orders')
          .insert({
        'user_id': user.id,
        'status': 'pending',
        'delivery_method': _deliveryMethod,
        'delivery_address': _addressController.text.trim(),
        'delivery_lat': _selectedLat,
        'delivery_lng': _selectedLng,
        'delivery_fee': deliveryFee,
        'total': total,
        'notes': _notesController.text.trim(),
      })
          .select()
          .single();

      final orderId = orderResponse['id'];

      final orderItems = cart.items.map((item) => {
        'order_id': orderId,
        'menu_id': item.menu.id,
        'qty': item.quantity,
        'price': item.menu.price,
        'notes': item.notes,
      }).toList();

      // Increment stok (atomic — validasi & increment dalam satu transaksi DB)
      final today = DateTime.now().toIso8601String().split('T')[0];
      for (final item in cart.items) {
        try {
          await Supabase.instance.client.rpc('increment_used_qty', params: {
            'p_menu_id': item.menu.id,
            'p_date': today,
            'p_qty': item.quantity,
          });
        } catch (e) {
          // Stok tidak cukup — batalkan order dan kembalikan stok item sebelumnya
          await Supabase.instance.client.from('orders').delete().eq('id', orderId);
          final processedItems = cart.items.takeWhile((i) => i != item).toList();
          for (final processed in processedItems) {
            try {
              await Supabase.instance.client.rpc('decrement_used_qty', params: {
                'p_menu_id': processed.menu.id,
                'p_date': today,
                'p_qty': processed.quantity,
              });
            } catch (rollbackError) {
              debugPrint('Gagal rollback stok untuk ${processed.menu.name}: $rollbackError');
            }
          }
          String sisaText = '';
          if (e is PostgrestException) {
            final match = RegExp(r'Tersisa (\d+) porsi').firstMatch(e.message);
            if (match != null) sisaText = ', tersisa ${match.group(1)} porsi';
          }
          throw Exception('${item.menu.name} stok tidak mencukupi$sisaText. Silakan update keranjang!');
        }
      }

      await Supabase.instance.client.from('order_items').insert(orderItems);

      // Buat payment record
      final expiredAt = DateTime.now().add(const Duration(minutes: 30));
      await Supabase.instance.client.from('payments').insert({
        'order_id': orderId,
        'method': _paymentMethod,
        'status': _paymentMethod == 'cod' ? 'cod' : 'pending',
        'expired_at': _paymentMethod == 'cod' ? null : expiredAt.toIso8601String(),
      });

      cart.clearCart();

      // Kirim notifikasi ke admin
      try {
        final adminData = await Supabase.instance.client
            .from('admins')
            .select('id')
            .single();
        final userData = await Supabase.instance.client
            .from('users')
            .select('name')
            .eq('id', user.id)
            .single();
        await NotificationService.newOrderToAdmin(
          adminUserId: adminData['id'],
          orderId: orderId,
          customerName: userData['name'] ?? 'Pelanggan',
        );
      } catch (e) {
        debugPrint('Notif admin error: $e');
      }

      if (mounted) {
        if (_paymentMethod == 'cod') {
          Navigator.pushReplacementNamed(
            context,
            '/order-status',
            arguments: {'order_id': orderId},
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            '/payment',
            arguments: {
              'order_id': orderId,
              'payment_method': _paymentMethod,
              'total': total,
              'expired_at': expiredAt.toIso8601String(),
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final deliveryFee = _deliveryMethod == 'delivery' ? _deliveryFee : 0;
    final total = cart.totalPrice + deliveryFee;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Checkout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Metode Pengiriman
            _sectionTitle('Metode Pengiriman'),
            Row(
              children: [
                Expanded(
                  child: _methodCard(
                    title: 'Diantar',
                    icon: Icons.delivery_dining,
                    value: 'delivery',
                    groupValue: _deliveryMethod,
                    onTap: () => setState(() => _deliveryMethod = 'delivery'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _methodCard(
                    title: 'Ambil Sendiri',
                    icon: Icons.store,
                    value: 'pickup',
                    groupValue: _deliveryMethod,
                    onTap: () => setState(() => _deliveryMethod = 'pickup'),
                  ),
                ),
              ],
            ),

            // Lokasi & Alamat (kalau delivery)
            if (_deliveryMethod == 'delivery') ...[
              const SizedBox(height: 16),
              _sectionTitle('Lokasi Pengiriman'),

              // Tombol pilih di Maps
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LocationPickerScreen()),
                  );
                  if (result != null) {
                    setState(() {
                      _selectedLat = result['lat'];
                      _selectedLng = result['lng'];
                      _selectedDistance = result['distance'];
                    });
                    _setDeliveryFee(result['delivery_fee'] ?? 0);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedLat != null
                          ? Colors.orange
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: _selectedLat != null ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedLat != null
                              ? 'Lokasi dipilih ✅ (${_selectedDistance?.toStringAsFixed(1)} km via jalan)'
                              : 'Tap untuk pilih lokasi di Maps',
                          style: TextStyle(
                            color: _selectedLat != null ? Colors.orange : Colors.grey,
                            fontWeight: _selectedLat != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Detail alamat
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  hintText: 'Detail alamat (contoh: Blok J1/17, rumah warna kuning)',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              // Info ongkir
              if (_selectedLat != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ongkir (${_selectedDistance?.toStringAsFixed(1)} km via jalan)',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        _deliveryFee == 0
                            ? 'Gratis! 🎉'
                            : _formatPrice(_deliveryFee),
                        style: TextStyle(
                          color: _deliveryFee == 0 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 16),

            // Metode Pembayaran
            _sectionTitle('Metode Pembayaran'),
            Column(
              children: [
                _paymentCard('transfer', Icons.account_balance, 'Transfer Bank'),
                const SizedBox(height: 8),
                _paymentCard('qris', Icons.qr_code, 'QRIS'),
                const SizedBox(height: 8),
                _paymentCard('cod', Icons.payments_outlined, 'Cash/Tunai'),
              ],
            ),

            const SizedBox(height: 16),

            // Catatan
            _sectionTitle('Catatan (opsional)'),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Contoh: tidak pakai sambal...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Ringkasan Pesanan
            _sectionTitle('Ringkasan Pesanan'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ...cart.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${item.menu.name} x${item.quantity}'),
                        Text(_formatPrice(item.subtotal)),
                      ],
                    ),
                  )),
                  const Divider(),
                  if (deliveryFee > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ongkir'),
                          Text(_formatPrice(deliveryFee)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        _formatPrice(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Tombol Order
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Buat Pesanan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _methodCard({
    required String title,
    required IconData icon,
    required String value,
    required String groupValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard(String value, IconData icon, String title) {
    final isSelected = value == _paymentMethod;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.orange : Colors.grey),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.orange : Colors.black,
                fontWeight:
                isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.orange, size: 20),
          ],
        ),
      ),
    );
  }
}