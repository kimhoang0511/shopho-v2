import 'package:flutter/foundation.dart';

/// Global debug logger for iOS call accept flow.
/// Events are stored in memory and displayed as an overlay on the Home screen.
/// Set enabled = false before shipping to production.
class CallDebugLogger {
  static bool enabled = true;
  static const int maxEvents = 50;

  static final List<_DebugEvent> _events = [];

  static List<_DebugEvent> get events => List.unmodifiable(_events);

  static void log(String source, String message, {Map<String, dynamic>? data}) {
    if (!enabled) return;
    final event = _DebugEvent(
      timestamp: DateTime.now(),
      source: source,
      message: message,
      data: data,
    );
    _events.add(event);
    if (_events.length > maxEvents) _events.removeRange(0, _events.length - maxEvents);
    debugPrint('[CallDebug][$source] $message ${data ?? ''}');
  }

  static void clear() => _events.clear();
}

class _DebugEvent {
  final DateTime timestamp;
  final String source;
  final String message;
  final Map<String, dynamic>? data;

  _DebugEvent({
    required this.timestamp,
    required this.source,
    required this.message,
    this.data,
  });

  String get time {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = (timestamp.millisecond ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() => '[$time][$source] $message ${data != null ? data : ''}';
}