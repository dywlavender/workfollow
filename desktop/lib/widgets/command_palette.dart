import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';

Future<void> showCommandPalette({
  required BuildContext context,
  required WorkspaceController controller,
  required VoidCallback onToggleTheme,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: '搜索与命令',
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(.28),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _CommandPalette(controller: controller, onToggleTheme: onToggleTheme),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 8 * animation.value, sigmaY: 8 * animation.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(curved),
              child: child),
        ),
      );
    },
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette(
      {required this.controller, required this.onToggleTheme});

  final WorkspaceController controller;
  final VoidCallback onToggleTheme;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final TextEditingController queryController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    queryController.addListener(() {
      if (mounted) setState(() => selectedIndex = 0);
    });
  }

  @override
  void dispose() {
    queryController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  List<_Command> get commands => [
        _Command('打开今天', '查看现在最重要的事', Icons.wb_sunny_outlined,
            () => widget.controller.selectView(WorkspaceView.today)),
        _Command('打开收集箱', '稍后再安排', Icons.inbox_outlined,
            () => widget.controller.selectView(WorkspaceView.inbox)),
        _Command('打开计划', '安排未来几天', Icons.upcoming_outlined,
            () => widget.controller.selectView(WorkspaceView.plan)),
        _Command('打开日历', '按日期查看任务', Icons.calendar_month_outlined,
            () => widget.controller.selectView(WorkspaceView.calendar)),
        _Command('打开看板', '按优先级或日期推进任务', Icons.view_kanban_outlined,
            () => widget.controller.selectView(WorkspaceView.board)),
        _Command('打开习惯', '记录连续完成与 28 天轨迹', Icons.track_changes_outlined,
            () => widget.controller.selectView(WorkspaceView.habits)),
        _Command('打开笔记', '继续写下刚才的想法', Icons.note_alt_outlined,
            () => widget.controller.selectView(WorkspaceView.notes)),
        _Command('打开废纸篓', '恢复或彻底删除已移除的内容', Icons.delete_outline_rounded,
            () => widget.controller.selectView(WorkspaceView.trash)),
        _Command('切换外观', '在浅色和深色之间切换', Icons.brightness_6_outlined,
            widget.onToggleTheme),
      ];

  List<_Command> get filteredCommands {
    final query = queryController.text.trim().toLowerCase();
    if (query.isEmpty) return commands;

    final results = <_Command>[
      // Typing a query always offers to capture it as a task in the current
      // context; the palette never invents an "未命名任务" to chase afterwards.
      _Command(
        '新建任务「${queryController.text.trim()}」',
        '保存到${widget.controller.creationTargetLabel}',
        Icons.add_task_rounded,
        () => widget.controller.addTask(queryController.text.trim()),
      ),
    ];
    final taskResults = widget.controller.activeTasks
        .where((task) =>
            '${task.title} ${task.listName} ${task.description ?? task.note ?? ''} ${task.tags.join(' ')}'
                .toLowerCase()
                .contains(query))
        .take(7)
        .map(
          (task) => _Command(
            task.title,
            '${task.listName} · ${task.displayTimeLabel ?? '未安排'}',
            task.completed
                ? Icons.check_circle_outline_rounded
                : Icons.check_circle_outline,
            () => widget.controller.openTask(task.id),
          ),
        );
    final noteResults = widget.controller.activeNotes
        .where((note) =>
            '${note.title}${note.preview}${note.plainText ?? ''}${note.folder}'
                .toLowerCase()
                .contains(query))
        .take(5)
        .map(
          (note) => _Command(
            note.title,
            '笔记 · ${note.folder}',
            Icons.note_alt_outlined,
            () => widget.controller.openNote(note.id),
          ),
        );
    final commandResults = commands.where((command) =>
        '${command.title}${command.subtitle}'.toLowerCase().contains(query));
    return [...results, ...taskResults, ...noteResults, ...commandResults];
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final list = filteredCommands;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && list.isNotEmpty) {
      setState(() => selectedIndex = (selectedIndex + 1) % list.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && list.isNotEmpty) {
      setState(() =>
          selectedIndex = (selectedIndex - 1 + list.length) % list.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && list.isNotEmpty) {
      _run(list[selectedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _run(_Command command) {
    command.action();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final list = filteredCommands;
    final safeIndex =
        list.isEmpty ? 0 : selectedIndex.clamp(0, list.length - 1).toInt();
    return Center(
      // The dialog route has no Scaffold above it; a Material ancestor is
      // required for the TextField to build at all.
      child: Material(
        type: MaterialType.transparency,
        child: Focus(
          autofocus: true,
          focusNode: focusNode,
          onKeyEvent: _handleKey,
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 500),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: tokens.overlay,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.borderStrong.withOpacity(.72)),
              boxShadow: [
                BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 46,
                    offset: const Offset(0, 22))
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 16, 15, 13),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 20, color: tokens.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('command-palette-query'),
                          controller: queryController,
                          autofocus: true,
                          onSubmitted: (_) {
                            if (list.isNotEmpty) _run(list[safeIndex]);
                          },
                          cursorColor: tokens.accent,
                          style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                              hintText: '搜索任务、笔记或命令…',
                              hintStyle: TextStyle(
                                  color: tokens.textTertiary, fontSize: 15),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero),
                        ),
                      ),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                              color: tokens.accentFaint,
                              borderRadius: BorderRadius.circular(5)),
                          child: Text('esc',
                              style: TextStyle(
                                  color: tokens.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.border),
                if (list.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('没有找到相关内容',
                          style: TextStyle(
                              color: tokens.textTertiary, fontSize: 13)))
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final command = list[index];
                        final selected = index == safeIndex;
                        return GestureDetector(
                          onTap: () => _run(command),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 10),
                            decoration: BoxDecoration(
                                color: selected
                                    ? tokens.accentSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9)),
                            child: Row(
                              children: [
                                Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                        color: selected
                                            ? tokens.overlay
                                            : tokens.accentFaint,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Icon(command.icon,
                                        size: 16,
                                        color: selected
                                            ? tokens.accent
                                            : tokens.textSecondary)),
                                const SizedBox(width: 11),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(command.title,
                                          style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(command.subtitle,
                                          style: TextStyle(
                                              color: tokens.textTertiary,
                                              fontSize: 11))
                                    ])),
                                if (selected)
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 15, color: tokens.accent),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(17, 10, 17, 11),
                  decoration: BoxDecoration(
                      color: tokens.accentFaint.withOpacity(.55),
                      border: Border(top: BorderSide(color: tokens.border))),
                  child: Row(children: [
                    Icon(Icons.keyboard_return_rounded,
                        size: 14, color: tokens.textTertiary),
                    const SizedBox(width: 5),
                    Text('选择',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 10)),
                    const SizedBox(width: 16),
                    Icon(Icons.keyboard_arrow_up_rounded,
                        size: 14, color: tokens.textTertiary),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 14, color: tokens.textTertiary),
                    const SizedBox(width: 5),
                    Text('移动',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 10)),
                    const Spacer(),
                    Text('打勾命令面板',
                        style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600))
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Command {
  const _Command(this.title, this.subtitle, this.icon, this.action);

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback action;
}
