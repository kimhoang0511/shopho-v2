import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../global_messenger.dart';
import 'call_cancel_notifier.dart';
import 'call_service.dart';

const _channelId = 'shopho_orders';
const _channelName = 'Đơn hàng';
const _notifTapChannel = MethodChannel('shopho/notif_tap');

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
  /// Set a non-null orderId to trigger navigation to that order.
  /// Listeners should consume the value and reset it to null.
  static final pendingOrderTapNotifier = ValueNotifier<String?>(null);

  static StreamSubscription<String>? _tokenRefreshSub;

  static Future<void> init(FirebaseOptions options) async {

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
          pendingOrderTapNotifier.value = orderId;
        }
      },
    );

    // iOS: suppress Firebase's own foreground banner — AppDelegate.willPresent
    // returns [.banner, .sound, .badge] so the native system banner is shown
    // instead, and didReceive handles tap navigation via MethodChannel.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // iOS: AppDelegate.didReceive invokes "onTap" when the user taps a notification
    // while the app is in foreground or resuming from background.
    if (Platform.isIOS) {
      _notifTapChannel.setMethodCallHandler((call) async {
        if (call.method == 'onTap') {
          final orderId = call.arguments as String?;
          if (orderId != null && orderId.isNotEmpty) {
            pendingOrderTapNotifier.value = orderId;
          }
        }
      });
      // Cold-start: AppDelegate saved the order_id to UserDefaults before the
      // channel was ready. Read it now — _ShopHoAppState may already have read
      // and cleared it, in which case we get null and do nothing.
      try {
        final orderId = await _notifTapChannel.invokeMethod<String?>('getPendingOrderTap');
        if (orderId != null && orderId.isNotEmpty) {
          pendingOrderTapNotifier.value = orderId;
        }
      } catch (_) {}
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
      // Show a local notification so onDidReceiveNotificationResponse handles the tap.
      // On iOS the native FCM banner is suppressed by AppDelegate.willPresent (it
      // returns [.badge] for gcm.message_id messages), so there is no duplicate.
      // On Android this is the standard foreground notification path.
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
    // Must be awaited so callers (cold-start re-registration) know it completed.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _registerVoipToken(dio);
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

  static const _nativeCallChannel = MethodChannel('shopho/call_native');

  static Future<void> _registerVoipToken(Dio dio) async {
    try {
      debugPrint('[FCM] _registerVoipToken: starting…');
      // Primary: flutter_callkit_incoming plugin (set by AppDelegate.didUpdate).
      // PushKit token is delivered asynchronously — retry up to 10s.
      String? voipToken;
      for (int i = 0; i < 5; i++) {
        final t = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        debugPrint('[FCM] getDevicePushTokenVoIP attempt ${i + 1}: ${t == null ? "null" : t.toString().substring(0, 10) + "…"}');
        if (t != null && t.toString().isNotEmpty) {
          voipToken = t.toString();
          break;
        }
        await Future.delayed(const Duration(seconds: 2));
      }

      // Fallback: AppDelegate.didUpdate saves the raw token to UserDefaults before
      // the Flutter engine initialises. If the plugin path above still returns null
      // (engine init race), read the token from native UserDefaults directly.
      if (voipToken == null || voipToken.isEmpty) {
        debugPrint('[FCM] VoIP token not available from plugin — trying UserDefaults fallback…');
        try {
          final stored = await _nativeCallChannel.invokeMethod<String?>('getStoredVoipToken');
          debugPrint('[FCM] UserDefaults fallback: ${stored == null ? "null" : stored.substring(0, 10) + "…"}');
          if (stored != null && stored.isNotEmpty) {
            voipToken = stored;
          }
        } catch (e) {
          debugPrint('[FCM] getStoredVoipToken error: $e');
        }
      }

      if (voipToken == null || voipToken.isEmpty) {
        debugPrint('[FCM] VoIP token not available after all retries — skipping registration');
        return;
      }
      debugPrint('[FCM] posting VoIP token to backend: ${voipToken.substring(0, 10)}…');
      await dio.post(
        '/users/me/device-token',
        data: {'token': voipToken, 'platform': 'ios_voip'},
      );
      debugPrint('[FCM] VoIP token registered OK: ${voipToken.substring(0, 10)}…');
    } catch (e, st) {
      debugPrint('[FCM] VoIP token registration error: $e\n$st');
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
