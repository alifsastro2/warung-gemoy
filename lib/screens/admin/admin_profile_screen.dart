import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _isLoading = true;
  String _name = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('admins')
          .select('name')
          .eq('id', userId)
          .single();
      setState(() {
        _name = data['name'] ?? '';
        _email = email;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _email = email;
        _isLoading = false;
      });
    }
  }

  Future<String> _getDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final model = info.model;
        final modelStr =
            model.toLowerCase().startsWith(info.brand.toLowerCase())
                ? model
                : '${info.brand.toUpperCase()} $model';
        return '$modelStr (Android ${info.version.release})';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return '${info.name} (iOS ${info.systemVersion})';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Future<void> _logAction(String action, String detail) async {
    final adminId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final deviceInfo = await _getDeviceInfo();
      await Supabase.instance.client.from('admin_audit_logs').insert({
        'admin_id': adminId,
        'action': action,
        'detail': detail,
        'device_info': deviceInfo,
      });
    } catch (_) {}
  }

  void _editName() {
    final controller = TextEditingController(text: _name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nama baru',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              await _saveName(newName);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Simpan',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveName(String newName) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    try {
      await Supabase.instance.client
          .from('admins')
          .update({'name': newName}).eq('id', userId!);
      await _logAction('change_name', 'Nama diubah menjadi "$newName"');
      setState(() => _name = newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nama berhasil diubah'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  void _editEmail() {
    final controller = TextEditingController(text: _email);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Email Login'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email baru',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newEmail = controller.text.trim();
              if (newEmail.isEmpty || !newEmail.contains('@')) return;
              Navigator.pop(ctx);
              await _saveEmail(newEmail);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Simpan',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEmail(String newEmail) async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );
      await _logAction('change_email', 'Email diubah menjadi "$newEmail"');
      setState(() => _email = newEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Email berhasil diubah'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  void _editPassword() {
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ubah Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'Password baru',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setDialogState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Konfirmasi password',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final newPass = newPassCtrl.text;
                final confirm = confirmCtrl.text;
                if (newPass.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Password minimal 6 karakter')),
                  );
                  return;
                }
                if (newPass != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Konfirmasi password tidak cocok')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _savePassword(newPass);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Simpan',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePassword(String newPassword) async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      await _logAction('change_password', 'Password admin diubah');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password berhasil diubah'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
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
          'Profil Admin',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Avatar
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.orange.shade100,
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.orange, size: 40),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _name.isNotEmpty ? _name : 'Admin',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(_email,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                const SizedBox(height: 24),

                // Info tiles
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _infoTile(
                        icon: Icons.person_outline,
                        label: 'Nama',
                        value: _name.isNotEmpty ? _name : '-',
                        onTap: _editName,
                      ),
                      const Divider(height: 1, indent: 56),
                      _infoTile(
                        icon: Icons.email_outlined,
                        label: 'Email Login',
                        value: _email,
                        onTap: _editEmail,
                      ),
                      const Divider(height: 1, indent: 56),
                      _infoTile(
                        icon: Icons.lock_outline,
                        label: 'Password',
                        value: '••••••••',
                        onTap: _editPassword,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.orange),
      title: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value,
          style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }
}
