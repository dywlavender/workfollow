import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/migration.dart';
import '../services/local_workspace_store.dart';
import '../services/notification_service.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';

enum _ImportMode { merge, replace }

Future<void> showSettingsPanel({
  required BuildContext context,
  required WorkspaceController controller,
  required VoidCallback onToggleTheme,
  required ValueChanged<ThemeMode> onSetThemeMode,
  required ThemeMode themeMode,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '设置',
    barrierColor: Colors.black.withOpacity(.24),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => _SettingsPanel(
      controller: controller,
      onToggleTheme: onToggleTheme,
      onSetThemeMode: onSetThemeMode,
      themeMode: themeMode,
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
  });

  final WorkspaceController controller;
  final VoidCallback onToggleTheme;
  final ValueChanged<ThemeMode> onSetThemeMode;
  final ThemeMode themeMode;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  bool importing = false;
  int page = 0;
  late ThemeMode appearance = widget.themeMode;
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
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 17),
                  _ImportCountRow(label: '任务', count: bundle.tasks.length),
                  _ImportCountRow(label: '笔记', count: bundle.notes.length),
                  _ImportCountRow(label: '清单', count: bundle.lists.length),
                  _ImportCountRow(label: '文件夹', count: bundle.folders.length),
                  const SizedBox(height: 14),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.merge,
                    groupValue: mode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: tokens.accent,
                    title:
                        const Text('合并到本机', style: TextStyle(fontSize: 12.5)),
                    subtitle: const Text('保留本地已有内容，相同 ID 的记录跳过',
                        style: TextStyle(fontSize: 10.5)),
                    onChanged: (value) => setDialogState(() => mode = value!),
                  ),
                  RadioListTile<_ImportMode>(
                    value: _ImportMode.replace,
                    groupValue: mode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: tokens.accent,
                    title:
                        const Text('清空本机后导入', style: TextStyle(fontSize: 12.5)),
                    subtitle: const Text('以文件内容为准，本机当前任务和笔记会被清空',
                        style: TextStyle(fontSize: 10.5)),
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          width: 720,
          height: 520,
          child: Row(children: [
            Material(
                color: tokens.canvas,
                child: Container(
                    width: 165,
                    padding: const EdgeInsets.fromLTRB(12, 22, 12, 14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('设置',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: tokens.textPrimary))),
                          const SizedBox(height: 24),
                          for (var i = 0; i < pages.length; i++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                    dense: true,
                                    selected: page == i,
                                    selectedTileColor: tokens.accentSoft,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(7)),
                                    leading: Icon(
                                        [
                                          Icons.tune,
                                          Icons.notifications_none,
                                          Icons.folder_outlined,
                                          Icons.keyboard_outlined
                                        ][i],
                                        size: 18),
                                    title: Text(pages[i],
                                        style: const TextStyle(fontSize: 13)),
                                    onTap: () => setState(() => page = i))),
                          const Spacer(),
                          Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text('打勾 · 个人版',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: tokens.textTertiary))),
                        ]))),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 18, 24, 24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(pages[page],
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                                tooltip: '关闭',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close, size: 19))
                          ]),
                          const SizedBox(height: 22),
                          Expanded(
                              child: SingleChildScrollView(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                if (page == 0) ...[
                                  const Text('界面模式',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text('选择你习惯的明暗外观。',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: 16),
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: _ModeSegment(
                                          current: appearance,
                                          onSelect: (value) {
                                            setState(() => appearance = value);
                                            widget.onSetThemeMode(value);
                                          })),
                                  const SizedBox(height: 32),
                                  const Text('个人工作空间',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text('任务、笔记与附件保存在这台 Mac。首次使用从空白空间开始。',
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          color: tokens.textSecondary)),
                                ],
                                if (page == 1) ...[
                                  const Text('系统通知',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text('设置任务提醒后，由 macOS 在指定时刻通知你。点击通知可回到任务。',
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: 18),
                                  const Align(
                                      alignment: Alignment.centerLeft,
                                      child: _NotificationStatus()),
                                  const SizedBox(height: 28),
                                  Text('提醒与安排日期是两回事：安排日期决定任务在哪一天显示，提醒决定何时通知。',
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.6,
                                          color: tokens.textTertiary)),
                                ],
                                if (page == 2) ...[
                                  const Text('导入与导出',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 10, runSpacing: 8, children: [
                                    OutlinedButton.icon(
                                        onPressed:
                                            importing ? null : _importData,
                                        icon: const Icon(
                                            Icons.file_open_outlined,
                                            size: 17),
                                        label:
                                            Text(importing ? '读取中…' : '导入文件')),
                                    OutlinedButton.icon(
                                        onPressed: _export,
                                        icon: const Icon(Icons.ios_share,
                                            size: 17),
                                        label: const Text('导出全部数据')),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text('导出文件包含任务、笔记和本地附件，可用于迁移到另一台 Mac。',
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.6,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: 26),
                                  const Text('备份与恢复',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text('每天自动保存一份快照。恢复前会保留当前内容。',
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.6,
                                          color: tokens.textSecondary)),
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 10, runSpacing: 8, children: [
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
                                    '日历 / 笔记': '⌘4 / ⌘5',
                                    '全局快速录入': '⇧⌘Space',
                                    '收起编辑 / 取消弹窗': 'Esc'
                                  }.entries)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        child: Row(children: [
                                          Expanded(
                                              child: Text(entry.key,
                                                  style: const TextStyle(
                                                      fontSize: 13))),
                                          Text(entry.value,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: tokens.textSecondary)),
                                        ])),
                                ],
                                if (importMessage != null ||
                                    importError != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 20),
                                      child: Text(importError ?? importMessage!,
                                          style: TextStyle(
                                              fontSize: 12,
                                              height: 1.5,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.content,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in const [
            (ThemeMode.system, '跟随系统', Icons.computer_outlined),
            (ThemeMode.light, '浅色', Icons.light_mode_outlined),
            (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
          ])
            InkWell(
              onTap: () => onSelect(mode.$1),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: current == mode.$1
                      ? tokens.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(mode.$3,
                        size: 12,
                        color: current == mode.$1
                            ? tokens.accent
                            : tokens.textTertiary),
                    const SizedBox(width: 4),
                    Text(mode.$2,
                        style: TextStyle(
                          color: current == mode.$1
                              ? tokens.accent
                              : tokens.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
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
            fontSize: 11,
          )),
      if (_status == 'notDetermined' || _status == 'denied') ...[
        const SizedBox(width: 8),
        TextButton(
          onPressed:
              _status == 'denied' ? null : (_requesting ? null : _request),
          style: TextButton.styleFrom(
            foregroundColor: tokens.accent,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_status == 'denied' ? '需到系统设置' : '开启通知',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
        ),
      ],
    ]);
  }
}
