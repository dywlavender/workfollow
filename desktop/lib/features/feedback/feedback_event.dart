import 'package:flutter/material.dart';

import '../../theme/workfollow_motion.dart';

/// What a piece of feedback *means*, never how it should look.
///
/// The ordering is also the arbitration rule: when something is already on
/// screen, an incoming item replaces it only if it is at least as important.
/// See [WorkFollowFeedbackKind.priority].
///
/// The point of keeping this separate from the visual layer is that the action
/// layer should be able to say "this was a completion" without knowing whether
/// that becomes a dark HUD, a banner or a sound. A screen that had to match on
/// `undo.label == '撤销完成'` to find that out is exactly what this replaces.
enum WorkFollowFeedbackKind {
  /// A task (or a batch) was finished. The one kind that plays a sound.
  completion(60),

  /// A mutation succeeded and there is nothing to take back.
  success(40),

  /// A mutation succeeded and can be undone. Outranks [completion] so a
  /// destructive action's undo is never pushed off screen by a later
  /// completion.
  undoable(80),

  /// Neither success nor failure; context the user asked for.
  info(20),

  /// Something failed. Outranks everything.
  error(100);

  const WorkFollowFeedbackKind(this.priority);

  /// Higher wins. Two items of equal priority: the newer replaces the older.
  final int priority;

  bool get isFailure => this == WorkFollowFeedbackKind.error;
}

/// Which tone, if any, accompanies a piece of feedback.
///
/// Deliberately not a bool: focus rounds and completions must be
/// distinguishable by ear, and a third caller should not have to add another
/// bool to the model.
enum WorkFollowFeedbackSound {
  /// Silent.
  none,

  /// A task was ticked off.
  completion,

  /// A focus round ran out. A different figure from [completion] so the user
  /// can tell "I finished this" from "the timer finished" without looking.
  focus,
}

/// One transient result, ready to present.
///
/// Everything here is content or timing. Nothing describes a colour, a radius
/// or an offset — those belong to the host so that one change restyles every
/// result in the app.
@immutable
class WorkFollowFeedback {
  const WorkFollowFeedback({
    required this.kind,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.sound = WorkFollowFeedbackSound.none,
    this.duration,
    this.coalesceKey,
    this.coalescedMessage,
  });

  final WorkFollowFeedbackKind kind;
  final String message;

  /// Label for the single trailing action. [WorkFollowFeedback.kind] decides
  /// nothing about it; an undoable item supplies "撤销" here.
  final String? actionLabel;

  /// Drawn instead of [actionLabel] when set — the completion HUD shows the
  /// undo glyph rather than a word.
  final IconData? actionIcon;

  final VoidCallback? onAction;

  final WorkFollowFeedbackSound sound;

  /// How long to hold. Null falls back to [hold].
  final Duration? duration;

  /// Identifies a family of interchangeable results. Two items sharing a key
  /// collapse into one instead of stacking: `已完成 2 个任务` rather than two
  /// toasts. See [coalescedMessage].
  final String? coalesceKey;

  /// Builds the message for an aggregated item. Receives the new total.
  final String Function(int count)? coalescedMessage;

  /// How long the toast stays up.
  ///
  /// Longer when there is something to take back: an undo affordance that
  /// disappears while the user is still reaching for it is worse than no
  /// affordance.
  Duration get hold {
    if (duration != null) return duration!;
    if (onAction != null) return WorkFollowFeedbackTiming.undoHold;
    return switch (kind) {
      WorkFollowFeedbackKind.error => WorkFollowFeedbackTiming.errorHold,
      WorkFollowFeedbackKind.completion =>
        WorkFollowFeedbackTiming.completionHold,
      _ => WorkFollowFeedbackTiming.defaultHold,
    };
  }

  /// Same identity as [other] for aggregation purposes.
  bool coalescesWith(WorkFollowFeedback other) =>
      coalesceKey != null && coalesceKey == other.coalesceKey;

  WorkFollowFeedback copyWith({String? message, VoidCallback? onAction}) =>
      WorkFollowFeedback(
        kind: kind,
        message: message ?? this.message,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
        onAction: onAction ?? this.onAction,
        sound: sound,
        duration: duration,
        coalesceKey: coalesceKey,
        coalescedMessage: coalescedMessage,
      );

  @override
  String toString() => 'WorkFollowFeedback(${kind.name}, "$message")';
}
