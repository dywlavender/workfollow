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
        width: TaskPickerMetrics.repeatPickerWidth,
        maxHeight: TaskPickerMetrics.repeatPickerMaxHeight,
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
      padding: WorkFollowSpacing.popoverPadding,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('重复任务',
                style: TextStyle(fontWeight: WorkFollowMacWeight.semibold)),
            const SizedBox(height: WorkFollowSpacing.space3),
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
                    'MONTHLY': '每月',
                    'YEARLY': '每年',
                    'WEEKDAYS': '每周一至周五',
                    'WEEKENDS': '每周六、周日',
                    'WORKDAYS': '法定工作日',
                    'HOLIDAYS': '法定休息日'
                  }.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value))
                ],
                onChanged: (value) => setState(() => type = value!)),
            if (type == 'WEEKLY' || type == 'MONTHLY') ...[
              const SizedBox(height: WorkFollowSpacing.space3),
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
            const SizedBox(height: WorkFollowSpacing.space3),
            const Text('完成本次任务后，会自动生成下一次。',
                style: TextStyle(fontSize: WorkFollowMacTypography.supporting)),
            const SizedBox(height: WorkFollowSpacing.space4),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                          RecurrenceDraft(type: type, config: {
                            if (widget.task.recurrenceConfig?['endDate'] !=
                                null)
                              'endDate':
                                  widget.task.recurrenceConfig!['endDate'],
                            if (widget.task.recurrenceConfig?['count'] != null)
                              'count': widget.task.recurrenceConfig!['count'],
                            if (type == 'WEEKLY') 'weekday': weekday,
                            if (type == 'MONTHLY' || type == 'YEARLY')
                              'dayOfMonth': day,
                            if (type == 'YEARLY')
                              'month': widget.task.recurrenceConfig?['month'] ??
                                  (localDateTimeFromStorage(
                                              widget.task.dueAt) ??
                                          DateTime.now())
                                      .month,
                          }),
                        ),
                    child: const Text('确定'))),
          ]));
}
