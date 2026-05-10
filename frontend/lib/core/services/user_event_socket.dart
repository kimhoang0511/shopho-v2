import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import 'call_cancel_notifier.dart';
import 'call_service.dart';

/// Persistent WebSocket that delivers call/cancel events instantly when the
/// app is in the foreground. FCM remains the fallback for background/killed.
class UserEventSocket {
  static WebSocketChannel? _channel;
  static StreamSubscription? _sub;
  static Timer? _pingTimer;
  static Timer? _reconnectTimer;
  static bool _active = false;
  static bool _connecting = false;
  static String? _token;

  static Future<void> connect(String accessToken) async {
    _token = accessToken;
    _active = true;
    // Already connected or connecting — nothing to do.
    if (_channel != null || _connecting) return;
    await _doConnect();
  }

  static void disconnect() {
    _active = false;
    _connecting = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    debugPrint('[UserEventSocket] disconnected');
  }

  static Future<void> _doConnect() async {
    if (!_active || _token == null || _connecting) return;
    _connecting = true;
    try {
      final uri = Uri.parse('$wsBaseUrl/ws/user/events?token=$_token');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      debugPrint('[UserEventSocket] connected');

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
        cancelOnError: true,
      );

      // Ping every 25s to keep the connection alive through NAT/proxies.
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[UserEventSocket] connect error: $e');
      _channel = null;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  static void _onDisconnect() {
    debugPrint('[UserEventSocket] disconnected — will retry');
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel = null;
    _scheduleReconnect();
  }

  static void _scheduleReconnect() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _doConnect);
  }

  static void _onMessage(dynamic raw) {
    if (raw == 'pong') return;
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'call') {
        debugPrint('[UserEventSocket] incoming call via socket');
        CallService.showIncomingCall(
          callId: data['call_id'] as String? ?? '',
          callerName: data['caller_name'] as String? ?? 'Người gọi',
          orderId: data['order_id'] as String? ?? '',
          livekitUrl: data['livekit_url'] as String? ?? '',
          roomName: data['room_name'] as String? ?? '',
          initiatedAt: data['initiated_at'] as int?,
        );
      } else if (type == 'call_cancel') {
        final callId = data['call_id'] as String? ?? '';
        debugPrint('[UserEventSocket] call_cancel via socket: $callId');
        if (callId.isNotEmpty) {
          callCancelNotifier.value = callId;
        }
      }
    } catch (e) {
      debugPrint('[UserEventSocket] message parse error: $e');
    }
  }
}
