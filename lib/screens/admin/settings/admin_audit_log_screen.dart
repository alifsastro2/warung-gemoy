import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedFilter; // null = semua
  final _searchController = TextEditingController();

  static const _filters = [
    {'label': 'Semua', 'value': null},
    {'label': 'Login', 'value': 'login'},
    {'label': 'Reset PW', 'value': 'reset_password'},
    {'label': 'Nonaktifkan', 'value': 'disable_account'},
    {'label': 'Aktifkan', 'value': 'enable_account'},
    {'label': 'Hapus Akun', 'value': 'delete_account'},
    {'label': 'Ubah Profil', 'value': 'profile'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final adminId = Supabase.instance.client.auth.currentUser?.id;
    if (adminId == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('admin_audit_logs')
          .select()
          .eq('admin_id', adminId)
          .order('created_at', ascending: false);
      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _logs.where((log) {
      final action = log['action'] as String? ?? '';
      final detail = (log['detail'] ?? '').toString().toLowerCase();
      final phone = (log['target_user_phone'] ?? '').toString().toLowerCase();
      final device = (log['device_info'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      // Filter aksi
      if (_selectedFilter != null) {
        if (_selectedFilter == 'profile') {
          if (!['change_name', 'change_email', 'change_password']
              .contains(action)) return false;
        } else {
          if (action != _selectedFilter) return false;
        }
      }

      // Search
      if (q.isNotEmpty) {
        return detail.contains(q) || phone.contains(q) || device.contains(q);
      }

      return true;
    }).toList();
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'login': return 'Login';
      case 'reset_password': return 'Reset Password Pelanggan';
      case 'disable_account': return 'Nonaktifkan Akun';
      case 'enable_account': return 'Aktifkan Akun';
      case 'delete_account': return 'Hapus Akun';
      case 'change_name': return 'Ubah Nama Admin';
      case 'change_email': return 'Ubah Email Admin';
      case 'change_password': return 'Ubah Password Admin';
      default: return action;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'login': return Icons.login;
      case 'reset_password': return Icons.lock_reset;
      case 'disable_account': return Icons.block;
      case 'enable_account': return Icons.check_circle_outline;
      case 'delete_account': return Icons.delete_outline;
      case 'change_name': return Icons.badge_outlined;
      case 'change_email': return Icons.email_outlined;
      case 'change_password': return Icons.lock_outline;
      default: return Icons.history;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'login': return Colors.green;
      case 'reset_password': return Colors.blue;
      case 'disable_account': return Colors.orange;
      case 'enable_account': return Colors.teal;
      case 'delete_account': return Colors.red;
      case 'change_name':
      case 'change_email':
      case 'change_password': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Riwayat Aktivitas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama, nomor HP, atau perangkat...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 16),
                    ),
                  ),
                ),

                // Filter chips
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final f = _filters[i];
                      final isSelected = _selectedFilter == f['value'];
                      return ChoiceChip(
                        label: Text(f['label'] as String),
                        selected: isSelected,
                        selectedColor: Colors.orange,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontSize: 12,
                        ),
                        onSelected: (_) => setState(
                            () => _selectedFilter = f['value'] as String?),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 6),

                // Jumlah hasil + keterangan retensi
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filtered.length} aktivitas',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const Text(
                        'Data otomatis dihapus setelah 90 hari',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // List
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada hasil',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadLogs,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) => _logCard(filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _logCard(Map<String, dynamic> log) {
    final action = log['action'] as String? ?? '';
    final color = _actionColor(action);
    final dt = DateTime.tryParse(log['created_at'] ?? '')?.toLocal();
    final dateStr = dt != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(dt)
        : '-';
    final detail = (log['detail'] ?? '').toString().trim();
    final targetPhone = (log['target_user_phone'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
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
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_actionIcon(action), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_actionLabel(action),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (action == 'login')
                  Text(
                    (log['device_info'] ?? '').toString().trim().isNotEmpty
                        ? (log['device_info'] as String).trim()
                        : 'Info perangkat tidak tersedia',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  )
                else if (['change_name', 'change_email', 'change_password']
                    .contains(action)) ...[
                  if (detail.isNotEmpty)
                    Text(detail,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  if ((log['device_info'] ?? '').toString().trim().isNotEmpty)
                    Text((log['device_info'] as String).trim(),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                ] else if (detail.isNotEmpty)
                  Text(
                    '$detail${targetPhone.isNotEmpty && targetPhone != detail ? ' ($targetPhone)' : ''}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                Text(dateStr,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
