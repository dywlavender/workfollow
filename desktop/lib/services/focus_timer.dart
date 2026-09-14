import 'dart:async';

import 'package:flutter/foundation.dart';

/// A small foreground timer for the personal desktop app. The countdown is
/// kept in memory; only the optional task's completed-session count is saved.
/// A scheduled local notification makes the timer useful even when the window
/// is hidden behind another app.
class FocusTimerController extends ChangeNotifier {
  FocusTimerController({
    required Future<void> Function(String sessionId, DateTime at)
        scheduleNotification,
    required Future<void> Function(String sessionId) cancelNotification,
    void Function(String? taskId)? onCompleted,
  })  : _scheduleNotification = scheduleNotification,
        _cancelNotification = cancelNotification,
        _onCompleted = onCompleted;

  final Future<void> Function(String sessionId, DateTime at)
      _scheduleNotification;
  final Future<void> Function(String sessionId) _cancelNotification;
  final void Function(String? taskId)? _onCompleted;

  Timer? _ticker;
  Duration _remaining = const Duration(minutes: 25);
  int _durationMinutes = 25;
  bool _running = false;
  String? _taskId;
  String? _sessionId;
  DateTime? _endsAt;
  bool _disposed = false;

  Duration get remaining => _remaining;
  int get durationMinutes => _durationMinutes;
  bool get isRunning => _running;
  bool get hasStarted => _sessionId != null;
  String? get taskId => _taskId;
  String get display =>
      '${_remaining.inMinutes.toString().padLeft(2, '0')}:${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}';

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void setDuration(int minutes) {
    if (_running) return;
    if (![15, 25, 45].contains(minutes)) return;
    _durationMinutes = minutes;
    _remaining = Duration(minutes: minutes);
    _sessionId = null;
    _notify();
  }

  void setTask(String? taskId) {
    if (_running) return;
    _taskId = taskId;
    _notify();
  }

  void start() {
    if (_running) return;
    if (_remaining <= Duration.zero) {
      _remaining = Duration(minutes: _durationMinutes);
    }
    final sessionId =
        _sessionId ??= DateTime.now().microsecondsSinceEpoch.toString();
    _running = true;
    _endsAt = DateTime.now().add(_remaining);
    unawaited(_scheduleNotification(sessionId, _endsAt!));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _notify();
  }

  void pause() {
    if (!_running) return;
    _tick(notify: false);
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    final id = _sessionId;
    if (id != null) unawaited(_cancelNotification(id));
    _endsAt = null;
    _notify();
  }

  void reset() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    final id = _sessionId;
    if (id != null) unawaited(_cancelNotification(id));
    _sessionId = null;
    _endsAt = null;
    _remaining = Duration(minutes: _durationMinutes);
    _notify();
  }

  void _tick({bool notify = true}) {
    if (!_running || _endsAt == null) return;
    final next = _endsAt!.difference(DateTime.now());
    if (next > Duration.zero) {
      _remaining = next;
      if (notify) _notify();
      return;
    }
    _remaining = Duration.zero;
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    final taskId = _taskId;
    _sessionId = null;
    _onCompleted?.call(taskId);
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    final id = _sessionId;
    if (id != null) unawaited(_cancelNotification(id));
    super.dispose();
  }
}
