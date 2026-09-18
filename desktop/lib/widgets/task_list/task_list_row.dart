import 'package:flutter/material.dart';

import '../../theme/workfollow_theme.dart';

/// The three-column body of one task row:
///
/// ```text
/// ┌──────────────────────────────────────────┐
/// │ Checkbox │ Main content      │ Metadata   │
/// │          │ Description       │            │
/// └──────────────────────────────────────────┘
/// ```
///
/// The row used to run four things through one line — a list-colour bar, the
/// checkbox, a mixed title/metadata `Wrap` and the more button — so the title
/// competed with the metadata for the same pixels and every row carried a
/// coloured stripe. The bar is gone; list identity belongs to the list picker
/// and the navigation dot, not to every task. The frame owns the geometry and
/// the neutral state fill only; behaviour stays in `TaskRow`.
class TaskListRowFrame extends StatelessWidget {
  const TaskListRowFrame({
    super.key,
    this.surfaceKey,
    this.leading,
    required this.checkbox,
    required this.content,
    this.metadata,
    this.trailing,
    this.selected = false,
    this.hovering = false,
    this.focused = false,
    this.compact = false,
  });

  /// Key of the fill surface. Tests read the colour from it.
  final Key? surfaceKey;

  /// Optional gutter widget before the checkbox (the tree fold chevron).
  final Widget? leading;
  final Widget checkbox;
  final Widget content;
  final Widget? metadata;
  final Widget? trailing;
  final bool selected;
  final bool hovering;
  final bool focused;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      key: surfaceKey,
      constraints:
          const BoxConstraints(minHeight: TaskListMetrics.rowMinHeight),
      padding: EdgeInsets.symmetric(
          horizontal: TaskListMetrics.rowHorizontalPadding,
          vertical: compact
              ? TaskListMetrics.rowVerticalPadding - WorkFollowSpacing.microGap
              : TaskListMetrics.rowVerticalPadding),
      decoration: BoxDecoration(
          color: TaskListColors.rowFill(tokens,
              selected: selected, hovering: hovering),
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: focused
              ? Border.all(color: TaskListColors.rowFocusRing(tokens))
              : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 2)],
          checkbox,
          const SizedBox(width: TaskListMetrics.checkboxTitleGap),
          Expanded(child: content),
          if (metadata != null) ...[
            const SizedBox(width: WorkFollowSpacing.space2),
            // Let the title take the remaining width. Metadata stays a
            // non-flex child so it remains pinned to the right, but the
            // column has a contract of its own: a task with several flags
            // must not squeeze the title down to a couple of characters.
            ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: TaskListMetrics.metadataMaxWidth),
                child: metadata!),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
