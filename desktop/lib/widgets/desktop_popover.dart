import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/workfollow_theme.dart';

/// One anchored surface for desktop property editors. Escape and outside
/// clicks cancel; only the editor's explicit action commits a draft.
Future<T?> showDesktopPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 340,
  double maxHeight = 620,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final position = box?.localToGlobal(Offset.zero) ?? const Offset(80, 80);
  final anchorHeight = box?.size.height ?? 30;
  final theme = Theme.of(anchor);
  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: '关闭弹出面板',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (context, _, __) {
      final screen = MediaQuery.sizeOf(context);
      final panelWidth = math.min(width, screen.width - 24);
      final anchorBottom = position.dy + anchorHeight;
      final spaceBelow = math.max(0.0, screen.height - anchorBottom - 22);
      final spaceAbove = math.max(0.0, position.dy - 22);
      // Prefer the side with the most room. A bottom toolbar therefore opens
      // upward instead of being clamped to a fictitious max-height box far
      // above its trigger.
      final openBelow = spaceBelow >= 180 || spaceBelow >= spaceAbove;
      // When opening below, keep the full viewport allowance and clamp the
      // top edge. This lets a tall date picker start at the window edge rather
      // than laying out its action row below the visible viewport. For an
      // upward menu, limit the viewport to the actual room above the trigger.
      final panelHeight = openBelow
          ? math.min(maxHeight, screen.height - 32)
          : math.min(maxHeight,
              math.max(80.0, math.min(spaceAbove, screen.height - 32)));
      final left =
          position.dx.clamp(12.0, math.max(12, screen.width - panelWidth - 12));
      final top = (anchorBottom + 6)
          .clamp(16.0, math.max(16.0, screen.height - panelHeight - 16));
      final bottom = math.max(16.0, screen.height - position.dy + 6);
      return Theme(
        data: theme,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Stack(children: [
            Positioned(
              left: left.toDouble(),
              top: openBelow ? top.toDouble() : null,
              bottom: openBelow ? null : bottom.toDouble(),
              width: panelWidth,
              child: Focus(
                autofocus: true,
                child: Material(
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: .18),
                  color: WorkFollowTheme.of(context).content,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: WorkFollowTheme.of(context).border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: panelHeight),
                    child: SingleChildScrollView(child: builder(context)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    },
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
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
}) =>
    showDesktopPopover<T>(anchor, width: 245, maxHeight: 380,
        builder: (context) {
      final tokens = WorkFollowTheme.of(context);
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final entry in entries)
            ListTile(
              key: ValueKey('menu-option-${entry.value}'),
              dense: true,
              minTileHeight: 38,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: entry.icon == null
                  ? null
                  : Icon(entry.icon,
                      size: 17,
                      color: entry.destructive
                          ? tokens.danger
                          : tokens.textSecondary),
              title: Text(entry.label,
                  style: TextStyle(
                      fontSize: 13,
                      color: entry.destructive
                          ? tokens.danger
                          : tokens.textPrimary)),
              trailing: selected == entry.value
                  ? Icon(Icons.check, size: 16, color: tokens.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(entry.value),
            ),
        ]),
      );
    });

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
                icon: Icon(icon, size: 15),
                label:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  backgroundColor: active ? tokens.accentFaint : tokens.canvas,
                  textStyle: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                  minimumSize: const Size(0, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
              ),
            ));
  }
}
