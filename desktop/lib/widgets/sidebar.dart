import 'package:flutter/material.dart';

import '../models/list_color.dart';
import '../models/migration.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';

/// The persistent product-level navigation from the web app, adapted to a
/// native macOS rail. Personal builds intentionally omit team and notification
/// destinations, but keep the same visual hierarchy and active-state language.
/// It deliberately has two visual levels: a narrow icon rail for
/// muscle-memory destinations and a readable
/// navigation column for smart views, lists, tags and note folders. Keeping
/// both levels in one widget means the shell can collapse the whole surface
/// without losing the current selection semantics.
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.controller,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenSettings,
  });

  // TickTick keeps the navigation readable but deliberately gives the task
  // list most of the window. 52pt icon rail + 190pt label column lands close
  // to the native macOS proportions at the default 1280pt window.
  static const double width = 242;

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
      child: Row(
        children: [
          _IconRail(controller: controller),
          Container(width: 1, color: tokens.border),
          Expanded(
            child: Column(
              children: [
                const _RailBrand(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(9, 6, 9, 12),
                    child: _ContextNavigation(controller: controller),
                  ),
                ),
                _RailFooter(
                  isDark: isDark,
                  onToggleTheme: onToggleTheme,
                  onOpenSettings: onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps every first-level rail destination to its own second-column grammar.
///
/// The old implementation only distinguished tasks from notes, which meant
/// that calendar, matrix, board, habits and stats all rendered the complete
/// task tree. TickTick keeps those modules quiet and contextual, so the
/// second column must change as soon as the first rail changes.
class _ContextNavigation extends StatelessWidget {
  const _ContextNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.view) {
      WorkspaceView.home => _HomeNavigation(controller: controller),
      WorkspaceView.notes => _NotesNavigation(controller: controller),
      WorkspaceView.calendar => _CalendarNavigation(controller: controller),
      WorkspaceView.matrix => _MatrixNavigation(controller: controller),
      WorkspaceView.board => _BoardNavigation(controller: controller),
      WorkspaceView.habits => _HabitsNavigation(controller: controller),
      WorkspaceView.stats => _StatsNavigation(controller: controller),
      _ => _TaskNavigation(controller: controller),
    };
  }
}

/// Home is a dashboard rather than a task list. Keep only dashboard actions
/// here; task filters remain in the task context after selecting the task rail.
class _HomeNavigation extends StatelessWidget {
  const _HomeNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailSectionHeader(label: '概览'),
        _RailItem(
          key: const ValueKey('rail-context-home'),
          label: '首页',
          icon: Icons.check_rounded,
          selected: controller.view == WorkspaceView.home,
          onTap: () => controller.selectView(WorkspaceView.home),
        ),
        _RailItem(
          key: const ValueKey('rail-context-home-quick-add'),
          label: '快速录入',
          icon: Icons.add_task_outlined,
          selected: false,
          onTap: controller.requestQuickAddFocus,
        ),
      ],
    );
  }
}

/// Calendar owns its month/week controls in the page header. The second
/// column intentionally exposes only the calendar destination instead of
/// duplicating task filters that belong to the task context.
class _CalendarNavigation extends StatelessWidget {
  const _CalendarNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => _SingleContextNavigation(
        controller: controller,
        sectionLabel: '日历',
        label: '日历',
        icon: Icons.calendar_month_outlined,
        view: WorkspaceView.calendar,
      );
}

class _MatrixNavigation extends StatelessWidget {
  const _MatrixNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => _SingleContextNavigation(
        controller: controller,
        sectionLabel: '四象限',
        label: '四象限',
        icon: Icons.grid_view_rounded,
        view: WorkspaceView.matrix,
      );
}

class _BoardNavigation extends StatelessWidget {
  const _BoardNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => _SingleContextNavigation(
        controller: controller,
        sectionLabel: '看板',
        label: '看板',
        icon: Icons.view_column_outlined,
        view: WorkspaceView.board,
      );
}

class _HabitsNavigation extends StatelessWidget {
  const _HabitsNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => _SingleContextNavigation(
        controller: controller,
        sectionLabel: '习惯',
        label: '习惯',
        icon: Icons.repeat_rounded,
        view: WorkspaceView.habits,
      );
}

class _StatsNavigation extends StatelessWidget {
  const _StatsNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => _SingleContextNavigation(
        controller: controller,
        sectionLabel: '统计',
        label: '统计',
        icon: Icons.insights_outlined,
        view: WorkspaceView.stats,
      );
}

class _SingleContextNavigation extends StatelessWidget {
  const _SingleContextNavigation({
    required this.controller,
    required this.sectionLabel,
    required this.label,
    required this.icon,
    required this.view,
  });

  final WorkspaceController controller;
  final String sectionLabel;
  final String label;
  final IconData icon;
  final WorkspaceView view;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailSectionHeader(label: sectionLabel),
        _RailItem(
          key: ValueKey('rail-context-${view.name}'),
          label: label,
          icon: icon,
          selected: controller.view == view,
          onTap: () => controller.selectView(view),
        ),
      ],
    );
  }
}

/// The second navigation column follows the selected first-level context.
/// TickTick does not mix note folders into the task list navigation; keeping
/// the two trees separate makes the current workspace immediately legible.
class _TaskNavigation extends StatelessWidget {
  const _TaskNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailSectionHeader(label: '任务'),
        _RailItem(
          label: '最近 7 天',
          icon: Icons.date_range_outlined,
          count: controller.countFor(WorkspaceView.recent),
          selected: controller.view == WorkspaceView.recent,
          onTap: () => controller.selectView(WorkspaceView.recent),
        ),
        _RailItem(
          label: '今天',
          icon: Icons.wb_sunny_outlined,
          count: controller.countFor(WorkspaceView.today),
          selected: controller.view == WorkspaceView.today &&
              controller.selectedListName == null,
          onTap: () => controller.selectView(WorkspaceView.today),
        ),
        _RailItem(
          label: '过期',
          icon: Icons.history_rounded,
          count: controller.countFor(WorkspaceView.overdue),
          selected: controller.view == WorkspaceView.overdue,
          onTap: () => controller.selectView(WorkspaceView.overdue),
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
          label: '摘要',
          icon: Icons.subject_outlined,
          selected: false,
          onTap: () => controller.selectView(WorkspaceView.home),
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
              onPressed: () => _showAddListDialog(context, controller)),
        ),
        ...controller.orderedLists
            .where((list) => list.name != '收集箱')
            .map((list) => _TaskListItem(controller: controller, list: list)),
        _TagSection(controller: controller),
        _RailItem(
          label: '废纸篓',
          icon: Icons.delete_outline_rounded,
          count: controller.countFor(WorkspaceView.trash),
          selected: controller.view == WorkspaceView.trash,
          onTap: () => controller.selectView(WorkspaceView.trash),
        ),
      ],
    );
  }
}

class _NotesNavigation extends StatelessWidget {
  const _NotesNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onPressed: () => _showAddFolderDialog(context, controller)),
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
          count: controller.activeNotes.where((note) => note.isFavorite).length,
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
                  onMenu: () => _editFolder(anchor, controller, folder),
                ))),
      ],
    );
  }
}

/// The narrow rail mirrors the high-frequency destinations from the local
/// TickTick reference. Labels stay available through tooltips and Semantics,
/// while the full names remain in the adjacent navigation column.
class _IconRail extends StatelessWidget {
  const _IconRail({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final taskRailSelected = switch (controller.view) {
      WorkspaceView.recent ||
      WorkspaceView.today ||
      WorkspaceView.overdue ||
      WorkspaceView.inbox ||
      WorkspaceView.plan ||
      WorkspaceView.all ||
      WorkspaceView.completed ||
      WorkspaceView.work ||
      WorkspaceView.study ||
      WorkspaceView.personal ||
      WorkspaceView.trash =>
        true,
      _ => false,
    };
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          const SizedBox(height: 12),
          _IconRailButton(
            label: '首页',
            icon: Icons.check_rounded,
            selected: controller.view == WorkspaceView.home,
            onPressed: () => controller.selectView(WorkspaceView.home),
            filled: true,
          ),
          const SizedBox(height: 10),
          _IconRailButton(
            label: '任务',
            icon: Icons.checklist_rounded,
            selected: taskRailSelected,
            onPressed: () => controller.selectView(WorkspaceView.today),
          ),
          _IconRailButton(
            label: '笔记',
            icon: Icons.notes_outlined,
            selected: controller.view == WorkspaceView.notes,
            onPressed: () => controller.selectView(WorkspaceView.notes),
          ),
          _IconRailButton(
            label: '日历',
            icon: Icons.calendar_month_outlined,
            selected: controller.view == WorkspaceView.calendar,
            onPressed: () => controller.selectView(WorkspaceView.calendar),
          ),
          _IconRailButton(
            label: '四象限',
            icon: Icons.grid_view_rounded,
            selected: controller.view == WorkspaceView.matrix,
            onPressed: () => controller.selectView(WorkspaceView.matrix),
          ),
          _IconRailButton(
            label: '看板',
            icon: Icons.view_column_outlined,
            selected: controller.view == WorkspaceView.board,
            onPressed: () => controller.selectView(WorkspaceView.board),
          ),
          _IconRailButton(
            label: '习惯',
            icon: Icons.repeat_rounded,
            selected: controller.view == WorkspaceView.habits,
            onPressed: () => controller.selectView(WorkspaceView.habits),
          ),
          _IconRailButton(
            label: '统计',
            icon: Icons.insights_outlined,
            selected: controller.view == WorkspaceView.stats,
            onPressed: () => controller.selectView(WorkspaceView.stats),
          ),
          const Spacer(),
          Semantics(
            label: '本地空间',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Icon(Icons.computer_outlined,
                  size: 16, color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconRailButton extends StatefulWidget {
  const _IconRailButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final bool filled;

  @override
  State<_IconRailButton> createState() => _IconRailButtonState();
}

class _IconRailButtonState extends State<_IconRailButton> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // `filled` only chooses the home glyph's stronger visual treatment.  It
    // must not make Home look selected while the user is in Tasks/Notes/etc.;
    // the first rail otherwise shows two active destinations at once.
    final active = widget.selected;
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => hovering = true),
          onExit: (_) => setState(() => hovering = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: active
                    ? tokens.accent.withValues(alpha: .16)
                    : hovering
                        ? tokens.content.withValues(alpha: .65)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: widget.filled ? 21 : 19,
                color: active ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ),
        ),
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

/// Tags follow TickTick's collapsible section grammar. Keeping the section
/// state local avoids changing the task model just to remember a navigation
/// preference; the list stays expanded once the user opens it during a run.
class _TagSection extends StatefulWidget {
  const _TagSection({required this.controller});

  final WorkspaceController controller;

  @override
  State<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<_TagSection> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tags = widget.controller.allTags();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailSectionHeader(
          label: '标签',
          trailing: AppIconButton(
            icon: expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            tooltip: expanded ? '收起标签' : '展开标签',
            size: 24,
            iconSize: 16,
            onPressed: () => setState(() => expanded = !expanded),
          ),
        ),
        if (expanded && tags.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 3, 8, 6),
            child: Text('在任务中输入 #标签',
                style: TextStyle(color: tokens.textTertiary, fontSize: 10.5)),
          ),
        if (expanded)
          ...tags.entries.map((entry) => _TagItem(
                controller: widget.controller,
                name: entry.key,
                count: entry.value,
              )),
      ],
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand();
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 14, 18),
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
    super.key,
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
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: hovering
                  ? tokens.content.withOpacity(.65)
                  : Colors.transparent,
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
    final listColor =
        Color(widget.controller.colorValueForList(widget.list.name));
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      // Dropping a dragged task row here moves it into this list.
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
        onAcceptWithDetails: (details) => widget.controller.taskActions
            .moveToList(details.data, widget.list.name),
        builder: (context, candidateData, rejectedData) {
          final dragActive = candidateData.isNotEmpty;
          return Semantics(
            button: true,
            selected: selected,
            label: '${widget.list.name}，$count 个未完成任务',
            child: GestureDetector(
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
                          ? listColor.withValues(alpha: .12)
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
                    Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: listColor, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.list.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color:
                                  selected ? listColor : tokens.textSecondary,
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                    if (count > 0)
                      Text('$count',
                          style: TextStyle(
                              color: selected ? listColor : tokens.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ExcludeSemantics(
                      excluding: !hovering,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: hovering ? 1 : 0,
                        child: AppIconButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: '清单操作',
                            size: 24,
                            iconSize: 14,
                            onPressed: () => _showListMenu(context)),
                      ),
                    ),
                  ],
                ),
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
      items: [
        PopupMenuItem(
            value: 'pin', child: Text(widget.list.pinned ? '取消置顶' : '置顶清单')),
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'color', child: Text('选择颜色')),
        const PopupMenuItem(value: 'board', child: Text('在看板中打开')),
        const PopupMenuItem(
            value: 'delete',
            child: Text('删除清单', style: TextStyle(color: Colors.redAccent))),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'pin') {
      widget.controller.toggleListPinned(widget.list.name);
    } else if (choice == 'rename') {
      await _renameList(context);
    } else if (choice == 'color') {
      await _pickListColor(context);
    } else if (choice == 'board') {
      widget.controller.selectBoard(listName: widget.list.name);
    } else if (choice == 'delete') {
      await _confirmDelete(context);
    }
  }

  Future<void> _pickListColor(BuildContext context) async {
    final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('选择清单颜色'),
              content: SizedBox(
                width: 270,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final value in listColorPalette)
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => Navigator.of(dialogContext)
                            .pop(colorHexFromValue(value)),
                        child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                                color: Color(value), shape: BoxShape.circle),
                            child: widget.controller
                                        .colorHexForList(widget.list.name) ==
                                    colorHexFromValue(value)
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null),
                      ),
                  ],
                ),
              ),
            ));
    if (!context.mounted || selected == null) return;
    widget.controller.updateListColor(widget.list.name, selected);
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

class _TagItem extends StatefulWidget {
  const _TagItem({
    required this.controller,
    required this.name,
    required this.count,
  });

  final WorkspaceController controller;
  final String name;
  final int count;

  @override
  State<_TagItem> createState() => _TagItemState();
}

class _TagItemState extends State<_TagItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.selectedTagName == widget.name;
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: () => widget.controller.selectTag(widget.name),
        onSecondaryTap: () => _showMenu(context),
        child: Semantics(
          button: true,
          selected: selected,
          label: '#${widget.name}，${widget.count} 个任务',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
                color: selected
                    ? tokens.accentSoft
                    : (hovering
                        ? tokens.content.withValues(alpha: .65)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(9)),
            child: Row(children: [
              Icon(Icons.tag_outlined,
                  size: 17,
                  color: selected ? tokens.accent : tokens.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color:
                              selected ? tokens.accent : tokens.textSecondary,
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500))),
              Text('${widget.count}',
                  style: TextStyle(
                      color: selected ? tokens.accent : tokens.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final action = await showMenu<String>(
        context: context,
        position: const RelativeRect.fromLTRB(160, 240, 0, 0),
        items: const [
          PopupMenuItem(value: 'rename', child: Text('重命名标签')),
          PopupMenuItem(value: 'delete', child: Text('删除标签')),
        ]);
    if (!context.mounted || action == null) return;
    if (action == 'delete') {
      widget.controller.deleteTag(widget.name);
      return;
    }
    final input = TextEditingController(text: widget.name);
    final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('重命名标签'),
              content: TextField(
                  controller: input,
                  autofocus: true,
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(input.text),
                    child: const Text('保存')),
              ],
            ));
    input.dispose();
    if (!context.mounted || name == null) return;
    if (!widget.controller.renameTag(widget.name, name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标签名称为空或已存在。')));
    }
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
