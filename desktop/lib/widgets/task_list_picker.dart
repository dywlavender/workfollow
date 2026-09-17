import 'task_menu_style.dart';
import 'task_editor_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';

/// Searchable list chooser used by the task footer and quick add. It keeps the
/// familiar compact menu for four lists while remaining usable when a local
/// workspace grows beyond the visible viewport.
class TaskListPicker {
  const TaskListPicker._();

  static Future<String?> show(BuildContext anchor,
      {required WorkspaceController controller,
      String? selected,
      PopoverPlacement placement = PopoverPlacement.topStart}) {
    return showTaskEditorPopover<String>(
      anchor,
      width: TaskEditorPopoverStyle.listWidth,
      maxHeight: 440,
      placement: placement,
      focusPolicy: PopoverFocusPolicy.searchField,
      scrollable: false,
      builder: (_) => _TaskListPickerBody(
        controller: controller,
        selected: selected,
      ),
    );
  }
}

class _TaskListPickerBody extends StatefulWidget {
  const _TaskListPickerBody({required this.controller, this.selected});

  final WorkspaceController controller;
  final String? selected;

  @override
  State<_TaskListPickerBody> createState() => _TaskListPickerBodyState();
}

class _TaskListPickerBodyState extends State<_TaskListPickerBody> {
  late final TextEditingController search;
  late final FocusNode focus;
  int focusedIndex = 0;
  bool keyboardNavigation = false;

  @override
  void initState() {
    super.initState();
    search = TextEditingController();
    focus = FocusNode();
    search.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  void _changed() => setState(() => focusedIndex = 0);

  List<String> _visibleLists() {
    final query = search.text.trim().toLowerCase();
    return widget.controller.orderedLists
        .where(
            (item) => query.isEmpty || item.name.toLowerCase().contains(query))
        .map((item) => item.name)
        .toList(growable: false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final lists = _visibleLists();
    if (lists.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      keyboardNavigation = true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() =>
          focusedIndex = (focusedIndex + 1).clamp(0, lists.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() =>
          focusedIndex = (focusedIndex - 1).clamp(0, lists.length - 1).toInt());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => focusedIndex = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => focusedIndex = lists.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !focus.hasFocus) {
      Navigator.of(context).pop(lists[focusedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    search.removeListener(_changed);
    search.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = TaskMenuStyle.colors(context);
    final query = search.text.trim().toLowerCase();
    final lists = widget.controller.orderedLists
        .where(
            (item) => query.isEmpty || item.name.toLowerCase().contains(query))
        .toList(growable: false);
    return Focus(
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 204),
        child: Column(
          key: const ValueKey('task-list-picker'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                key: const ValueKey('task-list-search'),
                controller: search,
                focusNode: focus,
                autofocus: true,
                cursorColor: tokens.textPrimary,
                style: TextStyle(
                    fontSize: WorkFollowMacTypography.body,
                    height: WorkFollowMacTypography.lineTight,
                    fontWeight: WorkFollowMacWeight.regular,
                    letterSpacing: WorkFollowMacTracking.none),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  final names = _visibleLists();
                  if (names.isNotEmpty)
                    Navigator.of(context)
                        .pop(names[focusedIndex.clamp(0, names.length - 1)]);
                },
                decoration: InputDecoration(
                  prefixIcon: AppIcon(WorkFollowIcons.search,
                      size: WorkFollowMetrics.toolbarIcon,
                      color: tokens.textTertiary),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28),
                  hintText: '搜索',
                  hintStyle: TextStyle(color: tokens.textTertiary),
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Flexible(
                child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (lists.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text('没有匹配的清单',
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.body, color: tokens.textTertiary))),
                for (var index = 0; index < lists.length; index++)
                  Builder(builder: (context) {
                    final selected = widget.selected == lists[index].name;
                    final color = selected ? tokens.accent : tokens.textPrimary;
                    return Material(
                      color: keyboardNavigation && focusedIndex == index
                          ? tokens.accentFaint
                          : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('menu-option-${lists[index].name}'),
                        onTap: () =>
                            Navigator.of(context).pop(lists[index].name),
                        hoverColor: tokens.canvas,
                        child: SizedBox(
                            height: 34,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                AppIcon(
                                    lists[index].name == '收集箱'
                                        ? WorkFollowIcons.inbox
                                        : WorkFollowIcons.list,
                                    size: WorkFollowMetrics.toolbarIcon,
                                    color: color),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(lists[index].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: WorkFollowMacTypography.menu,
                                            height: WorkFollowMacTypography.lineControl,
                                            fontWeight: WorkFollowMacWeight.regular,
                                            letterSpacing: WorkFollowMacTracking.none,
                                            color: color))),
                                if (selected)
                                  AppIcon(WorkFollowIcons.check,
                                      size: WorkFollowMetrics.metadataIcon,
                                      color: tokens.accent),
                              ]),
                            )),
                      ),
                    );
                  }),
              ]),
            )),
          ],
        ),
      ),
    );
  }
}
