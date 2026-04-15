import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      // Cek token di tabel users dulu, lalu admins
      String? fcmToken;

      final userResponse = await Supabase.instance.client
          .from('users')
          .select('fcm_token')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse != null) {
        fcmToken = userResponse['fcm_token'] as String?;
      } else {
        // Coba cari di tabel admins
        final adminResponse = await Supabase.instance.client
            .from('admins')
            .select('fcm_token')
            .eq('id', userId)
            .maybeSingle();
        fcmToken = adminResponse?['fcm_token'] as String?;
      }

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Notif: user $userId tidak punya FCM token');
        return;
      }

      // Kirim via Edge Function
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'token': fcmToken,
          'title': title,
          'body': body,
          'data': data ?? {},
        },
        headers: {
          'Authorization': 'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}',
        },
      );

      debugPrint('Notif terkirim ke $userId: $title');
    } catch (e) {
      debugPrint('Notif error: $e');
    }
  }

  // Notifikasi status pesanan berubah
  static Future<void> orderStatusChanged({
    required String userId,
    required String orderId,
    required String newStatus,
  }) async {
    String title = '';
    String body = '';

    switch (newStatus) {
      case 'processing':
        title = '👨‍🍳 Pesanan Sedang Dimasak';
        body = 'Pesanan #${orderId.substring(0, 8).toUpperCase()} sedang disiapkan!';
        break;
      case 'delivered':
        title = '🛵 Pesanan Siap!';
        body = 'Pesanan #${orderId.substring(0, 8).toUpperCase()} siap diantar/diambil!';
        break;
      case 'completed':
        title = '✅ Pesanan Selesai';
        body = 'Pesanan #${orderId.substring(0, 8).toUpperCase()} telah selesai. Terima kasih!';
        break;
      case 'cancelled':
        title = '❌ Pesanan Dibatalkan';
        body = 'Pesanan #${orderId.substring(0, 8).toUpperCase()} telah dibatalkan.';
        break;
      case 'waiting_verification':
        title = '🔍 Pembayaran Diverifikasi';
        body = 'Bukti bayar pesanan #${orderId.substring(0, 8).toUpperCase()} sedang diverifikasi.';
        break;
    }

    if (title.isEmpty) return;

    await sendToUser(
      userId: userId,
      title: title,
      body: body,
      data: {'order_id': orderId, 'type': 'order_status'},
    );
  }

  // Notifikasi pembayaran dikonfirmasi
  static Future<void> paymentConfirmed({
    required String userId,
    required String orderId,
  }) async {
    await sendToUser(
      userId: userId,
      title: '✅ Pembayaran Dikonfirmasi!',
      body: 'Pembayaran pesanan #${orderId.substring(0, 8).toUpperCase()} telah dikonfirmasi.',
      data: {'order_id': orderId, 'type': 'payment_confirmed'},
    );
  }

  // Notifikasi pembayaran ditolak
  static Future<void> paymentRejected({
    required String userId,
    required String orderId,
  }) async {
    await sendToUser(
      userId: userId,
      title: '❌ Pembayaran Ditolak',
      body: 'Pembayaran pesanan #${orderId.substring(0, 8).toUpperCase()} ditolak. Silakan upload ulang bukti bayar.',
      data: {'order_id': orderId, 'type': 'payment_rejected'},
    );
  }

  // Notifikasi pesanan baru ke admin
  static Future<void> newOrderToAdmin({
    required String adminUserId,
    required String orderId,
    required String customerName,
  }) async {
    await sendToUser(
      userId: adminUserId,
      title: '🛒 Pesanan Baru!',
      body: 'Pesanan baru dari $customerName masuk!',
      data: {'order_id': orderId, 'type': 'new_order'},
    );
  }

  // Notifikasi bukti bayar diupload ke admin
  static Future<void> paymentProofUploaded({
    required String adminUserId,
    required String orderId,
    required String customerName,
  }) async {
    await sendToUser(
      userId: adminUserId,
      title: '💳 Bukti Bayar Masuk!',
      body: '$customerName mengupload bukti pembayaran untuk pesanan #${orderId.substring(0, 8).toUpperCase()}',
      data: {'order_id': orderId, 'type': 'new_order'},
    );
  }

  // Notifikasi pesanan dibatalkan pelanggan ke admin
  static Future<void> orderCancelledByCustomer({
    required String adminUserId,
    required String orderId,
    required String customerName,
  }) async {
    await sendToUser(
      userId: adminUserId,
      title: '❌ Pesanan Dibatalkan',
      body: '$customerName membatalkan pesanan #${orderId.substring(0, 8).toUpperCase()}',
      data: {'order_id': orderId, 'type': 'new_order'},
    );
  }

  // Notifikasi broadcast ke semua user
  static Future<void> sendBroadcast({
    required String title,
    required String body,
  }) async {
    try {
      // Ambil semua FCM token user aktif
      final users = await Supabase.instance.client
          .from('users')
          .select('id, fcm_token')
          .not('fcm_token', 'is', null);

      for (final user in users) {
        final fcmToken = user['fcm_token'] as String?;
        if (fcmToken == null || fcmToken.isEmpty) continue;

        await Supabase.instance.client.functions.invoke(
          'send-notification',
          body: {
            'token': fcmToken,
            'title': title,
            'body': body,
            'data': {'type': 'broadcast'},
          },
          headers: {
            'Authorization': 'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}',
          },
        );
      }
      debugPrint('Broadcast terkirim ke ${users.length} user');
    } catch (e) {
      debugPrint('Broadcast error: $e');
    }
  }
}