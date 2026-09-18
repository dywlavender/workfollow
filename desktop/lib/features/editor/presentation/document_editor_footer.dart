import 'package:flutter/material.dart';

import '../../../theme/workfollow_theme.dart';

/// Shared footer layout for task and note document editors.
///
/// The footer only arranges slots. Document-specific controls such as the task
/// list button or the note word count belong to [leading] and document actions
/// belong to [actions].
class DocumentEditorFooter extends StatelessWidget {
  const DocumentEditorFooter({
    super.key,
    this.leading,
    this.status,
    this.actions = const [],
    this.showTopBorder = false,
    this.minHeight,
    this.padding,
  });

  final Widget? leading;
  final Widget? status;
  final List<Widget> actions;
  final bool showTopBorder;
  final double? minHeight;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: padding ??
          const EdgeInsets.fromLTRB(
              WorkFollowSpacing.space5,
              WorkFollowSpacing.space1,
              WorkFollowSpacing.space5,
              WorkFollowSpacing.space3),
      decoration: showTopBorder
          ? BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            )
          : null,
      child: Row(
        children: [
          if (leading != null) leading!,
          const Spacer(),
          if (status != null) status!,
          for (final action in actions) ...[
            const SizedBox(width: WorkFollowSpacing.space2),
            action,
          ],
        ],
      ),
    );
  }
}
