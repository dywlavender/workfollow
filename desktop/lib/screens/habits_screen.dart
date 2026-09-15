import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/list_color.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';

/// A deliberately quiet habit page: today's check-ins are primary, while a
/// 28-day dot history makes consistency visible without introducing badges,
/// levels or social pressure.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final today = habitStartOfDay(DateTime.now());
    final habits = controller.habits;
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(26, 23, 26, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '习惯',
            subtitle: '${today.month} 月 ${today.day} 日 · 把重复的小事变成稳定的节奏。',
            trailing: FilledButton.icon(
              onPressed: () => _showHabitDialog(context, controller),
              icon: const AppIcon(WorkFollowIcons.add,
                  size: WorkFollowMetrics.toolbarIcon),
              label: const Text('新建习惯'),
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 18),
          if (habits.isEmpty)
            Expanded(
              child: Center(
                child: EmptyHint(
                  icon: WorkFollowIcons.habits,
                  title: '从一个小习惯开始',
                  hint: '每天一次、每周几次都可以，记录只保存在这台 Mac 上。',
                  actionLabel: '新建习惯',
                  onAction: () => _showHabitDialog(context, controller),
                ),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 980 ? 2 : 1;
                final width = columns == 2
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final habit in habits)
                        SizedBox(
                          width: width,
                          child: _HabitCard(
                            habit: habit,
                            controller: controller,
                            onEdit: () =>
                                _showHabitDialog(context, controller, habit),
                            onDelete: () =>
                                _confirmDelete(context, controller, habit),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Future<void> _showHabitDialog(
      BuildContext context, WorkspaceController controller,
      [HabitItem? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var icon = existing?.icon ?? 'check';
    var color = existing?.color ?? colorHexFromValue(listColorPalette[4]);
    var schedule =
        Set<int>.from(existing?.schedule ?? const <int>{1, 2, 3, 4, 5, 6, 7});
    final result = await showDialog<_HabitDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final tokens = WorkFollowTheme.of(context);
          return AlertDialog(
            title: Text(existing == null ? '新建习惯' : '编辑习惯'),
            content: SizedBox(
              width: 390,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(
                      labelText: '习惯名称', hintText: '例如：喝水、拉伸、阅读'),
                ),
                const SizedBox(height: 10),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('重复日',
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text(_weekday(day)),
                        selected: schedule.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            schedule.add(day);
                          } else if (schedule.length > 1) {
                            schedule.remove(day);
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                        selectedColor: tokens.accentSoft,
                        checkmarkColor: tokens.accent,
                        labelStyle: TextStyle(
                            color: schedule.contains(day)
                                ? tokens.accent
                                : tokens.textTertiary,
                            fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('颜色',
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 7),
                Row(children: [
                  for (final value in listColorPalette.take(8))
                    InkWell(
                      borderRadius: BorderRadius.circular(WorkFollowRadii.pill),
                      onTap: () =>
                          setState(() => color = colorHexFromValue(value)),
                      child: Container(
                        width: 25,
                        height: 25,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: color == colorHexFromValue(value)
                                ? Border.all(
                                    color: tokens.textPrimary, width: 2)
                                : null),
                      ),
                    ),
                ]),
                const SizedBox(height: 13),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('图标',
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 7),
                Row(children: [
                  for (final candidate in const ['check', 'sun', 'book', 'run'])
                    IconButton(
                      tooltip: _iconLabel(candidate),
                      onPressed: () => setState(() => icon = candidate),
                      icon: AppIcon(_habitIcon(candidate),
                          size: WorkFollowMetrics.navigationIcon,
                          color: icon == candidate
                              ? tokens.accent
                              : tokens.textTertiary),
                    ),
                ]),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(_HabitDraft(
                      name: name.text,
                      icon: icon,
                      color: color,
                      schedule: schedule)),
                  child: Text(existing == null ? '创建' : '保存')),
            ],
          );
        },
      ),
    );
    name.dispose();
    if (!context.mounted || result == null) return;
    if (existing == null) {
      controller.addHabit(result.name,
          icon: result.icon, color: result.color, schedule: result.schedule);
    } else if (!controller.updateHabit(existing.id,
        name: result.name,
        icon: result.icon,
        color: result.color,
        schedule: result.schedule)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称为空或已存在。')));
    }
  }

  Future<void> _confirmDelete(BuildContext context,
      WorkspaceController controller, HabitItem habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除习惯？'),
        content: Text('「${habit.name}」的本地打卡记录也会被移除。'),
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
    if (confirmed == true) controller.removeHabit(habit.id);
  }

  static String _weekday(int day) =>
      const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

  static String _iconLabel(String value) => switch (value) {
        'sun' => '晨间',
        'book' => '阅读',
        'run' => '运动',
        _ => '勾选',
      };

  static IconData _habitIcon(String value) => switch (value) {
        'sun' => WorkFollowIcons.habitSun,
        'book' => WorkFollowIcons.habitBook,
        'run' => WorkFollowIcons.habitRun,
        _ => WorkFollowIcons.check,
      };
}

class _HabitDraft {
  const _HabitDraft(
      {required this.name,
      required this.icon,
      required this.color,
      required this.schedule});

  final String name;
  final String icon;
  final String? color;
  final Set<int> schedule;
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  final HabitItem habit;
  final WorkspaceController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final accent = Color(colorValueFromHex(habit.color) ?? listColorPalette[4]);
    final today = habitStartOfDay(DateTime.now());
    final done = habit.isCompletedOn(today);
    final scheduled = habit.isScheduledOn(today);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(WorkFollowRadii.surface)),
              child: AppIcon(HabitsScreen._habitIcon(habit.icon),
                  size: WorkFollowMetrics.navigationIcon, color: accent)),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(_scheduleLabel(habit.schedule),
                  style: TextStyle(color: tokens.textTertiary, fontSize: 11)),
            ]),
          ),
          AppIconButton(
              icon: WorkFollowIcons.more,
              tooltip: '习惯操作',
              size: WorkFollowMetrics.iconHitTarget,
              iconSize: WorkFollowMetrics.toolbarIcon,
              onPressed: () => _showMenu(context)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: scheduled ? () => controller.toggleHabit(habit.id) : null,
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                    color:
                        done ? accent.withValues(alpha: .14) : tokens.overlay,
                    borderRadius:
                        BorderRadius.circular(WorkFollowRadii.control),
                    border: Border.all(
                        color: done
                            ? accent.withValues(alpha: .45)
                            : tokens.border)),
                child: Row(children: [
                  AppIcon(
                      done ? WorkFollowIcons.success : WorkFollowIcons.circle,
                      size: WorkFollowMetrics.navigationIcon,
                      color: scheduled ? accent : tokens.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                      done
                          ? '今天已完成'
                          : scheduled
                              ? '完成今天'
                              : '今天不安排',
                      style: TextStyle(
                          color: done ? accent : tokens.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                  color: tokens.accentFaint,
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${habit.streak()} 天',
                    style: TextStyle(
                        color: tokens.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                Text('连续',
                    style: TextStyle(color: tokens.textTertiary, fontSize: 11)),
              ])),
        ]),
        const SizedBox(height: 14),
        Text('最近 28 天',
            style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _HabitDots(habit: habit, accent: accent),
      ]),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final action = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(300, 220, 0, 0),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('编辑习惯')),
        PopupMenuItem(value: 'delete', child: Text('删除习惯')),
      ],
    );
    if (!context.mounted) return;
    if (action == 'edit') onEdit();
    if (action == 'delete') onDelete();
  }

  String _scheduleLabel(Set<int> schedule) {
    if (schedule.length == 7) return '每天';
    if (schedule.length == 5 &&
        schedule.contains(1) &&
        schedule.contains(2) &&
        schedule.contains(3) &&
        schedule.contains(4) &&
        schedule.contains(5)) return '工作日';
    final days = schedule.toList()..sort();
    return days
        .map((day) => '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}')
        .join(' · ');
  }
}

class _HabitDots extends StatelessWidget {
  const _HabitDots({required this.habit, required this.accent});

  final HabitItem habit;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final today = habitStartOfDay(DateTime.now());
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var offset = 27; offset >= 0; offset--)
          Builder(builder: (context) {
            final day = today.subtract(Duration(days: offset));
            final completed = habit.isCompletedOn(day);
            final scheduled = habit.isScheduledOn(day);
            final isToday = offset == 0;
            return Tooltip(
              message: '${day.month}月${day.day}日${completed ? ' · 已完成' : ''}',
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                    color: completed
                        ? accent
                        : scheduled
                            ? tokens.borderStrong
                            : tokens.border.withValues(alpha: .35),
                    shape: BoxShape.circle,
                    border: isToday
                        ? Border.all(color: tokens.textPrimary, width: 1.2)
                        : null),
              ),
            );
          }),
      ],
    );
  }
}
