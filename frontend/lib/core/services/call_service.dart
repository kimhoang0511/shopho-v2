import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class CallService {
  static Dio? _dio;
  static String? _baseUrl;

  /// Called after login so the service can reach the backend.
  static void registerDio(Dio dio) {
    _dio = dio;
    _baseUrl = dio.options.baseUrl;
    const FlutterSecureStorage().write(key: 'api_base_url', value: _baseUrl!);
  }

  static Future<Dio?> _getOrBuildDio() async {
    if (_dio != null) return _dio;
    var base = _baseUrl;
    if (base == null) {
      base = await const FlutterSecureStorage().read(key: 'api_base_url');
    }
    if (base == null) return null;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'access_token');
      if (token == null) return null;
      return Dio(BaseOptions(
        baseUrl: base,
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 8),
      ));
    } catch (_) {
      return null;
    }
  }

  // Stores a call that was accepted while the app was transitioning from background.
  // Consumed by the lifecycle observer in the root widget once the app is resumed.
  static Map<String, String>? _pendingAcceptedCall;

  // Fires whenever the user accepts a call so the root widget can navigate to
  // the call screen immediately — even when the app is already in the foreground.
  static final acceptedCallNotifier = ValueNotifier<Map<String, String>?>(null);

  // Must match _CALL_RING_TTL on the backend (seconds).
  static const int _CALL_RING_TTL_SECONDS = 45;

  // Tracks callIds seen in this session. Never cleared — keeps dedup active
  // even after decline/timeout so delayed FCM can't re-show the same call.
  static final Set<String> _activeCallIds = {};

  // Tracks callIds that have been fully accepted and navigation triggered.
  // Prevents double-navigation when EventChannel and MethodChannel both fire.
  static final Set<String> _handledAcceptCallIds = {};

  // Tracks missed-call callIds already shown so WS + FCM don't both show it.
  static final Set<String> _missedCallIds = {};

  static void markMissedCallSeen(String callId) {
    _missedCallIds.add(callId);
    _storage.write(key: '_missed_seen_$callId', value: '1').ignore();
  }

  // Tracks callIds that reached the talking state (both sides connected).
  // A missed call notification must never be shown for a connected call.
  static final Set<String> _connectedCallIds = {};

  static void markCallConnected(String callId) {
    if (callId.isNotEmpty) _connectedCallIds.add(callId);
  }

  static bool _initialized = false;

  // Prefetched LiveKit token for B (recipient). Started on Accept so the token
  // is ready (or close to ready) by the time WebRtcCallScreen._init() runs.
  static Future<Map<String, String>?>? _prefetchedTokenFuture;
  static String? _prefetchedTokenOrderId;

  static Future<Map<String, String>?>? consumePrefetchedToken(String orderId) {
    if (_prefetchedTokenOrderId != orderId) return null;
    _prefetchedTokenOrderId = null;
    final f = _prefetchedTokenFuture;
    _prefetchedTokenFuture = null;
    return f;
  }

  static void _prefetchRecipientToken(String orderId) {
    _prefetchedTokenOrderId = orderId;
    _prefetchedTokenFuture = _doFetchRecipientToken(orderId);
  }

  static Future<Map<String, String>?> _doFetchRecipientToken(String orderId) async {
    try {
      final dio = await _getOrBuildDio();
      if (dio == null) return null;
      final res = await dio.post('/orders/$orderId/livekit-token');
      return {
        'token': res.data['token'] as String? ?? '',
        'livekit_url': res.data['livekit_url'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('[CallService] _prefetchRecipientToken error: $e');
      return null;
    }
  }

  static Map<String, String>? consumePendingAcceptedCall() {
    final call = _pendingAcceptedCall;
    _pendingAcceptedCall = null;
    return call;
  }

  // ── In-memory call-data cache ──────────────────────────────────────────────
  // Populated when showIncomingCall() runs in the main isolate (WS / FCM
  // foreground). Gives _handleEvent a reliable source for orderId etc. when
  // event.body['extra'] is null on some Android devices.
  static final Map<String, Map<String, String>> _inMemoryCallCache = {};

  // ── Persistent call-data cache ─────────────────────────────────────────────
  // Covers the killed-app / FCM background isolate case where the main isolate
  // has no in-memory state. Written by showIncomingCall() from any isolate.
  static const _storage = FlutterSecureStorage();

  static Future<void> _saveCallData(
      String callId, String orderId, String callerName, String livekitUrl,
      {String orderNote = ''}) async {
    try {
      await _storage.write(
        key: '_call_$callId',
        value: jsonEncode({'o': orderId, 'n': callerName, 'u': livekitUrl, 't': orderNote}),
      );
    } catch (_) {}
  }

  static Future<Map<String, String>?> _loadCallData(String callId) async {
    try {
      final raw = await _storage.read(key: '_call_$callId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'order_id': m['o'] as String? ?? '',
        'caller_name': m['n'] as String? ?? '',
        'livekit_url': m['u'] as String? ?? '',
        'order_note': m['t'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearCallData(String callId) async {
    try {
      await _storage.delete(key: '_call_$callId');
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────

  static const _nativeChannel = MethodChannel('shopho/call_native');

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    FlutterCallkitIncoming.onEvent.listen(_handleEvent);

    if (Platform.isAndroid) {
      FlutterCallkitIncoming.requestFullIntentPermission();

      // Hướng 2: MethodChannel handler for when MainActivity detects an Accept
      // intent AFTER Flutter is already running (app was in background).
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'callAccepted') {
          final callId = call.arguments as String? ?? '';
          if (callId.isNotEmpty) await _handleNativeAccept(callId);
        }
      });

      // Poll for accept that arrived during cold start (app was killed).
      // MainActivity stores the callId in SharedPreferences; we read it here
      // once the engine is ready.
      try {
        final callId = await _nativeChannel.invokeMethod<String?>('getPendingAcceptCallId');
        if (callId != null && callId.isNotEmpty) {
          await _handleNativeAccept(callId);
          return; // skip redundant _recoverMissedAcceptedCall below
        }
      } catch (_) {}
    }

    // Fallback: plugin-based recovery for non-Android-14 accept paths.
    _recoverMissedAcceptedCall();
  }

  // Fallback: called when MethodChannel fires callAccepted (cold-start) or
  // when EventChannel event is dropped. Does NOT speculatively claim
  // _handledAcceptCallIds — only claims after confirming data exists, so that
  // a concurrent EventChannel arrival can still win the race.
  static Future<void> _handleNativeAccept(String callId) async {
    if (_handledAcceptCallIds.contains(callId)) return;

    String? orderId;
    String callerName = 'Người gọi';
    String livekitUrl = '';
    String orderNote = '';

    // 1. In-memory cache (WS / FCM-foreground path in same isolate).
    final cached = _inMemoryCallCache[callId];
    if (cached != null) {
      orderId = cached['order_id'];
      if ((cached['caller_name'] ?? '').isNotEmpty) callerName = cached['caller_name']!;
      if ((cached['livekit_url'] ?? '').isNotEmpty) livekitUrl = cached['livekit_url']!;
      if ((cached['order_note'] ?? '').isNotEmpty) orderNote = cached['order_note']!;
    }

    // 2. Persistent storage (killed-app or FCM background isolate).
    if (orderId == null || orderId.isEmpty) {
      final saved = await _loadCallData(callId);
      if (saved != null) {
        orderId = saved['order_id'];
        if ((saved['caller_name'] ?? '').isNotEmpty) callerName = saved['caller_name']!;
        if ((saved['livekit_url'] ?? '').isNotEmpty) livekitUrl = saved['livekit_url']!;
        if ((saved['order_note'] ?? '').isNotEmpty) orderNote = saved['order_note']!;
      }
    }

    if (orderId == null || orderId.isEmpty) {
      // No data found — let EventChannel path handle it if/when it arrives.
      debugPrint('[CallService] _handleNativeAccept: no data for $callId, deferring to EventChannel');
      return;
    }

    // Only claim after we have data, and re-check in case EventChannel won.
    if (_handledAcceptCallIds.contains(callId)) return;
    _handledAcceptCallIds.add(callId);

    debugPrint('[CallService] native accept callId=$callId orderId=$orderId');
    _activeCallIds.add(callId);
    _inMemoryCallCache.remove(callId);
    _clearCallData(callId).ignore();
    _prefetchRecipientToken(orderId);
    await Permission.microphone.request();

    final callInfo = {
      'orderId': orderId,
      'callerName': callerName,
      'livekitUrl': livekitUrl,
      'callId': callId,
      'orderNote': orderNote,
    };
    _pendingAcceptedCall = callInfo;
    acceptedCallNotifier.value = callInfo;
  }

  static Future<void> _recoverMissedAcceptedCall() async {
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is! List || active.isEmpty) return;

      for (final call in active) {
        final callId = call['id'] as String? ?? '';
        if (callId.isEmpty) continue;

        final isAccepted = call['isAccepted'] as bool? ?? false;
        if (!isAccepted) continue;

        // Already handled by the normal EventChannel path.
        if (_activeCallIds.contains(callId)) continue;
        if (_pendingAcceptedCall?['callId'] == callId) continue;

        final extra = call['extra'] as Map?;
        String? orderId = extra?['order_id'] as String?;
        String callerName = extra?['caller_name'] as String? ?? 'Người gọi';
        String livekitUrl = extra?['livekit_url'] as String? ?? '';
        String orderNote = extra?['order_note'] as String? ?? '';

        if ((orderId == null || orderId.isEmpty) && callId.isNotEmpty) {
          final cached = _inMemoryCallCache[callId];
          if (cached != null) {
            orderId = cached['order_id'];
            if ((cached['caller_name'] ?? '').isNotEmpty) callerName = cached['caller_name']!;
            if ((cached['livekit_url'] ?? '').isNotEmpty) livekitUrl = cached['livekit_url']!;
            if ((cached['order_note'] ?? '').isNotEmpty) orderNote = cached['order_note']!;
          }
        }

        if ((orderId == null || orderId.isEmpty) && callId.isNotEmpty) {
          final saved = await _loadCallData(callId);
          if (saved != null) {
            orderId = saved['order_id'];
            if ((saved['caller_name'] ?? '').isNotEmpty) callerName = saved['caller_name']!;
            if ((saved['livekit_url'] ?? '').isNotEmpty) livekitUrl = saved['livekit_url']!;
            if ((saved['order_note'] ?? '').isNotEmpty) orderNote = saved['order_note']!;
          }
        }

        if (orderId != null && orderId.isNotEmpty) {
          debugPrint('[CallService] recovered accepted call (Android 14): $callId orderId=$orderId');
          _activeCallIds.add(callId);
          _inMemoryCallCache.remove(callId);
          _clearCallData(callId).ignore();
          _prefetchRecipientToken(orderId);
          await Permission.microphone.request();
          final callInfo = {
            'orderId': orderId,
            'callerName': callerName,
            'livekitUrl': livekitUrl,
            'callId': callId,
            'orderNote': orderNote,
          };
          _pendingAcceptedCall = callInfo;
          acceptedCallNotifier.value = callInfo;
          break; // one call at a time
        }
      }
    } catch (e) {
      debugPrint('[CallService] _recoverMissedAcceptedCall error: $e');
    }
  }

  static void _handleEvent(CallEvent? event) async {
    if (event == null) return;
    final callId = event.body['id'] as String? ?? '';
    switch (event.event) {
      case Event.actionCallAccept:
        _activeCallIds.remove(callId);
        if (_handledAcceptCallIds.contains(callId)) break;
        _handledAcceptCallIds.add(callId);
        final extra = event.body['extra'] as Map?;
        String? orderId = extra?['order_id'] as String?;
        String callerName = extra?['caller_name'] as String? ?? 'Người gọi';
        String livekitUrl = extra?['livekit_url'] as String? ?? '';
        String orderNote = extra?['order_note'] as String? ?? '';

        // Fallback 1: in-memory cache (main-isolate WS / FCM-foreground path).
        if ((orderId == null || orderId.isEmpty) && callId.isNotEmpty) {
          final cached = _inMemoryCallCache[callId];
          if (cached != null) {
            orderId = cached['order_id'];
            if ((cached['caller_name'] ?? '').isNotEmpty) callerName = cached['caller_name']!;
            if ((cached['livekit_url'] ?? '').isNotEmpty) livekitUrl = cached['livekit_url']!;
            if ((cached['order_note'] ?? '').isNotEmpty) orderNote = cached['order_note']!;
            debugPrint('[CallService] extra from memory cache — orderId=$orderId');
          }
        }

        // Fallback 2: persistent storage (killed-app / FCM background isolate).
        if ((orderId == null || orderId.isEmpty) && callId.isNotEmpty) {
          final saved = await _loadCallData(callId);
          if (saved != null) {
            orderId = saved['order_id'];
            if ((saved['caller_name'] ?? '').isNotEmpty) callerName = saved['caller_name']!;
            if ((saved['livekit_url'] ?? '').isNotEmpty) livekitUrl = saved['livekit_url']!;
            if ((saved['order_note'] ?? '').isNotEmpty) orderNote = saved['order_note']!;
            debugPrint('[CallService] extra from storage — orderId=$orderId');
          }
        }

        if (orderId != null && orderId.isNotEmpty) {
          _inMemoryCallCache.remove(callId);
          _clearCallData(callId).ignore();
          _prefetchRecipientToken(orderId);
          // Await mic permission before navigating. On first install the dialog
          // must be granted first; on subsequent calls this resolves instantly.
          await Permission.microphone.request();
          final callInfo = {
            'orderId': orderId,
            'callerName': callerName,
            'livekitUrl': livekitUrl,
            'callId': callId,
            'orderNote': orderNote,
          };
          // Lifecycle-based fallback (background / lock-screen accept).
          _pendingAcceptedCall = callInfo;
          // Immediate signal for foreground case (no lifecycle event fired).
          acceptedCallNotifier.value = callInfo;
        }
        break;

      case Event.actionCallDecline:
      case Event.actionCallTimeout:
        // Keep callId in _activeCallIds — prevents delayed FCM/WS re-showing.
        _inMemoryCallCache.remove(callId);
        _clearCallData(callId).ignore();
        await FlutterCallkitIncoming.endAllCalls();
        final extra = event.body['extra'] as Map?;
        final orderId = extra?['order_id'] as String?;
        if (orderId != null && callId.isNotEmpty) {
          _sendCancel(orderId, callId).ignore();
        }
        break;

      case Event.actionCallEnded:
        // Fired when user taps "Kết thúc" in the ongoing call notification.
        // Send cancel to backend so the other party knows the call ended.
        final endedExtra = event.body['extra'] as Map?;
        String? endedOrderId = endedExtra?['order_id'] as String?;
        if ((endedOrderId == null || endedOrderId.isEmpty) && callId.isNotEmpty) {
          final cached = _inMemoryCallCache[callId];
          if (cached != null) endedOrderId = cached['order_id'];
        }
        if ((endedOrderId == null || endedOrderId.isEmpty) && callId.isNotEmpty) {
          final saved = await _loadCallData(callId);
          if (saved != null) endedOrderId = saved['order_id'];
        }
        _inMemoryCallCache.remove(callId);
        _clearCallData(callId).ignore();
        await FlutterCallkitIncoming.endAllCalls();
        if (endedOrderId != null && endedOrderId.isNotEmpty && callId.isNotEmpty) {
          _sendCancel(endedOrderId, callId).ignore();
        }
        break;

      default:
        break;
    }
  }

  static Future<void> _sendCancel(String orderId, String callId) async {
    try {
      final dio = await _getOrBuildDio();
      if (dio == null) {
        debugPrint('[CallService] _sendCancel: no Dio available');
        return;
      }
      await dio.post('/orders/$orderId/call-cancel', data: {'call_id': callId});
      debugPrint('[CallService] cancel sent for call $callId');
    } catch (e) {
      debugPrint('[CallService] _sendCancel error: $e');
    }
  }

  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String orderId,
    required String livekitUrl,
    required String roomName,
    int? initiatedAt,
    String orderNote = '',
  }) async {
    if (initiatedAt != null) {
      final ageSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - initiatedAt;
      if (ageSeconds > _CALL_RING_TTL_SECONDS) {
        debugPrint('[CallService] stale call ($ageSeconds s old): $callId — showing missed call');
        if (callId.isNotEmpty) _activeCallIds.add(callId);
        // Let showMissedCallNotification handle dedup internally.
        showMissedCallNotification(
          callerName: callerName,
          orderId: orderId.isNotEmpty ? orderId : null,
          callId: callId.isNotEmpty ? callId : null,
        );
        return;
      }
    }

    // In-isolate dedup — claim slot immediately before any await so concurrent
    // async paths (WS + FCM both in foreground) can't both slip through.
    if (_activeCallIds.contains(callId)) {
      debugPrint('[CallService] duplicate showIncomingCall for $callId — ignored (in-isolate)');
      return;
    }
    _activeCallIds.add(callId);

    // Cross-isolate dedup via native CallKit layer.
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List && active.any((c) => c['id'] == callId)) {
        debugPrint('[CallService] duplicate showIncomingCall for $callId — ignored (cross-isolate)');
        return;
      }
    } catch (_) {}

    // Cache call data in memory (same isolate) — reliable Accept fallback.
    _inMemoryCallCache[callId] = {
      'order_id': orderId,
      'caller_name': callerName,
      'livekit_url': livekitUrl,
      'order_note': orderNote,
    };

    // Also persist to storage for the killed-app / FCM background isolate case.
    _saveCallData(callId, orderId, callerName, livekitUrl, orderNote: orderNote).ignore();

    await _cleanUpStaleCalls(skipCallId: callId);

    final truncatedNote = orderNote.length > 60
        ? '${orderNote.substring(0, 57)}...'
        : orderNote;

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ShopHo',
      handle: truncatedNote.isNotEmpty ? truncatedNote : null,
      type: 0,
      duration: 45000,
      extra: {
        'order_id': orderId,
        'caller_name': callerName,
        'livekit_url': livekitUrl,
        'room_name': roomName,
        'order_note': orderNote,
      },
      // Ongoing call notification (shown after Accept, while in call).
      // Provides a "Kết thúc" hang-up button — critical fallback when the
      // call screen fails to appear on Android 14.
      callingNotification: const NotificationParams(
        showNotification: true,
        subtitle: 'Đang kết nối...',
        callbackText: 'Kết thúc',
        isShowCallback: true,
      ),
      android: AndroidParams(
        // true → on Android 14+: uses CallStyle.forOngoingCall() for the
        // ongoing notification, making the "Kết thúc" hang-up button always
        // visible without needing to expand. Incoming still uses
        // CallStyle.forIncomingCall() on Android 14 regardless of this flag.
        isCustomNotification: true,
        isShowFullLockedScreen: true,
        isShowCallID: truncatedNote.isNotEmpty,
        ringtonePath: 'default',
        actionColor: '#5B6AF0',
        incomingCallNotificationChannelName: 'Cuộc gọi đến',
        missedCallNotificationChannelName: 'Cuộc gọi nhỡ',
        isShowLogo: false,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> _cleanUpStaleCalls({required String skipCallId}) async {
    try {
      final raw = await FlutterCallkitIncoming.activeCalls();
      if (raw is! List || raw.isEmpty) return;

      bool foundStale = false;
      for (final item in raw) {
        final id = item['id'] as String? ?? '';
        if (id == skipCallId || id.isEmpty) continue;

        foundStale = true;
        final extra = item['extra'] as Map?;
        final staleOrderId = extra?['order_id'] as String?;
        if (staleOrderId != null) {
          debugPrint('[CallService] cleaning stale call $id for order $staleOrderId');
          await _sendCancel(staleOrderId, id);
        }
      }
      if (foundStale) await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[CallService] _cleanUpStaleCalls error: $e');
    }
  }

  static Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('[CallService] Microphone permission denied');
      return false;
    }
    return true;
  }

  static Future<void> showMissedCallNotification({
    required String callerName,
    String? orderId,
    String? callId,
  }) async {
    if (callId != null) {
      if (_connectedCallIds.contains(callId)) {
        debugPrint('[CallService] call $callId was connected — skipping missed call notification');
        return;
      }
      if (_missedCallIds.contains(callId)) {
        debugPrint('[CallService] duplicate missed call $callId — ignored (in-memory)');
        return;
      }
      // Cross-isolate dedup: background FCM handler and main isolate each have
      // their own _missedCallIds. SecureStorage is shared across all isolates.
      try {
        final seen = await _storage.read(key: '_missed_seen_$callId');
        if (seen != null) {
          debugPrint('[CallService] duplicate missed call $callId — ignored (cross-isolate)');
          _missedCallIds.add(callId);
          return;
        }
      } catch (_) {}
      _missedCallIds.add(callId);
      _storage.write(key: '_missed_seen_$callId', value: '1').ignore();
    }
    const channelId = 'shopho_missed_calls';
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.show(
      callerName.hashCode,
      'Cuộc gọi nhỡ',
      'Bạn vừa có một cuộc gọi nhỡ từ $callerName',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Cuộc gọi nhỡ',
          channelDescription: 'Thông báo cuộc gọi nhỡ',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: orderId,
    );
  }
}
