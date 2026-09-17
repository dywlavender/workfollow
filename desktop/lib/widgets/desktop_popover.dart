import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// The edge of the anchor a popover prefers to use.
enum PopoverSide { top, bottom, left, right }

/// The cross-axis alignment used when a popover is attached to an anchor.
enum PopoverAlignment { start, center, end }

/// Describes how a popover should take focus when it opens.
enum PopoverFocusPolicy {
  /// Do not move focus. Useful for editor toolbars and caret-preserving UI.
  none,

  /// Focus the menu surface so arrow keys and Enter work immediately.
  firstItem,

  /// Let the first search field own focus.
  searchField,

  /// Preserve the editor's current selection and focus.
  preserveEditor,
}

/// Placement policy for an anchored surface.
class PopoverPlacement {
  const PopoverPlacement({
    required this.preferredSide,
    this.alignment = PopoverAlignment.start,
    this.gap = 6,
    this.allowFlip = true,
  });

  static const topStart = PopoverPlacement(
    preferredSide: PopoverSide.top,
    alignment: PopoverAlignment.start,
  );
  static const topCenter = PopoverPlacement(
    preferredSide: PopoverSide.top,
    alignment: PopoverAlignment.center,
  );
  static const topEnd = PopoverPlacement(
    preferredSide: PopoverSide.top,
    alignment: PopoverAlignment.end,
  );
  static const bottomStart = PopoverPlacement(
    preferredSide: PopoverSide.bottom,
    alignment: PopoverAlignment.start,
  );
  static const bottomCenter = PopoverPlacement(
    preferredSide: PopoverSide.bottom,
    alignment: PopoverAlignment.center,
  );
  static const bottomEnd = PopoverPlacement(
    preferredSide: PopoverSide.bottom,
    alignment: PopoverAlignment.end,
  );
  static const leftStart = PopoverPlacement(
    preferredSide: PopoverSide.left,
    alignment: PopoverAlignment.start,
  );
  static const leftCenter = PopoverPlacement(
    preferredSide: PopoverSide.left,
    alignment: PopoverAlignment.center,
  );
  static const leftEnd = PopoverPlacement(
    preferredSide: PopoverSide.left,
    alignment: PopoverAlignment.end,
  );
  static const rightStart = PopoverPlacement(
    preferredSide: PopoverSide.right,
    alignment: PopoverAlignment.start,
  );
  static const rightCenter = PopoverPlacement(
    preferredSide: PopoverSide.right,
    alignment: PopoverAlignment.center,
  );
  static const rightEnd = PopoverPlacement(
    preferredSide: PopoverSide.right,
    alignment: PopoverAlignment.end,
  );

  final PopoverSide preferredSide;
  final PopoverAlignment alignment;
  final double gap;
  final bool allowFlip;
}

/// The result of positioning a popover inside a viewport.
///
/// This is deliberately a pure value object so placement behaviour can be
/// tested without pumping a Flutter route.
class PopoverGeometry {
  const PopoverGeometry({
    required this.rect,
    required this.side,
    required this.flipped,
    required this.availableSpace,
  });

  final Rect rect;
  final PopoverSide side;
  final bool flipped;
  final double availableSpace;

  Offset get position => rect.topLeft;
  Size get size => rect.size;
  bool get isFlipped => flipped;
}

/// Computes an anchored popover rectangle.
///
/// [desiredSize] represents the largest useful surface, not a mandatory
/// height. The widget can therefore use the returned height as a max
/// constraint while its actual content remains intrinsic. When the preferred
/// side cannot fit, the opposite side is chosen if possible; otherwise the
/// side with more room wins and the surface becomes scrollable.
PopoverGeometry calculatePopoverGeometry({
  required Rect anchor,
  required Size viewport,
  required Size desiredSize,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  EdgeInsets safeArea = const EdgeInsets.all(12),
}) {
  final safeWidth = math.max(0.0, viewport.width - safeArea.horizontal);
  final safeHeight = math.max(0.0, viewport.height - safeArea.vertical);
  final width = _clampDouble(desiredSize.width, 0, safeWidth);
  final height = _clampDouble(desiredSize.height, 0, safeHeight);

  double room(PopoverSide side) => switch (side) {
        PopoverSide.top =>
          math.max(0.0, anchor.top - safeArea.top - placement.gap),
        PopoverSide.bottom => math.max(0.0,
            viewport.height - safeArea.bottom - anchor.bottom - placement.gap),
        PopoverSide.left =>
          math.max(0.0, anchor.left - safeArea.left - placement.gap),
        PopoverSide.right => math.max(0.0,
            viewport.width - safeArea.right - anchor.right - placement.gap),
      };

  final preferredRoom = room(placement.preferredSide);
  final opposite = _oppositeSide(placement.preferredSide);
  final oppositeRoom = room(opposite);
  final desiredAxis = _isVertical(placement.preferredSide) ? height : width;
  var side = placement.preferredSide;
  if (placement.allowFlip && preferredRoom < desiredAxis) {
    if (oppositeRoom >= desiredAxis || oppositeRoom > preferredRoom) {
      side = opposite;
    }
  }

  final sideRoom = room(side);
  // Keep the measured/intrinsic surface height and clamp its rectangle to the
  // safe viewport below. The route applies a max-height constraint, so a
  // surface that genuinely cannot fit can still scroll without losing its
  // action row.
  final axisCapacity = _isVertical(side) ? safeHeight : safeWidth;
  final panelWidth = width;
  final panelHeight = _isVertical(side)
      ? _clampDouble(height, 0, axisCapacity)
      : _clampDouble(height, 0, safeHeight);
  final crossSize = _isVertical(side) ? panelWidth : panelHeight;

  double align(double start, double end, double size) {
    final value = switch (placement.alignment) {
      PopoverAlignment.start => start,
      PopoverAlignment.center => (start + end - size) / 2,
      PopoverAlignment.end => end - size,
    };
    return _clampDouble(
        value,
        _isVertical(side) ? safeArea.left : safeArea.top,
        (_isVertical(side)
                ? safeArea.left + safeWidth
                : safeArea.top + safeHeight) -
            size);
  }

  final cross = _isVertical(side)
      ? align(anchor.left, anchor.right, crossSize)
      : align(anchor.top, anchor.bottom, crossSize);
  final top = switch (side) {
    PopoverSide.top => _clampDouble(anchor.top - placement.gap - panelHeight,
        safeArea.top, safeArea.top + safeHeight - panelHeight),
    PopoverSide.bottom => _clampDouble(anchor.bottom + placement.gap,
        safeArea.top, safeArea.top + safeHeight - panelHeight),
    PopoverSide.left || PopoverSide.right => cross,
  };
  final left = switch (side) {
    PopoverSide.left => _clampDouble(anchor.left - placement.gap - panelWidth,
        safeArea.left, safeArea.left + safeWidth - panelWidth),
    PopoverSide.right => _clampDouble(anchor.right + placement.gap,
        safeArea.left, safeArea.left + safeWidth - panelWidth),
    PopoverSide.top || PopoverSide.bottom => cross,
  };

  return PopoverGeometry(
    rect: Rect.fromLTWH(left, top, panelWidth, panelHeight),
    side: side,
    flipped: side != placement.preferredSide,
    availableSpace: sideRoom,
  );
}

PopoverSide _oppositeSide(PopoverSide side) => switch (side) {
      PopoverSide.top => PopoverSide.bottom,
      PopoverSide.bottom => PopoverSide.top,
      PopoverSide.left => PopoverSide.right,
      PopoverSide.right => PopoverSide.left,
    };

bool _isVertical(PopoverSide side) =>
    side == PopoverSide.top || side == PopoverSide.bottom;

double _clampDouble(double value, double min, double max) {
  if (max < min) return min;
  return value.clamp(min, max).toDouble();
}

Rect? _globalRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  final origin = box.localToGlobal(Offset.zero);
  return origin & box.size;
}

/// The public anchored popover entry point.
///
/// [anchorRect] is optional for normal widget triggers. Supplying it is useful
/// for pointer/caret anchored surfaces where there is no meaningful widget
/// rectangle.
Future<T?> showAnchoredPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 340,
  double maxHeight = 620,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  PopoverFocusPolicy focusPolicy = PopoverFocusPolicy.none,
  bool scrollable = false,
  bool restoreFocus = true,
  EdgeInsets safeArea = const EdgeInsets.all(12),
  Rect? anchorRect,
  ThemeData? popoverTheme,
  BoxDecoration? surfaceDecoration,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final theme = popoverTheme ?? Theme.of(anchor);
  final result = await showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: '关闭弹出面板',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (context, _, __) => _AnchoredPopoverPage(
      anchor: anchor,
      anchorRect: anchorRect,
      builder: builder,
      width: width,
      maxHeight: maxHeight,
      placement: placement,
      focusPolicy: focusPolicy,
      scrollable: scrollable,
      safeArea: safeArea,
      theme: theme,
      surfaceDecoration: surfaceDecoration,
    ),
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  if (restoreFocus && previousFocus != null && previousFocus.canRequestFocus) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previousFocus.canRequestFocus) previousFocus.requestFocus();
    });
  }
  return result;
}

/// Naming alias for callers that prefer a class-based API.
class AnchoredPopover {
  const AnchoredPopover._();

  static Future<T?> show<T>(
    BuildContext anchor, {
    required WidgetBuilder builder,
    double width = 340,
    double maxHeight = 620,
    PopoverPlacement placement = PopoverPlacement.bottomStart,
    PopoverFocusPolicy focusPolicy = PopoverFocusPolicy.none,
    bool scrollable = false,
    bool restoreFocus = true,
    EdgeInsets safeArea = const EdgeInsets.all(12),
    Rect? anchorRect,
  }) =>
      showAnchoredPopover<T>(
        anchor,
        builder: builder,
        width: width,
        maxHeight: maxHeight,
        placement: placement,
        focusPolicy: focusPolicy,
        scrollable: scrollable,
        restoreFocus: restoreFocus,
        safeArea: safeArea,
        anchorRect: anchorRect,
      );
}

/// Backwards-compatible name used by the existing desktop surfaces.
Future<T?> showDesktopPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 340,
  double maxHeight = 620,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  PopoverFocusPolicy focusPolicy = PopoverFocusPolicy.none,
  bool scrollable = false,
  bool restoreFocus = true,
  EdgeInsets safeArea = const EdgeInsets.all(12),
  Rect? anchorRect,
}) =>
    showAnchoredPopover<T>(
      anchor,
      builder: builder,
      width: width,
      maxHeight: maxHeight,
      placement: placement,
      focusPolicy: focusPolicy,
      scrollable: scrollable,
      restoreFocus: restoreFocus,
      safeArea: safeArea,
      anchorRect: anchorRect,
    );

class _AnchoredPopoverPage extends StatefulWidget {
  const _AnchoredPopoverPage({
    required this.anchor,
    required this.anchorRect,
    required this.builder,
    required this.width,
    required this.maxHeight,
    required this.placement,
    required this.focusPolicy,
    required this.scrollable,
    required this.safeArea,
    required this.theme,
    this.surfaceDecoration,
  });

  final BuildContext anchor;
  final Rect? anchorRect;
  final WidgetBuilder builder;
  final double width;
  final double maxHeight;
  final PopoverPlacement placement;
  final PopoverFocusPolicy focusPolicy;
  final bool scrollable;
  final EdgeInsets safeArea;
  final ThemeData theme;
  final BoxDecoration? surfaceDecoration;

  @override
  State<_AnchoredPopoverPage> createState() => _AnchoredPopoverPageState();
}

class _AnchoredPopoverPageState extends State<_AnchoredPopoverPage>
    with WidgetsBindingObserver {
  Rect? _rect;
  double? _contentHeight;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScrollPosition();
      _refreshRect();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollPosition();
  }

  void _attachScrollPosition() {
    final next = Scrollable.maybeOf(widget.anchor)?.position;
    if (identical(next, _scrollPosition)) return;
    _scrollPosition?.removeListener(_refreshRect);
    _scrollPosition = next;
    _scrollPosition?.addListener(_refreshRect);
  }

  Rect? _currentRect() => widget.anchorRect ?? _globalRect(widget.anchor);

  void _refreshRect() {
    if (!mounted || widget.anchorRect != null) return;
    final next = _currentRect();
    if (_rect == next) return;
    setState(() => _rect = next);
  }

  void _onContentSizeChanged(Size size) {
    if (!mounted || size.height <= 0) return;
    final next = math.min(widget.maxHeight, size.height);
    if (_contentHeight != null && (_contentHeight! - next).abs() < .5) return;
    setState(() => _contentHeight = next);
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRect());
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_refreshRect);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final anchorRect =
        _rect ?? _currentRect() ?? const Rect.fromLTWH(80, 80, 30, 30);
    final geometry = calculatePopoverGeometry(
      anchor: anchorRect,
      viewport: screen,
      desiredSize: Size(widget.width, _contentHeight ?? widget.maxHeight),
      placement: widget.placement,
      safeArea: widget.safeArea,
    );
    final content = _MeasurePopoverContent(
      onSizeChanged: _onContentSizeChanged,
      child: widget.builder(context),
    );
    final constrained = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: geometry.rect.height),
      child:
          widget.scrollable ? SingleChildScrollView(child: content) : content,
    );
    final focusAware = switch (widget.focusPolicy) {
      PopoverFocusPolicy.none ||
      PopoverFocusPolicy.preserveEditor =>
        constrained,
      PopoverFocusPolicy.firstItem ||
      PopoverFocusPolicy.searchField =>
        FocusScope(autofocus: true, canRequestFocus: true, child: constrained),
    };
    final tokens = widget.theme.extension<WorkFollowTheme>() ??
        WorkFollowTheme.of(context);
    final material = Material(
      elevation: widget.surfaceDecoration == null ? 12 : 0,
      shadowColor: Colors.black.withValues(alpha: .18),
      color: tokens.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: widget.surfaceDecoration?.borderRadius ??
            BorderRadius.circular(WorkFollowRadii.popover),
        side: widget.surfaceDecoration == null
            ? BorderSide(color: tokens.border)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: focusAware,
    );
    final surface = widget.surfaceDecoration == null
        ? material
        : DecoratedBox(decoration: widget.surfaceDecoration!, child: material);
    final positioned = switch (geometry.side) {
      PopoverSide.top => Positioned(
          left: geometry.rect.left,
          // Material's 1px surface border is included in the child bounds;
          // lift top-anchored surfaces by that pixel so the last menu row
          // never overlaps its trigger after rounding.
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
      data: widget.theme,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Navigator.of(context).pop();
                return null;
              },
            ),
          },
          child: Stack(children: [positioned]),
        ),
      ),
    );
  }
}

/// Reports intrinsic content height after layout so a short menu can hug its
/// trigger while a tall picker can switch to a clipped, scrollable viewport.
class _MeasurePopoverContent extends SingleChildRenderObjectWidget {
  const _MeasurePopoverContent({required this.onSizeChanged, super.child});

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasurePopoverContentRenderObject(onSizeChanged);

  @override
  void updateRenderObject(BuildContext context,
      covariant _MeasurePopoverContentRenderObject renderObject) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _MeasurePopoverContentRenderObject extends RenderProxyBox {
  _MeasurePopoverContentRenderObject(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _lastSize) return;
    final measuredSize = size;
    _lastSize = measuredSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSizeChanged(measuredSize);
    });
  }
}

class DesktopMenuEntry<T> {
  const DesktopMenuEntry(this.value, this.label,
      {this.icon, this.destructive = false});
  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;
}

Future<T?> showDesktopMenu<T>(
  BuildContext anchor, {
  required List<DesktopMenuEntry<T>> entries,
  T? selected,
  double width = 245,
  double maxHeight = 380,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  Rect? anchorRect,
}) =>
    showDesktopPopover<T>(
      anchor,
      width: width,
      maxHeight: maxHeight,
      placement: placement,
      focusPolicy: PopoverFocusPolicy.firstItem,
      scrollable: true,
      anchorRect: anchorRect,
      builder: (context) => _DesktopMenuSurface<T>(
        entries: entries,
        selected: selected,
      ),
    );

class _DesktopMenuSurface<T> extends StatefulWidget {
  const _DesktopMenuSurface({required this.entries, this.selected});

  final List<DesktopMenuEntry<T>> entries;
  final T? selected;

  @override
  State<_DesktopMenuSurface<T>> createState() => _DesktopMenuSurfaceState<T>();
}

class _DesktopMenuSurfaceState<T> extends State<_DesktopMenuSurface<T>> {
  late final FocusNode focus;
  late int focusedIndex;

  @override
  void initState() {
    super.initState();
    focus = FocusNode(debugLabel: 'desktop-menu');
    final selectedIndex =
        widget.entries.indexWhere((entry) => entry.value == widget.selected);
    focusedIndex = selectedIndex >= 0 ? selectedIndex : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.entries.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => focusedIndex =
          (focusedIndex + 1).clamp(0, widget.entries.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => focusedIndex =
          (focusedIndex - 1).clamp(0, widget.entries.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => focusedIndex = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => focusedIndex = widget.entries.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      Navigator.of(context).pop(widget.entries[focusedIndex].value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Focus(
      focusNode: focus,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.entries.length; index++)
              _entry(context, widget.entries[index], index, tokens),
          ],
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, DesktopMenuEntry<T> entry, int index,
      WorkFollowTheme tokens) {
    final focused = index == focusedIndex;
    final foreground = entry.destructive
        ? tokens.danger
        : focused
            ? tokens.textPrimary
            : tokens.textSecondary;
    return MouseRegion(
      onEnter: (_) {
        if (focusedIndex != index) setState(() => focusedIndex = index);
      },
      child: ListTile(
        key: ValueKey('menu-option-${entry.value}'),
        dense: true,
        minTileHeight: WorkFollowMetrics.menuRowHeight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        tileColor: focused ? tokens.menuSelected : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: entry.icon == null
            ? null
            : AppIcon(entry.icon!,
                size: WorkFollowMetrics.toolbarIcon, color: foreground),
        title: Text(entry.label,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.control,
                color: entry.destructive ? tokens.danger : tokens.textPrimary)),
        trailing: widget.selected == entry.value
            ? AppIcon(WorkFollowIcons.check,
                size: WorkFollowMetrics.toolbarIcon, color: tokens.accent)
            : null,
        onTap: () => Navigator.of(context).pop(entry.value),
      ),
    );
  }
}

class PropertyButton extends StatelessWidget {
  const PropertyButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.active = false,
      this.color,
      this.tooltip});
  final IconData icon;
  final String label;
  final void Function(BuildContext anchor) onPressed;
  final bool active;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final foreground = color ?? (active ? tokens.accent : tokens.textSecondary);
    return Builder(
        builder: (anchor) => Tooltip(
              message: tooltip ?? label,
              child: TextButton.icon(
                onPressed: () => onPressed(anchor),
                icon: AppIcon(icon,
                    size: WorkFollowMetrics.compactFieldIcon,
                    color: foreground),
                label:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  backgroundColor: active ? tokens.accentFaint : tokens.canvas,
                  textStyle: TextStyle(
                      fontSize: WorkFollowMacTypography.control,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.medium,
                      letterSpacing: WorkFollowMacTracking.none),
                  minimumSize: const Size(0, WorkFollowMetrics.chipHeight),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(WorkFollowRadii.control)),
                ),
              ),
            ));
  }
}
