import 'dart:async';

import 'package:flutter/foundation.dart';

import 'feedback_event.dart';
import 'feedback_sound_service.dart';

/// The single owner of transient result feedback.
///
/// One of these lives in the shell. Screens, rows, the inspector and the menu
/// bar all hand it a [WorkFollowFeedback] and forget about it; none of them
/// draw a toast, own a timer, or decide whether something is worth showing.
///
/// What lives here vs. in the host:
/// - here: which item is current, how long it stays, arbitration between
///   competing items, aggregation, and whether a tone plays;
/// - in `feedback_host.dart`: everything visual, including the animation.
class FeedbackController extends ChangeNotifier {
  FeedbackController({
    FeedbackSoundService? soundService,
    this.animatedFeedback = true,
    this.completionSoundEnabled = true,
  }) : _sound = soundService ?? FeedbackSoundService();

  final FeedbackSoundService _sound;

  /// Drives the spring entrance. Off (the 动态反馈 setting, or a reduce-motion
  /// preference) keeps the toast but uses the shared short fade instead.
  bool animatedFeedback;

  /// The 完成任务时播放提示音 setting.
  bool completionSoundEnabled;

  WorkFollowFeedback? _current;
  WorkFollowFeedback? get current => _current;

  Timer? _holdTimer;

  /// Bumped on every presentation. A hold timer that belongs to an older
  /// presentation must not dismiss a newer one.
  int _generation = 0;

  /// How many items the current toast stands for.
  int _coalescedCount = 0;

  /// The last `WorkspaceController.actionVersion` an entry point already
  /// reported through [show].
  ///
  /// Transitional. The shell still watches `actionVersion` to catch actions
  /// that no entry point reports (notes moving to the trash, menu-bar
  /// commands); without this marker those paths would double up with the toast
  /// the entry point just showed.
  int _presentedActionVersion = -1;

  bool wasActionPresented(int actionVersion) =>
      actionVersion == _presentedActionVersion;

  /// Presents [feedback], or folds it into what is already showing.
  void show(WorkFollowFeedback feedback, {int? actionVersion}) {
    if (actionVersion != null) _presentedActionVersion = actionVersion;

    final showing = _current;
    if (showing != null) {
      // Same family: aggregate rather than stack. `已完成 2 个任务` is one fact;
      // two identical toasts sliding over each other is noise.
      if (showing.coalescesWith(feedback)) {
        _coalescedCount += 1;
        final build = feedback.coalescedMessage;
        _current = feedback.copyWith(
            message: build == null ? feedback.message : build(_coalescedCount));
        _restartHold();
        _playSoundIfDue(feedback);
        notifyListeners();
        return;
      }
      // Something more important is on screen. Passing over feedback is better
      // than replacing an undo the user is still reaching for, or a failure.
      if (showing.kind.priority > feedback.kind.priority) return;
    }

    _coalescedCount = 1;
    _current = feedback;
    _playSoundIfDue(feedback);
    _restartHold();
    notifyListeners();
  }

  /// Hides the current item. Safe to call when nothing is showing.
  void dismiss() {
    _generation += 1;
    _holdTimer?.cancel();
    _holdTimer = null;
    _coalescedCount = 0;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Runs the current item's action and clears it.
  ///
  /// The toast always leaves once its action fires: leaving it up would invite
  /// a second tap on an action that has already been taken.
  void invokeAction() {
    final action = _current?.onAction;
    dismiss();
    action?.call();
  }

  void _restartHold() {
    _holdTimer?.cancel();
    final hold = _current?.hold ?? const Duration(seconds: 3);
    final generation = ++_generation;
    _holdTimer = Timer(hold, () {
      if (generation != _generation) return;
      dismiss();
    });
  }

  void _playSoundIfDue(WorkFollowFeedback feedback) {
    if (!completionSoundEnabled) return;
    if (feedback.sound == WorkFollowFeedbackSound.none) return;
    unawaited(_sound.play(feedback.sound));
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }
}
