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
  static String? _lastError;
  static DateTime? _startedAt;
  static DateTime? _connectedAt;

  static bool get isActive => _isConnecting || _isConnected;
  static bool get isConnected => _isConnected;
  static String? get callId => _callId;
  static String? get orderId => _orderId;
  static String? get lastError => _lastError;
  static String get status {
    if (_isConnected) return 'CONNECTED';
    if (_isConnecting) return 'CONNECTING';
    if (_lastError != null) return 'FAILED: $_lastError';
    return 'IDLE';
  }

  static Future<void> startConnection({
    required String callId,
    required String orderId,
    required String livekitUrl,
  }) async {
    _log('startConnection called callId=$callId orderId=$orderId livekitUrl=$livekitUrl isConnecting=$_isConnecting isConnected=$_isConnected');

    if (_isConnecting || _isConnected) {
      _log('startConnection: already active, skip');
      return;
    }

    _callId = callId;
    _orderId = orderId;
    _isConnecting = true;
    _lastError = null;
    _startedAt = DateTime.now();

    try {
      // 1. Fetch token
      _log('step 1: fetching livekit token...');
      final sw = Stopwatch()..start();
      final accessToken = await const FlutterSecureStorage().read(key: 'access_token');
      if (accessToken == null) {
        _log('step 1 FAILED: no access token in secure storage');
        throw Exception('No access token');
      }
      _log('step 1: access token found (${accessToken.length} chars)');

      final dio = Dio(BaseOptions(
        baseUrl: apiBaseUrl,
        headers: {'Authorization': 'Bearer $accessToken'},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final res = await dio.post('/orders/$orderId/livekit-token');
      sw.stop();
      _log('step 1 DONE: token fetched in ${sw.elapsedMilliseconds}ms status=${res.statusCode} hasToken=${res.data['token'] != null} hasUrl=${res.data['livekit_url'] != null}');

      final token = res.data['token'] as String;
      final url = res.data['livekit_url'] as String? ?? livekitUrl;
      _log('step 1: token=${token.length > 20 ? token.substring(0, 20) : token}... url=$url');

      // 2. Connect to room
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );
      _log('step 2: Room created, connecting...');

      sw.reset(); sw.start();
      await _room!.connect(url, token);
      sw.stop();
      _log('step 2 DONE: room connected in ${sw.elapsedMilliseconds}ms roomName=${_room!.name} localSid=${_room!.localParticipant?.sid ?? "null"} remoteCount=${_room!.remoteParticipants.length}');

      // 3. Create audio track
      _log('step 3: creating audio track...');
      sw.reset(); sw.start();
      _audioTrack = await LocalAudioTrack.create(const AudioCaptureOptions());
      _log('step 3: audio track created in ${sw.elapsedMilliseconds}ms');

      // 4. Publish audio track
      _log('step 4: publishing audio track...');
      sw.reset(); sw.start();
      await _room!.localParticipant?.publishAudioTrack(_audioTrack!);
      sw.stop();
      _log('step 4 DONE: audio published in ${sw.elapsedMilliseconds}ms');

      _isConnecting = false;
      _isConnected = true;
      _connectedAt = DateTime.now();
      final totalTime = _connectedAt!.difference(_startedAt!).inMilliseconds;
      _log('BACKGROUND CONNECTION COMPLETE in ${totalTime}ms remoteCount=${_room!.remoteParticipants.length}');
    } catch (e, st) {
      _isConnecting = false;
      _lastError = e.toString();
      _log('startConnection FAILED: $e');
      debugPrint('[BGCall] FAILED: $e\n$st');
      await dispose();
    }
  }

  static BackgroundCallResult? consume() {
    _log('consume called isConnected=$_isConnected hasRoom=${_room != null} hasTrack=${_audioTrack != null} callId=$_callId orderId=$_orderId status=$status lastError=$_lastError');

    if (!_isConnected || _room == null) {
      _log('consume: returning NULL (not ready) isConnected=$_isConnected room=${_room != null} lastError=$_lastError');
      return null;
    }

    final result = BackgroundCallResult(
      room: _room!,
      audioTrack: _audioTrack!,
      callId: _callId!,
      orderId: _orderId!,
    );

    _log('consume: returning Room remoteCount=${_room!.remoteParticipants.length}');

    _room = null;
    _audioTrack = null;
    _callId = null;
    _orderId = null;
    _isConnected = false;

    return result;
  }

  /// Cancel any background connection (e.g. when call was already cancelled by A).
  static void cancel() {
    _log('cancel called — discarding background connection');
    _callId = null;
    _orderId = null;
    _isConnecting = false;
    _isConnected = false;
  }

  static Future<void> dispose() async {
    _log('dispose called hadRoom=${_room != null} hadTrack=${_audioTrack != null}');
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

  static void _log(String msg) {
    CallDebugLogger.log('BGCall', msg);
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