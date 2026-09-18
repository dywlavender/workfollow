import 'package:flutter/widgets.dart';

import 'workfollow_theme.dart';

/// Motion roles used by the desktop shell.
///
/// A role describes the intent of a transition.  Widgets should ask for a
/// role instead of choosing a duration or curve at the call site.  This keeps
/// the timing contract reviewable and lets the whole shell honour reduced
/// motion consistently.
enum WorkFollowMotionRole {
  hoverTransition,
  selectionTransition,
  controlPress,
  popoverEnter,
  popoverExit,
  panelTransition,
  collapseExpand,
  taskComplete,
  feedbackToastEnter,
  feedbackToastExit,
  dragReorder,
}

/// Named timing primitives and role mappings for the macOS desktop shell.
///
/// The primitive values remain backed by [WorkFollowMotion] so the existing
/// design-token contract has one source of truth.  A small number of roles
/// intentionally have their own value when the interaction needs a distinct
/// rhythm (for example the 200ms completion spring envelope).
class WorkFollowMotionTokens {
  const WorkFollowMotionTokens._();

  static const Duration instant = WorkFollowMotion.instant;
  static const Duration fast = WorkFollowMotion.fast;
  static const Duration normal = WorkFollowMotion.normal;
  static const Curve standard = WorkFollowMotion.standard;

  static const Duration hoverTransition = instant;
  static const Duration selectionTransition = fast;
  static const Duration controlPress = instant;
  static const Duration popoverEnter = fast;
  static const Duration popoverExit = fast;
  static const Duration panelTransition = normal;
  static const Duration collapseExpand = normal;
  static const Duration taskComplete = Duration(milliseconds: 200);
  static const Duration feedbackToastEnter = taskComplete;
  static const Duration feedbackToastExit = taskComplete;
  static const Duration dragReorder = fast;

  /// Curves are named by motion intent, so callers do not need to know the
  /// Material curve catalogue.
  static const Curve entrance = Curves.easeOutCubic;
  static const Curve settle = Curves.easeInOut;
  static const Curve exit = Curves.easeInCubic;
  static const Curve reduced = Curves.linear;

  /// Shared completion/feedback spring specification.  The feedback HUD
  /// uses a bounded design envelope (rise, overshoot, settle), while this
  /// description is available to any future physics-driven transition.
  static const SpringDescription feedbackSpring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 32,
  );

  static Duration durationFor(WorkFollowMotionRole role) => switch (role) {
        WorkFollowMotionRole.hoverTransition => hoverTransition,
        WorkFollowMotionRole.selectionTransition => selectionTransition,
        WorkFollowMotionRole.controlPress => controlPress,
        WorkFollowMotionRole.popoverEnter => popoverEnter,
        WorkFollowMotionRole.popoverExit => popoverExit,
        WorkFollowMotionRole.panelTransition => panelTransition,
        WorkFollowMotionRole.collapseExpand => collapseExpand,
        WorkFollowMotionRole.taskComplete => taskComplete,
        WorkFollowMotionRole.feedbackToastEnter => feedbackToastEnter,
        WorkFollowMotionRole.feedbackToastExit => feedbackToastExit,
        WorkFollowMotionRole.dragReorder => dragReorder,
      };

  static Curve curveFor(WorkFollowMotionRole role) => switch (role) {
        WorkFollowMotionRole.hoverTransition ||
        WorkFollowMotionRole.selectionTransition ||
        WorkFollowMotionRole.controlPress ||
        WorkFollowMotionRole.popoverEnter ||
        WorkFollowMotionRole.panelTransition ||
        WorkFollowMotionRole.collapseExpand ||
        WorkFollowMotionRole.dragReorder =>
          standard,
        WorkFollowMotionRole.popoverExit ||
        WorkFollowMotionRole.feedbackToastExit =>
          exit,
        WorkFollowMotionRole.taskComplete ||
        WorkFollowMotionRole.feedbackToastEnter =>
          entrance,
      };
}

/// Hold durations for transient result feedback.
///
/// These are not animation durations. They describe how long a result remains
/// available before the feedback host dismisses it, so callers do not scatter
/// unexplained timeout literals through the event model.
class WorkFollowFeedbackTiming {
  const WorkFollowFeedbackTiming._();

  static const Duration undoHold = Duration(milliseconds: 4000);
  static const Duration errorHold = Duration(milliseconds: 5000);
  static const Duration completionHold = Duration(milliseconds: 2600);
  static const Duration defaultHold = completionHold;
}

/// Resolves a role against the current accessibility preference.
///
/// Reduced motion keeps a short, linear fade/slide so state changes remain
/// visible without running a spring or a long panel transition.
class WorkFollowMotionPolicy {
  const WorkFollowMotionPolicy._();

  static bool reducedMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(
    BuildContext context,
    WorkFollowMotionRole role,
  ) =>
      reducedMotion(context)
          ? WorkFollowMotionTokens.instant
          : WorkFollowMotionTokens.durationFor(role);

  static Curve curve(
    BuildContext context,
    WorkFollowMotionRole role,
  ) =>
      reducedMotion(context)
          ? WorkFollowMotionTokens.reduced
          : WorkFollowMotionTokens.curveFor(role);

  static SpringDescription? spring(
    BuildContext context,
    WorkFollowMotionRole role,
  ) =>
      reducedMotion(context) ||
              (role != WorkFollowMotionRole.taskComplete &&
                  role != WorkFollowMotionRole.feedbackToastEnter)
          ? null
          : WorkFollowMotionTokens.feedbackSpring;
}
