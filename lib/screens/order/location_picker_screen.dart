import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(-6.290379, 107.027322);
  LatLng? _storeLocation;
  double? _distanceKm;
  int? _deliveryFee;
  bool _isLoading = true;
  bool _isCalculating = false;

  final _linkController = TextEditingController();
  bool _locationConfirmed = false;

  static const _apiKey = Config.googleMapsKey;
  static const _serverApiKey = Config.googleDistanceMatrixKey;

  @override
  void initState() {
    super.initState();
    _loadStoreLocation();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreLocation() async {
    try {
      final settings = await Supabase.instance.client
          .from('store_settings')
          .select('store_lat, store_lng')
          .single();

      final storeLat = (settings['store_lat'] as num?)?.toDouble() ?? -6.290379;
      final storeLng = (settings['store_lng'] as num?)?.toDouble() ??
          107.027322;

      setState(() {
        _storeLocation = LatLng(storeLat, storeLng);
        _selectedLocation = LatLng(storeLat, storeLng);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _storeLocation = const LatLng(-6.290379, 107.027322);
        _isLoading = false;
      });
    }
  }

  String? _extractPlaceName(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      // Format: /maps/place/NAMA_TEMPAT/data=...
      if (pathSegments.length >= 2 && pathSegments[1] == 'place') {
        final rawName = pathSegments[2];
        return Uri.decodeComponent(rawName.replaceAll('+', ' '));
      }
    } catch (e) {
      debugPrint('Extract place name error: $e');
    }
    return null;
  }

  Future<LatLng?> _geocodePlaceName(String placeName) async {
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
        return LatLng(
          (location['lat'] as num).toDouble(),
          (location['lng'] as num).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return null;
  }
  LatLng? _extractCoordinates(String url) {
    final patterns = [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'!8m2!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        if (lat != null && lng != null &&
            lat >= -90 && lat <= 90 &&
            lng >= -180 && lng <= 180) {
          return LatLng(lat, lng);
        }
      }
    }
    return null;
  }

  Future<String> _resolveShortUrl(String url) async {
    try {
      // Coba via Google Maps redirect API
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0';

      final response = await client.send(request).timeout(
          const Duration(seconds: 10));
      client.close();

      // Ambil dari header Location kalau ada redirect
      final location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        debugPrint('RESOLVED VIA REDIRECT: $location');
        return location;
      }

      // Fallback ke URL biasa
      final finalUrl = response.request?.url.toString() ?? url;
      debugPrint('RESOLVED URL: $finalUrl');
      return finalUrl;
    } catch (e) {
      debugPrint('RESOLVE ERROR: $e');
      return url;
    }
  }

  Future<void> _processLink() async {
    final input = _linkController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste link Google Maps dulu!')),
      );
      return;
    }

    setState(() => _isCalculating = true);

    try {
      String url = input;

      if (url.contains('maps.app.goo.gl') || url.contains('goo.gl')) {
        url = await _resolveShortUrl(url);
      }

      debugPrint('EXTRACTING FROM: $url');
      LatLng? coords = _extractCoordinates(url);

      // Fallback: extract nama tempat → geocode
      if (coords == null) {
        final placeName = _extractPlaceName(url);
        if (placeName != null) {
          debugPrint('GEOCODING PLACE: $placeName');
          coords = await _geocodePlaceName(placeName);
        }
      }

      if (coords == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Koordinat tidak ditemukan. Pastikan link dari Google Maps!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isCalculating = false);
        return;
      }

      setState(() => _selectedLocation = coords!);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(coords, 16),
      );

      await _calculateDistance(coords);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isCalculating = false);
    }
  }

  Future<void> _calculateDistance(LatLng destination) async {
    if (_storeLocation == null) return;

    try {
      final origin =
          '${_storeLocation!.latitude},${_storeLocation!.longitude}';
      final dest = '${destination.latitude},${destination.longitude}';

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json'
            '?origins=$origin'
            '&destinations=$dest'
            '&mode=driving'
            '&key=$_serverApiKey',
      );

      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      debugPrint('DISTANCE MATRIX RESPONSE: ${response.body}');
      if (data['status'] == 'OK') {
        final element = data['rows'][0]['elements'][0];
        if (element['status'] == 'OK') {
          final distanceMeters = element['distance']['value'] as int;
          final distanceKm = distanceMeters / 1000;

          final settings = await Supabase.instance.client
              .from('store_settings')
              .select('free_km, delivery_fee_per_km, max_delivery_km')
              .single();

          final freeKm = settings['free_km'] as int? ?? 3;
          final feePerKm = settings['delivery_fee_per_km'] as int? ?? 2000;
          final maxDeliveryKm = settings['max_delivery_km'] as int? ?? 10;

          // Cek jarak maksimal
          if (distanceKm > maxDeliveryKm) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Maaf, lokasi kamu terlalu jauh (${distanceKm.toStringAsFixed(1)} km). '
                        'Jangkauan pengiriman maksimal $maxDeliveryKm km.',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            setState(() => _locationConfirmed = false);
            return;
          }

          int fee = 0;
          if (distanceKm > freeKm) {
            final excessKm = distanceKm - freeKm;
            final excessKmCeiled = excessKm.ceil();
            fee = excessKmCeiled * feePerKm;
          }

          setState(() {
            _distanceKm = distanceKm;
            _deliveryFee = fee;
            _locationConfirmed = true;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tidak dapat menghitung jarak. Coba lagi!'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Distance Matrix error: $e');
    }
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
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Pilih Lokasi Pengiriman',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.orange))
          : Column(
        children: [
          // Peta
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: _locationConfirmed
                      ? {
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedLocation,
                      infoWindow: const InfoWindow(
                          title: 'Lokasi Pengiriman'),
                    ),
                  }
                      : {},
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                ),

                if (!_locationConfirmed)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Paste link Google Maps kamu di bawah untuk menentukan lokasi pengiriman',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Lokasi Tersimpan
          _SavedLocationsList(
            onSelect: (lat, lng, distanceKm, deliveryFee) {
              setState(() {
                _selectedLocation = lat;
                _distanceKm = distanceKm;
                _deliveryFee = deliveryFee;
                _locationConfirmed = true;
              });
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(lat, 16),
              );
            },
          ),

          // Bottom panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Link Google Maps',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _linkController,
                        decoration: InputDecoration(
                          hintText: 'Paste link Google Maps...',
                          hintStyle: const TextStyle(fontSize: 12),
                          isDense: true,
                          contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.grey.shade300),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste,
                                color: Colors.grey, size: 18),
                            onPressed: () async {
                              final data =
                              await Clipboard.getData(
                                  Clipboard.kTextPlain);
                              if (data?.text != null) {
                                _linkController.text = data!.text!;
                              }
                            },
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed:
                      _isCalculating ? null : _processLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: _isCalculating
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text(
                        'Cek',
                        style:
                        TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                      builder: (ctx) =>
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cara mendapatkan link Google Maps:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                _step('1',
                                    'Buka aplikasi Google Maps di HP kamu'),
                                _step('2',
                                    'Cari atau tap lokasi rumah kamu'),
                                _step('3',
                                    'Tap tombol "Share" atau "Bagikan"'),
                                _step('4',
                                    'Pilih "Copy link" atau "Salin tautan"'),
                                _step('5',
                                    'Kembali ke app ini dan paste linknya'),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.help_outline,
                          color: Colors.orange, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Cara mendapatkan link Google Maps',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),

                // Opsi simpan lokasi
                if (_locationConfirmed) ...[
                  const SizedBox(height: 12),
                  _SaveLocationWidget(
                    lat: _selectedLocation.latitude,
                    lng: _selectedLocation.longitude,
                    distanceKm: _distanceKm,
                    deliveryFee: _deliveryFee,
                    linkUrl: _linkController.text.trim(),
                    onSaved: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lokasi berhasil disimpan!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                ],
                // Hasil kalkulasi
                if (_locationConfirmed) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border:
                      Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Lokasi ditemukan!',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
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
                            const Text('Jarak tempuh:',
                                style: TextStyle(fontSize: 13)),
                            Text(
                              '${_distanceKm?.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Ongkir:',
                                style: TextStyle(fontSize: 13)),
                            Text(
                              _deliveryFee == 0
                                  ? 'Gratis! 🎉'
                                  : _formatPrice(_deliveryFee!),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _deliveryFee == 0
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _locationConfirmed
                        ? () {
                      Navigator.pop(context, {
                        'lat': _selectedLocation.latitude,
                        'lng': _selectedLocation.longitude,
                        'address':
                        '${_selectedLocation.latitude}, ${_selectedLocation
                            .longitude}',
                        'distance': _distanceKm,
                        'delivery_fee': _deliveryFee,
                      });
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor:
                      Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Gunakan Lokasi Ini',
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

  Widget _step(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SavedLocationsList extends StatefulWidget {
  final Function(LatLng lat, LatLng lng, double distanceKm, int deliveryFee)
  onSelect;

  const _SavedLocationsList({required this.onSelect});

  @override
  State<_SavedLocationsList> createState() => _SavedLocationsListState();
  }

  class _SavedLocationsListState extends State<_SavedLocationsList> {
  List<Map<String, dynamic>> _locations = [];

  @override
  void initState() {
  super.initState();
  _load();
  }

  Future<void> _load() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;
  final response = await Supabase.instance.client
      .from('saved_locations')
      .select()
      .eq('user_id', user.id)
      .order('created_at', ascending: false);
  setState(() => _locations = List<Map<String, dynamic>>.from(response));
  }

  String _formatPrice(int price) {
  return 'Rp ${price.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]}.',
  )}';
  }

  @override
  Widget build(BuildContext context) {
  if (_locations.isEmpty) return const SizedBox();
  return Container(
  color: Colors.white,
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  const Text(
  'Lokasi Tersimpan',
  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
  ),
  const SizedBox(height: 8),
  SizedBox(
  height: 80,
  child: ListView.builder(
  scrollDirection: Axis.horizontal,
  itemCount: _locations.length,
  itemBuilder: (context, index) {
  final loc = _locations[index];
  final distanceKm =
  (loc['distance_km'] as num?)?.toDouble() ?? 0;
  final deliveryFee = loc['delivery_fee'] as int? ?? 0;
  final lat = (loc['lat'] as num).toDouble();
  final lng = (loc['lng'] as num).toDouble();

  return GestureDetector(
  onTap: () => widget.onSelect(
  LatLng(lat, lng),
  LatLng(lat, lng),
  distanceKm,
  deliveryFee,
  ),
  child: Container(
  margin: const EdgeInsets.only(right: 8),
  padding: const EdgeInsets.symmetric(
  horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
  color: Colors.orange.withOpacity(0.1),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(
  color: Colors.orange.withOpacity(0.3)),
  ),
  child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  Row(
  mainAxisSize: MainAxisSize.min,
  children: [
  const Icon(Icons.location_on,
  color: Colors.orange, size: 14),
  const SizedBox(width: 4),
  Text(
  loc['label'] ?? '-',
  style: const TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 13,
  color: Colors.orange,
  ),
  ),
  ],
  ),
  const SizedBox(height: 4),
  Text(
  '${distanceKm.toStringAsFixed(1)} km · ${deliveryFee == 0 ? "Gratis" : _formatPrice(deliveryFee)}',
  style: TextStyle(
  fontSize: 11,
  color: Colors.grey.shade600,
  ),
  ),
  ],
  ),
  ),
  );
  },
  ),
  ),
  const SizedBox(height: 8),
  const Divider(),
  ],
  ),
  );
  }
  }

  class _SaveLocationWidget extends StatefulWidget {
  final double lat;
  final double lng;
  final double? distanceKm;
  final int? deliveryFee;
  final String linkUrl;
  final VoidCallback onSaved;

  const _SaveLocationWidget({
  required this.lat,
  required this.lng,
  required this.distanceKm,
  required this.deliveryFee,
  required this.linkUrl,
  required this.onSaved,
  });

  @override
  State<_SaveLocationWidget> createState() => _SaveLocationWidgetState();
  }

  class _SaveLocationWidgetState extends State<_SaveLocationWidget> {
  bool _isSaving = false;
  bool _saved = false;
  final _labelController = TextEditingController();

  @override
  void dispose() {
  _labelController.dispose();
  super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  if (_saved) {
  return Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
  color: Colors.green.shade50,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: Colors.green.shade200),
  ),
  child: const Row(
  children: [
  Icon(Icons.check_circle, color: Colors.green, size: 16),
  SizedBox(width: 6),
  Text(
  'Lokasi disimpan!',
  style: TextStyle(color: Colors.green, fontSize: 12),
  ),
  ],
  ),
  );
  }

  return Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
  color: Colors.grey.shade50,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: Colors.grey.shade200),
  ),
  child: Row(
  children: [
  Expanded(
    child: TextField(
      controller: _labelController,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'Simpan sebagai... (Rumah, Kantor)',
        hintStyle: TextStyle(fontSize: 12),
        isDense: true,
        contentPadding:
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12),
    ),
  ),
  const SizedBox(width: 8),
  ElevatedButton(
  onPressed: _isSaving || _labelController.text.trim().isEmpty
  ? null
      : () async {
  setState(() => _isSaving = true);
  try {
  final user =
  Supabase.instance.client.auth.currentUser!;
  await Supabase.instance.client
      .from('saved_locations')
      .insert({
  'user_id': user.id,
  'label': _labelController.text.trim(),
  'address': widget.linkUrl,
  'lat': widget.lat,
  'lng': widget.lng,
  'distance_km': widget.distanceKm,
  'delivery_fee': widget.deliveryFee ?? 0,
  });
  setState(() => _saved = true);
  widget.onSaved();
  } catch (e) {
  debugPrint('Save error: $e');
  } finally {
  setState(() => _isSaving = false);
  }
  },
  style: ElevatedButton.styleFrom(
  backgroundColor: Colors.orange,
  shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(8),
  ),
  padding:
  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  ),
  child: _isSaving
  ? const SizedBox(
  width: 14,
  height: 14,
  child: CircularProgressIndicator(
  color: Colors.white, strokeWidth: 2),
  )
      : const Text('Simpan',
  style: TextStyle(color: Colors.white, fontSize: 12)),
  ),
  ],
  ),
  );
  }
  }