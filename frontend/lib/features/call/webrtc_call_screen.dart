import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api/api_client.dart';
import '../../core/services/call_cancel_notifier.dart';
import '../../core/services/call_service.dart';

enum _CallState { connecting, talking, noAnswer, ended }

class WebRtcCallScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String callId;
  final String counterpartName;
  final String livekitUrl;
  /// Pre-provided token (caller). Empty string → screen fetches its own token (recipient).
  final String token;

  const WebRtcCallScreen({
    super.key,
    required this.orderId,
    required this.callId,
    required this.counterpartName,
    required this.livekitUrl,
    required this.token,
  });

  @override
  ConsumerState<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends ConsumerState<WebRtcCallScreen> {
  late final Room _room;
  EventsListener<RoomEvent>? _listener;
  LocalAudioTrack? _audioTrack;

  _CallState _callState = _CallState.connecting;
  bool _muted = false;
  bool _disposed = false;

  Timer? _durationTimer;
  Timer? _ringTimeout;
  Duration _elapsed = Duration.zero;
  bool _cancelSent = false;

  @override
  void initState() {
    super.initState();
    _room = Room();
    callCancelNotifier.addListener(_onRemoteCancel);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _disposed = true;
    callCancelNotifier.removeListener(_onRemoteCancel);
    _durationTimer?.cancel();
    _ringTimeout?.cancel();
    _listener?.dispose();
    _room.disconnect().then((_) => _room.dispose()).ignore();
    // Tell CallKit the call is over so iOS removes the "ongoing call" status bar indicator.
    if (widget.callId.isNotEmpty) {
      FlutterCallkitIncoming.endCall(widget.callId);
    }
    super.dispose();
  }

  void _onRemoteDisconnect() {
    if (_disposed || !mounted) return;
    _durationTimer?.cancel();
    _ringTimeout?.cancel();
    if (_callState == _CallState.talking) {
      setState(() => _callState = _CallState.ended);
      Future.delayed(const Duration(seconds: 2), () => _hangup(sendCancel: false));
    } else {
      _hangup(sendCancel: false);
    }
  }

  void _onRemoteCancel() {
    final cancelId = callCancelNotifier.value;
    if (cancelId == null) return;
    if (cancelId != widget.callId && widget.callId.isNotEmpty) return;
    if (_disposed || !mounted) return;
    _ringTimeout?.cancel();
    setState(() => _callState = _CallState.noAnswer);
    Future.delayed(const Duration(seconds: 2), () => _hangup(sendCancel: false));
  }

  Future<void> _init() async {
    String token;
    String livekitUrl = widget.livekitUrl;

    // Phase 1: resolve token
    // For recipient (token is empty): try the prefetched token first.
    // The prefetch was started in CallService when the user tapped Accept,
    // so it has been running in parallel with navigation — may already be done.
    try {
      if (widget.token.isEmpty) {
        final prefetchFuture = CallService.consumePrefetchedToken(widget.orderId);
        Map<String, String>? prefetched;
        if (prefetchFuture != null) {
          prefetched = await prefetchFuture;
        }
        if (prefetched != null && prefetched['token']!.isNotEmpty) {
          token = prefetched['token']!;
          if (prefetched['livekit_url']!.isNotEmpty) livekitUrl = prefetched['livekit_url']!;
        } else {
          // Prefetch failed or wasn't started — fall back to a fresh fetch.
          final res = await ref.read(apiClientProvider).dio
              .post('/orders/${widget.orderId}/livekit-token');
          token = res.data['token'] as String;
          livekitUrl = res.data['livekit_url'] as String? ?? livekitUrl;
        }
      } else {
        token = widget.token;
      }
    } catch (e) {
      debugPrint('[LiveKit] token fetch failed: $e');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Phase 2: connect to LiveKit room AND initialize audio track in parallel.
    // LocalAudioTrack.create() only opens the mic — it doesn't need the room.
    // Overlapping it with room.connect() saves ~200-400ms.
    try {
      final connectFuture = _room.connect(
        livekitUrl,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );
      final trackFuture = LocalAudioTrack.create(const AudioCaptureOptions());

      await connectFuture;
      _audioTrack = await trackFuture;
      await _room.localParticipant?.publishAudioTrack(_audioTrack!);

      // Phase 3: wait for remote participant to join
      _listener = _room.createListener()
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted && _callState != _CallState.talking) {
            _ringTimeout?.cancel();
            setState(() => _callState = _CallState.talking);
            _startDurationTimer();
          }
        })
        ..on<ParticipantDisconnectedEvent>((_) => _onRemoteDisconnect())
        ..on<RoomDisconnectedEvent>((_) => _onRemoteDisconnect());

      // Remote participant already in room (recipient joins after caller)
      if (_room.remoteParticipants.isNotEmpty && mounted) {
        _ringTimeout?.cancel();
        setState(() => _callState = _CallState.talking);
        _startDurationTimer();
      } else {
        // No-answer timeout: 45s no one joins → noAnswer state → auto hang up
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          if (_callState != _CallState.talking && !_disposed && mounted) {
            setState(() => _callState = _CallState.noAnswer);
            Future.delayed(const Duration(seconds: 2), () => _hangup());
          }
        });
      }
    } catch (e) {
      debugPrint('[LiveKit] connect error: $e');
      final msg = e.toString().toLowerCase();
      final isPermission = msg.contains('permission') || msg.contains('denied') || msg.contains('microphone');
      if (mounted) {
        if (isPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần cấp quyền microphone để thực hiện cuộc gọi')),
          );
        }
        Navigator.of(context).pop();
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _hangup({bool sendCancel = true}) async {
    if (_disposed) return;
    _disposed = true;
    _durationTimer?.cancel();
    _ringTimeout?.cancel();

    // Pop immediately so the user sees instant feedback.
    // Cleanup (cancel signal + LiveKit disconnect) runs in the background.
    if (mounted) Navigator.of(context).pop();

    if (sendCancel && !_cancelSent && widget.callId.isNotEmpty) {
      _cancelSent = true;
      try {
        final dio = ref.read(apiClientProvider).dio;
        dio
            .post('/orders/${widget.orderId}/call-cancel',
                data: {'call_id': widget.callId})
            .ignore();
      } catch (_) {}
    }
    _room.disconnect().ignore();
  }

  Future<void> _toggleMute() async {
    final track = _audioTrack;
    if (track == null) return;
    if (_muted) {
      await track.unmute();
    } else {
      await track.mute();
    }
    if (mounted) setState(() => _muted = !_muted);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _hangup(),
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A3E),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 60),

              // Avatar + name + status badge
              Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: const Color(0xFF5B6AF0).withValues(alpha: 0.3),
                        child: Text(
                          widget.counterpartName.isNotEmpty
                              ? widget.counterpartName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 48,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      _StateIndicator(state: _callState),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.counterpartName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StateBadge(
                    state: _callState,
                    elapsed: _elapsed,
                  ),
                ],
              ),

              // Controls
              Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CircleBtn(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Bỏ tắt' : 'Tắt mic',
                      enabled: _callState == _CallState.talking,
                      onTap: _toggleMute,
                    ),
                    _HangupBtn(onTap: _hangup),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── State indicator dot on avatar ───────────────────────────

class _StateIndicator extends StatelessWidget {
  final _CallState state;
  const _StateIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      _CallState.connecting => (Colors.grey, Icons.sync),
      _CallState.talking    => (Colors.greenAccent, Icons.phone_in_talk),
      _CallState.noAnswer   => (Colors.red, Icons.phone_missed),
      _CallState.ended      => (Colors.grey, Icons.call_end),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF1A1A3E), width: 2),
      ),
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}

// ─── Status badge below name ──────────────────────────────────

class _StateBadge extends StatelessWidget {
  final _CallState state;
  final Duration elapsed;
  const _StateBadge({required this.state, required this.elapsed});

  String get _label => switch (state) {
    _CallState.connecting => 'Đang kết nối',
    _CallState.talking    => _fmt(elapsed),
    _CallState.noAnswer   => 'Đã ngắt cuộc gọi',
    _CallState.ended      => 'Cuộc gọi đã kết thúc',
  };

  Color get _color => switch (state) {
    _CallState.connecting => Colors.white54,
    _CallState.talking    => Colors.greenAccent,
    _CallState.noAnswer   => Colors.redAccent,
    _CallState.ended      => Colors.white54,
  };

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Đang trao đổi · $m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _label,
        style: TextStyle(color: _color, fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── Buttons ──────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _CircleBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.15 : 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: enabled ? Colors.white : Colors.white30, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white30, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HangupBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _HangupBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          const Text('Kết thúc', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
