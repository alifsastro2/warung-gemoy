import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home/home_screen.dart';
import 'order/my_orders_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _activeOrderCount = 0;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const MyOrdersScreen(),
      const ProfileScreen(),
    ];
    _loadActiveOrderCount();
  }

  Future<void> _loadActiveOrderCount() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('orders')
          .select('id, status')
          .eq('user_id', user.id)
          .inFilter('status', ['pending', 'waiting_verification', 'processing', 'delivered', 'completed']);

      final orders = response as List;

      final ratings = await Supabase.instance.client
          .from('ratings')
          .select('order_id')
          .eq('user_id', user.id);

      final ratedIds = Set<String>.from(
        (ratings as List).map((r) => r['order_id'] as String),
      );

      int count = 0;
      for (final order in orders) {
        final status = order['status'] as String;
        if (status == 'completed') {
          if (!ratedIds.contains(order['id'])) count++;
        } else {
          count++;
        }
      }

      setState(() => _activeOrderCount = count);
    } catch (e) {
      debugPrint('Badge count error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 1) {
            _screens[1] = MyOrdersScreen(key: ValueKey(DateTime.now().millisecondsSinceEpoch));
            _loadActiveOrderCount();
          }
          setState(() => _currentIndex = index);
        },
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _activeOrderCount > 0,
              label: Text('$_activeOrderCount'),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _activeOrderCount > 0,
              label: Text('$_activeOrderCount'),
              child: const Icon(Icons.receipt_long),
            ),
            label: 'Pesanan',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outlined),
            activeIcon: Icon(Icons.person),
            label: 'Akun',
          ),
        ],
      ),
    );
  }
}