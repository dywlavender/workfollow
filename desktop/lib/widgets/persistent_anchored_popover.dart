import 'package:flutter/material.dart';

import '../theme/workfollow_motion.dart';
import '../theme/workfollow_surface_tokens.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';

/// A non-modal anchored surface that stays mounted until its owner closes it.
///
/// Unlike [showAnchoredPopover], this controller does not create a route or a
/// dismissible barrier. That makes it suitable for tools such as the task
/// editor's formatting strip: clicks in the document and repeated formatting
/// commands must not close the surface. The anchor is measured again whenever
/// [markNeedsBuild] is called, so an owner can keep it aligned after a resize
/// or a scrolling/layout change.
class PersistentAnchoredPopoverController {
  PersistentAnchoredPopoverController();

  OverlayEntry? _entry;
  BuildContext? _anchor;
  Rect? Function()? _anchorRectResolver;
  WidgetBuilder? _builder;
  ThemeData? _theme;
  BoxDecoration? _surfaceDecoration;
  double _width = 340;
  double _height = 620;
  PopoverPlacement _placement = PopoverPlacement.bottomStart;
  EdgeInsets _safeArea =
      const EdgeInsets.all(WorkFollowSpacing.popoverSafeArea);
  bool _dismissOnTapOutside = false;
  VoidCallback? _onDismiss;
  Rect? _lastAnchorRect;
  GlobalKey<_PersistentPopoverSurfaceState>? _surfaceKey;

  bool get isOpen => _entry != null;

  /// Inserts the surface into the root overlay. Returns false when the anchor
  /// is not currently attached to an overlay.
  bool open(
    BuildContext anchor, {
    required WidgetBuilder builder,
    double width = 340,
    double height = 620,
    PopoverPlacement placement = PopoverPlacement.bottomStart,
    EdgeInsets safeArea =
        const EdgeInsets.all(WorkFollowSpacing.popoverSafeArea),
    ThemeData? popoverTheme,
    BoxDecoration? surfaceDecoration,
    Rect? Function()? anchorRectResolver,
    DesktopOverlayPolicy? policy,
    bool dismissOnTapOutside = false,
    VoidCallback? onDismiss,
  }) {
    close();
    final overlay = Overlay.maybeOf(anchor, rootOverlay: true);
    if (overlay == null) return false;

    _anchor = anchor;
    _anchorRectResolver = anchorRectResolver;
    _builder = builder;
    _theme = popoverTheme ?? Theme.of(anchor);
    _surfaceDecoration = surfaceDecoration;
    _width = width;
    _height = height;
    _placement = placement;
    _safeArea = safeArea;
    _policy = policy;
    _dismissOnTapOutside = policy?.dismissOnTapOutside ?? dismissOnTapOutside;
    _onDismiss = onDismiss;
    _lastAnchorRect = anchorRectResolver?.call() ?? _anchorRect(anchor);
    final surfaceKey = GlobalKey<_PersistentPopoverSurfaceState>();
    _surfaceKey = surfaceKey;
    _entry = OverlayEntry(builder: (context) => _build(context, surfaceKey));
    overlay.insert(_entry!);
    return true;
  }

  /// Requests a new geometry calculation on the next overlay build.
  void markNeedsBuild() => _entry?.markNeedsBuild();

  /// Removes the surface and releases its anchor/builder references.
  void close() {
    final entry = _entry;
    if (entry == null) return;
    final surfaceKey = _surfaceKey;
    _entry = null;
    _surfaceKey = null;
    _anchor = null;
    _anchorRectResolver = null;
    _builder = null;
    _theme = null;
    _surfaceDecoration = null;
    _dismissOnTapOutside = false;
    _onDismiss = null;
    _lastAnchorRect = null;
    _policy = null;

    void removeEntry() {
      // An entry can be closed while a new surface is being opened. The old
      // exit callback must only remove its own entry.
      entry.remove();
    }

    final state = surfaceKey?.currentState;
    if (state == null) {
      removeEntry();
    } else {
      state.dismiss(removeEntry);
    }
  }

  Widget _build(BuildContext context,
      GlobalKey<_PersistentPopoverSurfaceState> surfaceKey) {
    final screen = MediaQuery.sizeOf(context);
    final anchor = _anchor;
    final anchorRect = anchor == null
        ? (_lastAnchorRect ??
            Rect.fromLTWH(screen.width / 2, screen.height - 1, 1, 1))
        : (_anchorRectResolver?.call() ??
            _anchorRect(anchor) ??
            _lastAnchorRect ??
            Rect.fromLTWH(screen.width / 2, screen.height - 1, 1, 1));
    _lastAnchorRect = anchorRect;

    final geometry = calculatePopoverGeometry(
      anchor: anchorRect,
      viewport: screen,
      desiredSize: Size(_width, _height),
      placement: _placement,
      safeArea: _safeArea,
    );
    final theme = _theme ?? Theme.of(context);
    final tokens =
        theme.extension<WorkFollowTheme>() ?? WorkFollowTheme.of(context);
    final content = SizedBox(
      width: geometry.rect.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: geometry.rect.height),
        child: _builder?.call(context) ?? const SizedBox.shrink(),
      ),
    );
    final material = Material(
      elevation: _surfaceDecoration == null
          ? WorkFollowShadows.level2Elevation
          : WorkFollowShadows.level0Elevation,
      shadowColor: tokens.shadow,
      color: tokens.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: _surfaceDecoration?.borderRadius ??
            BorderRadius.circular(WorkFollowRadii.popover),
        side: _surfaceDecoration == null
            ? BorderSide(color: tokens.border)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
    final decoratedSurface = _surfaceDecoration == null
        ? material
        : DecoratedBox(decoration: _surfaceDecoration!, child: material);
    final rawSurface = _dismissOnTapOutside
        ? TapRegion(
            onTapOutside: (_) {
              _onDismiss?.call();
              close();
            },
            child: decoratedSurface,
          )
        : decoratedSurface;
    final motionRole = _policy?.motionRole ??
        (_surfaceDecoration == null
            ? WorkFollowMotionRole.popoverEnter
            : WorkFollowMotionRole.controlPress);
    final surface = _PersistentPopoverSurface(
      key: surfaceKey,
      duration: WorkFollowMotionPolicy.duration(context, motionRole),
      curve: WorkFollowMotionPolicy.curve(context, motionRole),
      reverseCurve: WorkFollowMotionPolicy.curve(
          context, WorkFollowMotionRole.popoverExit),
      toolbar: motionRole == WorkFollowMotionRole.controlPress,
      child: rawSurface,
    );

    final positioned = switch (geometry.side) {
      PopoverSide.top => Positioned(
          left: geometry.rect.left,
          bottom: screen.height - geometry.rect.bottom + 1,
          width: geometry.rect.width,
          child: surface,
        ),
      PopoverSide.bottom => Positioned(
          left: geometry.rect.left,
          top: geometry.rect.top,
          width: geometry.rect.width,
          child: surface,
        ),
      PopoverSide.left => Positioned(
          right: screen.width - geometry.rect.right,
          top: geometry.rect.top,
          width: geometry.rect.width,
          child: surface,
        ),
      PopoverSide.right => Positioned(
          left: geometry.rect.left,
          top: geometry.rect.top,
          width: geometry.rect.width,
          child: surface,
        ),
    };

    return Theme(
      data: theme,
      child: Stack(clipBehavior: Clip.none, children: [positioned]),
    );
  }

  DesktopOverlayPolicy? _policy;
}

/// Animated surface used by persistent editor overlays.
///
/// The controller remains responsible for placement and lifecycle.  This
/// small stateful wrapper owns only the enter/exit transition, which lets a
/// toolbar fade out before its entry is removed without changing its settled
/// size or focus behaviour.
class _PersistentPopoverSurface extends StatefulWidget {
  const _PersistentPopoverSurface({
    super.key,
    required this.duration,
    required this.curve,
    required this.reverseCurve,
    required this.child,
    this.toolbar = false,
  });

  final Duration duration;
  final Curve curve;
  final Curve reverseCurve;
  final Widget child;
  final bool toolbar;

  @override
  State<_PersistentPopoverSurface> createState() =>
      _PersistentPopoverSurfaceState();
}

class _PersistentPopoverSurfaceState extends State<_PersistentPopoverSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _dismissRequested = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: widget.reverseCurve,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _PersistentPopoverSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.curve != widget.curve ||
        oldWidget.reverseCurve != widget.reverseCurve) {
      _animation
        ..curve = widget.curve
        ..reverseCurve = widget.reverseCurve;
    }
  }

  /// Runs the short exit transition, then removes the overlay entry.
  void dismiss(VoidCallback onDismissed) {
    if (_dismissRequested) return;
    _dismissRequested = true;
    _controller.reverse().whenCompleteOrCancel(() {
      if (mounted) onDismissed();
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beginOffset =
        widget.toolbar ? const Offset(0, .015) : const Offset(0, .02);
    final beginScale = widget.toolbar ? .99 : .98;
    return IgnorePointer(
      ignoring: _dismissRequested,
      child: FadeTransition(
        opacity: _animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
              .animate(_animation),
          child: ScaleTransition(
            scale: Tween<double>(begin: beginScale, end: 1).animate(_animation),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

Rect? _anchorRect(BuildContext context) {
  if (!context.mounted) return null;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Returns the standard formatting-strip decoration used by the task editor.
BoxDecoration taskFormattingToolbarDecoration(WorkFollowTheme tokens) =>
    WorkFollowSurfaceTokens.popover(
      tokens,
      radius: BorderRadius.circular(WorkFollowRadii.control),
    );
