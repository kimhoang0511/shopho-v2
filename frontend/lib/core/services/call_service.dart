import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
    // Persist base URL so _getOrBuildDio can reconstruct Dio after app kill.
    const FlutterSecureStorage().write(key: 'api_base_url', value: _baseUrl!);
  }

  /// Returns an available Dio. Falls back to a fresh one built from the stored
  /// auth token when the registered Dio is unavailable (e.g. app was killed).
  static Future<Dio?> _getOrBuildDio() async {
    if (_dio != null) return _dio;
    var base = _baseUrl;
    if (base == null) {
      // App was killed — recover base URL from secure storage.
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
  // the call screen immediately — even when the app is already in the foreground
  // (in which case AppLifecycleState.resumed never fires).
  static final acceptedCallNotifier = ValueNotifier<Map<String, String>?>(null);

  // Must match _CALL_RING_TTL on the backend (seconds).
  static const int _CALL_RING_TTL_SECONDS = 45;

  // Tracks callIds seen in this session. Never cleared — keeps dedup active
  // even after decline/timeout so delayed FCM can't re-show the same call.
  static final Set<String> _activeCallIds = {};

  // Tracks missed-call callIds already shown so WS + FCM don't both show it.
  static final Set<String> _missedCallIds = {};

  // Called from FCM background isolate to pre-mark a missed call as seen,
  // preventing the WS reconnect from showing a duplicate notification.
  static void markMissedCallSeen(String callId) => _missedCallIds.add(callId);

  // Prefetched LiveKit token for B (recipient). Started on Accept so the token
  // is ready (or close to ready) by the time WebRtcCallScreen._init() runs.
  static Future<Map<String, String>?>? _prefetchedTokenFuture;
  static String? _prefetchedTokenOrderId;

  /// Called by WebRtcCallScreen to consume the prefetched token.
  /// Returns null if no prefetch was started or orderId doesn't match.
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

  static Future<void> init() async {
    FlutterCallkitIncoming.onEvent.listen(_handleEvent);
  }

  static void _handleEvent(CallEvent? event) async {
    if (event == null) return;
    final callId = event.body['id'] as String? ?? '';
    switch (event.event) {
      case Event.actionCallAccept:
        _activeCallIds.remove(callId);
        final extra = event.body['extra'] as Map?;
        final orderId = extra?['order_id'] as String?;
        final callerName = extra?['caller_name'] as String? ?? 'Người gọi';
        final livekitUrl = extra?['livekit_url'] as String? ?? '';
        if (orderId != null) {
          // Start fetching the LiveKit token immediately — runs in parallel
          // with the permission dialog so both resolve before _init() needs them.
          _prefetchRecipientToken(orderId);
          // Await mic permission before navigating. On fresh install the dialog
          // must be granted first — otherwise LocalAudioTrack.create() throws and
          // the call screen immediately pops itself. On subsequent calls this
          // resolves instantly because the permission is already granted.
          await Permission.microphone.request();
          final callInfo = {
            'orderId': orderId,
            'callerName': callerName,
            'livekitUrl': livekitUrl,
            'callId': callId,
          };
          // Keep for lifecycle-based fallback (background/killed app).
          _pendingAcceptedCall = callInfo;
          // Also notify immediately so foreground apps can navigate right away
          // without waiting for an AppLifecycleState.resumed event.
          acceptedCallNotifier.value = callInfo;
        }
        break;

      case Event.actionCallDecline:
      case Event.actionCallTimeout:
        // Keep callId in _activeCallIds — do NOT remove it. This prevents
        // delayed FCM/WS deliveries of the same call from re-showing the UI
        // after the user has already declined or the ring timed out.
        await FlutterCallkitIncoming.endAllCalls();
        final extra = event.body['extra'] as Map?;
        final orderId = extra?['order_id'] as String?;
        if (orderId != null && callId.isNotEmpty) {
          _sendCancel(orderId, callId).ignore();
        }
        break;

      case Event.actionCallEnded:
        // Keep callId in _activeCallIds for the same reason.
        await FlutterCallkitIncoming.endAllCalls();
        break;

      default:
        break;
    }
  }

  /// Send call-cancel to backend. Uses registered Dio or builds a fallback one
  /// from the stored auth token (covers the case where the app was killed and
  /// the event fires before Dio is registered again).
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
  }) async {
    // Reject calls that are too old — handles delayed FCM and stale Redis
    // pending_calls delivered on WS reconnect after the ring window expired.
    if (initiatedAt != null) {
      final ageSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - initiatedAt;
      if (ageSeconds > _CALL_RING_TTL_SECONDS) {
        debugPrint('[CallService] ignoring stale call ($ageSeconds s old): $callId');
        return;
      }
    }

    // In-isolate dedup (WS + FCM arriving in the same isolate).
    if (_activeCallIds.contains(callId)) {
      debugPrint('[CallService] duplicate showIncomingCall for $callId — ignored (in-isolate)');
      return;
    }

    // Cross-isolate dedup: FCM background handler runs in a separate Dart isolate,
    // so _activeCallIds above won't catch it. Query the native CallKit layer instead
    // — it is shared across all isolates.
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List && active.any((c) => c['id'] == callId)) {
        debugPrint('[CallService] duplicate showIncomingCall for $callId — ignored (cross-isolate)');
        _activeCallIds.add(callId); // sync local set so subsequent in-isolate checks work
        return;
      }
    } catch (_) {}

    _activeCallIds.add(callId);

    // If there are stale calls from a previous session that the user dismissed
    // without using Accept/Decline (e.g. swiped the app away or the process was
    // killed), clean them up now and notify the caller side before showing the
    // new incoming call.
    await _cleanUpStaleCalls(skipCallId: callId);

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ShopHo',
      type: 0,
      duration: 45000,
      extra: {
        'order_id': orderId,
        'caller_name': callerName,
        'livekit_url': livekitUrl,
        'room_name': roomName,
      },
      android: const AndroidParams(
        isCustomNotification: false,
        isShowFullLockedScreen: true,
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

  /// Ends any CallKit calls that are not the new incoming one, and sends cancel
  /// signals to the backend for each stale call so the other party is notified.
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
      // Only end all calls when there were actually stale calls to clean up.
      // Calling endAllCalls() when skipCallId is the only active call would
      // kill the new incoming call and trigger a spurious actionCallDecline.
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
    // Dedup: WS delivers on reconnect AND FCM may also arrive — show only once.
    if (callId != null) {
      if (_missedCallIds.contains(callId)) {
        debugPrint('[CallService] duplicate missed call $callId — ignored');
        return;
      }
      _missedCallIds.add(callId);
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
