import 'package:flutter/material.dart';

import '../models/list_color.dart';
import '../models/migration.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_color_tokens.dart';
import '../theme/workfollow_interaction_states.dart';
import '../theme/workfollow_motion.dart';
import '../theme/workfollow_theme.dart';
import '../theme/workfollow_theme_parity.dart';
import '../features/feedback/feedback_event.dart';
import '../features/feedback/feedback_scope.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';

Color _sidebarAccent(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationAccent(context, tokens);

Color _sidebarAccentSoft(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationSelected(context, tokens);

Color _sidebarRail(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationRail(context, tokens);

Color _sidebarForeground(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationForeground(context, tokens);

Color _sidebarForegroundMuted(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationForegroundMuted(context, tokens);

Color _sidebarBorder(BuildContext context, WorkFollowTheme tokens) =>
    WorkFollowColorTokens.navigationBorder(context, tokens);

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

  // This native shell intentionally merges the Web client's global rail and
  // task-view sidebar into one surface. The Web width remains the migration
  // contract, while the local shell uses the compact profile so the second
  // column does not dominate the macOS window. [width] is the expanded width;
  // module pages drop the second column, so the live width is computed in
  // [build].
  static const double width =
      _iconRailWidth + 1 + WorkFollowLayout.compactTaskNavigationWidth;
  static const double _iconRailWidth = 52;

  final WorkspaceController controller;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // Module pages (calendar, matrix) are self-contained:
    // their page header already owns the mode and range controls, so a second
    // column could only repeat the destination the icon rail selected. Dropping
    // it hands the column's width back to the page and leaves the icons as the
    // single navigation surface.
    final contextColumn = !controller.isSelfContainedView;
    return Container(
      width: _iconRailWidth +
          1 +
          (contextColumn ? WorkFollowLayout.compactTaskNavigationWidth : 0),
      decoration: BoxDecoration(
        color: WorkFollowColorTokens.navigationSurface(context, tokens),
        border: Border(
            right: BorderSide(
                color: tokens.border,
                width: WorkFollowMetrics.dividerThickness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: _sidebarRail(context, tokens),
            child: _IconRail(
              controller: controller,
              isDark: isDark,
              onToggleTheme: onToggleTheme,
              onOpenSettings: onOpenSettings,
            ),
          ),
          if (contextColumn) ...[
            Container(
                width: WorkFollowMetrics.dividerThickness,
                color: tokens.border),
            Expanded(
              key: const ValueKey('rail-context-column'),
              child: Column(
                children: [
                  // No product brand here. The brand mark used to sit above the
                  // note tree only, so the tab strip changed height and started
                  // with a logo the moment the user switched to notes, while
                  // the task views started straight at the first destination.
                  // The app icon and the window title already carry the name;
                  // the column now opens the same way in every view.
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          WorkFollowSpacing.navigationScrollHorizontalPadding,
                          WorkFollowSpacing.navigationScrollTopPadding,
                          WorkFollowSpacing.navigationScrollHorizontalPadding,
                          WorkFollowSpacing.space3),
                      child: _ContextNavigation(controller: controller),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Maps the remaining first-level rail destinations to their second-column
/// grammar.
///
/// Only two contexts own a column: the note tree and the task tree. Home,
/// calendar and matrix have no column at all — see
/// [WorkspaceController.isSelfContainedView] — so this switch never sees them.
class _ContextNavigation extends StatelessWidget {
  const _ContextNavigation({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.view) {
      WorkspaceView.notes => _NotesNavigation(controller: controller),
      _ => _TaskNavigation(controller: controller),
    };
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
          icon: WorkFollowIcons.recent,
          count: controller.countFor(WorkspaceView.recent),
          selected: controller.view == WorkspaceView.recent,
          onTap: () => controller.selectView(WorkspaceView.recent),
        ),
        _RailItem(
          label: '今天',
          icon: WorkFollowIcons.today,
          count: controller.countFor(WorkspaceView.today),
          selected: controller.view == WorkspaceView.today &&
              controller.selectedListName == null,
          onTap: () => controller.selectView(WorkspaceView.today),
        ),
        _RailItem(
          label: '收集箱',
          icon: WorkFollowIcons.inbox,
          count: controller.countFor(WorkspaceView.inbox),
          selected: controller.view == WorkspaceView.inbox,
          onTap: () => controller.selectView(WorkspaceView.inbox),
        ),
        _RailItem(
          label: '所有任务',
          icon: WorkFollowIcons.allTasks,
          count: controller.countFor(WorkspaceView.all),
          selected: controller.view == WorkspaceView.all &&
              controller.selectedListName == null,
          onTap: () => controller.selectView(WorkspaceView.all),
        ),
        _RailSectionHeader(
          label: '清单',
          trailing: AppIconButton(
              icon: WorkFollowIcons.add,
              tooltip: '新建清单',
              size: WorkFollowMetrics.compactNavigationIconHitTarget,
              iconSize: WorkFollowMetrics.toolbarIcon,
              onPressed: () => _showAddListDialog(context, controller)),
        ),
        ...controller.orderedLists
            .where((list) => list.name != '收集箱')
            .map((list) => _TaskListItem(controller: controller, list: list)),
        _TagSection(controller: controller),
        // 已完成 and 垃圾桶 close the column as one group. Both hold work the
        // user is done with, and the finished list used to sit between 所有任务
        // and 清单 — inside the part of the column that is a live workspace.
        // The break keeps the pair from reading as two more rows of 标签.
        //
        // Keyed after `rail-navigation-item-*`: the pair's placement is a
        // contract with the column, and the break is the only thing that says
        // where the pair starts.
        const _RailGroupBreak(key: ValueKey('rail-group-break')),
        _RailItem(
          label: '已完成',
          icon: WorkFollowIcons.completed,
          count: controller.countFor(WorkspaceView.completed),
          selected: controller.view == WorkspaceView.completed,
          onTap: () => controller.selectView(WorkspaceView.completed),
        ),
        _RailItem(
          label: '垃圾桶',
          icon: WorkFollowIcons.trash,
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
                icon: WorkFollowIcons.add,
                tooltip: '新建笔记',
                size: WorkFollowMetrics.compactNavigationIconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: () => controller.addNoteInCurrentFolder()),
            AppIconButton(
                icon: WorkFollowIcons.newFolder,
                tooltip: '新建文件夹',
                size: WorkFollowMetrics.compactNavigationIconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: () => _showAddFolderDialog(context, controller)),
          ]),
        ),
        _RailItem(
          label: '全部笔记',
          icon: WorkFollowIcons.notes,
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
          icon: WorkFollowIcons.favoriteOutline,
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
          icon: WorkFollowIcons.inbox,
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
                  icon: WorkFollowIcons.folder,
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
  const _IconRail({
    required this.controller,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenSettings,
  });

  final WorkspaceController controller;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final taskRailSelected = switch (controller.view) {
      WorkspaceView.recent ||
      WorkspaceView.today ||
      WorkspaceView.inbox ||
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
      width: AppRail._iconRailWidth,
      child: Column(
        children: [
          const SizedBox(height: WorkFollowSpacing.space3),
          _IconRailButton(
            label: '首页',
            icon: WorkFollowIcons.brand,
            selected: controller.view == WorkspaceView.home,
            onPressed: () => controller.selectView(WorkspaceView.home),
            filled: true,
          ),
          const SizedBox(height: WorkFollowSpacing.controlGap),
          _IconRailButton(
            label: '任务',
            icon: WorkFollowIcons.tasks,
            selected: taskRailSelected,
            onPressed: () => controller.selectView(WorkspaceView.today),
          ),
          _IconRailButton(
            label: '笔记',
            icon: WorkFollowIcons.notes,
            selected: controller.view == WorkspaceView.notes,
            onPressed: () => controller.selectView(WorkspaceView.notes),
          ),
          _IconRailButton(
            label: '日历',
            icon: WorkFollowIcons.calendar,
            selected: controller.view == WorkspaceView.calendar,
            onPressed: () => controller.selectView(WorkspaceView.calendar),
          ),
          _IconRailButton(
            label: '四象限',
            icon: WorkFollowIcons.matrix,
            selected: controller.view == WorkspaceView.matrix,
            onPressed: () => controller.selectView(WorkspaceView.matrix),
          ),
          const Spacer(),
          _IconRailFooter(
            isDark: isDark,
            onToggleTheme: onToggleTheme,
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

/// The narrow rail owns global controls. Keeping them in this fixed column
/// prevents the task navigation from growing a second, unrelated footer and
/// leaves the main column dedicated to task lists, tags and filters.
class _IconRailFooter extends StatelessWidget {
  const _IconRailFooter({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          WorkFollowSpacing.inlineGap,
          WorkFollowSpacing.space2,
          WorkFollowSpacing.inlineGap,
          WorkFollowSpacing.cardInset),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space1),
        decoration: BoxDecoration(
          color: WorkFollowColorTokens.navigationFooterSurface(context, tokens),
          borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
          border: Border.all(color: _sidebarBorder(context, tokens)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: '本地空间',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: WorkFollowSpacing.space1),
                child: AppIcon(WorkFollowIcons.system,
                    size: WorkFollowMetrics.toolbarIcon,
                    color: _sidebarForegroundMuted(context, tokens)),
              ),
            ),
            _IconRailFooterButton(
              icon: WorkFollowIcons.settings,
              label: '设置',
              onPressed: onOpenSettings,
            ),
            _IconRailFooterButton(
              icon:
                  isDark ? WorkFollowIcons.lightMode : WorkFollowIcons.darkMode,
              label: isDark ? '切换浅色' : '切换深色',
              onPressed: onToggleTheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconRailFooterButton extends StatelessWidget {
  const _IconRailFooterButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      width: SidebarMetrics.footerButtonSize,
      height: SidebarMetrics.footerButtonSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: label,
            child: AppIconButton(
              key: ValueKey('rail-footer-$label'),
              icon: icon,
              tooltip: label,
              onPressed: onPressed,
              size: SidebarMetrics.footerButtonSize,
              iconSize: WorkFollowMetrics.compactFieldIcon,
              iconColor: _sidebarForeground(context, tokens),
            ),
          ),
          // Keep the old text-based automation target available without
          // bringing labels back into the 52pt rail. The transparent target
          // is still keyboard/screen-reader addressable and shares the same
          // action as the visible icon.
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              overlayColor: Colors.transparent,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label,
                // Not a type role: 1pt keeps this invisible target out of the
                // layout while leaving it keyboard and screen-reader
                // addressable. Excluded from the typography contract on purpose.
                style: const TextStyle(
                    fontSize: WorkFollowMacDisplay.accessibilityHidden,
                    color: Colors.transparent)),
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
  bool pressed = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // `filled` only chooses the home glyph's stronger visual treatment.  It
    // must not make Home look selected while the user is in Tasks/Notes/etc.;
    // the first rail otherwise shows two active destinations at once.
    // The rail fill never eases: hover and selection both have to land in the
    // same frame as the pointer or the click. With a 150ms transition every
    // icon the pointer swept past stayed lit (0.19 of the fill measured 90ms
    // after the pointer had left) and the icon that just lost the selection
    // kept its tint for another 150ms — both read as a stray click.
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
          child: Focus(
            onFocusChange: (value) => setState(() => focused = value),
            child: GestureDetector(
              onTap: widget.onPressed,
              onTapDown: (_) => setState(() => pressed = true),
              onTapUp: (_) => setState(() => pressed = false),
              onTapCancel: () => setState(() => pressed = false),
              child: Container(
                key: ValueKey('rail-button-${widget.label}'),
                width: SidebarMetrics.railButtonSize,
                height: SidebarMetrics.railButtonSize,
                margin: const EdgeInsets.symmetric(
                    vertical: WorkFollowSpacing.tightGap),
                decoration: BoxDecoration(
                  color: WorkFollowInteractionStyles.customFill(
                    defaultColor: Colors.transparent,
                    hoverColor:
                        WorkFollowColorTokens.navigationHover(context, tokens),
                    selectedColor: WorkFollowColorTokens.navigationRailSelected(
                        context, tokens),
                    pressedColor: WorkFollowColorTokens.navigationPressed(
                        context, tokens),
                    selected: active,
                    hovered: hovering,
                    pressed: pressed,
                  ),
                  borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
                  border: Border.fromBorderSide(
                    WorkFollowInteractionStyles.focusBorder(
                      tokens,
                      focused: focused,
                    ),
                  ),
                ),
                child: AppIcon(
                  widget.icon,
                  size: widget.filled
                      ? WorkFollowMetrics.railIcon + 1
                      : WorkFollowMetrics.railIcon,
                  color: active
                      ? _sidebarAccent(context, tokens)
                      : (hovering
                          ? _sidebarForeground(context, tokens)
                          : _sidebarForegroundMuted(context, tokens)),
                ),
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
    showFeedback(
        context,
        const WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.error, message: '清单名称为空，或已经存在。'));
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
    showFeedback(
        context,
        const WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.error, message: '文件夹名称为空，或已经存在。'));
    return;
  }
  controller.setNotesFolderFilter(folder.id);
  controller.selectView(WorkspaceView.notes);
}

/// The hairline that opens the rail's closing group (已完成 / 垃圾桶).
///
/// The column's other groups announce themselves with a [_RailSectionHeader],
/// which works because each of them has a name — 任务, 清单, 标签. The closing
/// pair has no name to carry, and inventing one ("归档", "回收") would put a
/// word in the user's way that the product never uses. A rule marks the same
/// break without adding vocabulary.
class _RailGroupBreak extends StatelessWidget {
  const _RailGroupBreak({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          top: WorkFollowMetrics.compactNavigationSectionTop,
          bottom: WorkFollowMetrics.compactNavigationSectionBottom),
      child: Container(
        height: WorkFollowMetrics.dividerThickness,
        color: tokens.border,
      ),
    );
  }
}

class _RailSectionHeader extends StatelessWidget {
  const _RailSectionHeader({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          top: WorkFollowMetrics.compactNavigationSectionTop,
          bottom: WorkFollowMetrics.compactNavigationSectionBottom),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textTertiary,
                // A rail group title is navigation chrome, not a content
                // heading: it sits above the [_RailItem] rows it labels and
                // separates itself from them with colour and size. Weight is
                // not part of that separation — the rows are regular too, so
                // this line is not the one carrying the hierarchy.
                fontSize: WorkFollowMacTypography.navigationMeta,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular,
                letterSpacing: WorkFollowMacTracking.none,
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
                ? WorkFollowIcons.expandLess
                : WorkFollowIcons.expandMore,
            tooltip: expanded ? '收起标签' : '展开标签',
            size: WorkFollowMetrics.compactNavigationIconHitTarget,
            iconSize: WorkFollowMetrics.toolbarIcon,
            onPressed: () => setState(() => expanded = !expanded),
          ),
        ),
        if (expanded && tags.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                WorkFollowSpacing.navigationContentInset,
                WorkFollowSpacing.tightGap,
                WorkFollowSpacing.space2,
                WorkFollowSpacing.xs),
            child: Text('在任务中输入 #标签',
                style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: WorkFollowMacTypography.supporting,
                    height: WorkFollowMacTypography.lineList,
                    fontWeight: WorkFollowMacWeight.regular)),
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

class _RailItem extends StatefulWidget {
  // No key: the second column is rebuilt wholesale when the view changes, and
  // no caller identifies a row by key any more (the home column that did is
  // gone). Tests reach rows by their label.
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
  bool pressed = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // See _IconRailButtonState: the surface fill never eases.
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: Focus(
          onFocusChange: (value) => setState(() => focused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => pressed = true),
            onTapUp: (_) => setState(() => pressed = false),
            onTapCancel: () => setState(() => pressed = false),
            onSecondaryTap: widget.onMenu,
            child: Container(
              key: ValueKey('rail-navigation-item-${widget.label}'),
              height: WorkFollowMetrics.compactNavigationRowHeight,
              margin: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.hairlineGap),
              padding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.cardInset),
              decoration: BoxDecoration(
                color: WorkFollowInteractionStyles.customFill(
                  defaultColor: Colors.transparent,
                  hoverColor:
                      WorkFollowColorTokens.navigationHover(context, tokens),
                  // Selection is a state, not a colour: the fill is the same
                  // quiet grey every other selected row wears, and the words
                  // keep their own ink. Tinting both was what made the column
                  // read as a row of coloured labels.
                  selectedColor: tokens.listRowSelected,
                  pressedColor:
                      WorkFollowColorTokens.navigationPressed(context, tokens),
                  selected: widget.selected,
                  hovered: hovering,
                  pressed: pressed,
                ),
                borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                border: Border.fromBorderSide(
                  WorkFollowInteractionStyles.focusBorder(
                    tokens,
                    focused: focused,
                  ),
                ),
              ),
              child: Row(
                children: [
                  AppIcon(
                    widget.icon,
                    size: WorkFollowMetrics.navigationIcon,
                    color: tokens.textPrimary,
                  ),
                  const SizedBox(width: WorkFollowSpacing.controlGap),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: WorkFollowMacTypography.navigation,
                        height: WorkFollowMacTypography.lineControl,
                        // Every row carries the same ink and the same weight,
                        // selected or not. Regular is the reference's weight,
                        // read off its own rendering rather than eyeballed: at
                        // the same 14pt the navigation rows there resolve to
                        // PingFangUITextSC-Regular, while ours resolved to
                        // Medium and laid down about 19% more ink — a full
                        // weight step, which is what made the column read as
                        // heavy. Selection belongs to the fill alone.
                        fontWeight: WorkFollowMacWeight.regular,
                      ),
                    ),
                  ),
                  if (hovering && widget.onMenu != null)
                    SizedBox(
                        width: SidebarMetrics.folderMoreWidth,
                        height: SidebarMetrics.folderMoreHeight,
                        child: IconButton(
                            tooltip: '文件夹操作',
                            padding: EdgeInsets.zero,
                            iconSize: WorkFollowMetrics.metadataIcon,
                            onPressed: widget.onMenu,
                            icon: const AppIcon(WorkFollowIcons.more)))
                  else if (widget.count != null && widget.count! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: WorkFollowSpacing.compactGap,
                          vertical: WorkFollowSpacing.microGap),
                      decoration: BoxDecoration(
                        // The count is a quiet figure beside the words, so its
                        // chip is the one thing that steps off the row's own
                        // surface: a grey pill on the resting column, white
                        // once the row's selected grey has taken it over.
                        color: WorkFollowColorTokens.navigationCountChip(
                            context, tokens,
                            selected: widget.selected),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.pill),
                      ),
                      child: Text('${widget.count}',
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: WorkFollowMacTypography.navigationMeta,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.regular)),
                    ),
                ],
              ),
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
  bool pressed = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.isListSelected(widget.list.name);
    // See _IconRailButtonState: the surface fill never eases.
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
          return Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: WorkFollowMetrics.listItemMaxWidth),
              child: Semantics(
                button: true,
                selected: selected,
                label: '${widget.list.name}，$count 个未完成任务',
                child: Focus(
                  onFocusChange: (value) => setState(() => focused = value),
                  child: GestureDetector(
                    onTap: () => widget.controller.selectList(widget.list.name),
                    onTapDown: (_) => setState(() => pressed = true),
                    onTapUp: (_) => setState(() => pressed = false),
                    onTapCancel: () => setState(() => pressed = false),
                    child: Container(
                      key: ValueKey('rail-list-item-${widget.list.name}'),
                      height: WorkFollowMetrics.compactNavigationRowHeight,
                      margin: const EdgeInsets.symmetric(
                          vertical: WorkFollowSpacing.hairlineGap),
                      padding: const EdgeInsets.symmetric(
                          horizontal: WorkFollowSpacing.cardInset),
                      decoration: BoxDecoration(
                        color: dragActive
                            ? _sidebarAccentSoft(context, tokens)
                            : WorkFollowInteractionStyles.customFill(
                                defaultColor: Colors.transparent,
                                hoverColor: WorkFollowColorTokens.navigationHover(
                                    context, tokens),
                                // A selected list is a selected row, not a
                                // swatch: the fill is neutral like every other
                                // row's, and the list's colour stays on the
                                // dot where it does the recognising.
                                selectedColor: tokens.listRowSelected,
                                pressedColor:
                                    WorkFollowColorTokens.navigationPressed(
                                        context, tokens),
                                selected: selected,
                                hovered: hovering,
                                pressed: pressed,
                              ),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.control),
                        border: dragActive
                            ? Border.all(
                                color: _sidebarAccent(context, tokens)
                                    .withValues(alpha: .5))
                            : Border.fromBorderSide(
                                WorkFollowInteractionStyles.focusBorder(
                                  tokens,
                                  focused: focused,
                                ),
                              ),
                      ),
                      child: Row(
                        children: [
                          Container(
                              width: SidebarMetrics.listColorDotSize,
                              height: SidebarMetrics.listColorDotSize,
                              decoration: BoxDecoration(
                                  color: listColor, shape: BoxShape.circle)),
                          const SizedBox(width: WorkFollowSpacing.space2),
                          Expanded(
                            child: Text(widget.list.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize:
                                        WorkFollowMacTypography.navigation,
                                    height: WorkFollowMacTypography.lineControl,
                                    // Same weight as every other row in this
                                    // column — see _RailItemState.
                                    fontWeight: WorkFollowMacWeight.regular)),
                          ),
                          if (count > 0)
                            Text('$count',
                                style: TextStyle(
                                    color: tokens.textTertiary,
                                    fontSize:
                                        WorkFollowMacTypography.navigationMeta,
                                    height: WorkFollowMacTypography.lineControl,
                                    fontWeight: WorkFollowMacWeight.regular)),
                          ExcludeSemantics(
                            excluding: !hovering,
                            child: AnimatedOpacity(
                              duration: WorkFollowMotionPolicy.duration(context,
                                  WorkFollowMotionRole.hoverTransition),
                              opacity: hovering ? 1 : 0,
                              child: AppIconButton(
                                  icon: WorkFollowIcons.more,
                                  tooltip: '清单操作',
                                  size: WorkFollowMetrics
                                      .compactNavigationIconHitTarget,
                                  iconSize: WorkFollowMetrics.metadataIcon,
                                  onPressed: () => _showListMenu(context)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showListMenu(BuildContext context) async {
    final choice = await showDesktopMenu<String>(
      context,
      placement: PopoverPlacement.bottomEnd,
      entries: [
        DesktopMenuEntry('pin', widget.list.pinned ? '取消置顶' : '置顶清单',
            icon: WorkFollowIcons.pin),
        const DesktopMenuEntry('rename', '重命名', icon: WorkFollowIcons.edit),
        const DesktopMenuEntry('color', '选择颜色'),
        const DesktopMenuEntry('delete', '删除清单',
            icon: WorkFollowIcons.delete, destructive: true),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'pin') {
      widget.controller.toggleListPinned(widget.list.name);
    } else if (choice == 'rename') {
      await _renameList(context);
    } else if (choice == 'color') {
      await _pickListColor(context);
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
                width: SidebarMetrics.listColorPickerWidth,
                child: Wrap(
                  spacing: WorkFollowSpacing.controlGap,
                  runSpacing: WorkFollowSpacing.controlGap,
                  children: [
                    for (final value in listColorPalette)
                      ListColorSwatch(
                        value: value,
                        selected: widget.controller
                                .colorHexForList(widget.list.name) ==
                            colorHexFromValue(value),
                        onPick: () => Navigator.of(dialogContext)
                            .pop(colorHexFromValue(value)),
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
      showFeedback(
          context,
          const WorkFollowFeedback(
              kind: WorkFollowFeedbackKind.error, message: '名称为空或已存在。'));
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
  bool pressed = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.selectedTagName == widget.name;
    // See _IconRailButtonState: the surface fill never eases.
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Focus(
        onFocusChange: (value) => setState(() => focused = value),
        child: GestureDetector(
          onTap: () => widget.controller.selectTag(widget.name),
          onTapDown: (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          onSecondaryTap: () => _showMenu(context),
          child: Semantics(
            button: true,
            selected: selected,
            label: '#${widget.name}，${widget.count} 个任务',
            child: Container(
              key: ValueKey('rail-tag-item-${widget.name}'),
              height: WorkFollowMetrics.compactNavigationRowHeight,
              margin: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.hairlineGap),
              padding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.cardInset),
              decoration: BoxDecoration(
                  color: WorkFollowInteractionStyles.customFill(
                    defaultColor: Colors.transparent,
                    hoverColor:
                        WorkFollowColorTokens.navigationHover(context, tokens),
                    selectedColor: tokens.listRowSelected,
                    pressedColor: WorkFollowColorTokens.navigationPressed(
                        context, tokens),
                    selected: selected,
                    hovered: hovering,
                    pressed: pressed,
                  ),
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  border: Border.fromBorderSide(
                    WorkFollowInteractionStyles.focusBorder(
                      tokens,
                      focused: focused,
                    ),
                  )),
              child: Row(children: [
                AppIcon(WorkFollowIcons.tag,
                    size: WorkFollowMetrics.navigationIcon,
                    color: tokens.textPrimary),
                const SizedBox(width: WorkFollowSpacing.controlGap),
                Expanded(
                    child: Text(widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.navigation,
                            height: WorkFollowMacTypography.lineControl,
                            // Same weight as every other row in this column —
                            // see _RailItemState.
                            fontWeight: WorkFollowMacWeight.regular))),
                Text('${widget.count}',
                    style: TextStyle(
                        color: tokens.textTertiary,
                        fontSize: WorkFollowMacTypography.navigationMeta,
                        height: WorkFollowMacTypography.lineControl,
                        fontWeight: WorkFollowMacWeight.regular)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final action = await showDesktopMenu<String>(
      context,
      placement: PopoverPlacement.bottomEnd,
      entries: const [
        DesktopMenuEntry('rename', '重命名标签', icon: WorkFollowIcons.edit),
        DesktopMenuEntry('delete', '删除标签',
            icon: WorkFollowIcons.delete, destructive: true),
      ],
    );
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
      showFeedback(
          context,
          const WorkFollowFeedback(
              kind: WorkFollowFeedbackKind.error, message: '标签名称为空或已存在。'));
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
  bool pressed = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.view == widget.view;
    // See _IconRailButtonState: the surface fill never eases.
    final count = widget.controller.countFor(widget.view);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${widget.label}，${widget.hint}',
        child: Focus(
          onFocusChange: (value) => setState(() => focused = value),
          child: GestureDetector(
            onTap: () => widget.controller.selectView(widget.view),
            onTapDown: (_) => setState(() => pressed = true),
            onTapUp: (_) => setState(() => pressed = false),
            onTapCancel: () => setState(() => pressed = false),
            child: Container(
              key: ValueKey('rail-view-item-${widget.view.name}'),
              margin: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.microGap),
              padding: const EdgeInsets.fromLTRB(
                  WorkFollowSpacing.railItemHorizontalInset,
                  WorkFollowSpacing.xs,
                  WorkFollowSpacing.railItemTrailingInset,
                  WorkFollowSpacing.xs),
              decoration: BoxDecoration(
                color: WorkFollowInteractionStyles.customFill(
                  defaultColor: Colors.transparent,
                  hoverColor:
                      WorkFollowColorTokens.navigationHover(context, tokens),
                  selectedColor: _sidebarAccentSoft(context, tokens),
                  pressedColor:
                      WorkFollowColorTokens.navigationPressed(context, tokens),
                  selected: selected,
                  hovered: hovering,
                  pressed: pressed,
                ),
                borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                border: Border.fromBorderSide(
                  WorkFollowInteractionStyles.focusBorder(
                    tokens,
                    focused: focused,
                  ),
                ),
              ),
              child: Row(
                children: [
                  AppIcon(widget.icon,
                      size: WorkFollowMetrics.navigationIcon,
                      color: selected
                          ? _sidebarAccent(context, tokens)
                          : tokens.textPrimary),
                  const SizedBox(width: WorkFollowSpacing.compactInset),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? _sidebarAccent(context, tokens)
                                : tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.navigation,
                            height: WorkFollowMacTypography.lineControl,
                            // Nothing instantiates this row any more, so this
                            // is not the grammar the column draws with — see
                            // _RailItemState. It is kept in step with it rather
                            // than left at w500, because a `selected ? medium :
                            // regular` sitting here is exactly the line the
                            // next reader would take for the rule.
                            fontWeight: WorkFollowMacWeight.regular,
                          ),
                        ),
                        const SizedBox(height: WorkFollowSpacing.microGap),
                        Text(
                          widget.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: WorkFollowMacTypography.navigationMeta,
                              height: WorkFollowMacTypography.lineControl),
                        ),
                      ],
                    ),
                  ),
                  if (count > 0)
                    Padding(
                      padding: const EdgeInsets.only(
                          left: WorkFollowSpacing.inlineGap),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: selected
                              ? _sidebarAccent(context, tokens)
                              : tokens.textTertiary,
                          fontSize: WorkFollowMacTypography.navigationMeta,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular,
                        ),
                      ),
                    ),
                ],
              ),
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
    DesktopMenuEntry('rename', '重命名', icon: WorkFollowIcons.edit),
    DesktopMenuEntry('remove', '删除文件夹…',
        icon: WorkFollowIcons.delete, destructive: true),
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
    showFeedback(
        anchor,
        const WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.error, message: '请输入一个不重复的文件夹名称。'));
  }
}

/// One colour in the list-colour palette.
///
/// The disc *is* the value being chosen, so the pointer must not tint it: a
/// deeper shade under the cursor would show a colour the row will never get.
/// The ring is drawn over a transparent border instead, which leaves the
/// resting swatch pixel-for-pixel unchanged and never grows the swatch, so the
/// wrap that lays the palette out keeps its geometry.
///
/// This deliberately is not an InkWell. An InkWell paints its ink on the
/// nearest Material, *under* its child, so a fill painted by the child hides
/// the pointer feedback completely — which is what the swatch used to do.
class ListColorSwatch extends StatefulWidget {
  const ListColorSwatch({
    super.key,
    required this.value,
    required this.selected,
    required this.onPick,
  });

  final int value;
  final bool selected;
  final VoidCallback onPick;

  @override
  State<ListColorSwatch> createState() => _ListColorSwatchState();
}

class _ListColorSwatchState extends State<ListColorSwatch> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onPick,
        child: Container(
          width: SidebarMetrics.colorSwatchSize,
          height: SidebarMetrics.colorSwatchSize,
          decoration: BoxDecoration(
            color: Color(widget.value),
            shape: BoxShape.circle,
            border: Border.all(
              color: hovering ? tokens.borderStrong : Colors.transparent,
              width: SidebarMetrics.colorSwatchRingWidth,
            ),
          ),
          child: widget.selected
              ? AppIcon(WorkFollowIcons.check,
                  size: WorkFollowMetrics.toolbarIcon,
                  color: WorkFollowThemeContrast.foregroundOn(
                      Color(widget.value)))
              : null,
        ),
      ),
    );
  }
}
