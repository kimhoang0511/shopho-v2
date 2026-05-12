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

// Top-level function referenced from main.dart — must be a top-level symbol.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
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
      orderNote: message.data['order_note'] ?? '',
    );
  } else if (message.data['type'] == 'call_cancel') {
    final callId = message.data['call_id'] as String? ?? '';
    if (callId.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(callId);
    }
  }
  // missed_call via FCM background: system shows notification automatically (title/body set).
  // Mark callId as seen so when WS reconnects and re-delivers, it's ignored.
  if (message.data['type'] == 'missed_call') {
    final callId = message.data['call_id'] as String?;
    if (callId != null) CallService.markMissedCallSeen(callId);
  }
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

    // Firebase.initializeApp() and onBackgroundMessage() are called in main()
    // before runApp() so the onMessageOpenedApp listener is ready on iOS before
    // the first frame. onMessageOpenedApp and getInitialMessage are also handled
    // in main(). Here we only set up the foreground & local-notification plumbing.

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
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (details) {
        final orderId = details.payload;
        if (orderId != null && orderId.isNotEmpty) {
          _navigate?.call(orderId);
        }
      },
    );

    // iOS: don't show FCM native banner in foreground — onMessage shows a local
    // notification with an orderId payload for reliable tap navigation.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

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
          orderNote: message.data['order_note'] ?? '',
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
        final callId = message.data['call_id'] as String?;
        CallService.showMissedCallNotification(callerName: callerName, orderId: orderId, callId: callId);
        return;
      }
      // On iOS, message.notification can be null even for notification messages
      // (Firebase delivers data separately from the notification payload).
      // Fall back to data fields so foreground notifications always appear.
      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] as String?;
      final body  = notification?.body  ?? message.data['body']  as String?;
      if (title == null && body == null) return;
      final orderId = message.data['order_id'] as String?;
      _localNotif.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: orderId,
      );
    });

    // Request permission (iOS/Android 13+) + pre-warm APNs token on iOS
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOS: trigger APNs registration at startup so the token is ready by login time.
    // getAPNSToken() returns null until Apple's servers respond — retry up to 10s.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        (settings.authorizationStatus == AuthorizationStatus.authorized ||
         settings.authorizationStatus == AuthorizationStatus.provisional)) {
      _preWarmApnsToken();
    }
  }

  static Future<void> _preWarmApnsToken() async {
    for (int i = 0; i < 5; i++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) {
        debugPrint('[FCM] APNs pre-warm OK: ${apns.substring(0, 10)}…');
        return;
      }
      debugPrint('[FCM] APNs pre-warm retry ${i + 1}/5…');
      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('[FCM] APNs pre-warm failed — token not available at startup');
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
      // iOS: APNs token phải có trước thì getToken() mới hoạt động.
      // Retry tối đa 10 lần (10 giây) chờ APNs cấp token.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (int i = 0; i < 10; i++) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          if (apnsToken != null) break;
          debugPrint('[FCM] APNs token null — retry ${i + 1}/10…');
          await Future.delayed(const Duration(seconds: 1));
        }
        if (apnsToken == null) {
          debugPrint('[FCM] APNs token not available after 10s — push will not work on iOS');
          return;
        }
        debugPrint('[FCM] APNs token ready: ${apnsToken.substring(0, 10)}…');
      }

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
            debugPrint('[FCM] permission denied: ${settings.authorizationStatus.name}');
            return;
          }
        } on TimeoutException {
          debugPrint('[FCM] requestPermission timed out');
          return;
        }
      }

      if (token == null) {
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
        debugPrint('[FCM] backend register failed: $e');
      }
    } catch (e) {
      debugPrint('[FCM] registerToken unexpected error: $e');
    }
  }

  static Future<void> _registerVoipToken(Dio dio) async {
    try {
      // PushKit token is delivered asynchronously — retry up to 10s.
      String? voipToken;
      for (int i = 0; i < 5; i++) {
        final t = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (t != null && t.toString().isNotEmpty) {
          voipToken = t.toString();
          break;
        }
        debugPrint('[FCM] VoIP token null — retry ${i + 1}/5…');
        await Future.delayed(const Duration(seconds: 2));
      }
      if (voipToken == null) {
        debugPrint('[FCM] VoIP token not available after retries');
        return;
      }
      await dio.post(
        '/users/me/device-token',
        data: {'token': voipToken, 'platform': 'ios_voip'},
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
        await dio.delete('/users/me/device-token', data: {'token': token});
      }
      // Remove VoIP token on iOS
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          if (voipToken != null && voipToken.toString().isNotEmpty) {
            await dio.delete('/users/me/device-token', data: {'token': voipToken.toString()});
          }
        } catch (_) {}
      }
      // Invalidate token so a fresh one is generated on next login
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FCM] unregisterToken error: $e');
    }
  }
}
