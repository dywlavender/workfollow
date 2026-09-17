import 'package:flutter/material.dart';

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
  Rect? _lastAnchorRect;

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
    _lastAnchorRect = anchorRectResolver?.call() ?? _anchorRect(anchor);
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
    return true;
  }

  /// Requests a new geometry calculation on the next overlay build.
  void markNeedsBuild() => _entry?.markNeedsBuild();

  /// Removes the surface and releases its anchor/builder references.
  void close() {
    _entry?.remove();
    _entry = null;
    _anchor = null;
    _anchorRectResolver = null;
    _builder = null;
    _theme = null;
    _surfaceDecoration = null;
    _lastAnchorRect = null;
  }

  Widget _build(BuildContext context) {
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
      elevation: _surfaceDecoration == null ? 12 : 0,
      shadowColor: Colors.black.withValues(alpha: .18),
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
    final surface = _surfaceDecoration == null
        ? material
        : DecoratedBox(decoration: _surfaceDecoration!, child: material);

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
}

Rect? _anchorRect(BuildContext context) {
  if (!context.mounted) return null;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Returns the standard formatting-strip decoration used by the task editor.
BoxDecoration taskFormattingToolbarDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: .19),
            blurRadius: 13,
            spreadRadius: 1,
            offset: const Offset(0, 2)),
      ],
    );
