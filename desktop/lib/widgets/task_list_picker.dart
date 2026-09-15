import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';

/// Searchable list chooser used by the task footer and quick add. It keeps the
/// familiar compact menu for four lists while remaining usable when a local
/// workspace grows beyond the visible viewport.
class TaskListPicker {
  const TaskListPicker._();

  static Future<String?> show(BuildContext anchor,
      {required WorkspaceController controller, String? selected}) {
    return showDesktopPopover<String>(
      anchor,
      width: 300,
      maxHeight: 440,
      placement: PopoverPlacement.topStart,
      focusPolicy: PopoverFocusPolicy.searchField,
      scrollable: true,
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
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
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
    final tokens = WorkFollowTheme.of(context);
    final query = search.text.trim().toLowerCase();
    final lists = widget.controller.orderedLists
        .where(
            (item) => query.isEmpty || item.name.toLowerCase().contains(query))
        .toList(growable: false);
    return Focus(
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('task-list-search'),
              controller: search,
              focusNode: focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                final names = _visibleLists();
                if (names.isNotEmpty) {
                  Navigator.of(context).pop(
                      names[focusedIndex.clamp(0, names.length - 1).toInt()]);
                }
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: search.clear,
                      ),
                hintText: '搜索清单',
                hintStyle: TextStyle(color: tokens.textTertiary, fontSize: 13),
                filled: true,
                fillColor: tokens.canvas,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              ),
            ),
            const SizedBox(height: 8),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text('没有匹配的清单',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textTertiary, fontSize: 12)),
              )
            else
              for (var index = 0; index < lists.length; index++)
                MouseRegion(
                  onEnter: (_) {
                    if (focusedIndex != index) {
                      setState(() => focusedIndex = index);
                    }
                  },
                  child: ListTile(
                    key: ValueKey('menu-option-${lists[index].name}'),
                    dense: true,
                    minTileHeight: 38,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                    tileColor:
                        focusedIndex == index ? tokens.accentFaint : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      lists[index].name == '收集箱'
                          ? Icons.inbox_outlined
                          : Icons.list_rounded,
                      size: 17,
                      color: tokens.textSecondary,
                    ),
                    title: Text(lists[index].name,
                        style:
                            TextStyle(fontSize: 13, color: tokens.textPrimary)),
                    trailing: widget.selected == lists[index].name
                        ? Icon(Icons.check_rounded,
                            size: 16, color: tokens.accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(lists[index].name),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
