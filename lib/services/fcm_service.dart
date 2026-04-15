import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'gemoy_kitchen_channel',
    'Warung Gemoy Notifications',
    description: 'Notifikasi dari Warung Gemoy',
    importance: Importance.high,
  );

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        _handleNotificationTap(details.payload);
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('FCM: Izin notifikasi diberikan');
      await _saveToken();
    }

    _messaging.onTokenRefresh.listen((token) async {
      await _updateToken(token);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM Foreground: ${message.notification?.title}');
      _showPopupNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final type = message.data['type'] as String?;
      final orderId = message.data['order_id'] as String?;
      _navigateFromNotification(type, orderId);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type'] as String?;
      final orderId = initialMessage.data['order_id'] as String?;
      Future.delayed(const Duration(seconds: 1), () {
        _navigateFromNotification(type, orderId);
      });
    }
  }

  static Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      debugPrint('FCM Token: $token');

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Cek apakah ini akun admin
      final isAdmin = await Supabase.instance.client
          .from('admins')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (isAdmin != null) {
        await Supabase.instance.client
            .from('admins')
            .update({'fcm_token': token}).eq('id', user.id);
        debugPrint('FCM Token tersimpan untuk admin!');
        return;
      }

      // Akun pelanggan biasa
      final userExists = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (userExists == null) {
        debugPrint('FCM: user belum ada di tabel users, skip');
        return;
      }

      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token}).eq('id', user.id);

      debugPrint('FCM Token tersimpan!');
    } catch (e) {
      debugPrint('FCM save token error: $e');
    }
  }

  static void _showPopupNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String?;
    final orderId = message.data['order_id'] as String?;
    final payload = type != null ? '$type|${orderId ?? ''}' : '';

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  static void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    final type = parts.isNotEmpty ? parts[0] : null;
    final orderId = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    _navigateFromNotification(type, orderId);
  }

  static void _navigateFromNotification(String? type, String? orderId) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;

    switch (type) {
      case 'order_status':
      case 'payment_confirmed':
      case 'payment_rejected':
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
              (route) => false,
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          Navigator.pushNamed(context, '/my-orders');
        });
        break;
      case 'broadcast':
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
              (route) => false,
        );
        break;
      case 'new_order':
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/admin-dashboard',
              (route) => false,
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          Navigator.pushNamed(context, '/admin-orders');
        });
        break;
    }
  }

  static Future<void> _updateToken(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final isAdmin = await Supabase.instance.client
          .from('admins').select('id').eq('id', user.id).maybeSingle();

      if (isAdmin != null) {
        await Supabase.instance.client
            .from('admins').update({'fcm_token': token}).eq('id', user.id);
      } else {
        await Supabase.instance.client
            .from('users').update({'fcm_token': token}).eq('id', user.id);
      }
    } catch (e) {
      debugPrint('FCM update token error: $e');
    }
  }

  static Future<void> clearToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final isAdmin = await Supabase.instance.client
          .from('admins').select('id').eq('id', user.id).maybeSingle();

      if (isAdmin != null) {
        await Supabase.instance.client
            .from('admins').update({'fcm_token': null}).eq('id', user.id);
      } else {
        await Supabase.instance.client
            .from('users').update({'fcm_token': null}).eq('id', user.id);
      }
    } catch (e) {
      debugPrint('FCM clear token error: $e');
    }
  }
}