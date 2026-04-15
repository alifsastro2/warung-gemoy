import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _storeSettings;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isCancelledByTimer = false;
  bool _isExpired = false;
  File? _proofImage;
  late String _orderId;
  late String _paymentMethod;
  late int _total;
  late DateTime _expiredAt;
  late Stream<Duration> _timerStream;
  List<Map<String, dynamic>> _orderItems = [];
  String _orderNotes = '';
  int _deliveryFee = 0;
  String _deliveryMethod = 'delivery';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _orderId = args['order_id'];
      _paymentMethod = args['payment_method'];
      _total = args['total'];
      _expiredAt = DateTime.parse(args['expired_at']);
      _loadStoreSettings();
      _startTimer();
    });
  }

  void _startTimer() {
    _timerStream = Stream.periodic(const Duration(seconds: 1), (_) {
      final remaining = _expiredAt.difference(DateTime.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        if (!_isCancelledByTimer) _cancelExpiredOrder();
        return Duration.zero;
      }
      return remaining;
    });
  }

  Future<void> _cancelExpiredOrder() async {
    if (_isCancelledByTimer) return;
    _isCancelledByTimer = true;
    try {
      final currentOrder = await Supabase.instance.client
          .from('orders')
          .select('status')
          .eq('id', _orderId)
          .single();

      if (currentOrder['status'] == 'pending') {
        await Supabase.instance.client
            .from('orders')
            .update({'status': 'cancelled'})
            .eq('id', _orderId);

        await Supabase.instance.client
            .from('payments')
            .update({'status': 'cancelled'})
            .eq('order_id', _orderId);
      }
      if (mounted) setState(() => _isExpired = true);
    } catch (e) {
      debugPrint('Error cancelling expired order: $e');
    }
  }

  Future<void> _loadStoreSettings() async {
    try {
      final response = await Supabase.instance.client
          .from('store_settings')
          .select()
          .single();

      final items = await Supabase.instance.client
          .from('order_items')
          .select('qty, price, notes, menus(name)')
          .eq('order_id', _orderId);

      final orderData = await Supabase.instance.client
          .from('orders')
          .select('notes, delivery_fee, delivery_method')
          .eq('id', _orderId)
          .single();

      setState(() {
        _storeSettings = response;
        _orderItems = List<Map<String, dynamic>>.from(items);
        _orderNotes = orderData['notes'] ?? '';
        _deliveryFee = orderData['delivery_fee'] as int? ?? 0;
        _deliveryMethod = orderData['delivery_method'] as String? ?? 'delivery';
        _isLoading = false;
      });

    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) {
      final file = File(picked.path);
      final sizeInMB = await file.length() / (1024 * 1024);
      if (sizeInMB > 5) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ukuran foto maksimal 5 MB. Silakan pilih foto lain.')),
          );
        }
        return;
      }
      setState(() => _proofImage = file);
    }
  }

  Future<void> _uploadProof() async {
    if (_proofImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih foto bukti pembayaran dulu!')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final fileName = 'proof_${_orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await _proofImage!.readAsBytes();

      await Supabase.instance.client.storage
          .from('payment-proofs')
          .uploadBinary(fileName, bytes);

      final proofUrl = Supabase.instance.client.storage
          .from('payment-proofs')
          .getPublicUrl(fileName);

      // Update payment record
      await Supabase.instance.client
          .from('payments')
          .update({
        'proof_url': proofUrl,
        'status': 'waiting_verification',
      })
          .eq('order_id', _orderId);

      // Update order status
      await Supabase.instance.client
          .from('orders')
          .update({'status': 'waiting_verification'})
          .eq('id', _orderId);

      // Notif ke admin bahwa bukti bayar sudah diupload
      try {
        final user = Supabase.instance.client.auth.currentUser;
        final adminData = await Supabase.instance.client
            .from('admins').select('id').limit(1).single();
        final userData = await Supabase.instance.client
            .from('users').select('name').eq('id', user!.id).maybeSingle();
        await NotificationService.paymentProofUploaded(
          adminUserId: adminData['id'],
          orderId: _orderId,
          customerName: userData?['name'] ?? 'Pelanggan',
        );
      } catch (e) {
        debugPrint('Notif bukti bayar error: $e');
      }

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/order-status',
          arguments: {'order_id': _orderId},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal upload: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _openWhatsApp() async {
    final phone = _storeSettings?['whatsapp_number'] ?? '628123456789';
    final message = Uri.encodeComponent(
      'Halo admin Warung Gemoy, saya sudah transfer untuk pesanan saya.\nOrder ID: ${_orderId.substring(0, 8).toUpperCase()}\nTotal: ${_formatPrice(_total)}',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Pembayaran',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Timer
            StreamBuilder<Duration>(
              stream: _timerStream,
              builder: (context, snapshot) {
                final remaining = snapshot.data ?? _expiredAt.difference(DateTime.now());
                final isExpired = remaining == Duration.zero;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isExpired ? Colors.red : Colors.orange,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isExpired ? '⚠️ Waktu Pembayaran Habis!' : '⏳ Batas Waktu Pembayaran',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isExpired ? 'Pesanan dibatalkan otomatis' : _formatDuration(remaining),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Ringkasan Pesanan
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
                    'Ringkasan Pesanan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._orderItems.map((item) {
                    final menu = item['menus'] as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    '${item['qty']}x',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    menu['name'],
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                                    Text(
                                      '📝 ${item['notes']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            _formatPrice(item['price'] * item['qty'] as int),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_orderNotes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📝 ', style: TextStyle(fontSize: 13)),
                          Expanded(
                            child: Text(
                              'Catatan: $_orderNotes',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(),
                  if (_deliveryFee > 0 && _deliveryMethod != 'pickup')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ongkir'),
                          Text(_formatPrice(_deliveryFee)),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Pembayaran',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatPrice(_total),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tombol kembali saat expired
            if (_isExpired) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (route) => false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text('Kembali ke Beranda',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Info Pembayaran (disembunyikan jika expired)
            if (!_isExpired) ...[

            // Info Pembayaran
            if (_paymentMethod == 'transfer') ...[
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
                      'Transfer ke Rekening',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _bankRow('Bank', _storeSettings?['bank_name'] ?? '-'),
                    const SizedBox(height: 8),
                    _bankRow('Atas Nama', _storeSettings?['bank_holder'] ?? '-'),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _storeSettings?['bank_account'] ?? '-',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                text: _storeSettings?['bank_account'] ?? '',
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Nomor rekening disalin!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_paymentMethod == 'qris') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _storeSettings?['qris_image_url'] != null
                        ? Image.network(
                      _storeSettings!['qris_image_url'],
                      height: 250,
                    )
                        : Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'QR Code belum diatur admin',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Upload Bukti Bayar
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
                    'Upload Bukti Pembayaran',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: _proofImage != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _proofImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                          : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file,
                              size: 40, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'Tap untuk pilih foto',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tombol Upload
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadProof,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Konfirmasi Pembayaran',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tombol WA
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _openWhatsApp,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF25D366)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                label: const Text(
                  'Hubungi Admin via WhatsApp',
                  style: TextStyle(
                    color: Color(0xFF25D366),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            ], // end if (!_isExpired)

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _bankRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}