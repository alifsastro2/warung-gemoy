import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/fcm_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  int _tapCount = 0;
  bool _isWaiting = false;
  bool _isCooldown = false;
  DateTime? _lastTapTime;

  void _handleLogoTap() async {
    if (_isCooldown) return;

    final now = DateTime.now();

    // Reset kalau sudah lebih dari 3 detik sejak tap terakhir
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inSeconds > 3) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    if (_tapCount == 7) {
      // Tunggu 5 detik
      setState(() => _isWaiting = true);
      await Future.delayed(const Duration(seconds: 5));

      // Cek apakah masih 7 (tidak ada tap tambahan selama 5 detik)
      if (_tapCount == 7 && mounted) {
        setState(() {
          _isWaiting = false;
          _tapCount = 0;
        });
        Navigator.pushNamed(context, '/admin-login');
      } else {
        // Kelebihan tap → cooldown
        setState(() {
          _isWaiting = false;
          _isCooldown = true;
          _tapCount = 0;
        });
        await Future.delayed(const Duration(seconds: 5));
        if (mounted) setState(() => _isCooldown = false);
      }
    } else if (_tapCount > 7) {
      // Langsung cooldown
      setState(() {
        _isCooldown = true;
        _tapCount = 0;
      });
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) setState(() => _isCooldown = false);
    }
  }

  Future<void> _login() async {
    if (_phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor HP dan password wajib diisi!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fakeEmail = '${_phoneController.text.trim()}@gemoykitchen.com';
      await Supabase.instance.client.auth.signInWithPassword(
        email: fakeEmail,
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        await FcmService.init();
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nomor HP atau password salah!')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _handleLogoTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isWaiting)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: _handleLogoTap,
                  child: Image.asset(
                    'assets/images/logo_gemoy_kitchen.png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Warung Gemoy',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Masuk ke akunmu',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Nomor HP',
                  hintText: 'Contoh: 08123456789',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    try {
                      final settings = await Supabase.instance.client
                          .from('store_settings')
                          .select('whatsapp_number')
                          .single();
                      final phone = settings['whatsapp_number'] ?? '628123456789';
                      final message = Uri.encodeComponent(
                          'Halo admin, saya lupa password akun Warung Gemoy saya.');
                      final url = Uri.parse('https://wa.me/$phone?text=$message');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('WhatsApp tidak ditemukan di perangkat ini.')),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Gagal membuka WhatsApp. Coba lagi.')),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Lupa password? Hubungi Admin',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'Masuk',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/register'),
                  child: const Text(
                    'Belum punya akun? Daftar di sini',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Footer Digital bNb
              Center(
                child: Column(
                  children: [
                    const Text(
                      'by Digital bNb',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Image.asset(
                      'assets/images/logo_digital_bnb.png',
                      height: 54,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}