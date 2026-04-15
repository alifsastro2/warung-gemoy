import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCustomerAccountsScreen extends StatefulWidget {
  const AdminCustomerAccountsScreen({super.key});

  @override
  State<AdminCustomerAccountsScreen> createState() =>
      _AdminCustomerAccountsScreenState();
}

class _AdminCustomerAccountsScreenState
    extends State<AdminCustomerAccountsScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('users')
          .select('id, name, phone, is_active, created_at')
          .order('created_at', ascending: false);
      setState(() {
        _users = List<Map<String, dynamic>>.from(data);
        _applyFilter(_searchController.text);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_users)
          : _users.where((u) {
              final name = (u['name'] ?? '').toString().toLowerCase();
              final phone = (u['phone'] ?? '').toString();
              return name.contains(q) || phone.contains(q);
            }).toList();
    });
  }

  Future<String> _getDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = info.brand.toUpperCase();
        final model = info.model;
        final modelStr = model.toLowerCase().startsWith(info.brand.toLowerCase())
            ? model
            : '$brand $model';
        return '$modelStr (Android ${info.version.release})';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return '${info.name} (iOS ${info.systemVersion})';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Future<void> _logAction(String action, Map<String, dynamic> user) async {
    final adminId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final deviceInfo = await _getDeviceInfo();
      await Supabase.instance.client.from('admin_audit_logs').insert({
        'admin_id': adminId,
        'action': action,
        'target_user_id': user['id'],
        'target_user_phone': user['phone'],
        'detail': user['name'] ?? user['phone'] ?? '-',
        'device_info': deviceInfo,
      });
    } catch (_) {}
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final phone = user['phone'] ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
            'Reset password "${user['name'] ?? phone}" ke nomor HP-nya?\n\nPassword baru: $phone'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Ya, Reset',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc('reset_user_password', params: {
        'target_user_id': user['id'],
        'new_password': phone,
      });
      await _logAction('reset_password', user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password berhasil direset ke "$phone"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal reset password: $e')),
        );
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final isActive = user['is_active'] ?? true;
    final newState = !isActive;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newState ? 'Aktifkan Akun' : 'Nonaktifkan Akun'),
        content: Text(
            'Yakin ingin ${newState ? 'mengaktifkan' : 'menonaktifkan'} akun "${user['name'] ?? user['phone']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: newState ? Colors.green : Colors.orange),
            child: Text(
              newState ? 'Ya, Aktifkan' : 'Ya, Nonaktifkan',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await Supabase.instance.client
          .from('users')
          .update({'is_active': newState}).eq('id', user['id']);
      await _logAction(newState ? 'enable_account' : 'disable_account', user);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Akun berhasil ${newState ? 'diaktifkan' : 'dinonaktifkan'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  Future<void> _deleteAccount(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Akun'),
        content: Text(
            'Yakin hapus akun "${user['name'] ?? user['phone']}" secara permanen?\n\nTindakan ini tidak bisa dibatalkan!'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus Permanen',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _logAction('delete_account', user); // log sebelum hapus
      await Supabase.instance.client.rpc('delete_user_account',
          params: {'target_user_id': user['id']});
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Akun berhasil dihapus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal hapus: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Kelola Akun Pelanggan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _applyFilter,
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor HP...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.orange))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('Tidak ada pelanggan',
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _loadUsers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _userCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final isActive = user['is_active'] ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    isActive ? Colors.orange.shade100 : Colors.grey.shade200,
                child: Icon(Icons.person,
                    color: isActive ? Colors.orange : Colors.grey, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['name'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(user['phone'] ?? '-',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? 'Aktif' : 'Nonaktif',
                  style: TextStyle(
                    color: isActive ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                label: 'Reset PW',
                icon: Icons.lock_reset,
                color: Colors.blue,
                onTap: () => _resetPassword(user),
              ),
              const SizedBox(width: 8),
              _actionButton(
                label: isActive ? 'Nonaktifkan' : 'Aktifkan',
                icon: isActive
                    ? Icons.block
                    : Icons.check_circle_outline,
                color: isActive ? Colors.orange : Colors.green,
                onTap: () => _toggleActive(user),
              ),
              const SizedBox(width: 8),
              _actionButton(
                label: 'Hapus',
                icon: Icons.delete_outline,
                color: Colors.red,
                onTap: () => _deleteAccount(user),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
