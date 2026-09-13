import 'package:flutter/material.dart';

import '../models/migration.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';

/// The persistent product-level navigation from the web app, adapted to a
/// native macOS rail. Personal builds intentionally omit team and notification
/// destinations, but keep the same visual hierarchy and active-state language.
/// The unified navigation rail. Task views, lists, note folders and system
/// destinations live in one column, so no second navigation pane is needed
/// and the space goes to content (see the productization plan, section 5.1).
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.controller,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenSettings,
  });

  static const double width = 212;

  final WorkspaceController controller;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        children: [
          const _RailBrand(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RailItem(
                    label: '首页',
                    icon: Icons.home_outlined,
                    selected: controller.view == WorkspaceView.home,
                    onTap: () => controller.selectView(WorkspaceView.home),
                  ),
                  _RailSectionHeader(label: '任务'),
                  _RailItem(
                    label: '今天',
                    icon: Icons.wb_sunny_outlined,
                    count: controller.countFor(WorkspaceView.today),
                    selected: controller.view == WorkspaceView.today &&
                        controller.selectedListName == null,
                    onTap: () => controller.selectView(WorkspaceView.today),
                  ),
                  _RailItem(
                    label: '计划',
                    icon: Icons.upcoming_outlined,
                    count: controller.countFor(WorkspaceView.plan),
                    selected: controller.view == WorkspaceView.plan,
                    onTap: () => controller.selectView(WorkspaceView.plan),
                  ),
                  _RailItem(
                    label: '收集箱',
                    icon: Icons.inbox_outlined,
                    count: controller.countFor(WorkspaceView.inbox),
                    selected: controller.view == WorkspaceView.inbox,
                    onTap: () => controller.selectView(WorkspaceView.inbox),
                  ),
                  _RailItem(
                    label: '所有任务',
                    icon: Icons.list_alt_outlined,
                    count: controller.countFor(WorkspaceView.all),
                    selected: controller.view == WorkspaceView.all &&
                        controller.selectedListName == null,
                    onTap: () => controller.selectView(WorkspaceView.all),
                  ),
                  _RailItem(
                    label: '已完成',
                    icon: Icons.check_circle_outline_rounded,
                    count: controller.countFor(WorkspaceView.completed),
                    selected: controller.view == WorkspaceView.completed,
                    onTap: () => controller.selectView(WorkspaceView.completed),
                  ),
                  _RailSectionHeader(
                    label: '清单',
                    trailing: AppIconButton(
                        icon: Icons.add,
                        tooltip: '新建清单',
                        size: 24,
                        iconSize: 15,
                        onPressed: () =>
                            _showAddListDialog(context, controller)),
                  ),
                  ...controller.lists
                      .where((list) => list.name != '收集箱')
                      .map((list) => _TaskListItem(
                            controller: controller,
                            list: list,
                          )),
                  _RailSectionHeader(
                    label: '笔记',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIconButton(
                          icon: Icons.add,
                          tooltip: '新建笔记',
                          size: 24,
                          iconSize: 15,
                          onPressed: () => controller.addNoteInCurrentFolder()),
                      AppIconButton(
                          icon: Icons.create_new_folder_outlined,
                          tooltip: '新建文件夹',
                          size: 24,
                          iconSize: 15,
                          onPressed: () =>
                              _showAddFolderDialog(context, controller)),
                    ]),
                  ),
                  _RailItem(
                    label: '全部笔记',
                    icon: Icons.notes_outlined,
                    count: controller.activeNotes.length,
                    selected: controller.view == WorkspaceView.notes &&
                        controller.notesFolderFilter == null &&
                        !controller.notesFavoritesOnly &&
                        !controller.notesUnfiledOnly,
                    onTap: () {
                      controller.clearNotesFilters();
                      controller.selectView(WorkspaceView.notes);
                    },
                  ),
                  _RailItem(
                    label: '收藏',
                    icon: Icons.star_border_rounded,
                    count: controller.activeNotes
                        .where((note) => note.isFavorite)
                        .length,
                    selected: controller.view == WorkspaceView.notes &&
                        controller.notesFavoritesOnly,
                    onTap: () {
                      controller.setNotesFavoritesOnly(true);
                      controller.selectView(WorkspaceView.notes);
                    },
                  ),
                  _RailItem(
                    label: '未归档',
                    icon: Icons.inbox_outlined,
                    count: controller.activeNotes
                        .where((note) => note.folderId == null)
                        .length,
                    selected: controller.view == WorkspaceView.notes &&
                        controller.notesUnfiledOnly,
                    onTap: () {
                      controller.setNotesUnfiledOnly(true);
                      controller.selectView(WorkspaceView.notes);
                    },
                  ),
                  ...controller.folders.map((folder) => Builder(
                      builder: (anchor) => _RailItem(
                            label: folder.name,
                            icon: Icons.folder_outlined,
                            count: controller.activeNotes
                                .where((note) =>
                                    note.folderId == folder.id ||
                                    note.folder == folder.name)
                                .length,
                            selected: controller.view == WorkspaceView.notes &&
                                controller.notesFolderFilter == folder.id,
                            onTap: () {
                              controller.setNotesFolderFilter(folder.id);
                              controller.selectView(WorkspaceView.notes);
                            },
                            onMenu: () =>
                                _editFolder(anchor, controller, folder),
                          ))),
                  _RailSectionHeader(label: '位置'),
                  _RailItem(
                    label: '日历',
                    icon: Icons.calendar_month_outlined,
                    selected: controller.view == WorkspaceView.calendar,
                    onTap: () => controller.selectView(WorkspaceView.calendar),
                  ),
                  _RailItem(
                    label: '废纸篓',
                    icon: Icons.delete_outline_rounded,
                    count: controller.countFor(WorkspaceView.trash),
                    selected: controller.view == WorkspaceView.trash,
                    onTap: () => controller.selectView(WorkspaceView.trash),
                  ),
                ],
              ),
            ),
          ),
          _RailFooter(
            isDark: isDark,
            onToggleTheme: onToggleTheme,
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

Future<void> _showAddListDialog(
    BuildContext context, WorkspaceController controller) async {
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('新建清单'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: '例如：旅行准备'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(nameController.text),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  nameController.dispose();
  if (!context.mounted || name == null) return;
  if (!controller.addList(name)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('清单名称为空，或已经存在。')),
    );
  }
}

Future<void> _showAddFolderDialog(
    BuildContext context, WorkspaceController controller) async {
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: '例如：旅行灵感'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(nameController.text),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  nameController.dispose();
  if (!context.mounted || name == null) return;
  final folder = controller.addFolder(name);
  if (folder == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件夹名称为空，或已经存在。')),
    );
    return;
  }
  controller.setNotesFolderFilter(folder.id);
  controller.selectView(WorkspaceView.notes);
}

class _RailSectionHeader extends StatelessWidget {
  const _RailSectionHeader({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand();
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
        child: Row(children: [
          Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: tokens.accent, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.check_rounded,
                  size: 21, color: Theme.of(context).colorScheme.onPrimary)),
          const SizedBox(width: 10),
          Text('打勾',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary)),
        ]));
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    this.onMenu,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final VoidCallback? onMenu;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTap: widget.onMenu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? tokens.accentSoft
                  : (hovering
                      ? tokens.content.withOpacity(.65)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected
                          ? tokens.accent
                          : tokens.textSecondary,
                      fontSize: 12.5,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (hovering && widget.onMenu != null)
                  SizedBox(
                      width: 22,
                      height: 20,
                      child: IconButton(
                          tooltip: '文件夹操作',
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: widget.onMenu,
                          icon: const Icon(Icons.more_horiz)))
                else if (widget.count != null && widget.count! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? tokens.content
                          : tokens.content.withOpacity(.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${widget.count}',
                        style: TextStyle(
                            color: widget.selected
                                ? tokens.accent
                                : tokens.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenSettings,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          _RailFooterAction(
            icon: Icons.tune_outlined,
            label: '设置',
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 7, 8),
            decoration: BoxDecoration(
              color: tokens.content.withOpacity(.62),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border.withOpacity(.8)),
            ),
            child: Row(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accentFaint,
                  ),
                  child: Icon(Icons.computer_outlined,
                      size: 15, color: tokens.accent),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '个人空间',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '本地数据',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon: isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  tooltip: isDark ? '切换浅色' : '切换深色',
                  onPressed: onToggleTheme,
                  size: 26,
                  iconSize: 15,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailFooterAction extends StatefulWidget {
  const _RailFooterAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_RailFooterAction> createState() => _RailFooterActionState();
}

class _RailFooterActionState extends State<_RailFooterAction> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                hovering ? tokens.content.withOpacity(.65) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 17, color: tokens.textSecondary),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskListItem extends StatefulWidget {
  const _TaskListItem({required this.controller, required this.list});

  final WorkspaceController controller;
  final MigrationListRecord list;

  @override
  State<_TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<_TaskListItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.isListSelected(widget.list.name);
    final count = widget.controller.countForList(widget.list.name);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      // Dropping a dragged task row here moves it into this list.
      child: DragTarget<String>(
        onWillAccept: (data) => data != null,
        onAccept: (taskId) =>
            widget.controller.moveTaskToList(taskId, widget.list.name),
        builder: (context, candidateData, rejectedData) {
          final dragActive = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () => widget.controller.selectList(widget.list.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
              decoration: BoxDecoration(
                color: dragActive
                    ? tokens.accentSoft
                    : (selected
                        ? tokens.accentSoft
                        : (hovering
                            ? tokens.content.withOpacity(.7)
                            : Colors.transparent)),
                borderRadius: BorderRadius.circular(9),
                border: dragActive
                    ? Border.all(color: tokens.accent.withOpacity(.5))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.list_alt_outlined,
                      size: 18,
                      color: selected ? tokens.accent : tokens.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.list.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                selected ? tokens.accent : tokens.textSecondary,
                            fontSize: 12.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  if (count > 0)
                    Text('$count',
                        style: TextStyle(
                            color:
                                selected ? tokens.accent : tokens.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: hovering ? 1 : 0,
                    child: AppIconButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: '清单操作',
                        size: 24,
                        iconSize: 14,
                        onPressed: () => _showListMenu(context)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showListMenu(BuildContext context) async {
    final tokens = WorkFollowTheme.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? const Offset(200, 200)
        : box.localToGlobal(Offset(box.size.width - 8, box.size.height - 6));
    final choice = await showMenu<String>(
      context: context,
      color: tokens.overlay,
      position: RelativeRect.fromLTRB(
          anchor.dx, anchor.dy, anchor.dx + 1, anchor.dy + 1),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(
            value: 'delete',
            child: Text('删除清单', style: TextStyle(color: Colors.redAccent))),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'rename') {
      await _renameList(context);
    } else if (choice == 'delete') {
      await _confirmDelete(context);
    }
  }

  Future<void> _renameList(BuildContext context) async {
    final nameController = TextEditingController(text: widget.list.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名清单'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text),
              child: const Text('保存')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null ||
        name.trim().isEmpty ||
        name.trim() == widget.list.name) {
      return;
    }
    if (!widget.controller.renameList(widget.list.name, name)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称为空或已存在。')));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除清单？'),
        content: Text('「${widget.list.name}」里的任务会移回收集箱，不会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) widget.controller.deleteList(widget.list.name);
  }
}

class _TaskViewItem extends StatefulWidget {
  const _TaskViewItem({
    required this.controller,
    required this.view,
    required this.label,
    required this.hint,
    required this.icon,
  });

  final WorkspaceController controller;
  final WorkspaceView view;
  final String label;
  final String hint;
  final IconData icon;

  @override
  State<_TaskViewItem> createState() => _TaskViewItemState();
}

class _TaskViewItemState extends State<_TaskViewItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.view == widget.view;
    final count = widget.controller.countFor(widget.view);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${widget.label}，${widget.hint}',
        child: GestureDetector(
          onTap: () => widget.controller.selectView(widget.view),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.accentSoft
                  : (hovering
                      ? tokens.content.withOpacity(.7)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(widget.icon,
                    size: 17,
                    color: selected ? tokens.accent : tokens.textSecondary),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? tokens.accent : tokens.textPrimary,
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: 9.5,
                            height: 1.1),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: selected ? tokens.accent : tokens.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _editFolder(BuildContext anchor, WorkspaceController controller,
    MigrationFolderRecord folder) async {
  final action = await showDesktopMenu<String>(anchor, entries: const [
    DesktopMenuEntry('rename', '重命名', icon: Icons.edit_outlined),
    DesktopMenuEntry('remove', '删除文件夹…',
        icon: Icons.delete_outline, destructive: true),
  ]);
  if (!anchor.mounted || action == null) return;
  if (action == 'remove') {
    final confirmed = await showDialog<bool>(
        context: anchor,
        builder: (context) => AlertDialog(
              title: Text('删除“${folder.name}”？'),
              content: const Text('其中的笔记会保留，并移到“未归档”。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除文件夹'))
              ],
            ));
    if (confirmed == true) controller.removeFolder(folder.id);
    return;
  }
  var draft = folder.name;
  final name = await showDialog<String>(
      context: anchor,
      builder: (context) => AlertDialog(
            title: const Text('重命名文件夹'),
            content: TextFormField(
                initialValue: draft,
                onChanged: (value) => draft = value,
                autofocus: true,
                decoration: const InputDecoration(labelText: '文件夹名称'),
                onFieldSubmitted: (value) => Navigator.pop(context, value)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, draft),
                  child: const Text('保存'))
            ],
          ));
  if (name != null &&
      !controller.renameFolder(folder.id, name) &&
      anchor.mounted) {
    ScaffoldMessenger.of(anchor)
        .showSnackBar(const SnackBar(content: Text('请输入一个不重复的文件夹名称。')));
  }
}
