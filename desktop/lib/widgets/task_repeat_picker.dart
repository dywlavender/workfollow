import 'package:flutter/material.dart';

import '../features/tasks/domain/task_draft.dart';
import '../models/task.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';

class TaskRepeatPicker {
  const TaskRepeatPicker._();

  static Future<RecurrenceDraft?> show(BuildContext anchor,
      {required TaskItem task}) {
    return showDesktopPopover<RecurrenceDraft>(anchor,
        width: 300,
        maxHeight: 290,
        placement: PopoverPlacement.bottomStart,
        focusPolicy: PopoverFocusPolicy.firstItem,
        builder: (_) => _TaskRepeatEditor(task: task));
  }
}

class _TaskRepeatEditor extends StatefulWidget {
  const _TaskRepeatEditor({required this.task});
  final TaskItem task;

  @override
  State<_TaskRepeatEditor> createState() => _TaskRepeatEditorState();
}

class _TaskRepeatEditorState extends State<_TaskRepeatEditor> {
  late String type;
  late int weekday;
  late int day;

  @override
  void initState() {
    super.initState();
    final normalized = RecurrenceDraft(
            type: widget.task.recurrenceType,
            config: widget.task.recurrenceConfig)
        .normalized();
    final fallback =
        localDateTimeFromStorage(widget.task.dueAt) ?? DateTime.now();
    type = normalized.type;
    weekday =
        ((normalized.config?['weekday'] as num?)?.toInt() ?? fallback.weekday)
            .clamp(1, 7)
            .toInt();
    day = ((normalized.config?['dayOfMonth'] as num?)?.toInt() ?? fallback.day)
        .clamp(1, 31)
        .toInt();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(WorkFollowSpacing.md),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('重复任务', style: TextStyle(fontWeight: WorkFollowMacWeight.semibold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: type,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: '频率',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  for (final entry in {
                    'NONE': '不重复',
                    'DAILY': '每天',
                    'WEEKLY': '每周',
                    'MONTHLY': '每月'
                  }.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value))
                ],
                onChanged: (value) => setState(() => type = value!)),
            if (type == 'WEEKLY' || type == 'MONTHLY') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                  key: ValueKey(type),
                  initialValue: type == 'WEEKLY' ? weekday : day,
                  decoration: InputDecoration(
                      labelText: type == 'WEEKLY' ? '星期' : '每月日期',
                      border: const OutlineInputBorder(),
                      isDense: true),
                  items: [
                    for (var i = 1; i <= (type == 'WEEKLY' ? 7 : 31); i++)
                      DropdownMenuItem(
                          value: i,
                          child: Text(type == 'WEEKLY'
                              ? '星期${'一二三四五六日'[i - 1]}'
                              : '$i 日'))
                  ],
                  onChanged: (value) => setState(() {
                        if (type == 'WEEKLY') {
                          weekday = value!;
                        } else {
                          day = value!;
                        }
                      })),
            ],
            const SizedBox(height: 12),
            const Text('完成本次任务后，会自动生成下一次。', style: TextStyle(fontSize: WorkFollowMacTypography.supporting)),
            const SizedBox(height: 16),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                          RecurrenceDraft(
                              type: type,
                              config: type == 'WEEKLY'
                                  ? <String, dynamic>{'weekday': weekday}
                                  : type == 'MONTHLY'
                                      ? <String, dynamic>{'dayOfMonth': day}
                                      : null),
                        ),
                    child: const Text('确定'))),
          ]));
}
