import 'package:flutter/material.dart';

import 'feedback_controller.dart';
import 'feedback_event.dart';

/// Makes the shell's [FeedbackController] reachable from anywhere in the tree.
///
/// An inherited notifier rather than constructor plumbing: the completion
/// affordance appears in rows, the inspector, the board, the home screen and
/// the menu bar, and threading a controller through every one of them would
/// mean a new parameter on each intermediate widget that has nothing to do with
/// feedback.
///
/// Look it up with [maybeOf], not [of]. Widgets are routinely mounted on their
/// own in tests and in previews, and a row without a host must simply not show
/// feedback rather than throw.
class FeedbackScope extends InheritedNotifier<FeedbackController> {
  const FeedbackScope(
      {super.key, required FeedbackController controller, required super.child})
      : super(notifier: controller);

  static FeedbackController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FeedbackScope>()
      ?.notifier;

  static FeedbackController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No FeedbackScope above this widget.');
    return controller!;
  }
}

/// Presents [feedback] through the scope above [context], if there is one.
///
/// The one-liner form for callers that hold nothing but a context and are not
/// reporting a task command — a dialog's validate-and-complain path, a status
/// readout, a preview.
void showFeedback(BuildContext context, WorkFollowFeedback feedback) =>
    FeedbackScope.maybeOf(context)?.show(feedback);
