import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:livekit_client/livekit_client.dart';

import '../api/api_client.dart';
import 'call_debug_logger.dart';

/// Handles LiveKit connection in the background when the user accepts
/// a call from the iOS lock screen. The pre-connected [Room] and
/// [LocalAudioTrack] are handed off to [WebRtcCallScreen] when it opens.
class BackgroundCallService {
  static Room? _room;
  static LocalAudioTrack? _audioTrack;
  static String? _callId;
  static String? _orderId;
  static bool _isConnecting = false;
  static bool _isConnected = false;

  static bool get isActive => _isConnecting || _isConnected;
  static bool get isConnected => _isConnected;
  static String? get callId => _callId;
  static String? get orderId => _orderId;

  static Future<void> startConnection({
    required String callId,
    required String orderId,
    required String livekitUrl,
  }) async {
    if (_isConnecting || _isConnected) {
      CallDebugLogger.log('BGCall', 'startConnection: already active, skip');
      return;
    }

    _callId = callId;
    _orderId = orderId;
    _isConnecting = true;

    CallDebugLogger.log('BGCall', 'startConnection: callId=$callId orderId=$orderId');

    try {
      CallDebugLogger.log('BGCall', 'fetching livekit token...');
      final accessToken = await const FlutterSecureStorage().read(key: 'access_token');
      if (accessToken == null) throw Exception('No access token');
      final res = await Dio(BaseOptions(
        baseUrl: apiBaseUrl,
        headers: {'Authorization': 'Bearer $accessToken'},
        connectTimeout: const Duration(seconds: 10),
      )).post('/orders/$orderId/livekit-token');
      final token = res.data['token'] as String;
      final url = res.data['livekit_url'] as String? ?? livekitUrl;
      CallDebugLogger.log('BGCall', 'token fetched OK');

      _room = Room();
      CallDebugLogger.log('BGCall', 'connecting to room...');
      await _room!.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );
      CallDebugLogger.log('BGCall', 'room connected');

      _audioTrack = await LocalAudioTrack.create(const AudioCaptureOptions());
      await _room!.localParticipant?.publishAudioTrack(_audioTrack!);
      CallDebugLogger.log('BGCall', 'audio track published');

      _isConnecting = false;
      _isConnected = true;
      CallDebugLogger.log('BGCall', 'background connection COMPLETE');
    } catch (e) {
      _isConnecting = false;
      CallDebugLogger.log('BGCall', 'startConnection FAILED: $e');
      await dispose();
    }
  }

  static BackgroundCallResult? consume() {
    if (!_isConnected || _room == null) return null;

    final result = BackgroundCallResult(
      room: _room!,
      audioTrack: _audioTrack!,
      callId: _callId!,
      orderId: _orderId!,
    );

    _room = null;
    _audioTrack = null;
    _callId = null;
    _orderId = null;
    _isConnected = false;

    CallDebugLogger.log('BGCall', 'consumed by WebRtcCallScreen');
    return result;
  }

  static Future<void> dispose() async {
    final room = _room;
    final track = _audioTrack;

    _room = null;
    _audioTrack = null;
    _callId = null;
    _orderId = null;
    _isConnecting = false;
    _isConnected = false;

    if (room != null) {
      try { await room.disconnect(); await room.dispose(); } catch (_) {}
    }
    if (track != null) {
      try { await track.stop(); await track.dispose(); } catch (_) {}
    }
  }
}

class BackgroundCallResult {
  final Room room;
  final LocalAudioTrack audioTrack;
  final String callId;
  final String orderId;

  BackgroundCallResult({
    required this.room,
    required this.audioTrack,
    required this.callId,
    required this.orderId,
  });
}