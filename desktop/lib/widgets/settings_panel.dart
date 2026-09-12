import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/migration.dart';
import '../services/local_workspace_store.dart';
import '../services/notification_service.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

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
  String? importMessage;
  String? importError;

  Future<void> _importData() async {
    setState(() {
      importing = true;
      importMessage = null;
      importError = null;
    });
    try {
      final bundle = await LocalWorkspaceStore().pickAndReadMigration();
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

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);

    return Center(
      child: Material(
        color: tokens.overlay,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 650,
          height: 500,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: tokens.borderStrong.withOpacity(.8)),
            boxShadow: [
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 45,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Row(
            children: [
              _SettingsNavigation(tokens: tokens),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(27, 19, 25, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '通用',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _SettingGroup(
                        label: '外观',
                        children: [
                          _SettingRow(
                            label: '界面模式',
                            description: '跟随系统、浅色或深色，重启后保留',
                            trailing: _ModeSegment(
                              current: widget.themeMode,
                              onSelect: widget.onSetThemeMode,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 21),
                      _SettingGroup(
                        label: '提醒',
                        children: [
                          _SettingRow(
                            label: '系统通知',
                            description: '任务到点由系统投递提醒，点击通知打开对应任务',
                            trailing: const _NotificationStatus(),
                          ),
                          _SettingRow(
                            label: '全局快速录入',
                            description: '在任何应用里按 ⇧⌘Space 呼出录入条，Return 保存到收集箱',
                            trailing: SoftPill(
                              label: '⇧⌘Space',
                              color: tokens.accentFaint,
                              textColor: tokens.accent,
                              icon: Icons.keyboard_command_key_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 21),
                      _SettingGroup(
                        label: '数据',
                        children: [
                          _SettingRow(
                            label: '从 Web 导入',
                            description: '选择 .workfollow.json 文件，导入个人任务和笔记',
                            trailing: FilledButton.tonalIcon(
                              onPressed: importing ? null : _importData,
                              icon: importing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.file_open_outlined,
                                      size: 15),
                              label: Text(importing ? '读取中' : '选择文件'),
                            ),
                          ),
                          _SettingRow(
                            label: '本地数据',
                            description: '导入后数据保存在本机，重启应用仍会保留',
                            trailing: SoftPill(
                              label: '本地模式',
                              color: tokens.accentFaint,
                              textColor: tokens.accent,
                              icon: Icons.lock_outline_rounded,
                            ),
                          ),
                          _SettingRow(
                            label: '自动备份',
                            description: '每天首次修改后生成快照副本，保留最近 7 份',
                            trailing: FutureBuilder<WorkspaceBackupInfo>(
                              future: LocalWorkspaceStore().backupInfo(),
                              builder: (context, snapshot) {
                                final info = snapshot.data;
                                final label = info == null || !info.exists
                                    ? '暂无备份'
                                    : '最近 ${info.latestAt!.month} 月 ${info.latestAt!.day} 日';
                                return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(label,
                                          style: TextStyle(
                                            color: tokens.textTertiary,
                                            fontSize: 11,
                                          )),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () async {
                                          await LocalWorkspaceStore()
                                              .backupNow();
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content:
                                                        Text('已创建本机备份副本')));
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: tokens.accent,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 3),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('立即备份',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ]);
                              },
                            ),
                          ),
                        ],
                      ),
                      if (importMessage != null || importError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          importError ?? importMessage!,
                          style: TextStyle(
                            color: importError == null
                                ? tokens.success
                                : tokens.danger,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '迁移范围先覆盖个人任务、清单、笔记和文件夹；附件与团队数据暂不导入。',
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 10.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({required this.tokens});

  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 175,
      color: tokens.inspector,
      padding: const EdgeInsets.fromLTRB(14, 19, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设置',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 23),
          const _SettingsNavItem(
            icon: Icons.tune_rounded,
            label: '通用',
            selected: true,
          ),
          const _SettingsNavItem(
            icon: Icons.palette_outlined,
            label: '外观',
          ),
          const _SettingsNavItem(
            icon: Icons.notifications_none_rounded,
            label: '提醒',
          ),
          const _SettingsNavItem(
            icon: Icons.storage_outlined,
            label: '数据',
          ),
          const _SettingsNavItem(
            icon: Icons.keyboard_command_key_rounded,
            label: '快捷键',
          ),
          const Spacer(),
          Text(
            '打勾 个人版',
            style: TextStyle(
              color: tokens.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem(
      {required this.icon, required this.label, this.selected = false});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? tokens.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: selected ? tokens.accent : tokens.textSecondary,
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              color: selected ? tokens.accent : tokens.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: tokens.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .55,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.inspector,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(
      {required this.label, required this.description, required this.trailing});

  final String label;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
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
