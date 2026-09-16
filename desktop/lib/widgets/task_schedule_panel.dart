import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/domain/task_schedule_settings.dart';
import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'task_editor_glyph.dart';
import 'task_editor_popover.dart';
import 'task_menu_style.dart';
import 'task_menu_glyph.dart';
import 'task_reminder_picker.dart';
import 'task_repeat_picker.dart';

Future<TaskScheduleSettings?> showTaskSchedulePanel(
        BuildContext anchor, TaskItem task) =>
    showTaskEditorPopover<TaskScheduleSettings>(
      anchor,
      width: TaskEditorPopoverStyle.dateWidth,
      maxHeight: 650,
      scrollable: true,
      builder: (_) => TaskSchedulePanel(task: task),
    );

class TaskSchedulePanel extends StatefulWidget {
  const TaskSchedulePanel({super.key, required this.task});
  final TaskItem task;
  @override
  State<TaskSchedulePanel> createState() => _TaskSchedulePanelState();
}

class _TaskSchedulePanelState extends State<TaskSchedulePanel> {
  late DateTime start;
  late DateTime end;
  late DateTime month;
  late bool range;
  late bool timed;
  bool choosingEnd = false;
  bool timeExpanded = false;
  late DateTime? reminder;
  late RecurrenceDraft recurrence;
  late final TextEditingController hour, minute, endHour, endMinute;
  String? error;

  @override
  void initState() {
    super.initState();
    final initial =
        localDateTimeFromStorage(widget.task.dueAt) ?? DateTime.now();
    start = DateUtils.dateOnly(initial);
    final initialEnd = localDateTimeFromStorage(widget.task.dueEndAt) ??
        initial.add(const Duration(hours: 1));
    end = DateUtils.dateOnly(initialEnd);
    month = DateTime(initial.year, initial.month);
    range = widget.task.dueEndAt != null;
    timed = widget.task.scheduledWithTime;
    reminder = localDateTimeFromStorage(widget.task.reminderAt);
    recurrence = RecurrenceDraft(
        type: widget.task.recurrenceType, config: widget.task.recurrenceConfig);
    hour = TextEditingController(
        text: '${timed ? initial.hour : 9}'.padLeft(2, '0'));
    minute = TextEditingController(
        text: '${timed ? initial.minute : 0}'.padLeft(2, '0'));
    endHour = TextEditingController(
        text: '${timed ? initialEnd.hour : 10}'.padLeft(2, '0'));
    endMinute = TextEditingController(
        text: '${timed ? initialEnd.minute : 0}'.padLeft(2, '0'));
  }

  @override
  void dispose() {
    for (final field in [hour, minute, endHour, endMinute]) {
      field.dispose();
    }
    super.dispose();
  }

  void choose(DateTime day) => setState(() {
        if (range && choosingEnd) {
          end = DateUtils.dateOnly(day);
        } else {
          start = DateUtils.dateOnly(day);
          if (end.isBefore(start)) end = start;
          if (range) choosingEnd = true;
        }
        month = DateTime(day.year, day.month);
        error = null;
      });

  DateTime? clock(
      DateTime date, TextEditingController h, TextEditingController m) {
    if (!timed) return DateUtils.dateOnly(date);
    final hours = int.tryParse(h.text), minutes = int.tryParse(m.text);
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        hours > 23 ||
        minutes < 0 ||
        minutes > 59) return null;
    return DateTime(date.year, date.month, date.day, hours, minutes);
  }

  void apply() {
    final from = clock(start, hour, minute);
    final to = range ? clock(end, endHour, endMinute) : null;
    if (from == null || (range && to == null)) {
      setState(() => error = '时间范围为 00:00 至 23:59');
      return;
    }
    if (to != null && to.isBefore(from)) {
      setState(() => error = '结束时间不能早于开始时间');
      return;
    }
    Navigator.of(context).pop(TaskScheduleSettings(
      schedule: TaskScheduleDraft(dueAt: from, hasTime: timed),
      endAt: to,
      reminderAt: reminder,
      recurrence: recurrence,
    ));
  }

  String dateLabel(DateTime date) => '${date.month}月${date.day}日';
  String get recurrenceLabel => switch (recurrence.type) {
        'DAILY' => '每天',
        'WEEKLY' => '每周',
        'MONTHLY' => '每月',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDay = DateTime(month.year, month.month, 1 - month.weekday % 7);
    final text = Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(fontSize: WorkFollowMacTypography.body, height: WorkFollowMacTypography.lineTight, color: colors.textPrimary);
    return Padding(
      key: const ValueKey('task-schedule-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                  color: colors.canvas, borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(2),
              child: Row(children: [
                for (final tab in [false, true])
                  Expanded(
                      child: InkWell(
                    key: ValueKey(
                        tab ? 'schedule-range-tab' : 'schedule-date-tab'),
                    onTap: () => setState(() {
                      range = tab;
                      choosingEnd = false;
                      error = null;
                    }),
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: range == tab
                              ? colors.overlay
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7)),
                      child: Text(tab ? '时间段' : '日期',
                          style: text.copyWith(
                              color: range == tab
                                  ? colors.textPrimary
                                  : colors.textSecondary)),
                    ),
                  )),
              ]),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final shortcut in [
                ('today', '今天', today),
                ('tomorrow', '明天', today.add(const Duration(days: 1))),
                ('next-7', '七天后', today.add(const Duration(days: 7))),
                ('tonight', '今晚', today)
              ])
                Tooltip(
                    message: shortcut.$2,
                    child: InkWell(
                      key: ValueKey('date-shortcut-${shortcut.$2}'),
                      onTap: () {
                        choose(shortcut.$3);
                        if (shortcut.$1 == 'tonight')
                          setState(() {
                            timed = true;
                            hour.text = '20';
                            minute.text = '00';
                          });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                          width: 36,
                          height: 32,
                          child: Center(
                              child: shortcut.$1 == 'tonight'
                                  ? TaskEditorGlyph('moon',
                                      size: 23, color: colors.textSecondary)
                                  : TaskMenuGlyph(shortcut.$1,
                                      size: 23, color: colors.textSecondary))),
                    )),
            ]),
            const SizedBox(height: 8),
            if (range) ...[
              Row(children: [
                for (final isEnd in [false, true])
                  Expanded(
                      child: TextButton(
                    key: ValueKey(
                        isEnd ? 'schedule-range-end' : 'schedule-range-start'),
                    onPressed: () => setState(() {
                      choosingEnd = isEnd;
                      final date = isEnd ? end : start;
                      month = DateTime(date.year, date.month);
                    }),
                    style: TextButton.styleFrom(
                        foregroundColor: choosingEnd == isEnd
                            ? colors.accent
                            : colors.textSecondary),
                    child: Text(
                        '${isEnd ? '结束' : '开始'} ${dateLabel(isEnd ? end : start)}',
                        style: text.copyWith(fontSize: WorkFollowMacTypography.listMeta)),
                  )),
              ]),
            ],
            Row(children: [
              Expanded(
                  child: Text('${month.year}年${month.month}月',
                      style: text.copyWith(fontWeight: WorkFollowMacWeight.semibold))),
              _monthButton(
                  'date-prev-month',
                  '上个月',
                  Icons.chevron_left,
                  () => setState(
                      () => month = DateTime(month.year, month.month - 1))),
              _monthButton(
                  'date-this-month',
                  '回到本月',
                  Icons.circle_outlined,
                  () => setState(
                      () => month = DateTime(today.year, today.month))),
              _monthButton(
                  'date-next-month',
                  '下个月',
                  Icons.chevron_right,
                  () => setState(
                      () => month = DateTime(month.year, month.month + 1))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final day in ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                    child: Center(
                        child: Text(day,
                            style: text.copyWith(
                                fontSize: WorkFollowMacTypography.caption, color: colors.textTertiary))))
            ]),
            const SizedBox(height: 6),
            GridView.builder(
              key: const ValueKey('schedule-calendar'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, mainAxisExtent: 30),
              itemCount: 42,
              itemBuilder: (context, index) {
                final day = firstDay.add(Duration(days: index));
                final selected = DateUtils.isSameDay(day, start) ||
                    (range && DateUtils.isSameDay(day, end));
                final inRange =
                    range && day.isAfter(start) && day.isBefore(end);
                return Container(
                  color: inRange ? colors.accentFaint : Colors.transparent,
                  alignment: Alignment.center,
                  child: SizedBox.square(
                      dimension: 30,
                      child: TextButton(
                        key: ValueKey(
                            'pick-day-${day.year}-${'${day.month}'.padLeft(2, '0')}-${'${day.day}'.padLeft(2, '0')}'),
                        onPressed: () => choose(day),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: const CircleBorder(),
                            backgroundColor: selected
                                ? colors.accent
                                : DateUtils.isSameDay(day, today)
                                    ? colors.accentFaint
                                    : Colors.transparent),
                        child: Text('${day.day}',
                            style: text.copyWith(
                                color: selected
                                    ? Colors.white
                                    : DateUtils.isSameDay(day, today)
                                        ? colors.accent
                                        : day.month == month.month
                                            ? colors.textPrimary
                                            : colors.textTertiary)),
                      )),
                );
              },
            ),
            const SizedBox(height: 12),
            _property(
                'schedule-time',
                '时间',
                Icons.access_time,
                timed ? '${hour.text}:${minute.text}' : '',
                (_) => setState(() => timeExpanded = !timeExpanded)),
            if (timeExpanded)
              Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Column(children: [
                    Row(children: [
                      Text('全天', style: text),
                      const Spacer(),
                      Switch(
                          key: const ValueKey('date-time-toggle'),
                          value: !timed,
                          onChanged: (value) => setState(() => timed = !value))
                    ]),
                    if (timed) ...[
                      _timeRow('开始', hour, minute),
                      if (range) _timeRow('结束', endHour, endMinute),
                    ],
                  ])),
            _property(
                'schedule-reminder',
                '提醒',
                WorkFollowIcons.reminder,
                reminder == null
                    ? ''
                    : '${dateLabel(reminder!)} ${'${reminder!.hour}'.padLeft(2, '0')}:${'${reminder!.minute}'.padLeft(2, '0')}',
                (anchor) async {
              final value = await TaskReminderPicker.show(anchor,
                  value: reminder?.toIso8601String());
              if (mounted && value != null)
                setState(() => reminder = value.date);
            }),
            _property('schedule-repeat', '重复', WorkFollowIcons.repeat,
                recurrenceLabel, (anchor) async {
              final value = await TaskRepeatPicker.show(anchor,
                  task: widget.task.copyWith(
                      dueAt: start.toIso8601String(),
                      recurrenceType: recurrence.type,
                      recurrenceConfig: recurrence.config,
                      clearRecurrenceConfig: recurrence.config == null));
              if (mounted && value != null) setState(() => recurrence = value);
            }),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error!,
                      style:
                          text.copyWith(color: colors.danger, fontSize: WorkFollowMacTypography.supporting))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      key: const ValueKey('date-clear'),
                      onPressed: () => Navigator.of(context)
                          .pop(const TaskScheduleSettings()),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(color: colors.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: text),
                      child: const Text('清除'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      key: const ValueKey('apply-date'),
                      onPressed: apply,
                      style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: text),
                      child: const Text('确定'))),
            ]),
          ]),
    );
  }

  Widget _monthButton(
          String key, String tooltip, IconData icon, VoidCallback onTap) =>
      SizedBox.square(
          dimension: 28,
          child: IconButton(
              key: ValueKey(key),
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              iconSize: key == 'date-this-month' ? 12 : 17,
              onPressed: onTap,
              icon: Icon(icon)));

  Widget _property(String key, String label, IconData icon, String value,
      void Function(BuildContext) onTap) {
    final colors = TaskMenuStyle.colors(context);
    return Builder(
        builder: (anchor) => InkWell(
              key: ValueKey(key),
              onTap: () => onTap(anchor),
              child: SizedBox(
                  height: 36,
                  child: Row(children: [
                    TaskEditorGlyph(
                        switch (key) {
                          'schedule-time' => 'clock',
                          'schedule-reminder' => 'alarm',
                          _ => 'repeat'
                        },
                        size: 18,
                        color: colors.textSecondary),
                    const SizedBox(width: 12),
                    Text(label,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                            fontSize: WorkFollowMacTypography.body,
                            height: WorkFollowMacTypography.lineTight,
                            color: colors.textPrimary)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(value,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: WorkFollowMacTypography.listMeta, color: colors.textTertiary))),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 16, color: colors.textTertiary),
                  ])),
            ));
  }

  Widget _timeRow(
          String label, TextEditingController h, TextEditingController m) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: WorkFollowMacTypography.control)),
          const Spacer(),
          for (final entry in [(h, '小时'), (m, '分钟')])
            SizedBox(
                width: 44,
                child: TextField(
                  key: ValueKey('schedule-$label-${entry.$2}'),
                  controller: entry.$1,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2)
                  ],
                  decoration: InputDecoration(
                      isDense: true,
                      labelText: entry.$2,
                      contentPadding: const EdgeInsets.all(6)),
                  style: const TextStyle(fontSize: WorkFollowMacTypography.control),
                )),
        ]),
      );
}
