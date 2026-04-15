import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_screen.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/dashboard/admin_dashboard_screen.dart';
import 'screens/admin/orders/admin_orders_screen.dart';
import 'screens/admin/menu/admin_menu_screen.dart';
import 'screens/admin/settings/admin_settings_screen.dart';
import 'screens/admin/admin_broadcast_screen.dart';
import 'screens/admin/admin_reports_screen.dart';
import 'screens/order/cart_screen.dart';
import 'screens/order/checkout_screen.dart';
import 'screens/order/order_detail_screen.dart';
import 'screens/order/payment_screen.dart';
import 'screens/order/order_status_screen.dart';
import 'screens/order/my_orders_screen.dart';
import 'screens/order/location_picker_screen.dart';
import 'services/cart_provider.dart';
import 'config.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: true,
    ),
  );

  runApp(const MyApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    FcmService.setNavigatorKey(_navigatorKey);
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        title: 'Warung Gemoy',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          useMaterial3: true,
        ),
        initialRoute: '/splash',
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainScreen(),
          '/cart': (context) => const CartScreen(),
          '/checkout': (context) => const CheckoutScreen(),
          '/order-detail': (context) => const OrderDetailScreen(),
          '/payment': (context) => const PaymentScreen(),
          '/order-status': (context) => const OrderStatusScreen(),
          '/my-orders': (context) => const MyOrdersScreen(),
          '/location-picker': (context) => const LocationPickerScreen(),
          '/admin-login': (context) => const AdminLoginScreen(),
          '/admin-dashboard': (context) => const AdminDashboardScreen(),
          '/admin-orders': (context) => const AdminOrdersScreen(),
          '/admin-menus': (context) => const AdminMenuScreen(),
          '/admin-settings': (context) => const AdminSettingsScreen(),
          '/admin-broadcast': (context) => const AdminBroadcastScreen(),
          '/admin-reports': (context) => const AdminReportsScreen(),
        },
      ),
    );
  }
}