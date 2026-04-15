import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  bool _isLoading = true;
  bool _isExporting = false;

  // Filter
  String _selectedPeriod = 'bulan_ini';
  String _selectedStatus = 'semua';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Data
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];

  // Summary
  int _totalOrders = 0;
  int _totalRevenue = 0;
  int _avgOrderValue = 0;
  String _topMenu = '-';

  final List<Map<String, dynamic>> _periodOptions = [
    {'value': 'hari_ini', 'label': 'Hari Ini'},
    {'value': 'minggu_ini', 'label': 'Minggu Ini'},
    {'value': 'bulan_ini', 'label': 'Bulan Ini'},
    {'value': 'tahun_ini', 'label': 'Tahun Ini'},
    {'value': 'semua', 'label': 'Semua'},
  ];

  final List<Map<String, dynamic>> _statusOptions = [
    {'value': 'semua', 'label': 'Semua Status'},
    {'value': 'pending', 'label': 'Menunggu Bayar'},
    {'value': 'waiting_verification', 'label': 'Verifikasi'},
    {'value': 'processing', 'label': 'Dimasak'},
    {'value': 'delivered', 'label': 'Dikirim'},
    {'value': 'completed', 'label': 'Selesai'},
    {'value': 'cancelled', 'label': 'Dibatalkan'},
  ];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTimeRange _getPeriodRange() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'hari_ini':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'minggu_ini':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(weekStart.year, weekStart.month, weekStart.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'bulan_ini':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59).toLocal(),
        );
      case 'tahun_ini':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, 12, 31, 23, 59, 59),
        );
      default:
        return DateTimeRange(
          start: DateTime(2000),
          end: DateTime(now.year + 1),
        );
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final range = _getPeriodRange();
      final response = await Supabase.instance.client
          .from('orders')
          .select('*, payments(*), users(name, phone), order_items(*, menus(name, price))')
          .gte('created_at', range.start.toIso8601String())
          .lte('created_at', range.end.toIso8601String())
          .order('created_at', ascending: false);

      final orders = List<Map<String, dynamic>>.from(response);
      setState(() {
        _orders = orders;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_orders);

    // Filter status
    if (_selectedStatus != 'semua') {
      filtered = filtered
          .where((o) => o['status'] == _selectedStatus)
          .toList();
    }

    // Filter search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        final orderId = (o['id'] as String).substring(0, 8).toLowerCase();
        final user = o['users'] as Map<String, dynamic>?;
        final name = (user?['name'] ?? '').toLowerCase();
        final phone = (user?['phone'] ?? '').toLowerCase();
        return orderId.contains(query) ||
            name.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // Hitung summary
    _totalOrders = filtered.length;
    _totalRevenue = filtered.fold(0, (sum, o) {
      final payments = o['payments'] as List;
      final isCod = payments.isNotEmpty && payments.first['method'] == 'cod';
      final status = o['status'] as String;
      if (isCod && status == 'completed') return sum + (o['total'] as int);
      if (!isCod && ['processing', 'delivered', 'completed'].contains(status)) {
        return sum + (o['total'] as int);
      }
      return sum;
    });
    _avgOrderValue = _totalOrders > 0 ? _totalRevenue ~/ _totalOrders : 0;

    // Hitung menu terlaris
    final menuCount = <String, int>{};
    for (final order in filtered) {
      final items = order['order_items'] as List? ?? [];
      for (final item in items) {
        final menu = item['menus'] as Map<String, dynamic>?;
        final name = menu?['name'] ?? '-';
        final qty = item['qty'] as int? ?? 0;
        menuCount[name] = (menuCount[name] ?? 0) + qty;
      }
    }
    if (menuCount.isNotEmpty) {
      _topMenu = menuCount.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    } else {
      _topMenu = '-';
    }

    _filteredOrders = filtered;
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    )}';
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.parse(dateStr).toLocal();
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
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

  String _getPeriodLabel() {
    return _periodOptions
        .firstWhere((p) => p['value'] == _selectedPeriod)['label'] as String;
  }

  // Export Excel
  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();

      // ── Sheet 1: Summary ──
      final summarySheet = excel['Ringkasan'];
      excel.setDefaultSheet('Ringkasan');

      // Header
      summarySheet.merge(
          CellIndex.indexByString('A1'), CellIndex.indexByString('D1'));
      final titleCell = summarySheet.cell(CellIndex.indexByString('A1'));
      titleCell.value = TextCellValue('LAPORAN GEMOY KITCHEN');
      titleCell.cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('FFF97316'),
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      );

      summarySheet.merge(
          CellIndex.indexByString('A2'), CellIndex.indexByString('D2'));
      final periodCell = summarySheet.cell(CellIndex.indexByString('A2'));
      periodCell.value = TextCellValue('Periode: ${_getPeriodLabel()}');
      periodCell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        italic: true,
      );

      summarySheet.appendRow([TextCellValue('')]);

      // Summary data
      final summaryData = [
        ['Total Pesanan', '$_totalOrders pesanan'],
        ['Total Pendapatan', _formatPrice(_totalRevenue)],
        ['Rata-rata Nilai Pesanan', _formatPrice(_avgOrderValue)],
        ['Menu Terlaris', _topMenu],
        ['Filter Status', _selectedStatus == 'semua' ? 'Semua Status' : _getStatusLabel(_selectedStatus)],
        ['Digenerate pada', _formatDateTime(DateTime.now().toIso8601String())],
      ];

      int summaryRowIndex = 3;
      for (final row in summaryData) {
        summarySheet.appendRow([
          TextCellValue(row[0]),
          TextCellValue(row[1]),
        ]);
        final labelCell = summarySheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRowIndex));
        labelCell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('FFFFF7ED'),
        );
        summaryRowIndex++;
      }

      // Set column width
      summarySheet.setColumnWidth(0, 30);
      summarySheet.setColumnWidth(1, 30);

      // ── Sheet 2: Detail Pesanan ──
      final detailSheet = excel['Detail Pesanan'];

      // Header row
      final headers = [
        'No', 'Order ID', 'Tanggal', 'Pelanggan', 'No. HP',
        'Item Pesanan', 'Metode Bayar', 'Pengiriman',
        'Ongkir', 'Total', 'Status'
      ];

      detailSheet.appendRow(
        headers.map((h) => TextCellValue(h)).toList(),
      );

      for (var col = 0; col < headers.length; col++) {
        final cell = detailSheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('FFF97316'),
          fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
          horizontalAlign: HorizontalAlign.Center,
        );
      }

      // Data rows
      for (var i = 0; i < _filteredOrders.length; i++) {
        final order = _filteredOrders[i];
        final user = order['users'] as Map<String, dynamic>?;
        final payments = order['payments'] as List;
        final payment = payments.isNotEmpty ? payments.first : null;
        final items = order['order_items'] as List? ?? [];
        final itemsText = items.map((item) {
          final menu = item['menus'] as Map<String, dynamic>?;
          return '${menu?['name'] ?? '-'} x${item['qty']}';
        }).join(', ');
        final deliveryFee = order['delivery_fee'] as int? ?? 0;

        detailSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue((order['id'] as String).substring(0, 8).toUpperCase()),
          TextCellValue(_formatDateTime(order['created_at'])),
          TextCellValue(user?['name'] ?? '-'),
          TextCellValue(user?['phone'] ?? '-'),
          TextCellValue(itemsText),
          TextCellValue(payment?['method'] == 'cod'
              ? 'Cash/Tunai'
              : payment?['method'] == 'qris'
              ? 'QRIS'
              : 'Transfer Bank'),
          TextCellValue(order['delivery_method'] == 'delivery'
              ? 'Diantar'
              : 'Ambil Sendiri'),
          TextCellValue(deliveryFee == 0 ? 'Gratis' : _formatPrice(deliveryFee)),
          TextCellValue(_formatPrice(order['total'] as int)),
          TextCellValue(_getStatusLabel(order['status'])),
        ]);

        // Warna baris selang-seling
        if (i % 2 == 0) {
          for (var col = 0; col < headers.length; col++) {
            final cell = detailSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1));
            cell.cellStyle = CellStyle(
              backgroundColorHex: ExcelColor.fromHexString('FFFFF7ED'),
            );
          }
        }
      }

      // Set column widths
      final widths = [6.0, 12.0, 18.0, 20.0, 15.0, 40.0, 15.0, 15.0, 12.0, 15.0, 15.0];
      for (var i = 0; i < widths.length; i++) {
        detailSheet.setColumnWidth(i, widths[i]);
      }

      // Hapus sheet default
      excel.delete('Sheet1');

      // Simpan file
      final bytes = excel.encode()!;
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'Laporan_WarungGemoy_${_getPeriodLabel().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Laporan Warung Gemoy - ${_getPeriodLabel()}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel: $e')),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // Export PDF
  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final boldFontData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      final font = pw.Font.ttf(fontData);
      final boldFont = pw.Font.ttf(boldFontData);
      final logoData = await rootBundle.load('assets/images/logo_gemoy_kitchen.png');
      final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

      final orangeColor = PdfColor.fromHex('F97316');
      final lightOrange = PdfColor.fromHex('FFF7ED');
      final greyColor = PdfColor.fromHex('6B7280');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: orangeColor,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Image(logoImage, width: 32, height: 32),
                      pw.SizedBox(width: 10),
                      pw.Text(
                        'LAPORAN WARUNG GEMOY',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 18,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Periode: ${_getPeriodLabel()} • Digenerate: ${_formatDateTime(DateTime.now().toIso8601String())}',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // Summary Cards
            pw.Text(
              'Ringkasan',
              style: pw.TextStyle(
                  font: boldFont, fontSize: 14, color: PdfColors.black),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                _pdfSummaryCard('Total Pesanan', '$_totalOrders', orangeColor,
                    boldFont, font),
                pw.SizedBox(width: 8),
                _pdfSummaryCard('Total Pendapatan',
                    _formatPrice(_totalRevenue), orangeColor, boldFont, font),
                pw.SizedBox(width: 8),
                _pdfSummaryCard('Rata-rata Pesanan',
                    _formatPrice(_avgOrderValue), orangeColor, boldFont, font),
                pw.SizedBox(width: 8),
                _pdfSummaryCard(
                    'Menu Terlaris', _topMenu, orangeColor, boldFont, font),
              ],
            ),

            pw.SizedBox(height: 16),

            // Tabel pesanan
            pw.Text(
              'Detail Pesanan',
              style: pw.TextStyle(
                  font: boldFont, fontSize: 14, color: PdfColors.black),
            ),
            pw.SizedBox(height: 8),

            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromHex('E5E7EB'), width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FixedColumnWidth(55),
                2: const pw.FixedColumnWidth(65),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FixedColumnWidth(90),
                5: const pw.FixedColumnWidth(50),
                6: const pw.FixedColumnWidth(55),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: orangeColor),
                  children: [
                    'No', 'Order ID', 'Tanggal', 'Pelanggan',
                    'Item', 'Total', 'Status'
                  ].map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 8,
                        color: PdfColors.white,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  )).toList(),
                ),

                // Data rows
                ..._filteredOrders.asMap().entries.map((entry) {
                  final i = entry.key;
                  final order = entry.value;
                  final user = order['users'] as Map<String, dynamic>?;
                  final items = order['order_items'] as List? ?? [];
                  final itemsText = items.map((item) {
                    final menu = item['menus'] as Map<String, dynamic>?;
                    return '${menu?['name'] ?? '-'} x${item['qty']}';
                  }).join('\n');

                  final bgColor =
                  i % 2 == 0 ? PdfColors.white : PdfColor.fromHex('FFF7ED');

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bgColor),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('${i + 1}',
                            style: pw.TextStyle(font: font, fontSize: 7),
                            textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          (order['id'] as String).substring(0, 8).toUpperCase(),
                          style: pw.TextStyle(font: boldFont, fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          _formatDateTime(order['created_at']),
                          style: pw.TextStyle(font: font, fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          user?['name'] ?? '-',
                          style: pw.TextStyle(font: font, fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          itemsText,
                          style: pw.TextStyle(font: font, fontSize: 7),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          _formatPrice(order['total'] as int),
                          style: pw.TextStyle(font: boldFont, fontSize: 7, color: orangeColor),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          _getStatusLabel(order['status']),
                          style: pw.TextStyle(font: font, fontSize: 7, color: greyColor),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),

            // Footer
            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColor.fromHex('E5E7EB')),
            pw.Text(
              'Laporan ini digenerate otomatis oleh sistem Warung Gemoy',
              style: pw.TextStyle(font: font, fontSize: 8, color: greyColor),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'Laporan_WarungGemoy_${_getPeriodLabel().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export PDF: $e')),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  pw.Widget _pdfSummaryCard(String title, String value, PdfColor color,
      pw.Font boldFont, pw.Font font) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: pw.BorderRadius.circular(6),
          color: PdfColor.fromHex('FFF7ED'),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(font: font, fontSize: 7,
                    color: PdfColor.fromHex('6B7280'))),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(font: boldFont, fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  void _showOrderDetail(Map<String, dynamic> order) {
    final payments = order['payments'] as List;
    final payment = payments.isNotEmpty ? payments.first : null;
    final user = order['users'] as Map<String, dynamic>?;
    final items = order['order_items'] as List? ?? [];
    final status = order['status'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #${(order['id'] as String).substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(_getStatusLabel(status), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Info pelanggan
              _detailRow('Pelanggan', user?['name'] ?? '-'),
              _detailRow('No. HP', user?['phone'] ?? '-'),
              _detailRow('Pengiriman', order['delivery_method'] == 'delivery' ? 'Diantar' : 'Ambil Sendiri'),
              if ((order['delivery_address'] ?? '').toString().isNotEmpty)
                _detailRow('Alamat', order['delivery_address']),
              if ((order['notes'] ?? '').toString().isNotEmpty)
                _detailRow('Catatan', order['notes']),
              _detailRow('Pembayaran', payment?['method'] == 'cod' ? 'Cash/Tunai' : payment?['method'] == 'qris' ? 'QRIS' : 'Transfer Bank'),
              _detailRow('Tanggal', _formatDateTime(order['created_at'])),
              const SizedBox(height: 12),

              // Item pesanan
              const Text('Item Pesanan:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...items.map((item) {
                final menu = item['menus'] as Map<String, dynamic>?;
                final qty = item['qty'] as int? ?? 0;
                final price = item['price'] as int? ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${menu?['name'] ?? '-'} x$qty', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      Text(_formatPrice(price * qty), style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                );
              }),
              const Divider(height: 16),
              if (order['delivery_method'] == 'delivery')
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ongkir', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    Text((order['delivery_fee'] as int? ?? 0) == 0 ? 'Gratis' : _formatPrice(order['delivery_fee'] as int),
                        style: TextStyle(fontSize: 13, color: (order['delivery_fee'] as int? ?? 0) == 0 ? Colors.green : Colors.grey.shade600)),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_formatPrice(order['total'] as int), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                ],
              ),
              const SizedBox(height: 16),

              // Timeline riwayat status
              const Text('Riwayat Status:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client
                    .from('order_status_history')
                    .select('status, created_at')
                    .eq('order_id', order['id'])
                    .order('created_at', ascending: false)
                    .then((res) => List<Map<String, dynamic>>.from(res)),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2));
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        ],
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
          'Laporan & History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.download, color: Colors.white),
              onSelected: (value) {
                if (value == 'excel') _exportExcel();
                if (value == 'pdf') _exportPdf();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Export Excel'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Export PDF'),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Cari Order ID, nama, atau nomor HP...',
                    prefixIcon: const Icon(Icons.search, color: Colors.orange),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                    )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),

                // 2 Dropdown dalam 1 baris
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPeriod,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Colors.orange, size: 20),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87),
                            items: _periodOptions.map((option) {
                              return DropdownMenuItem<String>(
                                value: option['value'] as String,
                                child: Text(option['label'] as String),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedPeriod = value);
                                _loadOrders();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Colors.orange, size: 20),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87),
                            items: _statusOptions.map((option) {
                              return DropdownMenuItem<String>(
                                value: option['value'] as String,
                                child: Text(option['label'] as String),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedStatus = value;
                                  _applyFilters();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Summary cards - 2x2 grid
          Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    _summaryCard('Total Pesanan', '$_totalOrders',
                        Icons.receipt_long, Colors.blue),
                    const SizedBox(width: 8),
                    _summaryCard('Pendapatan', _formatPrice(_totalRevenue),
                        Icons.attach_money, Colors.green, smallText: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _summaryCard('Rata-rata', _formatPrice(_avgOrderValue),
                        Icons.analytics, Colors.purple, smallText: true),
                    const SizedBox(width: 8),
                    _summaryCard('Menu Terlaris', _topMenu,
                        Icons.star, Colors.orange, smallText: true),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                child: CircularProgressIndicator(color: Colors.orange))
                : _filteredOrders.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'Tidak ada pesanan',
                    style:
                    TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadOrders,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: _filteredOrders.length,
                itemBuilder: (context, index) {
                  final order = _filteredOrders[index];
                  final user = order['users']
                  as Map<String, dynamic>?;
                  final payments = order['payments'] as List;
                  final payment = payments.isNotEmpty
                      ? payments.first
                      : null;
                  final items =
                      order['order_items'] as List? ?? [];

                  return GestureDetector(
                    onTap: () => _showOrderDetail(order),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Status dot
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: _getStatusColor(order['status']),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Order #${(order['id'] as String).substring(0, 8).toUpperCase()}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      _formatPrice(order['total'] as int),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      user?['name'] ?? '-',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    Text(
                                      _formatDateTime(order['created_at']),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(order['status']).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _getStatusLabel(order['status']),
                                    style: TextStyle(color: _getStatusColor(order['status']), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
      String title, String value, IconData icon, Color color,
      {bool smallText = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: smallText ? 13 : 20,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}