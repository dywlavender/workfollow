import 'package:flutter/material.dart';

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

  void _changed() => setState(() {});

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
    return Padding(
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
            for (final list in lists)
              ListTile(
                key: ValueKey('menu-option-${list.name}'),
                dense: true,
                minTileHeight: 38,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  list.name == '收集箱'
                      ? Icons.inbox_outlined
                      : Icons.list_rounded,
                  size: 17,
                  color: tokens.textSecondary,
                ),
                title: Text(list.name,
                    style: TextStyle(fontSize: 13, color: tokens.textPrimary)),
                trailing: widget.selected == list.name
                    ? Icon(Icons.check_rounded, size: 16, color: tokens.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(list.name),
              ),
        ],
      ),
    );
  }
}
