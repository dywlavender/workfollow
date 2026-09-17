import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/migration.dart';
import '../services/local_workspace_store.dart';
import '../services/notification_service.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

enum _ImportMode { merge, replace }

Future<void> showSettingsPanel({
  required BuildContext context,
  required WorkspaceController controller,
  required VoidCallback onToggleTheme,
  required ValueChanged<ThemeMode> onSetThemeMode,
  required ThemeMode themeMode,
  bool compactDensity = false,
  ValueChanged<bool>? onSetDensity,
  bool persistentInspector = true,
  ValueChanged<bool>? onSetPersistentInspector,
  bool completionSound = true,
  ValueChanged<bool>? onSetCompletionSound,
  bool animatedFeedback = true,
  ValueChanged<bool>? onSetAnimatedFeedback,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '设置',
    barrierColor: Colors.black.withValues(alpha: .24),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => _SettingsPanel(
      controller: controller,
      onToggleTheme: onToggleTheme,
      onSetThemeMode: onSetThemeMode,
      themeMode: themeMode,
      compactDensity: compactDensity,
      onSetDensity: onSetDensity,
      persistentInspector: persistentInspector,
      onSetPersistentInspector: onSetPersistentInspector,
      completionSound: completionSound,
      onSetCompletionSound: onSetCompletionSound,
      animatedFeedback: animatedFeedback,
      onSetAnimatedFeedback: onSetAnimatedFeedback,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: animation.value * 7, sigmaY: animation.value * 7),
            child: FadeTransition(opacity: animation, child: child)),
  );
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.controller,
    required this.onToggleTheme,
    required this.onSetThemeMode,
    required this.themeMode,
    this.compactDensity = false,
    this.onSetDensity,
    this.persistentInspector = true,
    this.onSetPersistentInspector,
    this.completionSound = true,
    this.onSetCompletionSound,
    this.animatedFeedback = true,
    this.onSetAnimatedFeedback,
  });

  final WorkspaceController controller;
  final VoidCallback onToggleTheme;
  final ValueChanged<ThemeMode> onSetThemeMode;
  final ThemeMode themeMode;
  final bool compactDensity;
  final ValueChanged<bool>? onSetDensity;
  final bool persistentInspector;
  final ValueChanged<bool>? onSetPersistentInspector;
  final bool completionSound;
  final ValueChanged<bool>? onSetCompletionSound;
  final bool animatedFeedback;
  final ValueChanged<bool>? onSetAnimatedFeedback;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  bool importing = false;
  int page = 0;
  late ThemeMode appearance = widget.themeMode;
  late bool densityCompact = widget.compactDensity;
  late bool inspectorPersistent = widget.persistentInspector;
  late bool completionSound = widget.completionSound;
  late bool animatedFeedback = widget.animatedFeedback;
  String? importMessage;
  String? importError;

  Future<void> _importData() async {
    setState(() {
      importing = true;
      importMessage = null;
      importError = null;
    });
    try {
      final bundle =
          await widget.controller.workspaceStore.pickAndReadMigration();
      if (!mounted || bundle == null) return;
      final mode = await _showImportPreview(bundle);
      if (!mounted || mode == null) return;
      final summary = mode == _ImportMode.replace
          ? await widget.controller.replaceWithMigration(bundle)
          : await widget.controller.importMigration(bundle);
      if (!mounted) return;
      setState(() {
        importMessage = mode == _ImportMode.replace
            ? '已清空本机并导入 ${summary.importedTasks} 个任务、${summary.importedNotes} 条笔记。'
            : '已导入 ${summary.importedTasks} 个任务、${summary.importedNotes} 条笔记。${summary.skippedTasks + summary.skippedNotes > 0 ? '重复记录已保留本地版本。' : ''}';
      });
    } on MigrationFormatException catch (error) {
      if (mounted) setState(() => importError = error.message);
    } on MigrationFileException catch (error) {
      if (mounted) setState(() => importError = error.message);
    } on Object {
      if (mounted) setState(() => importError = '导入失败，请重新导出后再试。');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<_ImportMode?> _showImportPreview(MigrationBundle bundle) {
    _ImportMode mode = _ImportMode.merge;
    return showDialog<_ImportMode>(
      context: context,
      builder: (dialogContext) {
        final tokens = WorkFollowTheme.of(dialogContext);
        return StatefulBuilder(builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('导入个人数据'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '文件来自 Web 端个人空间。',
                    style: TextStyle(color: tokens.textSecondary, fontSize: WorkFollowMacTypography.supporting),
                  ),
                  const SizedBox(height: WorkFollowSpacing.fieldGap),
                  _ImportCountRow(label: '任务', count: bundle.tasks.length),
                  _ImportCountRow(label: '笔记', count: bundle.notes.length),
                  _ImportCountRow(label: '清单', count: bundle.lists.length),
                  _ImportCountRow(label: '文件夹', count: bundle.folders.length),
                  const SizedBox(height: WorkFollowSpacing.relaxedGap),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.merge,
                    groupValue: mode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: tokens.accent,
                    title:
                        const Text('合并到本机', style: TextStyle(fontSize: WorkFollowMacTypography.control)),
                    subtitle: const Text('保留本地已有内容，相同 ID 的记录跳过',
                        style: TextStyle(fontSize: WorkFollowMacTypography.caption)),
                    onChanged: (value) => setDialogState(() => mode = value!),
                  ),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.replace,
                    groupValue: mode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: tokens.accent,
                    title:
                        const Text('清空本机后导入', style: TextStyle(fontSize: WorkFollowMacTypography.control)),
                    subtitle: const Text('以文件内容为准，本机当前任务和笔记会被清空',
                        style: TextStyle(fontSize: WorkFollowMacTypography.caption)),
                    onChanged: (value) => setDialogState(() => mode = value!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(mode),
                child: Text(mode == _ImportMode.replace ? '清空并导入' : '确认合并'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _export() async {
    try {
      await widget.controller.waitForPendingSaves();
      final saved = await widget.controller.workspaceStore
          .exportWorkspace(widget.controller.snapshot);
      if (saved && mounted)
        setState(() {
          importMessage = '已导出任务、笔记和本地附件。';
          importError = null;
        });
    } on Object {
      if (mounted) setState(() => importError = '导出失败，请选择其他保存位置后重试。');
    }
  }

  Future<void> _backup() async {
    await widget.controller.waitForPendingSaves();
    await widget.controller.workspaceStore.save(widget.controller.snapshot);
    await widget.controller.workspaceStore.backupNow();
    if (mounted)
      setState(() {
        importMessage = '已创建备份。';
        importError = null;
      });
  }

  Future<void> _restore() async {
    final backups = await widget.controller.workspaceStore.listBackups();
    if (!mounted) return;
    if (backups.isEmpty) {
      setState(() => importMessage = '还没有可恢复的备份。');
      return;
    }
    final file = await showDialog<File>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
              title: const Text('选择要恢复的备份'),
              children: [
                for (final file in backups.reversed)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(dialogContext).pop(file),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space2),
                        child: Text(file.uri.pathSegments.last)),
                  )
              ],
            ));
    if (file == null || !mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('恢复这份备份？'),
              content: const Text('任务和笔记将恢复到备份时的状态。恢复前会先备份当前内容。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('恢复'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      final bundle = MigrationBundle.fromJsonString(await file.readAsString());
      await widget.controller.replaceWithMigration(bundle);
      if (mounted)
        setState(() {
          importMessage = '已恢复所选备份。';
          importError = null;
        });
    } on Object {
      if (mounted) setState(() => importError = '无法恢复这份备份，请检查文件后重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    const pages = ['通用', '通知', '数据', '快捷键'];
    return Center(
        child: Material(
      color: tokens.content,
      borderRadius: BorderRadius.circular(WorkFollowRadii.popover),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          width: 720,
          height: 520,
          child: Row(children: [
            Material(
                color: tokens.canvas,
                child: Container(
                    width: 165,
                    padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.space3, WorkFollowSpacing.headingGap, WorkFollowSpacing.space3, WorkFollowSpacing.relaxedGap),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space3),
                              child: Text('设置',
                                  style: TextStyle(
                                      fontSize: WorkFollowMacTypography.pageTitle,
                                      fontWeight: WorkFollowMacWeight.semibold,
                                      color: tokens.textPrimary))),
                          const SizedBox(height: WorkFollowSpacing.space6),
                          for (var i = 0; i < pages.length; i++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: WorkFollowSpacing.space1),
                                child: ListTile(
                                    dense: true,
                                    selected: page == i,
                                    selectedTileColor: tokens.accentSoft,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            WorkFollowRadii.control)),
                                    leading: AppIcon(
                                        [
                                          WorkFollowIcons.settings,
                                          WorkFollowIcons.notification,
                                          WorkFollowIcons.folder,
                                          WorkFollowIcons.keyboard
                                        ][i],
                                        size: WorkFollowMetrics.navigationIcon),
                                    title: Text(pages[i],
                                        style: const TextStyle(fontSize: WorkFollowMacTypography.navigation)),
                                    onTap: () => setState(() => page = i))),
                          const Spacer(),
                          Padding(
                              padding: const EdgeInsets.only(left: WorkFollowSpacing.space3),
                              child: Text('打勾 · 个人版',
                                  style: TextStyle(
                                      fontSize: WorkFollowMacTypography.caption,
                                      color: tokens.textTertiary))),
                        ]))),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.space7, WorkFollowSpacing.sectionGap, WorkFollowSpacing.space6, WorkFollowSpacing.space6),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(pages[page],
                                    style: const TextStyle(
                                        fontSize: WorkFollowMacTypography.detailTitle,
                                        fontWeight: WorkFollowMacWeight.semibold))),
                            IconButton(
                                tooltip: '关闭',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const AppIcon(WorkFollowIcons.close,
                                    size: WorkFollowMetrics.headerIcon))
                          ]),
                          const SizedBox(height: WorkFollowSpacing.headingGap),
                          Expanded(
                              child: SingleChildScrollView(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                if (page == 0) ...[
                                  const Text('界面模式',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('选择你习惯的明暗外观。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.space4),
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: _ModeSegment(
                                          current: appearance,
                                          onSelect: (value) {
                                            setState(() => appearance = value);
                                            widget.onSetThemeMode(value);
                                          })),
                                  const SizedBox(height: WorkFollowSpacing.space8),
                                  const Text('列表密度',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('紧凑模式适合长清单；舒适模式保留更多呼吸感。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.space3),
                                  _DensitySegment(
                                      compact: densityCompact,
                                      onSelect: (value) {
                                        setState(() => densityCompact = value);
                                        widget.onSetDensity?.call(value);
                                      }),
                                  const SizedBox(height: WorkFollowSpacing.space6),
                                  const Text('详情面板',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('宽窗口可在右侧常驻显示任务详情；关闭后，点击任务仍会打开详情。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.inlineGap),
                                  SwitchListTile.adaptive(
                                      key: const ValueKey(
                                          'persistent-inspector-switch'),
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: const Text('宽窗常驻详情',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.control)),
                                      subtitle: const Text('仅在宽窗口生效',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.caption)),
                                      value: inspectorPersistent,
                                      activeThumbColor: tokens.accent,
                                      onChanged: (value) {
                                        setState(
                                            () => inspectorPersistent = value);
                                        widget.onSetPersistentInspector
                                            ?.call(value);
                                      }),
                                  const SizedBox(height: WorkFollowSpacing.headingGap),
                                  const Text('个人工作空间',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('任务、笔记与附件保存在这台 Mac。首次使用从空白空间开始。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.space3),
                                  Text('清单颜色可在侧栏清单的 ⋯ 菜单中选择，并会同步到任务行、日历和统计。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textTertiary)),
                                ],
                                if (page == 1) ...[
                                  const Text('系统通知',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('设置任务提醒后，由 macOS 在指定时刻通知你。点击通知可回到任务。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.sectionGap),
                                  const Align(
                                      alignment: Alignment.centerLeft,
                                      child: _NotificationStatus()),
                                  const SizedBox(height: WorkFollowSpacing.space7),
                                  Text('提醒与安排日期是两回事：安排日期决定任务在哪一天显示，提醒决定何时通知。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textTertiary)),
                                  const SizedBox(height: WorkFollowSpacing.space8),
                                  const Text('结果反馈',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('完成任务后会有一条短暂的提示，可以顺手撤销。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  SwitchListTile.adaptive(
                                      key: const ValueKey(
                                          'completion-sound-switch'),
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: const Text('完成提示音',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.control)),
                                      subtitle: const Text('连续完成时 1 秒内只响一次',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.caption)),
                                      value: completionSound,
                                      activeThumbColor: tokens.accent,
                                      onChanged: (value) {
                                        setState(() => completionSound = value);
                                        widget.onSetCompletionSound?.call(value);
                                      }),
                                  SwitchListTile.adaptive(
                                      key: const ValueKey(
                                          'animated-feedback-switch'),
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: const Text('动态反馈',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.control)),
                                      subtitle: const Text('关闭后提示改为淡入淡出',
                                          style: TextStyle(fontSize: WorkFollowMacTypography.caption)),
                                      value: animatedFeedback,
                                      activeThumbColor: tokens.accent,
                                      onChanged: (value) {
                                        setState(() => animatedFeedback = value);
                                        widget.onSetAnimatedFeedback?.call(value);
                                      }),
                                ],
                                if (page == 2) ...[
                                  const Text('导入与导出',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.controlGap),
                                  Wrap(spacing: WorkFollowSpacing.controlGap, runSpacing: WorkFollowSpacing.space2, children: [
                                    OutlinedButton.icon(
                                        onPressed:
                                            importing ? null : _importData,
                                        icon: const AppIcon(
                                            WorkFollowIcons.fileOpen,
                                            size:
                                                WorkFollowMetrics.toolbarIcon),
                                        label:
                                            Text(importing ? '读取中…' : '导入文件')),
                                    OutlinedButton.icon(
                                        onPressed: _export,
                                        icon: const AppIcon(
                                            WorkFollowIcons.export,
                                            size:
                                                WorkFollowMetrics.toolbarIcon),
                                        label: const Text('导出全部数据')),
                                  ]),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('导出文件包含任务、笔记和本地附件，可用于迁移到另一台 Mac。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.pageHorizontalPadding),
                                  const Text('备份与恢复',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.sectionTitle,
                                          fontWeight: WorkFollowMacWeight.semibold)),
                                  const SizedBox(height: WorkFollowSpacing.space2),
                                  Text('每天自动保存一份快照。恢复前会保留当前内容。',
                                      style: TextStyle(
                                          fontSize: WorkFollowMacTypography.supporting,
                                          height: WorkFollowMacTypography.lineControl,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: WorkFollowSpacing.space3),
                                  Wrap(spacing: WorkFollowSpacing.controlGap, runSpacing: WorkFollowSpacing.space2, children: [
                                    OutlinedButton(
                                        onPressed: _backup,
                                        child: const Text('立即备份')),
                                    OutlinedButton(
                                        onPressed: _restore,
                                        child: const Text('恢复备份…')),
                                    TextButton(
                                        onPressed: widget.controller
                                            .workspaceStore.revealDataDirectory,
                                        child: const Text('打开数据文件夹')),
                                  ]),
                                ],
                                if (page == 3) ...[
                                  for (final entry in const {
                                    '新建任务': '⌘N',
                                    '新建笔记': '⇧⌘N',
                                    '搜索任务和笔记': '⌘K',
                                    '设置': '⌘,',
                                    '今天 / 收集箱 / 计划': '⌘1 / ⌘2 / ⌘3',
                                    '日历 / 笔记 / 四象限': '⌘4 / ⌘5 / ⌘6',
                                    '全局快速录入': '⇧⌘Space',
                                    '收起编辑 / 取消弹窗': 'Esc'
                                  }.entries)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: WorkFollowSpacing
                                                .settingsShortcutRowVerticalPadding),
                                        child: Row(children: [
                                          Expanded(
                                              child: Text(entry.key,
                                                  style: const TextStyle(
                                                      fontSize: WorkFollowMacTypography.listBody))),
                                          Text(entry.value,
                                              style: TextStyle(
                                                  fontSize: WorkFollowMacTypography.listBody,
                                                  color: tokens.textSecondary)),
                                        ])),
                                ],
                                if (importMessage != null ||
                                    importError != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: WorkFollowSpacing.space5),
                                      child: Text(importError ?? importMessage!,
                                          style: TextStyle(
                                              fontSize: WorkFollowMacTypography.supporting,
                                              height: WorkFollowMacTypography.lineControl,
                                              color: importError == null
                                                  ? tokens.success
                                                  : tokens.danger))),
                              ]))),
                        ]))),
          ])),
    ));
  }
}

class _ImportCountRow extends StatelessWidget {
  const _ImportCountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space1),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: tokens.textSecondary, fontSize: WorkFollowMacTypography.listMeta)),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: WorkFollowMacTypography.listMeta,
              fontWeight: WorkFollowMacWeight.semibold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.current, required this.onSelect});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WorkFollowSpacing.microGap),
      decoration: BoxDecoration(
        color: tokens.content,
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in const [
            (ThemeMode.system, '跟随系统', WorkFollowIcons.system),
            (ThemeMode.light, '浅色', WorkFollowIcons.lightMode),
            (ThemeMode.dark, '深色', WorkFollowIcons.darkMode),
          ])
            InkWell(
              onTap: () => onSelect(mode.$1),
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.space1),
                decoration: BoxDecoration(
                  color: current == mode.$1
                      ? tokens.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(mode.$3,
                        size: WorkFollowMetrics.metadataIcon,
                        color: current == mode.$1
                            ? tokens.accent
                            : tokens.textTertiary),
                    const SizedBox(width: WorkFollowSpacing.space1),
                    Text(mode.$2,
                        style: TextStyle(
                          color: current == mode.$1
                              ? tokens.accent
                              : tokens.textSecondary,
                          fontSize: WorkFollowMacTypography.control,
                          fontWeight: WorkFollowMacWeight.semibold,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DensitySegment extends StatelessWidget {
  const _DensitySegment({required this.compact, required this.onSelect});

  final bool compact;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WorkFollowSpacing.microGap),
      decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: Border.all(color: tokens.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final option in const [(false, '舒适'), (true, '紧凑')])
          InkWell(
              onTap: () => onSelect(option.$1),
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.controlInset, vertical: WorkFollowSpacing.inlineGap),
                  decoration: BoxDecoration(
                      color: compact == option.$1
                          ? tokens.accentSoft
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(WorkFollowRadii.control)),
                  child: Text(option.$2,
                      style: TextStyle(
                          color: compact == option.$1
                              ? tokens.accent
                              : tokens.textSecondary,
                          fontSize: WorkFollowMacTypography.control,
                          fontWeight: WorkFollowMacWeight.semibold)))),
      ]),
    );
  }
}

/// Shows the live notification authorization status with a one-click enable.
class _NotificationStatus extends StatefulWidget {
  const _NotificationStatus();

  @override
  State<_NotificationStatus> createState() => _NotificationStatusState();
}

class _NotificationStatusState extends State<_NotificationStatus> {
  final NotificationService _notifications = NotificationService();
  String? _status;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await _notifications.authorizationStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    await _notifications.requestPermission();
    await _refresh();
    if (mounted) setState(() => _requesting = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final label = switch (_status) {
      'authorized' => '已授权',
      'denied' => '已在系统设置中关闭',
      'notDetermined' => '尚未授权',
      _ => '检查中…',
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(
            color:
                _status == 'authorized' ? tokens.success : tokens.textTertiary,
            fontSize: WorkFollowMacTypography.caption,
          )),
      if (_status == 'notDetermined' || _status == 'denied') ...[
        const SizedBox(width: WorkFollowSpacing.space2),
        TextButton(
          onPressed:
              _status == 'denied' ? null : (_requesting ? null : _request),
          style: TextButton.styleFrom(
            foregroundColor: tokens.accent,
            padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.inlineGap, vertical: WorkFollowSpacing.tightGap),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_status == 'denied' ? '需到系统设置' : '开启通知',
              style: TextStyle(fontSize: WorkFollowMacTypography.control, fontWeight: WorkFollowMacWeight.semibold)),
        ),
      ],
    ]);
  }
}
