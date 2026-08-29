import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

Future<void> showSettingsPanel({required BuildContext context, required VoidCallback onToggleTheme}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '设置',
    barrierColor: Colors.black.withOpacity(.24),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => _SettingsPanel(onToggleTheme: onToggleTheme),
    transitionBuilder: (context, animation, secondaryAnimation, child) => BackdropFilter(filter: ImageFilter.blur(sigmaX: animation.value * 7, sigmaY: animation.value * 7), child: FadeTransition(opacity: animation, child: child)),
  );
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.onToggleTheme});

  final VoidCallback onToggleTheme;

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
          height: 470,
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
                              onToggleTheme: onToggleTheme,
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
                            label: '本地数据',
                            description: '数据保存在本机，不需要网络连接',
                            trailing: SoftPill(
                              label: '本地模式',
                              color: tokens.accentFaint,
                              textColor: tokens.accent,
                              icon: Icons.lock_outline_rounded,
                            ),
                          ),
                          _SettingRow(
                            label: '最近备份',
                            description: '接入本地数据库后可在这里恢复',
                            trailing: Text(
                              '尚未备份',
                              style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '当前为第一轮交互原型，数据库、系统通知和全局快捷键将在下一阶段接入。',
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
  const _SettingsNavItem({required this.icon, required this.label, this.selected = false});

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
  const _SettingRow({required this.label, required this.description, required this.trailing});

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
