import 'task_menu_glyph.dart';
import 'task_menu_style.dart';
import 'package:flutter/material.dart';

import 'desktop_popover.dart';
import 'app_icon_button.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_interaction_states.dart';
import '../theme/workfollow_theme_parity.dart';
import '../theme/workfollow_theme.dart';

class TaskTagPicker {
  const TaskTagPicker._();

  static Future<String?> show(BuildContext anchor,
      {String initial = '',
      Iterable<String> availableTags = const [],
      PopoverPlacement placement = PopoverPlacement.bottomStart}) {
    return showDesktopPopover<String>(anchor,
        width: TaskPickerMetrics.tagPickerWidth,
        maxHeight: TaskPickerMetrics.tagPickerMaxHeight,
        placement: placement,
        focusPolicy: PopoverFocusPolicy.searchField,
        builder: (_) =>
            TaskTagPickerBody(initial: initial, availableTags: availableTags));
  }
}

class TaskTagPickerBody extends StatefulWidget {
  const TaskTagPickerBody(
      {super.key, required this.initial, this.availableTags = const []});
  final String initial;
  final Iterable<String> availableTags;

  @override
  State<TaskTagPickerBody> createState() => _TaskTagPickerBodyState();
}

class _TaskTagPickerBodyState extends State<TaskTagPickerBody> {
  final search = TextEditingController();
  late final selected = widget.initial
      .split(RegExp('[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  late final available = {...widget.availableTags, ...selected};

  void createTag() {
    final tags = search.text
        .split(RegExp('[,，]'))
        .map((tag) => tag.trim().replaceFirst(RegExp(r'^#'), ''))
        .where((tag) => tag.isNotEmpty);
    setState(() {
      available.addAll(tags);
      selected.addAll(tags);
      search.clear();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = TaskMenuStyle.colors(context);
    final query = search.text.trim();
    final matches = available
        .where((tag) => tag.toLowerCase().contains(query.toLowerCase()))
        .toList()
      ..sort();
    final canCreate = query.isNotEmpty && !available.contains(query);
    return Column(
      key: const ValueKey('task-tag-picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              WorkFollowSpacing.space4,
              WorkFollowSpacing.cardInset,
              WorkFollowSpacing.cardInset,
              WorkFollowSpacing.space2),
          child: TextField(
            key: const ValueKey('task-tag-search'),
            controller: search,
            autofocus: true,
            cursorColor: tokens.accent,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.body,
                color: tokens.textPrimary),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canCreate) createTag();
            },
            decoration: InputDecoration(
              prefixIcon: AppIcon(WorkFollowIcons.search,
                  color: tokens.textTertiary,
                  size: WorkFollowMetrics.fieldIcon),
              hintText: '输入标签',
              hintStyle: TextStyle(color: tokens.textTertiary),
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.space2),
              prefixIconConstraints: const BoxConstraints(
                  minWidth: TaskPickerMetrics.fieldPrefixMinWidth),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        Divider(
            height: WorkFollowMetrics.dividerThickness, color: tokens.border),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.space2,
                  vertical: WorkFollowSpacing.space2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (matches.isEmpty && !canCreate)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: WorkFollowSpacing.space6),
                    child: Column(children: [
                      TaskMenuGlyph('tags',
                          size: 60,
                          color: tokens.textTertiary.withValues(alpha: .4)),
                      const SizedBox(height: WorkFollowSpacing.space3),
                      Text('没有标签',
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.body,
                              color: tokens.textPrimary)),
                    ]),
                  ),
                for (final tag in matches)
                  CheckboxListTile(
                    key: ValueKey('task-tag-$tag'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: WorkFollowSpacing.space2),
                    controlAffinity: ListTileControlAffinity.trailing,
                    selected: selected.contains(tag),
                    selectedTileColor: tokens.menuSelected,
                    hoverColor: WorkFollowInteractionStyles.fill(
                      tokens,
                      hovered: true,
                      menu: true,
                    ),
                    secondary: AppIcon(WorkFollowIcons.tagLabel,
                        size: WorkFollowMetrics.toolbarIcon,
                        color: tokens.textSecondary),
                    title: Text(tag,
                        style: const TextStyle(
                            fontSize: WorkFollowMacTypography.menu)),
                    value: selected.contains(tag),
                    activeColor: tokens.accent,
                    overlayColor: WorkFollowInteractionStyles.overlay(
                      tokens,
                      menu: true,
                    ),
                    onChanged: (checked) => setState(() {
                      checked == true
                          ? selected.add(tag)
                          : selected.remove(tag);
                    }),
                  ),
                if (canCreate)
                  ListTile(
                    key: const ValueKey('task-tag-create'),
                    dense: true,
                    leading: AppIcon(WorkFollowIcons.add,
                        size: WorkFollowMetrics.toolbarIcon,
                        color: tokens.accent),
                    title: Text('创建「$query」',
                        style: TextStyle(
                            fontSize: WorkFollowMacTypography.menu,
                            color: tokens.accent)),
                    onTap: createTag,
                  ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(WorkFollowSpacing.space4),
          child: Row(children: [
            Expanded(
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        textStyle: TextStyle(
                            fontSize: WorkFollowMacTypography.control,
                            height: WorkFollowMacTypography.lineControl,
                            fontWeight: WorkFollowMacWeight.medium,
                            letterSpacing: WorkFollowMacTracking.none),
                        foregroundColor: tokens.textPrimary,
                        side: BorderSide(color: tokens.borderStrong),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                WorkFollowRadii.control))),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'))),
            const SizedBox(width: WorkFollowSpacing.space3),
            Expanded(
                child: FilledButton(
                    style: FilledButton.styleFrom(
                        textStyle: TextStyle(
                            fontSize: WorkFollowMacTypography.control,
                            height: WorkFollowMacTypography.lineControl,
                            fontWeight: WorkFollowMacWeight.medium,
                            letterSpacing: WorkFollowMacTracking.none),
                        backgroundColor: tokens.accent,
                        foregroundColor:
                            WorkFollowThemeContrast.foregroundOn(tokens.accent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                WorkFollowRadii.control))),
                    key: const ValueKey('task-tag-confirm'),
                    onPressed: () =>
                        Navigator.of(context).pop(selected.join('，')),
                    child: const Text('确定'))),
          ]),
        ),
      ],
    );
  }
}
