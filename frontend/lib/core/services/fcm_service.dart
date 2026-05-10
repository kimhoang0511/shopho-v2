import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../global_messenger.dart';
import 'call_cancel_notifier.dart';
import 'call_service.dart';

const _channelId = 'shopho_orders';
const _channelName = 'Đơn hàng';

final _localNotif = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'call') {
    final initiatedAt = int.tryParse(message.data['initiated_at'] ?? '');
    await CallService.showIncomingCall(
      callId: message.data['call_id'] ?? '',
      callerName: message.data['caller_name'] ?? 'Người gọi',
      orderId: message.data['order_id'] ?? '',
      livekitUrl: message.data['livekit_url'] ?? '',
      roomName: message.data['room_name'] ?? '',
      initiatedAt: initiatedAt,
    );
  } else if (message.data['type'] == 'call_cancel') {
    final callId = message.data['call_id'] as String? ?? '';
    if (callId.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(callId);
    }
  }
  // missed_call: delivered via FCM notification payload (title/body set by backend)
  // so the system shows it automatically — no extra handling needed here.
}

class FcmService {
  static void Function(String orderId)? _navigate;
  static String? _pendingOrderId;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// If the app was launched by tapping a notification while terminated,
  /// returns the order ID to navigate to (and clears it).
  static String? consumePendingNavigation() {
    final id = _pendingOrderId;
    _pendingOrderId = null;
    return id;
  }

  static Future<void> init(
    FirebaseOptions options, {
    required void Function(String orderId) onNavigateToOrder,
  }) async {
    _navigate = onNavigateToOrder;

    await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Android notification channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Init local notifications plugin — tap on foreground notification navigates to order
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        final orderId = details.payload;
        if (orderId != null && orderId.isNotEmpty) {
          _navigate?.call(orderId);
        }
      },
    );

    // iOS foreground presentation
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // App in background → user taps FCM notification → navigate to order
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final orderId = message.data['order_id'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        _navigate?.call(orderId);
      }
    });

    // App terminated → opened via FCM notification → store and navigate after first frame
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final orderId = initial.data['order_id'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        _pendingOrderId = orderId;
      }
    }

    // Show notification when app is in foreground
    FirebaseMessaging.onMessage.listen((message) {
      // Call messages: show callkit UI, not a regular notification
      if (message.data['type'] == 'call') {
        final initiatedAt = int.tryParse(message.data['initiated_at'] ?? '');
        CallService.showIncomingCall(
          callId: message.data['call_id'] ?? '',
          callerName: message.data['caller_name'] ?? 'Người gọi',
          orderId: message.data['order_id'] ?? '',
          livekitUrl: message.data['livekit_url'] ?? '',
          roomName: message.data['room_name'] ?? '',
          initiatedAt: initiatedAt,
        );
        return;
      }
      // Cancel signal: dismiss callkit + signal active call screen
      if (message.data['type'] == 'call_cancel') {
        final callId = message.data['call_id'] as String? ?? '';
        if (callId.isNotEmpty) {
          FlutterCallkitIncoming.endCall(callId);
          callCancelNotifier.value = callId;
        }
        return;
      }
      // Missed call: FCM carries the notification payload so the system shows it
      // automatically in background/killed. In foreground we must show it manually.
      if (message.data['type'] == 'missed_call') {
        final callerName = message.data['caller_name'] as String? ?? 'Người gọi';
        final orderId = message.data['order_id'] as String?;
        CallService.showMissedCallNotification(callerName: callerName, orderId: orderId);
        return;
      }
      final notification = message.notification;
      if (notification == null) return;
      final orderId = message.data['order_id'] as String?;
      _localNotif.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: orderId, // tapped → navigates to this order
      );
    });

    // Request permission (iOS/Android 13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Register FCM + VoIP tokens with the backend. Call after login.
  static Future<void> registerToken(Dio dio) async {
    CallService.registerDio(dio);

    // Cancel previous onTokenRefresh listener before adding a new one.
    // Without this, every login stacks an additional listener that never gets removed.
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        await dio.post(
          '/users/me/device-token',
          data: {'token': newToken, 'platform': defaultTargetPlatform.name.toLowerCase()},
        );
        debugPrint('[FCM] token refreshed and re-registered');
      } catch (e) {
        debugPrint('[FCM] onTokenRefresh re-register failed: $e');
      }
    });

    await _registerFcmToken(dio);

    // VoIP token — iOS only (PushKit). Guarantees waking app when killed.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _registerVoipToken(dio);
    }
  }

  static Future<void> _registerFcmToken(Dio dio) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();

      // getToken() returns null if permission hasn't been granted yet — retry once.
      if (token == null) {
        debugPrint('[FCM] token null — requesting permission and retrying…');
        try {
          final settings = await FirebaseMessaging.instance
              .requestPermission()
              .timeout(const Duration(seconds: 10));
          if (settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional) {
            token = await FirebaseMessaging.instance.getToken();
          } else {
            final status = settings.authorizationStatus.name;
            showGlobalError(
              '[Push] Quyền thông báo bị từ chối ($status) — thiết bị sẽ không nhận được cuộc gọi hay thông báo.',
            );
            debugPrint('[FCM] permission denied: $status');
            return;
          }
        } on TimeoutException {
          showGlobalError('[Push] Hết thời gian chờ cấp quyền thông báo.');
          debugPrint('[FCM] requestPermission timed out');
          return;
        }
      }

      if (token == null) {
        showGlobalError('[Push] Không lấy được FCM token — thiết bị sẽ không nhận được thông báo đẩy.');
        debugPrint('[FCM] getToken returned null after permission granted');
        return;
      }

      final platform = defaultTargetPlatform.name.toLowerCase();
      try {
        await dio.post(
          '/users/me/device-token',
          data: {'token': token, 'platform': platform},
        );
        debugPrint('[FCM] token registered ok (${token.substring(0, 12)}… platform=$platform)');
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        final detail = e.response?.data?['detail'] ?? e.message;
        showGlobalError('[Push] Đăng ký token thất bại (HTTP $code): $detail');
        debugPrint('[FCM] backend register failed: $e');
      }
    } catch (e) {
      // On iOS the APNs token arrives asynchronously; calling getToken() too early
      // throws apns-token-not-set. onTokenRefresh (registered above) will fire once
      // the token is ready, so this is safe to ignore silently.
      if (e.toString().contains('apns-token-not-set')) {
        debugPrint('[FCM] APNs token not ready yet — will register via onTokenRefresh');
        return;
      }
      showGlobalError('[Push] Lỗi không xác định khi đăng ký thông báo đẩy: $e');
      debugPrint('[FCM] registerToken unexpected error: $e');
    }
  }

  static Future<void> _registerVoipToken(Dio dio) async {
    try {
      final voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (voipToken == null || voipToken.toString().isEmpty) return;
      await dio.post(
        '/users/me/device-token',
        data: {'token': voipToken.toString(), 'platform': 'ios_voip'},
      );
      debugPrint('[FCM] VoIP token registered');
    } catch (e) {
      debugPrint('[FCM] VoIP token registration error: $e');
    }
  }

  /// Remove the device token from backend and invalidate it on Firebase.
  /// Call before logout so the device stops receiving push notifications.
  static Future<void> unregisterToken(Dio dio) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await dio.delete(
          '/users/me/device-token',
          data: {'token': token},
        );
      }
      // Invalidate token so a fresh one is generated on next login
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FCM] unregisterToken error: $e');
    }
  }
}
