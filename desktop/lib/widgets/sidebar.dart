import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// The persistent product-level navigation from the web app, adapted to a
/// native macOS rail. Personal builds intentionally omit team and notification
/// destinations, but keep the same visual hierarchy and active-state language.
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
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
    final tokens = WorkFollowTheme.of(context);
    return Container(
      width: 152,
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        children: [
          const _RailBrand(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RailItem(
                    label: '首页',
                    icon: Icons.home_outlined,
                    selected: controller.view == WorkspaceView.home,
                    onTap: () => controller.selectView(WorkspaceView.home),
                  ),
                  _RailItem(
                    label: '任务',
                    icon: Icons.checklist_outlined,
                    selected: controller.isTaskView,
                    onTap: () {
                      if (!controller.isTaskView)
                        controller.selectView(WorkspaceView.today);
                    },
                  ),
                  _RailItem(
                    label: '日历',
                    icon: Icons.calendar_month_outlined,
                    selected: controller.view == WorkspaceView.calendar,
                    onTap: () => controller.selectView(WorkspaceView.calendar),
                  ),
                  _RailItem(
                    label: '笔记',
                    icon: Icons.note_alt_outlined,
                    selected: controller.view == WorkspaceView.notes,
                    onTap: () => controller.selectView(WorkspaceView.notes),
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

class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 10),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: tokens.accent.withOpacity(.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '勾',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '打勾',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: widget.selected
                  ? tokens.accentSoft
                  : (hovering
                      ? tokens.content.withOpacity(.65)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 19,
                  color: widget.selected ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.selected
                          ? tokens.accent
                          : tokens.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
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

/// The task-specific second-level navigation mirrors the web task workspace.
/// It stays separate from [AppRail] so task views can collapse it independently.
class TaskViewSidebar extends StatelessWidget {
  const TaskViewSidebar(
      {super.key, required this.controller, required this.onAddList});

  static const double width = 218;

  final WorkspaceController controller;
  final VoidCallback onAddList;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      width: width,
      color: tokens.inspector,
      padding: const EdgeInsets.fromLTRB(14, 18, 12, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TaskViewGroup(
              label: '任务视图',
              children: [
                _TaskViewItem(
                    controller: controller,
                    view: WorkspaceView.all,
                    label: '所有',
                    hint: '全部任务',
                    icon: Icons.list_alt_outlined),
                _TaskViewItem(
                    controller: controller,
                    view: WorkspaceView.today,
                    label: '今天',
                    hint: '今天截止',
                    icon: Icons.calendar_today_outlined),
                _TaskViewItem(
                    controller: controller,
                    view: WorkspaceView.plan,
                    label: '计划',
                    hint: '未来安排',
                    icon: Icons.calendar_view_week_outlined),
                _TaskViewItem(
                    controller: controller,
                    view: WorkspaceView.inbox,
                    label: '收集箱',
                    hint: '尚未安排',
                    icon: Icons.inbox_outlined),
              ],
            ),
            const SizedBox(height: 19),
            _TaskViewGroup(
              label: '记录',
              children: [
                _TaskViewItem(
                    controller: controller,
                    view: WorkspaceView.completed,
                    label: '已完成',
                    hint: '完成记录',
                    icon: Icons.check_circle_outline_rounded),
              ],
            ),
            const SizedBox(height: 19),
            Row(
              children: [
                Expanded(child: _TaskGroupHeading(label: '清单')),
                AppIconButton(
                    icon: Icons.add,
                    tooltip: '新建清单',
                    size: 28,
                    iconSize: 16,
                    onPressed: onAddList),
              ],
            ),
            const SizedBox(height: 5),
            _TaskViewItem(
                controller: controller,
                view: WorkspaceView.work,
                label: '工作',
                hint: '任务清单',
                icon: Icons.list_alt_outlined),
            _TaskViewItem(
                controller: controller,
                view: WorkspaceView.study,
                label: '学习',
                hint: '任务清单',
                icon: Icons.list_alt_outlined),
            _TaskViewItem(
                controller: controller,
                view: WorkspaceView.personal,
                label: '个人',
                hint: '任务清单',
                icon: Icons.list_alt_outlined),
          ],
        ),
      ),
    );
  }
}

class _TaskViewGroup extends StatelessWidget {
  const _TaskViewGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TaskGroupHeading(label: label),
        const SizedBox(height: 5),
        ...children,
      ],
    );
  }
}

class _TaskGroupHeading extends StatelessWidget {
  const _TaskGroupHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 9),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .45,
        ),
      ),
    );
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
