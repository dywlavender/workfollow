import 'package:flutter/material.dart';

import '../services/focus_timer.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

Future<void> showFocusTimerDialog({
  required BuildContext context,
  required FocusTimerController timer,
  required WorkspaceController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FocusTimerDialog(timer: timer, controller: controller),
  );
}

class _FocusTimerDialog extends StatefulWidget {
  const _FocusTimerDialog({required this.timer, required this.controller});

  final FocusTimerController timer;
  final WorkspaceController controller;

  @override
  State<_FocusTimerDialog> createState() => _FocusTimerDialogState();
}

class _FocusTimerDialogState extends State<_FocusTimerDialog> {
  @override
  void initState() {
    super.initState();
    widget.timer.addListener(_changed);
    if (!widget.timer.hasStarted) {
      widget.timer.setTask(widget.controller.selectedTaskId);
    }
  }

  @override
  void dispose() {
    widget.timer.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final timer = widget.timer;
    final activeTasks =
        widget.controller.activeTasks.where((task) => !task.completed).toList();
    final selectedTaskId =
        activeTasks.any((task) => task.id == timer.taskId) ? timer.taskId : '';
    return AlertDialog(
      title: Row(children: [
        AppIcon(WorkFollowIcons.focus,
            size: WorkFollowMetrics.headerIcon + 2, color: tokens.accent),
        const SizedBox(width: WorkFollowSpacing.space2),
        const Text('专注'),
        const Spacer(),
        if (timer.isRunning)
          Text('进行中',
              style: TextStyle(
                  color: tokens.success,
                  fontSize: WorkFollowMacTypography.caption,
                  fontWeight: WorkFollowMacWeight.semibold)),
      ]),
      content: SizedBox(
        width: FocusTimerMetrics.dialogWidth,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space6),
            decoration: BoxDecoration(
                color: tokens.accentFaint,
                borderRadius: BorderRadius.circular(WorkFollowRadii.card)),
            child: Column(children: [
              Text(timer.display,
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: WorkFollowMacDisplay.timer,
                      fontWeight: WorkFollowMacWeight.regular,
                      letterSpacing: 1.2)),
              const SizedBox(height: WorkFollowSpacing.denseGap),
              Text(timer.isRunning ? '专注中，保持这个节奏' : '选择时长，开始一轮专注',
                  style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.caption)),
            ]),
          ),
          const SizedBox(height: WorkFollowSpacing.statusGap),
          Align(
              alignment: Alignment.centerLeft,
              child: Text('时长',
                  style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.sectionTitle,
                      fontWeight: WorkFollowMacWeight.semibold))),
          const SizedBox(height: WorkFollowSpacing.compactGap),
          Row(children: [
            for (final minutes in const [15, 25, 45])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: minutes == 45 ? WorkFollowSpacing.zero : WorkFollowSpacing.compactGap),
                  child: OutlinedButton(
                    onPressed: timer.isRunning
                        ? null
                        : () => timer.setDuration(minutes),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: timer.durationMinutes == minutes
                          ? tokens.accentSoft
                          : Colors.transparent,
                      side: BorderSide(
                          color: timer.durationMinutes == minutes
                              ? tokens.accent
                              : tokens.border),
                      foregroundColor: timer.durationMinutes == minutes
                          ? tokens.accent
                          : tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space2),
                    ),
                    child: Text('$minutes 分',
                        style: const TextStyle(
                            fontSize: WorkFollowMacTypography.control, fontWeight: WorkFollowMacWeight.semibold)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: WorkFollowSpacing.statusGap),
          Align(
              alignment: Alignment.centerLeft,
              child: Text('关联任务（可选）',
                  style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.sectionTitle,
                      fontWeight: WorkFollowMacWeight.semibold))),
          const SizedBox(height: WorkFollowSpacing.space1),
          DropdownButtonFormField<String>(
            initialValue: selectedTaskId,
            isExpanded: true,
            decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: tokens.overlay,
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(WorkFollowRadii.control),
                    borderSide: BorderSide(color: tokens.border))),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('不关联任务')),
              for (final task in activeTasks)
                DropdownMenuItem<String>(
                    value: task.id,
                    child: Text(task.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: timer.isRunning
                ? null
                : (value) =>
                    timer.setTask(value?.isEmpty == true ? null : value),
          ),
          const SizedBox(height: WorkFollowSpacing.relaxedGap),
          if (timer.hasStarted &&
              !timer.isRunning &&
              timer.remaining > Duration.zero)
            Align(
                alignment: Alignment.centerLeft,
                child: Text('暂停后可以继续这一轮，重置会清除当前进度。',
                    style:
                        TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.supporting))),
        ]),
      ),
      actions: [
        if (timer.hasStarted)
          TextButton(
              onPressed: timer.reset,
              child: Text('重置', style: TextStyle(color: tokens.textTertiary))),
        if (timer.isRunning)
          FilledButton.tonal(onPressed: timer.pause, child: const Text('暂停'))
        else
          FilledButton.icon(
              onPressed: timer.start,
              icon: const AppIcon(WorkFollowIcons.play,
                  size: WorkFollowMetrics.toolbarIcon),
              label: Text(timer.hasStarted ? '继续' : '开始')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭')),
      ],
    );
  }
}

/// Small toolbar affordance; the label changes while a focus session runs so
/// the timer remains discoverable without opening the dialog.
class FocusTimerButton extends StatelessWidget {
  const FocusTimerButton({super.key, required this.timer, required this.onTap});

  final FocusTimerController timer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AnimatedBuilder(
      animation: timer,
      builder: (context, _) => Tooltip(
        message: '专注计时器',
        child: Material(
          color: timer.isRunning ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.compactGap),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(WorkFollowIcons.focus,
                    size: WorkFollowMetrics.toolbarIcon,
                    color:
                        timer.isRunning ? tokens.accent : tokens.textTertiary),
                if (timer.isRunning) ...[
                  const SizedBox(width: WorkFollowSpacing.denseGap),
                  Text(timer.display,
                      style: TextStyle(
                          color: tokens.accent,
                          fontSize: WorkFollowMacTypography.caption,
                          fontWeight: WorkFollowMacWeight.semibold)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
