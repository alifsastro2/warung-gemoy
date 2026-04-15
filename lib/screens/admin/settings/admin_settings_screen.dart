import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  Map<String, dynamic>? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _refreshTimer;

  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _bankHolderController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _freeKmController = TextEditingController();
  final _maxDeliveryKmController = TextEditingController();
  final _maxOrdersController = TextEditingController();
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 20, minute: 0);
  String? _manuallyClosedDate;
  bool _isOpen = true;
  File? _qrisImageFile;
  String? _qrisImageUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Auto-refresh setiap menit untuk sync toggle dengan kondisi toko
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncStoreStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _bankHolderController.dispose();
    _whatsappController.dispose();
    _deliveryFeeController.dispose();
    _freeKmController.dispose();
    _maxDeliveryKmController.dispose();
    _maxOrdersController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('store_settings')
          .select()
          .single();

      setState(() {
        _settings = response;
        _bankNameController.text = response['bank_name'] ?? '';
        _bankAccountController.text = response['bank_account'] ?? '';
        _bankHolderController.text = response['bank_holder'] ?? '';
        _whatsappController.text = response['whatsapp_number'] ?? '';
        _deliveryFeeController.text =
            response['delivery_fee_per_km']?.toString() ?? '2000';
        _freeKmController.text = response['free_km']?.toString() ?? '3';
        _maxDeliveryKmController.text =
            response['max_delivery_km']?.toString() ?? '10';
        _maxOrdersController.text =
            response['max_orders_per_day']?.toString() ?? '50';
        _manuallyClosedDate = response['manually_closed_date'];
        _qrisImageUrl = response['qris_image_url'];
        _isOpen = response['is_open'] ?? true;

        if (response['open_time'] != null) {
          final parts = response['open_time'].toString().split(':');
          _openTime = TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (response['close_time'] != null) {
          final parts = response['close_time'].toString().split(':');
          _closeTime = TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Sync status toko: update DB jika perlu, lalu update toggle UI
  Future<void> _syncStoreStatus() async {
    if (_settings == null) return;
    try {
      final response = await Supabase.instance.client
          .from('store_settings')
          .select()
          .single();

      await _syncStoreStatusFromData(response);
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }

  Future<void> _syncStoreStatusFromData(Map<String, dynamic> data) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final isOpen = data['is_open'] ?? true;
    final manuallyOpened = data['manually_opened'] ?? false;
    final manuallyClosedDate = data['manually_closed_date'];

    bool effectiveOpen = isOpen;

    if (manuallyOpened) {
      // Admin buka manual → selalu tampilkan buka di toggle
      // Auto-tutup saat jam tutup hanya via Timer setiap menit
      effectiveOpen = true;
    } else if (!isOpen) {
      // Tutup manual → cek apakah sudah hari baru
      if (manuallyClosedDate != null && manuallyClosedDate != today) {
        // Hari baru → reset DB
        effectiveOpen = true;
        await Supabase.instance.client.from('store_settings').update({
          'is_open': true,
          'manually_closed_date': null,
          'manually_opened': false,
        }).eq('id', data['id']);
      } else {
        effectiveOpen = false;
      }
    }

    // Auto-tutup saat jam tutup lewat (hanya kalau manually_opened)
    if (manuallyOpened && isOpen) {
      final closeTimeParts = data['close_time'].toString().split(':');
      final closeMinutes =
          int.parse(closeTimeParts[0]) * 60 + int.parse(closeTimeParts[1]);
      final nowMinutes = now.hour * 60 + now.minute;

      if (nowMinutes > closeMinutes) {
        effectiveOpen = false;
        await Supabase.instance.client.from('store_settings').update({
          'is_open': false,
          'manually_opened': false,
        }).eq('id', data['id']);
      }
    }

    if (mounted) {
      setState(() => _isOpen = effectiveOpen);
    }
  }

  Future<void> _handleToggle(bool newValue) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newValue ? 'Buka Toko?' : 'Tutup Toko?'),
        content: Text(
          newValue
              ? 'Yakin ingin membuka toko sekarang?'
              : 'Yakin ingin menutup toko sekarang?\nToko akan buka kembali besok sesuai jadwal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newValue ? Colors.green : Colors.red,
            ),
            child: Text(
              newValue ? 'Ya, Buka Sekarang' : 'Ya, Tutup Sekarang',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isOpen = newValue);
      try {
        await Supabase.instance.client.from('store_settings').update({
          'is_open': newValue,
          'manually_closed_date': newValue ? null : today,
          'manually_opened': newValue ? true : false,
        }).eq('id', _settings!['id']);
      } catch (e) {
        debugPrint('Toggle ERROR: $e');
      }
    }
  }

  Future<void> _pickQrisImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Gambar QRIS',
          toolbarColor: Colors.orange,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
      ],
    );
    if (cropped != null) {
      setState(() => _qrisImageFile = File(cropped.path));
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      String? qrisUrl = _qrisImageUrl;

      if (_qrisImageFile != null) {
        final fileName = 'qris_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final bytes = await _qrisImageFile!.readAsBytes();
        await Supabase.instance.client.storage
            .from('menu-images')
            .uploadBinary(fileName, bytes);
        qrisUrl = Supabase.instance.client.storage
            .from('menu-images')
            .getPublicUrl(fileName);
      }

      final openTimeStr =
          '${_openTime.hour.toString().padLeft(2, '0')}:${_openTime.minute.toString().padLeft(2, '0')}';
      final closeTimeStr =
          '${_closeTime.hour.toString().padLeft(2, '0')}:${_closeTime.minute.toString().padLeft(2, '0')}';

      await Supabase.instance.client.from('store_settings').update({
        'bank_name': _bankNameController.text.trim(),
        'bank_account': _bankAccountController.text.trim(),
        'bank_holder': _bankHolderController.text.trim(),
        'whatsapp_number': _whatsappController.text.trim(),
        'delivery_fee_per_km':
        int.tryParse(_deliveryFeeController.text.trim()) ?? 2000,
        'free_km': int.tryParse(_freeKmController.text.trim()) ?? 3,
        'max_delivery_km':
        int.tryParse(_maxDeliveryKmController.text.trim()) ?? 10,
        'max_orders_per_day':
        int.tryParse(_maxOrdersController.text.trim()) ?? 50,
        'open_time': openTimeStr,
        'close_time': closeTimeStr,
        'qris_image_url': qrisUrl,
        // is_open, manually_opened, manually_closed_date
        // TIDAK diupdate di sini — dihandle oleh _handleToggle & _syncStoreStatus
      }).eq('id', _settings!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan berhasil disimpan!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickTime(bool isOpen) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? _openTime : _closeTime,
    );
    if (picked != null) {
      setState(() {
        if (isOpen) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Pengaturan Toko',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Toko
            _sectionCard(
              title: 'Status Toko',
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Toko Buka',
                            style:
                            TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _isOpen
                                ? 'Pelanggan bisa memesan'
                                : 'Toko sedang tutup',
                            style: TextStyle(
                              color:
                              _isOpen ? Colors.green : Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _isOpen,
                        activeColor: Colors.orange,
                        onChanged: _handleToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _timePicker(
                          label: 'Jam Buka',
                          time: _openTime,
                          onTap: () => _pickTime(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _timePicker(
                          label: 'Jam Tutup',
                          time: _closeTime,
                          onTap: () => _pickTime(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _maxOrdersController,
                    label: 'Maks. Order per Hari',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info Bank
            _sectionCard(
              title: 'Info Transfer Bank',
              child: Column(
                children: [
                  _textField(
                      controller: _bankNameController,
                      label: 'Nama Bank (contoh: BCA, BRI)'),
                  const SizedBox(height: 12),
                  _textField(
                      controller: _bankAccountController,
                      label: 'Nomor Rekening',
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _textField(
                      controller: _bankHolderController,
                      label: 'Atas Nama'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // QRIS
            _sectionCard(
              title: 'Gambar QRIS',
              child: GestureDetector(
                onTap: _pickQrisImage,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _qrisImageFile != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_qrisImageFile!,
                        fit: BoxFit.contain),
                  )
                      : _qrisImageUrl != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(_qrisImageUrl!,
                        fit: BoxFit.contain),
                  )
                      : Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code,
                          size: 60,
                          color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'Tap untuk upload gambar QRIS',
                        style: TextStyle(
                            color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Ongkir
            _sectionCard(
              title: 'Pengaturan Ongkir',
              child: Column(
                children: [
                  _textField(
                    controller: _maxDeliveryKmController,
                    label: 'Jangkauan pengiriman maksimal (km)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _freeKmController,
                    label: 'Gratis ongkir sampai (km)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _deliveryFeeController,
                    label: 'Biaya per km setelah gratis (Rp)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '📝 Contoh: gratis 3km, setelah itu Rp 2.000/km\n'
                          'Jarak 5km = Rp ${_formatExample()}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // WhatsApp
            _sectionCard(
              title: 'Nomor WhatsApp Admin',
              child: _textField(
                controller: _whatsappController,
                label: 'Format: 628xxxxxxxxx',
                keyboardType: TextInputType.phone,
              ),
            ),

            const SizedBox(height: 24),

            // Tombol Simpan
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(
                    color: Colors.white)
                    : const Text(
                  'Simpan Pengaturan',
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

  String _formatExample() {
    final freeKm = int.tryParse(_freeKmController.text) ?? 3;
    final feePerKm = int.tryParse(_deliveryFeeController.text) ?? 2000;
    final exampleDistance = freeKm + 2;
    final fee = (exampleDistance - freeKm) * feePerKm;
    return fee.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _timePicker({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  _formatTime(time),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}