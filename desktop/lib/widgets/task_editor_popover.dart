import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';
import 'task_menu_style.dart';

/// Proportions shared by the task document's four anchored controls.
class TaskEditorPopoverStyle {
  static const iconSize = 18.0;
  static const rowHeight = 34.0;
  static const listWidth = 196.0;
  static const dateWidth = 260.0;
  static const moreWidth = 164.0;
  static const toolbarWidth = 444.0;
  static const toolbarHeight = 38.0;

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final colors = TaskMenuStyle.colors(context);
    return base.copyWith(extensions: [
      ...base.extensions.values
          .where((extension) => extension is! WorkFollowTheme),
      colors,
    ]);
  }
}

Future<T?> showTaskEditorPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  required double width,
  double maxHeight = 560,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  PopoverFocusPolicy focusPolicy = PopoverFocusPolicy.firstItem,
  bool scrollable = false,
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
      anchorRect: anchorRect,
      popoverTheme: TaskEditorPopoverStyle.theme(anchor),
      surfaceDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
            width == TaskEditorPopoverStyle.toolbarWidth ? 8 : 12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .19),
              blurRadius: 13,
              spreadRadius: 1,
              offset: const Offset(0, 2))
        ],
      ),
    );
