import 'package:flutter/material.dart';

import '../../theme/workfollow_interaction_states.dart';
import '../../theme/workfollow_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/task_menu_style.dart';
import 'domain/document_selection_action.dart';

/// A small action strip anchored to the current document selection.
///
/// The editor keeps the selection and focus policy; this widget only renders
/// the profile-provided actions. It deliberately has no footer or document
/// state of its own, so it disappears as soon as the selection collapses.
class DocumentSelectionToolbar extends StatelessWidget {
  const DocumentSelectionToolbar({
    super.key,
    required this.actions,
    required this.onInvoke,
  });

  final List<DocumentSelectionAction> actions;
  final ValueChanged<DocumentSelectionAction> onInvoke;

  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    return SizedBox(
      key: const ValueKey('document-selection-toolbar'),
      height: TaskEditorMetrics.selectionToolbarHeight,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.inlineGap),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              KeyedSubtree(
                key: ValueKey('document-selection-action-${action.id}'),
                child: _SelectionActionButton(
                  action: action,
                  colors: colors,
                  onPressed: () => onInvoke(action),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.action,
    required this.colors,
    required this.onPressed,
  });

  final DocumentSelectionAction action;
  final WorkFollowTheme colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: action.label,
        child: InkWell(
          key: action.id == 'create-task'
              ? const ValueKey('generate-task-from-selection')
              : ValueKey('document-selection-action-button-${action.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(WorkFollowRadii.xs),
          focusColor: WorkFollowInteractionStyles.focusColor(colors),
          overlayColor: WorkFollowInteractionStyles.overlay(colors, menu: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.inlineGap),
            child: SizedBox(
              height: TaskEditorMetrics.selectionToolbarHeight -
                  WorkFollowSpacing.space2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(action.icon,
                      size: WorkFollowMetrics.compactFieldIcon,
                      color: colors.accent),
                  const SizedBox(width: WorkFollowSpacing.controlGap),
                  Text(action.label,
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.menu,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: colors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      );
}
