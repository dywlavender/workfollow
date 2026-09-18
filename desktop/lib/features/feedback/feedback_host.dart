import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/workfollow_motion.dart';
import 'feedback_controller.dart';
import 'feedback_event.dart';
import 'feedback_toast.dart';

/// The only place a result HUD is drawn.
///
/// Mounted once by the shell inside its root `Stack`, above every page, so a
/// screen never positions a toast and never has to know the window's bottom
/// inset. It renders whatever [FeedbackController] currently holds and owns the
/// motion.
class WorkFollowFeedbackHost extends StatefulWidget {
  const WorkFollowFeedbackHost(
      {super.key, required this.controller, this.animate = true});

  final FeedbackController controller;

  /// Overrides [FeedbackController.animatedFeedback]. Tests pin this so timing
  /// can be asserted without racing the setting.
  final bool animate;

  @override
  State<WorkFollowFeedbackHost> createState() => _WorkFollowFeedbackHostState();
}

class _WorkFollowFeedbackHostState extends State<WorkFollowFeedbackHost>
    with TickerProviderStateMixin {
  /// What is on screen. Kept separately from `controller.current` so the exit
  /// animation can finish after the controller has already cleared the item.
  WorkFollowFeedback? _rendered;

  late final AnimationController _enter;
  late final AnimationController _exit;
  late final AnimationController _fadeIn;
  late final AnimationController _fadeOut;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
        vsync: this, duration: WorkFollowMotionTokens.feedbackToastEnter);
    _exit = AnimationController(
        vsync: this, duration: WorkFollowMotionTokens.feedbackToastExit);
    _fadeIn = AnimationController(
        vsync: this, duration: WorkFollowMotionTokens.instant);
    _fadeOut = AnimationController(
        vsync: this, duration: WorkFollowMotionTokens.instant);
    widget.controller.addListener(_onFeedbackChanged);
    _onFeedbackChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = WorkFollowMotionPolicy.reducedMotion(context);
    if (next == _reducedMotion) return;
    _reducedMotion = next;
    // A host can be mounted after its controller already has a current item.
    // If the platform preference is reduced motion, switch that first frame
    // to the short fade path instead of leaving the spring controller running
    // behind an invisible fade controller.
    if (_rendered != null) {
      _startEnter();
    }
  }

  @override
  void didUpdateWidget(covariant WorkFollowFeedbackHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onFeedbackChanged);
      widget.controller.addListener(_onFeedbackChanged);
      _onFeedbackChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFeedbackChanged);
    _enter.dispose();
    _exit.dispose();
    _fadeIn.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  bool get _animated =>
      widget.animate && widget.controller.animatedFeedback && !_reducedMotion;

  void _onFeedbackChanged() {
    if (!mounted) return;
    final next = widget.controller.current;
    if (next != null) {
      // A replacement or an aggregated update swaps the content in place. Only
      // an empty stage replays the entrance; replaying it for `已完成 3 个任务`
      // would make the HUD look like it restarted on every tick.
      final wasEmpty = _rendered == null;
      setState(() => _rendered = next);
      if (wasEmpty) {
        _startEnter();
      } else {
        _exit.reset();
      }
      return;
    }
    if (_rendered == null) return;
    _startExit();
  }

  void _startEnter() {
    _exit.reset();
    if (_animated) {
      _fadeIn.reset();
      _enter.forward(from: 0);
    } else {
      _fadeOut.reset();
      _fadeIn.forward(from: 0);
    }
  }

  void _startExit() {
    final done = () {
      if (mounted) setState(() => _rendered = null);
    };
    if (_animated) {
      _fadeOut.reset();
      _exit.forward(from: 0).whenComplete(done);
    } else {
      _enter.reset();
      _fadeOut.forward(from: 0).whenComplete(done);
    }
  }

  /// The spring entrance: rise past the resting point, settle back.
  ///
  /// A [TweenSequence] rather than a `SpringSimulation` because the three
  /// positions are the design (overshoot 5pt, then rest), and a physical spring
  /// would let the overshoot drift whenever someone tunes a constant.
  static final Animatable<double> _rise = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween<double>(begin: 44, end: -5)
            .chain(CurveTween(curve: WorkFollowMotionTokens.entrance)),
        weight: 72),
    TweenSequenceItem(
        tween: Tween<double>(begin: -5, end: 0)
            .chain(CurveTween(curve: WorkFollowMotionTokens.settle)),
        weight: 28),
  ]);
  static final Animatable<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween<double>(begin: .96, end: 1.01)
            .chain(CurveTween(curve: WorkFollowMotionTokens.entrance)),
        weight: 72),
    TweenSequenceItem(
        tween: Tween<double>(begin: 1.01, end: 1)
            .chain(CurveTween(curve: WorkFollowMotionTokens.settle)),
        weight: 28),
  ]);

  @override
  Widget build(BuildContext context) {
    final rendered = _rendered;
    if (rendered == null) return const SizedBox.shrink();
    final bottom = math.max(FeedbackMetrics.bottomMargin,
        MediaQuery.paddingOf(context).bottom + 20);

    return Positioned(
        left: 0,
        right: 0,
        bottom: bottom,
        child: Center(
            child: AnimatedBuilder(
                animation: Listenable.merge([_enter, _exit, _fadeIn, _fadeOut]),
                builder: (context, child) {
                  final t = _animated ? _enter.value : _fadeIn.value;
                  final offset = _animated ? _rise.transform(t) : 0.0;
                  final scale = _animated ? _scale.transform(t) : 1.0;
                  final opacity = _animated
                      ? WorkFollowMotionTokens.entrance
                          .transform(math.min(1, t / .45))
                      : _fadeIn.value;
                  if (_animated && _exit.isAnimating) {
                    final out =
                        WorkFollowMotionTokens.exit.transform(_exit.value);
                    return _transform(offset + 28 * out, scale - .02 * out,
                        (1 - out) * opacity, child!);
                  }
                  if (!_animated && _fadeOut.isAnimating) {
                    return _transform(
                        0, 1, (1 - _fadeOut.value) * opacity, child!);
                  }
                  return _transform(offset, scale, opacity, child!);
                },
                child: Material(
                    type: MaterialType.transparency,
                    child: FeedbackToast(
                        feedback: rendered,
                        onAction: widget.controller.invokeAction)))));
  }

  Widget _transform(double dy, double scale, double opacity, Widget child) =>
      Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
              scale: scale, child: Opacity(opacity: opacity, child: child)));
}
