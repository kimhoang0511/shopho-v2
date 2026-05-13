import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api/api_client.dart';
import '../../core/services/call_cancel_notifier.dart';
import '../../core/services/call_service.dart';

enum _CallState { connecting, talking, noAnswer, ended }

// ─── Debug log ────────────────────────────────────────────────
// Remove or set to false before shipping to production.
const _kDebug = true;

class WebRtcCallScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String callId;
  final String counterpartName;
  final String livekitUrl;
  /// Pre-provided token (caller). Empty string → screen fetches its own token (recipient).
  final String token;
  final String orderNote;

  const WebRtcCallScreen({
    super.key,
    required this.orderId,
    required this.callId,
    required this.counterpartName,
    required this.livekitUrl,
    required this.token,
    this.orderNote = '',
  });

  @override
  ConsumerState<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends ConsumerState<WebRtcCallScreen>
    with WidgetsBindingObserver {
  late final Room _room;
  EventsListener<RoomEvent>? _listener;
  LocalAudioTrack? _audioTrack;

  _CallState _callState = _CallState.connecting;
  bool _muted = false;
  bool _disposed = false;
  bool _remoteAudioSubscribed = false;

  /// Timestamp when the LiveKit room was successfully connected.
  /// Used to ignore stale ParticipantDisconnectedEvent from previous calls
  /// in the same room (same order-id reuse).
  DateTime? _roomConnectedAt;

  /// Whether at least one remote participant has ever connected during this
  /// call session. Guards against stale disconnect events from previous calls.
  bool _remoteEverConnected = false;

  Timer? _durationTimer;
  Timer? _ringTimeout;
  Duration _elapsed = Duration.zero;
  bool _cancelSent = false;

  // ── Debug log ──────────────────────────────────────────────
  final List<String> _dbg = [];
  bool _showDebug = false;

  void _log(String msg) {
    final ts = DateTime.now();
    final s = '[${ts.hour.toString().padLeft(2,'0')}:'
        '${ts.minute.toString().padLeft(2,'0')}:'
        '${ts.second.toString().padLeft(2,'0')}.'
        '${(ts.millisecond ~/ 10).toString().padLeft(2,'0')}] $msg';
    debugPrint('[CallDebug] $s');
    if (_kDebug && mounted) setState(() { _dbg.add(s); if (_dbg.length > 30) _dbg.removeAt(0); });
  }

  @override
  void initState() {
    super.initState();
    _room = Room();
    callCancelNotifier.addListener(_onRemoteCancel);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log('initState — callId=${widget.callId} token=${widget.token.isEmpty ? "EMPTY(recipient)" : "PROVIDED(caller)"} lifecycle=${WidgetsBinding.instance.lifecycleState}');
      _init();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
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

    // Grace period: ignore stale ParticipantDisconnectedEvent that may fire
    // from a previous call's participant still in the LiveKit room.
    // Room names are reused per order (order-{id}), so a participant from
    // a prior call may disconnect after we connect — we must not treat this
    // as the current remote hanging up.
    if (_roomConnectedAt != null &&
        DateTime.now().difference(_roomConnectedAt!) < const Duration(seconds: 5) &&
        !_remoteEverConnected) {
      _log('_onRemoteDisconnect: IGNORED (within 5s grace, no remote ever connected)');
      return;
    }

    // If we've never seen a remote participant connect during this session,
    // the disconnect is from a stale participant — ignore it.
    if (!_remoteEverConnected && _callState == _CallState.connecting) {
      _log('_onRemoteDisconnect: IGNORED (no remote ever connected, still connecting)');
      return;
    }

    _durationTimer?.cancel();
    _ringTimeout?.cancel();
    if (_callState == _CallState.talking) {
      // Call was established — remote hung up normally, not a missed call.
      setState(() => _callState = _CallState.ended);
      Future.delayed(const Duration(seconds: 2), () => _hangup(sendCancel: false));
    } else if (_callState != _CallState.ended) {
      // Not yet connected — hang up immediately.
      // Guard _CallState.ended: both ParticipantDisconnectedEvent and
      // RoomDisconnectedEvent can fire together; only the first should act.
      _hangup(sendCancel: false);
    }
  }

  // When the user taps the iOS green in-call bar (banner accept path), the app
  // resumes from background. The audio session may have been inactive while the
  // screen was hidden — restart it so audio flows immediately on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('lifecycle → $state  callState=$_callState');
    if (state == AppLifecycleState.resumed && Platform.isIOS) {
      if (_callState == _CallState.connecting || _callState == _CallState.talking) {
        _log('resumed: calling restartAudio');
        CallService.restartAudioForCallKit()
            .then((_) => _log('restartAudio(resume) done'))
            .catchError((e) { _log('restartAudio(resume) ERR: $e'); return null; });
      }
    }
  }

  void _onRemoteCancel() {
    final cancelId = callCancelNotifier.value;
    if (cancelId == null) return;
    if (cancelId != widget.callId && widget.callId.isNotEmpty) return;
    if (_disposed || !mounted) return;
    // If the call already ended normally (remote disconnected from LiveKit),
    // ignore the subsequent cancel signal — don't overwrite 'ended' with 'noAnswer'.
    if (_callState == _CallState.ended) return;
    _ringTimeout?.cancel();
    // Only show missed call if:
    // 1. Call never reached talking state, AND
    // 2. We are the recipient (widget.token is empty) — not the caller.
    //    The caller (A) does not receive a "missed call" when B declines.
    if (_callState != _CallState.talking && widget.token.isEmpty) {
      CallService.showMissedCallNotification(
        callerName: widget.counterpartName,
        callId: widget.callId.isNotEmpty ? widget.callId : null,
      );
    }
    setState(() => _callState = _CallState.noAnswer);
    Future.delayed(const Duration(seconds: 2), () => _hangup(sendCancel: false));
  }

  Future<void> _init() async {
    _log('_init START  lifecycle=${WidgetsBinding.instance.lifecycleState}');
    String token;
    String livekitUrl = widget.livekitUrl;

    // Phase 1: resolve token
    try {
      if (widget.token.isEmpty) {
        final prefetchFuture = CallService.consumePrefetchedToken(widget.orderId);
        Map<String, String>? prefetched;
        if (prefetchFuture != null) {
          _log('token: awaiting prefetch');
          prefetched = await prefetchFuture;
        }
        if (prefetched != null && prefetched['token']!.isNotEmpty) {
          token = prefetched['token']!;
          if (prefetched['livekit_url']!.isNotEmpty) livekitUrl = prefetched['livekit_url']!;
          _log('token: from prefetch OK');
        } else {
          _log('token: prefetch miss → fresh fetch');
          final res = await ref.read(apiClientProvider).dio
              .post('/orders/${widget.orderId}/livekit-token');
          token = res.data['token'] as String;
          livekitUrl = res.data['livekit_url'] as String? ?? livekitUrl;
          _log('token: fresh fetch OK');
        }
      } else {
        token = widget.token;
        _log('token: pre-provided (caller)');
      }
    } catch (e) {
      _log('token FAILED: $e');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Phase 2: connect to LiveKit room AND initialize audio track in parallel.
    final callInitiatedAt = DateTime.now();
    try {
      _log('connecting to room…');
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
      _roomConnectedAt = DateTime.now();
      _log('room connected  lifecycle=${WidgetsBinding.instance.lifecycleState}');
      _audioTrack = await trackFuture;
      _log('audio track created');
      await _room.localParticipant?.publishAudioTrack(_audioTrack!);
      _log('audio track published  lifecycle=${WidgetsBinding.instance.lifecycleState}');

      if (Platform.isIOS && widget.callId.isNotEmpty && widget.token.isEmpty) {
        _log('iOS recipient: setCallConnected + restartAudio');
        await FlutterCallkitIncoming.setCallConnected(widget.callId);
        CallService.restartAudioForCallKit()
            .then((_) => _log('restartAudio(1) done'))
            .catchError((e) { _log('restartAudio(1) ERR: $e'); return null; });
      }

      // Phase 3: wait for remote participant
      _listener = _room.createListener()
        ..on<ParticipantConnectedEvent>((_) {
          _log('ParticipantConnectedEvent  lifecycle=${WidgetsBinding.instance.lifecycleState}');
          _remoteEverConnected = true;
          if (mounted && _callState != _CallState.talking) {
            _ringTimeout?.cancel();
            setState(() => _callState = _CallState.talking);
            _startDurationTimer();
            if (widget.callId.isNotEmpty) CallService.markCallConnected(widget.callId);
          }
          if (Platform.isIOS) {
            _log('restartAudio(ParticipantConnected)');
            CallService.restartAudioForCallKit()
                .then((_) => _log('restartAudio(2) done'))
                .catchError((e) { _log('restartAudio(2) ERR: $e'); return null; });
          }
        })
        ..on<TrackPublishedEvent>((e) {
          if (e.publication.kind == TrackType.AUDIO) {
            _log('TrackPublishedEvent(AUDIO)  lifecycle=${WidgetsBinding.instance.lifecycleState}');
            if (mounted && _callState != _CallState.talking) {
              _ringTimeout?.cancel();
              setState(() => _callState = _CallState.talking);
              _startDurationTimer();
              if (widget.callId.isNotEmpty) CallService.markCallConnected(widget.callId);
            }
            if (Platform.isIOS) {
              _log('restartAudio(TrackPublished)');
              CallService.restartAudioForCallKit()
                  .then((_) => _log('restartAudio(3) done'))
                  .catchError((e) { _log('restartAudio(3) ERR: $e'); return null; });
            }
          }
        })
        ..on<TrackSubscribedEvent>((e) {
          if (e.publication.kind == TrackType.AUDIO) {
            _log('TrackSubscribedEvent(AUDIO) participant=${e.participant.identity} muted=${e.publication.muted}');
            if (mounted) setState(() => _remoteAudioSubscribed = true);
            if (Platform.isIOS) {
              _log('restartAudio(TrackSubscribed)');
              CallService.restartAudioForCallKit()
                  .then((_) => _log('restartAudio(5) done'))
                  .catchError((e) { _log('restartAudio(5) ERR: $e'); return null; });
            }
          }
        })
        ..on<TrackUnsubscribedEvent>((e) {
          if (e.publication.kind == TrackType.AUDIO) {
            _log('TrackUnsubscribedEvent(AUDIO) participant=${e.participant.identity}');
            if (mounted) setState(() => _remoteAudioSubscribed = false);
          }
        })
        ..on<TrackMutedEvent>((e) {
          _log('TrackMutedEvent kind=${e.publication.kind} participant=${e.participant.identity}');
        })
        ..on<TrackUnmutedEvent>((e) {
          _log('TrackUnmutedEvent kind=${e.publication.kind} participant=${e.participant.identity}');
        })
        ..on<TrackStreamStateUpdatedEvent>((e) {
          if (e.publication.kind == TrackType.AUDIO) {
            _log('TrackStreamStateUpdated(AUDIO) participant=${e.participant.identity} state=${e.streamState}');
          }
        })
        ..on<ActiveSpeakersChangedEvent>((e) {
          final ids = e.speakers.map((p) => p.identity).join(',');
          _log('ActiveSpeakers: [$ids]');
        })
        ..on<RoomReconnectingEvent>((_) {
          _log('RoomReconnectingEvent — audio will pause');
        })
        ..on<RoomReconnectedEvent>((_) async {
          _log('RoomReconnectedEvent');
          if (Platform.isIOS) {
            try {
              await CallService.restartAudioForCallKit();
              _log('restartAudio(reconnect) done');
            } catch (e) { _log('restartAudio(reconnect) ERR: $e'); }
          }
          try {
            await _audioTrack?.restartTrack();
            _log('restartTrack(reconnect) done');
          } catch (e) { _log('restartTrack(reconnect) ERR: $e'); }
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          _log('ParticipantDisconnectedEvent');
          _onRemoteDisconnect();
        })
        ..on<RoomDisconnectedEvent>((_) {
          _log('RoomDisconnectedEvent');
          _onRemoteDisconnect();
        });

      final isCaller = widget.token.isNotEmpty;
      final activeRemote = _room.remoteParticipants.values.any(
        (p) => p.audioTrackPublications.isNotEmpty &&
               (!isCaller || p.joinedAt.isAfter(callInitiatedAt)),
      );
      _log('activeRemote=$activeRemote  remoteCount=${_room.remoteParticipants.length}');
      if (activeRemote && mounted) {
        _remoteEverConnected = true;
        _ringTimeout?.cancel();
        setState(() => _callState = _CallState.talking);
        _startDurationTimer();
        if (widget.callId.isNotEmpty) CallService.markCallConnected(widget.callId);
        if (Platform.isIOS) {
          _log('restartAudio(activeRemoteImmediate)');
          CallService.restartAudioForCallKit()
              .then((_) => _log('restartAudio(4) done'))
              .catchError((e) { _log('restartAudio(4) ERR: $e'); return null; });
        }
      } else {
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          if (_callState != _CallState.talking && !_disposed && mounted) {
            _log('ring timeout');
            setState(() => _callState = _CallState.noAnswer);
            Future.delayed(const Duration(seconds: 2), () => _hangup());
          }
        });
      }
    } catch (e) {
      _log('CONNECT ERROR: $e');
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
        body: Stack(
          children: [
            SafeArea(child: _buildMain()),
            if (_kDebug) _buildDebugPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildMain() {
    return Column(
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
                    isCaller: widget.token.isNotEmpty,
                  ),
                  if (widget.orderNote.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, color: Colors.white54, size: 15),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.orderNote,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    );
  }

  Widget _buildDebugPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => setState(() => _showDebug = !_showDebug),
        child: Container(
          color: Colors.black87,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showDebug = !_showDebug),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          'DEBUG [tap] state=$_callState local=${_audioTrack != null ? "ok" : "null"} remote=${_remoteAudioSubscribed ? "sub" : "NO"} muted=$_muted',
                          style: const TextStyle(color: Colors.yellow, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () async {
                      _log('MANUAL fix: restartAudio + restartTrack');
                      try {
                        await CallService.restartAudioForCallKit();
                        _log('restartAudio done');
                      } catch (e) {
                        _log('restartAudio ERR: $e');
                      }
                      try {
                        await _audioTrack?.restartTrack();
                        _log('restartTrack done');
                      } catch (e) {
                        _log('restartTrack ERR: $e');
                      }
                    },
                    child: const Text('⟳ Audio', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                  ),
                ],
              ),
              if (_showDebug)
                Container(
                  height: 200,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _dbg.length,
                    itemBuilder: (_, i) => Text(
                      _dbg[_dbg.length - 1 - i],
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontFamily: 'monospace'),
                    ),
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
  final bool isCaller;
  const _StateBadge({required this.state, required this.elapsed, required this.isCaller});

  String get _label => switch (state) {
    _CallState.connecting => 'Đang kết nối',
    _CallState.talking    => _fmt(elapsed),
    _CallState.noAnswer   => isCaller ? 'Không có trả lời' : 'Đã ngắt cuộc gọi',
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
