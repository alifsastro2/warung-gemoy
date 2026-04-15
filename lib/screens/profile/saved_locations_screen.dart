import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';

class SavedLocationsScreen extends StatefulWidget {
  const SavedLocationsScreen({super.key});

  @override
  State<SavedLocationsScreen> createState() => _SavedLocationsScreenState();
}

class _SavedLocationsScreenState extends State<SavedLocationsScreen> {
  List<Map<String, dynamic>> _locations = [];
  bool _isLoading = true;

  static const _apiKey = Config.googleMapsKey;
  static const _serverApiKey = Config.googleDistanceMatrixKey;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final response = await Supabase.instance.client
          .from('saved_locations')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _locations = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteLocation(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Lokasi?'),
        content: const Text('Lokasi ini akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client
          .from('saved_locations')
          .delete()
          .eq('id', id);
      _loadLocations();
    }
  }

  Future<void> _showAddLocationDialog() async {
    final linkController = TextEditingController();
    final labelController = TextEditingController();
    bool isCalculating = false;
    double? lat;
    double? lng;
    double? distanceKm;
    int? deliveryFee;
    String statusText = '';

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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'Tambah Lokasi Baru',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Label
                TextField(
                  controller: labelController,
                  decoration: InputDecoration(
                    labelText: 'Nama Lokasi (contoh: Rumah, Kantor)',
                    prefixIcon: const Icon(Icons.label_outline,
                        color: Colors.orange),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Link input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: linkController,
                        decoration: InputDecoration(
                          labelText: 'Link Google Maps',
                          hintText: 'Paste link...',
                          prefixIcon: const Icon(Icons.link,
                              color: Colors.orange),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: isCalculating
                          ? null
                          : () async {
                        final input = linkController.text.trim();
                        if (input.isEmpty) return;

                        setModalState(() {
                          isCalculating = true;
                          statusText = 'Memproses...';
                        });

                        try {
                          String url = input;
                          if (url.contains('maps.app.goo.gl') ||
                              url.contains('goo.gl')) {
                            url = await _resolveShortUrl(url);
                          }

                          Map<String, double>? coords = _extractCoordinates(url);

                          // Fallback geocode nama tempat
                          if (coords == null) {
                            final placeName = _extractPlaceName(url);
                            if (placeName != null) {
                              coords = await _geocodePlaceName(placeName);
                            }
                          }

                          if (coords == null) {
                            setModalState(() {
                              statusText = '❌ Koordinat tidak ditemukan';
                              isCalculating = false;
                            });
                            return;
                          }

                          lat = coords['lat'];
                          lng = coords['lng'];

                          // Hitung jarak
                          final result =
                          await _calculateDistance(lat!, lng!);
                          if (result != null && result['error'] == null) {
                            distanceKm = result['distanceKm'];
                            deliveryFee = result['deliveryFee'];
                            setModalState(() {
                              statusText =
                              '✅ Jarak: ${distanceKm?.toStringAsFixed(1)} km | Ongkir: ${deliveryFee == 0 ? "Gratis" : _formatPrice(deliveryFee!)}';
                              isCalculating = false;
                            });
                          } else {
                            setModalState(() {
                              statusText = result?['error'] ??
                                  '❌ Gagal hitung jarak';
                              isCalculating = false;
                            });
                          }
                        } catch (e) {
                          setModalState(() {
                            statusText = '❌ Error: $e';
                            isCalculating = false;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      child: isCalculating
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text('Cek',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),

                if (statusText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusText.startsWith('✅')
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusText.startsWith('✅')
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusText.startsWith('✅')
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: lat == null || labelController.text.trim().isEmpty
                        ? null
                        : () async {
                      final user = Supabase.instance.client.auth
                          .currentUser!;
                      await Supabase.instance.client
                          .from('saved_locations')
                          .insert({
                        'user_id': user.id,
                        'label': labelController.text.trim(),
                        'address': linkController.text.trim(),
                        'lat': lat,
                        'lng': lng,
                        'distance_km': distanceKm,
                        'delivery_fee': deliveryFee ?? 0,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadLocations();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lokasi berhasil disimpan!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Simpan Lokasi',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  Future<String> _resolveShortUrl(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0';

      final response = await client.send(request).timeout(
          const Duration(seconds: 10));
      client.close();

      final location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        return location;
      }
      return response.request?.url.toString() ?? url;
    } catch (e) {
      return url;
    }
  }

  Map<String, double>? _extractCoordinates(String url) {
    final patterns = [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'!8m2!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        if (lat != null && lng != null &&
            lat >= -90 && lat <= 90 &&
            lng >= -180 && lng <= 180) {
          return {'lat': lat, 'lng': lng};
        }
      }
    }
    return null;
  }

  String? _extractPlaceName(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2 && pathSegments[1] == 'place') {
        final rawName = pathSegments[2];
        return Uri.decodeComponent(rawName.replaceAll('+', ' '));
      }
    } catch (e) {
      debugPrint('Extract place name error: $e');
    }
    return null;
  }

  Future<Map<String, double>?> _geocodePlaceName(String placeName) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(placeName)}'
            '&key=$_serverApiKey',
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        final location = data['results'][0]['geometry']['location'];
        return {
          'lat': (location['lat'] as num).toDouble(),
          'lng': (location['lng'] as num).toDouble(),
        };
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _calculateDistance(
      double lat, double lng) async {
    try {
      final settings = await Supabase.instance.client
          .from('store_settings')
          .select('store_lat, store_lng, free_km, delivery_fee_per_km')
          .single();

      final storeLat =
          (settings['store_lat'] as num?)?.toDouble() ?? -6.290379;
      final storeLng =
          (settings['store_lng'] as num?)?.toDouble() ?? 107.027322;
      final freeKm = settings['free_km'] as int? ?? 3;
      final feePerKm = settings['delivery_fee_per_km'] as int? ?? 2000;
      final maxDeliveryKm = settings['max_delivery_km'] as int? ?? 10;

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json'
            '?origins=$storeLat,$storeLng'
            '&destinations=$lat,$lng'
            '&mode=driving'
            '&key=$_serverApiKey',
      );

      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK') {
        final element = data['rows'][0]['elements'][0];
        if (element['status'] == 'OK') {
          final distanceMeters = element['distance']['value'] as int;
          final distanceKm = distanceMeters / 1000;

          // Validasi jarak maksimal
          if (distanceKm > maxDeliveryKm) {
            return {'error': 'Lokasi terlalu jauh (${distanceKm.toStringAsFixed(1)} km). Maks. $maxDeliveryKm km'};
          }

          int fee = 0;
          if (distanceKm > freeKm) {
            final excessKm = distanceKm - freeKm;
            final excessKmCeiled = excessKm.ceil();
            fee = excessKmCeiled * feePerKm;
          }
          return {'distanceKm': distanceKm, 'deliveryFee': fee};
        }
      }
    } catch (e) {
      debugPrint('Distance error: $e');
    }
    return null;
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Alamat Tersimpan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _showAddLocationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.orange))
          : _locations.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off_outlined,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Belum ada lokasi tersimpan',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddLocationDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Tambah Lokasi',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _locations.length,
        itemBuilder: (context, index) {
          final loc = _locations[index];
          final distanceKm =
          (loc['distance_km'] as num?)?.toDouble();
          final deliveryFee = loc['delivery_fee'] as int? ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
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
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_on,
                      color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc['label'] ?? '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (distanceKm != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${distanceKm.toStringAsFixed(1)} km via jalan · ${deliveryFee == 0 ? "Gratis" : _formatPrice(deliveryFee)}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteLocation(loc['id']),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _locations.isNotEmpty
          ? FloatingActionButton(
        onPressed: _showAddLocationDialog,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
    );
  }
}