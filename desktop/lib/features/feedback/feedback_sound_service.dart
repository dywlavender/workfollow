import 'dart:async';

import 'package:flutter/services.dart';

import 'feedback_event.dart';

/// Plays the app's own result tones through the macOS runner.
///
/// Not `SystemSound.play(SystemSoundType.alert)`: the system alert is the sound
/// macOS uses for failures, and borrowing it for "you finished something" reads
/// as a warning. The runner plays a short system tone instead (see
/// `MainFlutterWindow.swift`), so nothing has to ship as an audio asset.
class FeedbackSoundService {
  FeedbackSoundService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('workfollow/feedback');

  final MethodChannel _channel;

  /// Continuous completions are the noisy case: ticking off a list of tasks
  /// used to mean one chime per row. Everything inside this window folds into
  /// the first chime.
  static const Duration throttle = Duration(seconds: 1);

  DateTime? _lastPlayed;

  /// Plays the tone for [sound] unless one played within [throttle].
  ///
  /// Returns whether it actually played, so a test can assert the suppression
  /// without listening to audio.
  Future<bool> play(WorkFollowFeedbackSound sound) async {
    if (sound == WorkFollowFeedbackSound.none) return false;
    final now = DateTime.now();
    final last = _lastPlayed;
    if (last != null && now.difference(last) < throttle) return false;
    _lastPlayed = now;
    try {
      await _channel.invokeMethod<void>('playFeedbackSound', sound.name);
    } on MissingPluginException {
      // Tests and any host without the runner: silence is the correct
      // degradation, and it must not surface as an error.
    } on PlatformException {
      // A failed playback is not worth a user-visible message.
    }
    return true;
  }

  /// Clears the throttle window. Used when the user turns the sound off and on
  /// again, and by tests that need a deterministic first play.
  void resetThrottle() => _lastPlayed = null;
}
