import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/migration.dart';
import '../services/local_workspace_store.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

Future<void> showSettingsPanel({
  required BuildContext context,
  required WorkspaceController controller,
  required VoidCallback onToggleTheme,
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
  });

  final WorkspaceController controller;
  final VoidCallback onToggleTheme;

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
      final confirmed = await _showImportPreview(bundle);
      if (!mounted || confirmed != true) return;
      final summary = await widget.controller.importMigration(bundle);
      if (!mounted) return;
      setState(() {
        importMessage =
            '已导入 ${summary.importedTasks} 个任务、${summary.importedNotes} 条笔记。${summary.skippedTasks + summary.skippedNotes > 0 ? '重复记录已保留本地版本。' : ''}';
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

  Future<bool?> _showImportPreview(MigrationBundle bundle) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final tokens = WorkFollowTheme.of(dialogContext);
        return AlertDialog(
          title: const Text('导入个人数据'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '文件来自 Web 端个人空间，确认后会合并到本机。',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 17),
                _ImportCountRow(label: '任务', count: bundle.tasks.length),
                _ImportCountRow(label: '笔记', count: bundle.notes.length),
                _ImportCountRow(label: '清单', count: bundle.lists.length),
                _ImportCountRow(label: '文件夹', count: bundle.folders.length),
                const SizedBox(height: 14),
                Text(
                  '团队数据、协作关系和附件不在本次迁移范围内。已有相同 ID 的本地记录会保留。',
                  style: TextStyle(
                      color: tokens.textTertiary, fontSize: 11, height: 1.45),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认合并'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

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
                            description: '调整工作台的明暗显示',
                            trailing: _ModeSegment(
                              dark: dark,
                              onToggleTheme: widget.onToggleTheme,
                            ),
                          ),
                          _SettingRow(
                            label: '季节氛围',
                            description: '在侧栏和空状态显示低强度插画',
                            trailing: Switch(
                              value: true,
                              onChanged: (_) {},
                              activeColor: tokens.accent,
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
                            label: '最近备份',
                            description: '迁移文件会自动保存为本机快照',
                            trailing: Text(
                              widget.controller.restoredFromDisk
                                  ? '已保存'
                                  : '等待导入',
                              style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: 11,
                              ),
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
  const _ModeSegment({required this.dark, required this.onToggleTheme});

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);

    return GestureDetector(
      onTap: onToggleTheme,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 13,
              color: tokens.accent,
            ),
            const SizedBox(width: 5),
            Text(
              dark ? '深色' : '浅色',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
