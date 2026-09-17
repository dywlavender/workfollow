import 'package:flutter/material.dart';

import '../widgets/app_icon_button.dart';
import 'workfollow_icons.dart';
import 'workfollow_surface_tokens.dart';
import 'workfollow_theme.dart';
import 'workfollow_theme_parity.dart';

/// Development-only catalogue for the desktop Design System.
///
/// The gallery is intentionally a plain widget rather than a product route.
/// Tests and a local preview can mount it with [WorkFollowThemeData.light] or
/// [WorkFollowThemeData.dark] to inspect the same roles used by the app.
class WorkFollowDesignSystemGallery extends StatelessWidget {
  const WorkFollowDesignSystemGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(WorkFollowSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Design System Gallery',
                key: const ValueKey('design-gallery-title'),
                style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.pageTitle,
                    fontWeight: WorkFollowMacWeight.semibold,
                    height: WorkFollowMacTypography.lineTight)),
            const SizedBox(height: WorkFollowSpacing.space1),
            Text('D11 · token、组件状态和 Light / Dark 回归目录',
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: WorkFollowMacTypography.supporting,
                    height: WorkFollowMacTypography.lineList)),
            const SizedBox(height: WorkFollowSpacing.space6),
            _section(
              context,
              keyName: 'typography',
              title: 'Typography',
              child: _typography(tokens),
            ),
            _section(
              context,
              keyName: 'colors',
              title: 'Colors',
              child: _colors(tokens),
            ),
            _section(
              context,
              keyName: 'icons',
              title: 'Icons',
              child: _icons(tokens),
            ),
            _section(
              context,
              keyName: 'controls',
              title: 'Controls and states',
              child: _controls(tokens),
            ),
            _section(
              context,
              keyName: 'task-row',
              title: 'TaskRow',
              child: _taskRows(tokens),
            ),
            _section(
              context,
              keyName: 'overlays',
              title: 'Menus, Pickers and Toolbar',
              child: _overlays(tokens),
            ),
            _section(
              context,
              keyName: 'feedback',
              title: 'Dialog and Completion Toast',
              child: _feedback(tokens),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context,
      {required String keyName, required String title, required Widget child}) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      key: ValueKey('design-gallery-section-$keyName'),
      margin: const EdgeInsets.only(bottom: WorkFollowSpacing.space5),
      padding: const EdgeInsets.all(WorkFollowSpacing.space4),
      decoration: WorkFollowSurfaceTokens.card(tokens, elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.sectionTitle,
                  fontWeight: WorkFollowMacWeight.semibold,
                  height: WorkFollowMacTypography.lineControl)),
          const SizedBox(height: WorkFollowSpacing.space3),
          child,
        ],
      ),
    );
  }

  Widget _typography(WorkFollowTheme tokens) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _typeSample('pageTitle', '页面标题', WorkFollowMacTypography.pageTitle,
              WorkFollowMacWeight.semibold, tokens.textPrimary),
          _typeSample(
              'sectionTitle',
              '分组标题',
              WorkFollowMacTypography.sectionTitle,
              WorkFollowMacWeight.semibold,
              tokens.textPrimary),
          _typeSample('listTitle', '任务标题', WorkFollowMacTypography.listTitle,
              WorkFollowMacWeight.semibold, tokens.textPrimary),
          _typeSample('listBody', '任务描述预览', WorkFollowMacTypography.listBody,
              WorkFollowMacWeight.regular, tokens.textSecondary),
          _typeSample(
              'listMeta',
              '日期 · 标签 · 重复',
              WorkFollowMacTypography.listMeta,
              WorkFollowMacWeight.regular,
              tokens.textTertiary),
          _typeSample(
              'documentH1',
              '正文一级标题',
              WorkFollowMacTypography.documentH1,
              WorkFollowMacWeight.semibold,
              tokens.textPrimary),
          _typeSample('body', '正文内容保持系统字体和统一字距。', WorkFollowMacTypography.body,
              WorkFollowMacWeight.regular, tokens.textPrimary),
          _typeSample('caption', '说明文字', WorkFollowMacTypography.caption,
              WorkFollowMacWeight.regular, tokens.textTertiary),
        ],
      );

  Widget _typeSample(String role, String value, double size, FontWeight weight,
          Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: WorkFollowSpacing.space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
                width: WorkFollowSpacing.space8 * 3,
                child: Text(role,
                    style: TextStyle(
                        color: color,
                        fontSize: WorkFollowMacTypography.caption,
                        fontWeight: WorkFollowMacWeight.medium))),
            Expanded(
                child: Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: size,
                        fontWeight: weight,
                        height: WorkFollowMacTypography.lineBody))),
          ],
        ),
      );

  Widget _colors(WorkFollowTheme tokens) => Wrap(
        spacing: WorkFollowSpacing.space3,
        runSpacing: WorkFollowSpacing.space3,
        children: [
          _colorSwatch('canvas', tokens.canvas),
          _colorSwatch('sidebar', tokens.sidebar),
          _colorSwatch('content', tokens.content),
          _colorSwatch('inspector', tokens.inspector),
          _colorSwatch('overlay', tokens.overlay),
          _colorSwatch('accent', tokens.accent),
          _colorSwatch('success', tokens.success),
          _colorSwatch('warning', tokens.warning),
          _colorSwatch('danger', tokens.danger),
          _colorSwatch('menuSelected', tokens.menuSelected),
          _colorSwatch('listRowSelected', tokens.listRowSelected),
        ],
      );

  Widget _colorSwatch(String label, Color color) {
    final foreground = WorkFollowThemeContrast.foregroundOn(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: WorkFollowSpacing.space8 * 3,
          height: WorkFollowMetrics.chipHeight,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
              border: Border.all(color: foreground.withValues(alpha: .18))),
          alignment: Alignment.center,
          child: Text('Aa',
              style: TextStyle(
                  color: foreground,
                  fontSize: WorkFollowMacTypography.control,
                  fontWeight: WorkFollowMacWeight.semibold)),
        ),
        const SizedBox(height: WorkFollowSpacing.space1),
        Text(label,
            style: const TextStyle(
                fontSize: WorkFollowMacTypography.caption,
                fontWeight: WorkFollowMacWeight.medium)),
      ],
    );
  }

  Widget _icons(WorkFollowTheme tokens) {
    const entries = <(String, IconData)>[
      ('complete', WorkFollowIcons.check),
      ('incomplete', WorkFollowIcons.unchecked),
      ('calendar', WorkFollowIcons.calendar),
      ('reminder', WorkFollowIcons.reminder),
      ('repeat', WorkFollowIcons.repeat),
      ('flag', WorkFollowIcons.flag),
      ('tag', WorkFollowIcons.tag),
      ('attachment', WorkFollowIcons.attachment),
      ('subtask', WorkFollowIcons.subtask),
      ('more', WorkFollowIcons.more),
      ('close', WorkFollowIcons.close),
      ('undo', WorkFollowIcons.undo),
      ('restore', WorkFollowIcons.restore),
      ('delete', WorkFollowIcons.delete),
    ];
    return Wrap(
      spacing: WorkFollowSpacing.space4,
      runSpacing: WorkFollowSpacing.space3,
      children: [
        for (final (label, icon) in entries)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon,
                  size: WorkFollowMetrics.headerIcon,
                  color: tokens.textSecondary,
                  semanticLabel: label),
              const SizedBox(height: WorkFollowSpacing.space1),
              Text(label,
                  style: const TextStyle(
                      fontSize: WorkFollowMacTypography.caption,
                      fontWeight: WorkFollowMacWeight.regular)),
            ],
          ),
      ],
    );
  }

  Widget _controls(WorkFollowTheme tokens) => Wrap(
        spacing: WorkFollowSpacing.space3,
        runSpacing: WorkFollowSpacing.space3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () {},
            icon: AppIcon(WorkFollowIcons.add,
                size: WorkFollowMetrics.toolbarIcon,
                color: WorkFollowThemeContrast.foregroundOn(tokens.accent)),
            label: const Text('主要操作'),
          ),
          OutlinedButton(onPressed: () {}, child: const Text('次要操作')),
          TextButton(onPressed: () {}, child: const Text('文本操作')),
          Checkbox(value: false, onChanged: (_) {}),
          Checkbox(value: true, onChanged: (_) {}),
          const SoftPill(label: '标签', icon: WorkFollowIcons.tag),
          const SoftPill(label: '禁用', icon: WorkFollowIcons.close),
        ],
      );

  Widget _taskRows(WorkFollowTheme tokens) => Column(
        children: [
          _taskRow(tokens, '默认任务', tokens.content, false),
          const SizedBox(height: WorkFollowSpacing.space1),
          _taskRow(tokens, 'Hover / Selected 任务', tokens.listRowSelected, true),
          const SizedBox(height: WorkFollowSpacing.space1),
          _taskRow(tokens, '已完成任务', tokens.content, false, completed: true),
        ],
      );

  Widget _taskRow(
      WorkFollowTheme tokens, String title, Color background, bool selected,
      {bool completed = false}) {
    final titleColor = completed ? tokens.textTertiary : tokens.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WorkFollowSpacing.taskRowHorizontalPadding,
          vertical: WorkFollowSpacing.taskRowVerticalPadding),
      decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: selected
              ? Border.all(color: tokens.borderStrong)
              : Border.fromBorderSide(BorderSide.none)),
      child: Row(
        children: [
          Checkbox(value: completed, onChanged: (_) {}),
          const SizedBox(width: TaskListMetrics.checkboxTitleGap),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: titleColor,
                        fontSize: WorkFollowMacTypography.listTitle,
                        fontWeight: WorkFollowMacWeight.semibold,
                        decoration:
                            completed ? TextDecoration.lineThrough : null)),
                Text('描述 · 日期 · 标签',
                    style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: WorkFollowMacTypography.listMeta)),
              ])),
          AppIcon(WorkFollowIcons.calendar,
              size: WorkFollowMetrics.metadataIcon, color: tokens.textTertiary),
        ],
      ),
    );
  }

  Widget _overlays(WorkFollowTheme tokens) => Wrap(
        spacing: WorkFollowSpacing.space5,
        runSpacing: WorkFollowSpacing.space4,
        children: [
          _overlayCard(tokens, 'Context Menu', [
            _menuRow(tokens, WorkFollowIcons.calendar, '截止日期', false),
            _menuRow(tokens, WorkFollowIcons.tag, '标签', true),
            _menuRow(tokens, WorkFollowIcons.delete, '删除', false,
                destructive: true),
          ]),
          _overlayCard(tokens, 'Picker', [
            _menuRow(tokens, WorkFollowIcons.search, '搜索任务', false),
            _menuRow(tokens, WorkFollowIcons.check, '已选择', true),
            _menuRow(tokens, WorkFollowIcons.add, '创建新的', false),
          ]),
          _overlayCard(tokens, 'A Toolbar', [
            Row(mainAxisSize: MainAxisSize.min, children: [
              _toolbarButton(tokens, WorkFollowIcons.bold, selected: true),
              _toolbarButton(tokens, WorkFollowIcons.italic),
              _toolbarButton(tokens, WorkFollowIcons.underline),
              _toolbarButton(tokens, WorkFollowIcons.highlight),
              _toolbarButton(tokens, WorkFollowIcons.link),
            ]),
          ]),
        ],
      );

  Widget _overlayCard(WorkFollowTheme tokens, String title, List<Widget> rows) {
    return Container(
      width: WorkFollowSpacing.space8 * 7,
      padding: const EdgeInsets.all(WorkFollowSpacing.space2),
      decoration: WorkFollowSurfaceTokens.popover(tokens),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.all(WorkFollowSpacing.space2),
              child: Text(title,
                  style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.caption,
                      fontWeight: WorkFollowMacWeight.semibold))),
          ...rows,
        ],
      ),
    );
  }

  Widget _menuRow(
      WorkFollowTheme tokens, IconData icon, String label, bool selected,
      {bool destructive = false}) {
    final color = destructive ? tokens.danger : tokens.textPrimary;
    return Container(
      height: WorkFollowMetrics.menuRowHeight,
      padding: WorkFollowSpacing.menuItemPadding,
      decoration: BoxDecoration(
          color: selected ? tokens.menuSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
      child: Row(children: [
        AppIcon(icon, size: WorkFollowMetrics.toolbarIcon, color: color),
        const SizedBox(width: WorkFollowSpacing.menuItemIconGap),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: WorkFollowMacTypography.menu,
                fontWeight: WorkFollowMacWeight.regular)),
      ]),
    );
  }

  Widget _toolbarButton(WorkFollowTheme tokens, IconData icon,
      {bool selected = false}) {
    return AppIconButton(
      icon: icon,
      active: selected,
      iconSize: WorkFollowMetrics.toolbarIcon,
      size: WorkFollowMetrics.toolbarControlHeight,
      semanticLabel: 'format',
      onPressed: () {},
    );
  }

  Widget _feedback(WorkFollowTheme tokens) => Wrap(
        spacing: WorkFollowSpacing.space5,
        runSpacing: WorkFollowSpacing.space4,
        children: [
          Container(
            width: WorkFollowSpacing.space8 * 8,
            padding: const EdgeInsets.all(WorkFollowSpacing.space4),
            decoration: WorkFollowSurfaceTokens.dialog(tokens),
            child: Text('Dialog surface',
                style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.body)),
          ),
          Container(
            width: WorkFollowSpacing.space8 * 8,
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.space4,
                vertical: WorkFollowSpacing.space3),
            decoration: WorkFollowSurfaceTokens.toast(tokens),
            child: Row(children: [
              Expanded(
                  child: Text('已完成 3 个任务',
                      style: TextStyle(
                          color: tokens.feedbackText,
                          fontSize: WorkFollowMacTypography.feedback))),
              Text('撤销',
                  style: TextStyle(
                      color: tokens.feedbackAction,
                      fontSize: WorkFollowMacTypography.control,
                      fontWeight: WorkFollowMacWeight.semibold)),
            ]),
          ),
        ],
      );
}
