import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

class WorkspaceSidebar extends StatelessWidget {
  const WorkspaceSidebar({
    super.key,
    required this.controller,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCollapse,
    required this.onOpenSettings,
  });

  final WorkspaceController controller;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onCollapse;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      width: 246,
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        children: [
          _BrandHeader(onCollapse: onCollapse),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SidebarSectionLabel(label: '智能清单'),
                  const SizedBox(height: 5),
                  _SidebarItem(controller: controller, view: WorkspaceView.inbox, label: '收集箱', icon: Icons.inbox_outlined),
                  _SidebarItem(controller: controller, view: WorkspaceView.today, label: '今天', icon: Icons.wb_sunny_outlined),
                  _SidebarItem(controller: controller, view: WorkspaceView.plan, label: '计划', icon: Icons.upcoming_outlined),
                  _SidebarItem(controller: controller, view: WorkspaceView.all, label: '全部任务', icon: Icons.checklist_outlined),
                  _SidebarItem(controller: controller, view: WorkspaceView.completed, label: '已完成', icon: Icons.task_alt_outlined),
                  const SizedBox(height: 20),
                  _SidebarSectionLabel(label: '内容'),
                  const SizedBox(height: 5),
                  _SidebarItem(controller: controller, view: WorkspaceView.calendar, label: '日历', icon: Icons.calendar_month_outlined),
                  _SidebarItem(controller: controller, view: WorkspaceView.notes, label: '笔记', icon: Icons.note_alt_outlined),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: _SidebarSectionLabel(label: '我的清单')),
                      AppIconButton(icon: Icons.add, tooltip: '新建清单', size: 26, iconSize: 16, onPressed: () {}),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _SidebarItem(controller: controller, view: WorkspaceView.work, label: '工作', icon: Icons.circle, iconColor: const Color(0xFF6E62CE)),
                  _SidebarItem(controller: controller, view: WorkspaceView.personal, label: '个人', icon: Icons.circle, iconColor: const Color(0xFF4CA987)),
                ],
              ),
            ),
          ),
          _SeasonalFooter(tokens: tokens),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: tokens.border))),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: _SidebarFooterAction(icon: Icons.tune_outlined, label: '设置', onTap: onOpenSettings),
                ),
                AppIconButton(
                  icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  tooltip: isDark ? '切换浅色' : '切换深色',
                  onPressed: onToggleTheme,
                  size: 30,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 14, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tokens.accent.withOpacity(.95), tokens.accentHover],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: tokens.accent.withOpacity(.22), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: const Center(
                child: Text('勾', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('打勾', style: TextStyle(color: tokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -.25)),
            ),
            AppIconButton(icon: Icons.keyboard_double_arrow_left_rounded, tooltip: '隐藏侧栏', onPressed: onCollapse, size: 30, iconSize: 17),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 2),
      child: Text(
        label,
        style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.controller,
    required this.view,
    required this.label,
    required this.icon,
    this.iconColor,
  });

  final WorkspaceController controller;
  final WorkspaceView view;
  final String label;
  final IconData icon;
  final Color? iconColor;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final selected = widget.controller.view == widget.view;
    final count = widget.controller.countFor(widget.view);
    final iconColor = widget.iconColor ?? (selected ? tokens.accent : tokens.textSecondary);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.label,
        child: GestureDetector(
          onTap: () => widget.controller.selectView(widget.view),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : (hovering ? tokens.content.withOpacity(.62) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: widget.icon == Icons.circle ? 9 : 17, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(color: selected ? tokens.accent : tokens.textSecondary, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
                if (count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(color: selected ? tokens.accent.withOpacity(.12) : tokens.border.withOpacity(.62), borderRadius: BorderRadius.circular(5)),
                    child: Text('$count', textAlign: TextAlign.center, style: TextStyle(color: selected ? tokens.accent : tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooterAction extends StatefulWidget {
  const _SidebarFooterAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarFooterAction> createState() => _SidebarFooterActionState();
}

class _SidebarFooterActionState extends State<_SidebarFooterAction> {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: hovering ? tokens.content.withOpacity(.58) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(widget.icon, size: 17, color: tokens.textSecondary),
              const SizedBox(width: 10),
              Text(widget.label, style: TextStyle(color: tokens.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonalFooter extends StatelessWidget {
  const _SeasonalFooter({required this.tokens});

  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Container(
        height: 68,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: tokens.seasonalSky,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border.withOpacity(.7)),
        ),
        child: Stack(
          children: [
            Positioned(right: 12, top: 9, child: Icon(Icons.wb_sunny_outlined, size: 18, color: tokens.accent.withOpacity(.55))),
            Positioned(left: -10, bottom: -24, child: Container(width: 160, height: 62, decoration: BoxDecoration(color: tokens.accent.withOpacity(.08), borderRadius: BorderRadius.circular(90)))),
            Positioned(left: 12, bottom: 10, child: Text('今天，也值得慢一点。', style: TextStyle(color: tokens.textSecondary, fontSize: 11, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}
