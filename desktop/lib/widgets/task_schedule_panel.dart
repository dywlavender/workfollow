import 'package:flutter/material.dart';

import '../features/tasks/domain/chinese_work_calendar.dart';
import '../features/tasks/domain/recurrence_engine.dart';
import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/domain/task_schedule_settings.dart';
import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_interaction_states.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_editor_glyph.dart';
import 'task_editor_popover.dart';
import 'task_menu_glyph.dart';
import 'task_menu_style.dart';
import 'task_schedule_options.dart';

/// Opens the schedule editor.
///
/// [focusPolicy] defaults to [PopoverFocusPolicy.firstItem] so the panel takes
/// the keyboard when it is opened from the task inspector. Callers that open it
/// from a field being edited (the Quick Add row) pass
/// [PopoverFocusPolicy.preserveEditor] instead: the pointer-down already
/// belongs to that field, and moving focus would end the edit.
Future<TaskScheduleSettings?> showTaskSchedulePanel(
        BuildContext anchor, TaskItem task,
        {PopoverFocusPolicy focusPolicy = PopoverFocusPolicy.firstItem}) =>
    showTaskEditorPopover<TaskScheduleSettings>(anchor,
        width: TaskScheduleMetrics.panelWidth,
        maxHeight: TaskScheduleMetrics.panelMaxHeight,
        scrollable: true,
        focusPolicy: focusPolicy,
        builder: (_) => TaskSchedulePanel(task: task));

class TaskSchedulePanel extends StatefulWidget {
  const TaskSchedulePanel({super.key, required this.task});
  final TaskItem task;
  @override
  State<TaskSchedulePanel> createState() => _TaskSchedulePanelState();
}

class _TaskSchedulePanelState extends State<TaskSchedulePanel> {
  late DateTime start, end, month;
  late bool range, timed;
  bool choosingEnd = false;
  late TimeOfDay time, endTime;
  late List<int> offsets;
  DateTime? legacyReminder;
  late RecurrenceDraft recurrence;
  String? error;

  @override
  void initState() {
    super.initState();
    final initial =
        localDateTimeFromStorage(widget.task.dueAt) ?? DateTime.now();
    final until = localDateTimeFromStorage(widget.task.dueEndAt) ??
        initial.add(const Duration(hours: 1));
    start = DateUtils.dateOnly(initial);
    end = DateUtils.dateOnly(until);
    month = DateTime(initial.year, initial.month);
    range = widget.task.dueEndAt != null;
    timed = widget.task.scheduledWithTime;
    time = timed
        ? TimeOfDay.fromDateTime(initial)
        : const TimeOfDay(hour: 9, minute: 0);
    endTime = timed
        ? TimeOfDay.fromDateTime(until)
        : const TimeOfDay(hour: 10, minute: 0);
    offsets = List.of(widget.task.reminderOffsets);
    legacyReminder = localDateTimeFromStorage(widget.task.reminderAt);
    if (offsets.isEmpty &&
        legacyReminder != null &&
        widget.task.dueAt != null) {
      final base = timed
          ? initial
          : DateTime(initial.year, initial.month, initial.day, 9);
      final difference = base.difference(legacyReminder!);
      if (!difference.isNegative && difference.inSeconds % 60 == 0) {
        offsets = [difference.inMinutes];
        legacyReminder = null;
      }
    }
    recurrence = RecurrenceDraft(
            type: widget.task.recurrenceType,
            config: widget.task.recurrenceConfig)
        .normalized();
  }

  void choose(DateTime day) => setState(() {
        if (range && choosingEnd) {
          end = DateUtils.dateOnly(day);
        } else {
          start = DateUtils.dateOnly(day);
          if (end.isBefore(start)) end = start;
          if (range) choosingEnd = true;
          final config = Map<String, dynamic>.of(recurrence.config ?? {});
          if (recurrence.type == 'WEEKLY') config['weekday'] = day.weekday;
          if (recurrence.type == 'MONTHLY' || recurrence.type == 'YEARLY')
            config['dayOfMonth'] = day.day;
          if (recurrence.type == 'YEARLY') config['month'] = day.month;
          recurrence = RecurrenceDraft(type: recurrence.type, config: config)
              .normalized();
        }
        month = DateTime(day.year, day.month);
        error = null;
      });

  DateTime clock(DateTime day, TimeOfDay value) => timed
      ? DateTime(day.year, day.month, day.day, value.hour, value.minute)
      : day;

  void apply() {
    final from = clock(start, time), to = range ? clock(end, endTime) : null;
    if (to != null && to.isBefore(from)) {
      setState(() => error = '结束时间不能早于开始时间');
      return;
    }
    final last = DateTime.tryParse('${recurrence.config?['endDate']}');
    if (last != null && last.isBefore(start)) {
      setState(() => error = '重复结束日期不能早于开始日期');
      return;
    }
    Navigator.pop(
        context,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(dueAt: from, hasTime: timed),
            endAt: to,
            reminderAt: offsets.isEmpty ? legacyReminder : null,
            reminderOffsets: offsets,
            recurrence: recurrence));
  }

  Future<void> editTime(BuildContext anchor, {bool isEnd = false}) async {
    final result = await showScheduleOptions<ScheduleTimeResult>(anchor,
        builder: (_) => ScheduleTimeOptions(
            value: timed ? (isEnd ? endTime : time) : null));
    if (mounted && result != null)
      setState(() {
        timed = result.time != null;
        if (result.time != null) {
          if (isEnd) {
            endTime = result.time!;
          } else {
            time = result.time!;
          }
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateTime(month.year, month.month, 1 - month.weekday % 7);
    final previewTask = widget.task.copyWith(
        dueAt: start.toIso8601String(),
        recurrenceType: recurrence.type,
        recurrenceConfig: recurrence.config,
        clearRecurrenceConfig: recurrence.config == null);
    final repeats = RecurrenceEngine.preview(
            previewTask, first.add(const Duration(days: 41)))
        .toSet();
    final text = TextStyle(
        fontSize: WorkFollowMacTypography.body,
        height: WorkFollowMacTypography.lineTight,
        fontWeight: WorkFollowMacWeight.regular,
        letterSpacing: WorkFollowMacTracking.none,
        color: colors.textPrimary);
    return Padding(
        key: const ValueKey('task-schedule-panel'),
        padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space3),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: WorkFollowSpacing.space4),
                  child: Column(children: [
                    Container(
                        decoration: BoxDecoration(
                            color: scheduleFieldBackground(context),
                            borderRadius:
                                BorderRadius.circular(WorkFollowRadii.control)),
                        padding:
                            const EdgeInsets.all(WorkFollowSpacing.microGap),
                        child: Row(children: [
                          for (final tab in [false, true])
                            Expanded(
                                child: InkWell(
                                    key: ValueKey(tab
                                        ? 'schedule-range-tab'
                                        : 'schedule-date-tab'),
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.control),
                                    focusColor:
                                        WorkFollowInteractionStyles.focusColor(
                                            colors),
                                    overlayColor:
                                        WorkFollowInteractionStyles.overlay(
                                            colors,
                                            menu: true),
                                    onTap: () => setState(() {
                                          range = tab;
                                          choosingEnd = false;
                                          error = null;
                                        }),
                                    child: Container(
                                        height: TaskScheduleMetrics.tabHeight,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: range == tab
                                                ? colors.overlay
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                                WorkFollowRadii.control)),
                                        child: Text(tab ? '时间段' : '日期',
                                            style: text.copyWith(
                                                color: range == tab
                                                    ? colors.textPrimary
                                                    : colors.textSecondary))))),
                        ])),
                    const SizedBox(height: WorkFollowSpacing.space5),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final shortcut in [
                            ('today', '今天', today),
                            (
                              'tomorrow',
                              '明天',
                              today.add(const Duration(days: 1))
                            ),
                            (
                              'next-7',
                              '七天后',
                              today.add(const Duration(days: 7))
                            ),
                            ('tonight', '今晚', today),
                          ])
                            Tooltip(
                                message: shortcut.$2,
                                child: InkWell(
                                    key: ValueKey(
                                        'date-shortcut-${shortcut.$2}'),
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.sm),
                                    focusColor: WorkFollowInteractionStyles.focusColor(
                                        colors),
                                    overlayColor: WorkFollowInteractionStyles.overlay(colors,
                                        menu: true),
                                    onTap: () {
                                      choose(shortcut.$3);
                                      if (shortcut.$1 == 'tonight')
                                        setState(() {
                                          timed = true;
                                          time = const TimeOfDay(
                                              hour: 20, minute: 0);
                                        });
                                    },
                                    child: SizedBox(
                                        width: TaskScheduleMetrics
                                            .dateShortcutSize,
                                        height: TaskScheduleMetrics
                                            .dateShortcutSize,
                                        child: Center(
                                            child: (shortcut.$1 == 'tonight' ||
                                                    shortcut.$1 == 'next-7')
                                                ? TaskEditorGlyph(
                                                    shortcut.$1 == 'tonight'
                                                        ? 'moon'
                                                        : 'next-7',
                                                    size: WorkFollowMetrics
                                                        .fieldIcon,
                                                    color: colors.textSecondary)
                                                : TaskMenuGlyph(shortcut.$1,
                                                    size: WorkFollowMetrics.fieldIcon,
                                                    color: colors.textSecondary))))),
                        ]),
                    const SizedBox(height: WorkFollowSpacing.space4),
                    if (range)
                      Row(children: [
                        for (final isEnd in [false, true])
                          Expanded(
                              child: TextButton(
                                  key: ValueKey(isEnd
                                      ? 'schedule-range-end'
                                      : 'schedule-range-start'),
                                  onPressed: () => setState(() {
                                        choosingEnd = isEnd;
                                        final day = isEnd ? end : start;
                                        month = DateTime(day.year, day.month);
                                      }),
                                  child: Text(
                                      '${isEnd ? '结束' : '开始'} ${(isEnd ? end : start).month}月${(isEnd ? end : start).day}日',
                                      style: text.copyWith(
                                          fontSize: WorkFollowMacTypography
                                              .supporting,
                                          color: choosingEnd == isEnd
                                              ? colors.accent
                                              : colors.textSecondary))))
                      ]),
                    Row(children: [
                      Expanded(
                          child: Text('${month.year}年${month.month}月',
                              style: text.copyWith(
                                  fontWeight: WorkFollowMacWeight.semibold))),
                      _monthButton(
                          'date-prev-month',
                          '上个月',
                          WorkFollowIcons.chevronPrevious,
                          () => setState(() =>
                              month = DateTime(month.year, month.month - 1))),
                      _monthButton(
                          'date-this-month',
                          '回到本月',
                          WorkFollowIcons.circle,
                          () => setState(
                              () => month = DateTime(today.year, today.month))),
                      _monthButton(
                          'date-next-month',
                          '下个月',
                          WorkFollowIcons.chevronNext,
                          () => setState(() =>
                              month = DateTime(month.year, month.month + 1))),
                    ]),
                    const SizedBox(height: WorkFollowSpacing.space2),
                    Row(children: [
                      for (final day in ['日', '一', '二', '三', '四', '五', '六'])
                        Expanded(
                            child: Center(
                                child: Text(day,
                                    style: text.copyWith(
                                        fontSize:
                                            WorkFollowMacTypography.caption,
                                        color: colors.textTertiary))))
                    ]),
                    const SizedBox(height: WorkFollowSpacing.space2),
                    GridView.builder(
                        key: const ValueKey('schedule-calendar'),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 42,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7, mainAxisExtent: 30),
                        itemBuilder: (context, index) {
                          final day = first.add(Duration(days: index));
                          final selected = DateUtils.isSameDay(day, start) ||
                              (range && DateUtils.isSameDay(day, end));
                          final future = !selected && repeats.contains(day);
                          final holiday = ChineseWorkCalendar.label(day);
                          final work = ChineseWorkCalendar.overrideFor(day);
                          return Container(
                              color: range &&
                                      day.isAfter(start) &&
                                      day.isBefore(end)
                                  ? colors.accentFaint
                                  : Colors.transparent,
                              child: Stack(clipBehavior: Clip.none, children: [
                                Center(
                                    child: SizedBox.square(
                                        dimension: 30,
                                        child: TextButton(
                                            key: ValueKey(
                                                'pick-day-${day.year}-${'${day.month}'.padLeft(2, '0')}-${'${day.day}'.padLeft(2, '0')}'),
                                            onPressed: () => choose(day),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: const CircleBorder(),
                                              backgroundColor: selected
                                                  ? colors.accent
                                                  : future
                                                      ? colors.accent
                                                          .withValues(
                                                              alpha: .48)
                                                      : DateUtils.isSameDay(
                                                              day, today)
                                                          ? colors.accentFaint
                                                          : Colors.transparent,
                                            ).copyWith(
                                              overlayColor:
                                                  WorkFollowInteractionStyles
                                                      .overlay(
                                                colors,
                                                menu: true,
                                              ),
                                            ),
                                            child: Semantics(
                                                label: future ? '重复日期' : null,
                                                child: Text('${day.day}',
                                                    style: text.copyWith(
                                                        color: selected
                                                            ? Colors.white
                                                            : DateUtils
                                                                    .isSameDay(
                                                                        day,
                                                                        today)
                                                                ? colors.accent
                                                                : day.month ==
                                                                        month
                                                                            .month
                                                                    ? colors
                                                                        .textPrimary
                                                                    : colors
                                                                        .textTertiary)))))),
                                if (holiday != null && !selected)
                                  Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: -1,
                                      child: IgnorePointer(
                                          child: Text(holiday,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize:
                                                      WorkFollowMacTypography
                                                          .calendarAnnotation,
                                                  height: 1,
                                                  color:
                                                      colors.textTertiary)))),
                                if (work != null)
                                  Positioned(
                                      right: -1,
                                      top: 1,
                                      child: IgnorePointer(
                                          child: Container(
                                              width: TaskScheduleMetrics
                                                  .propertyIndicatorSize,
                                              height: TaskScheduleMetrics
                                                  .propertyIndicatorSize,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: work
                                                      ? colors.warning
                                                      : colors.success),
                                              child: Text(work ? '班' : '休',
                                                  style: const TextStyle(
                                                      fontSize:
                                                          WorkFollowMacTypography
                                                              .calendarAnnotation,
                                                      height: 1,
                                                      color: Colors.white))))),
                              ]));
                        }),
                  ])),
              const SizedBox(height: WorkFollowSpacing.space3),
              _property(
                  'schedule-time',
                  'clock',
                  timed ? scheduleClock(time) : '时间',
                  timed,
                  (anchor) => editTime(anchor)),
              if (range)
                _property(
                    'schedule-end-time',
                    'clock',
                    timed ? '结束 ${scheduleClock(endTime)}' : '结束时间',
                    timed,
                    (anchor) => editTime(anchor, isEnd: true)),
              _property(
                  'schedule-reminder',
                  'alarm',
                  offsets.isNotEmpty
                      ? offsets.map(reminderOffsetLabel).join(', ')
                      : legacyReminder != null
                          ? '${legacyReminder!.month}月${legacyReminder!.day}日 ${scheduleClock(TimeOfDay.fromDateTime(legacyReminder!))}'
                          : '提醒',
                  offsets.isNotEmpty || legacyReminder != null, (anchor) async {
                final result = await showScheduleOptions<List<int>>(anchor,
                    maxHeight: TaskScheduleMetrics.reminderMaxHeight,
                    builder: (_) => ScheduleReminderOptions(
                        offsets: offsets, timed: timed));
                if (mounted && result != null)
                  setState(() {
                    offsets = result;
                    legacyReminder = null;
                  });
              }),
              _property(
                  'schedule-repeat',
                  'repeat',
                  scheduleRepeatLabel(recurrence, start),
                  recurrence.type != 'NONE', (anchor) async {
                final result = await showScheduleOptions<RecurrenceDraft>(
                    anchor,
                    builder: (_) =>
                        ScheduleRepeatOptions(rule: recurrence, day: start));
                if (mounted && result != null)
                  setState(() => recurrence = result);
              }),
              if (recurrence.type != 'NONE')
                _property('schedule-repeat-end', 'repeat-end',
                    scheduleEndLabel(recurrence), false, (anchor) async {
                  final result = await showScheduleOptions<RecurrenceDraft>(
                      anchor,
                      maxHeight: TaskScheduleMetrics.repeatEndMaxHeight,
                      builder: (_) =>
                          ScheduleEndOptions(rule: recurrence, day: start));
                  if (mounted && result != null)
                    setState(() => recurrence = result);
                }),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: WorkFollowSpacing.space4),
                    child: Text(error!,
                        style: text.copyWith(
                            color: colors.danger,
                            fontSize: WorkFollowMacTypography.supporting))),
              const SizedBox(height: WorkFollowSpacing.relaxedGap),
              Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: WorkFollowSpacing.space4),
                  child: Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            key: const ValueKey('date-clear'),
                            onPressed: () => Navigator.pop(
                                context, const TaskScheduleSettings()),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: colors.textPrimary,
                                minimumSize: const Size(0, 28),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(color: colors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.control)),
                                textStyle: text),
                            child: const Text('清除'))),
                    const SizedBox(width: WorkFollowSpacing.space2),
                    Expanded(
                        child: FilledButton(
                            key: const ValueKey('apply-date'),
                            onPressed: apply,
                            style: FilledButton.styleFrom(
                                backgroundColor: colors.accent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 28),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.control)),
                                textStyle: text),
                            child: const Text('确定'))),
                  ])),
            ]));
  }

  Widget _monthButton(
          String key, String tooltip, IconData icon, VoidCallback onTap) =>
      SizedBox.square(
          dimension: 24,
          child: IconButton(
              key: ValueKey(key),
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              iconSize: key == 'date-this-month'
                  ? WorkFollowMetrics.metadataIcon
                  : WorkFollowMetrics.compactFieldIcon,
              onPressed: onTap,
              icon: AppIcon(icon,
                  size: key == 'date-this-month'
                      ? WorkFollowMetrics.metadataIcon
                      : WorkFollowMetrics.compactFieldIcon)));

  Widget _property(String key, String icon, String label, bool selected,
      void Function(BuildContext) onTap) {
    final colors = TaskMenuStyle.colors(context);
    return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space1),
        child: Builder(
            builder: (anchor) => InkWell(
                key: ValueKey(key),
                borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                focusColor: WorkFollowInteractionStyles.focusColor(colors),
                overlayColor: WorkFollowInteractionStyles.overlay(
                  colors,
                  menu: true,
                ),
                onTap: () => onTap(anchor),
                child: SizedBox(
                    height: TaskScheduleMetrics.propertyRowHeight,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: WorkFollowSpacing.relaxedGap),
                        child: Row(children: [
                          TaskEditorGlyph(icon,
                              size: WorkFollowMetrics.compactFieldIcon,
                              color: selected
                                  ? colors.accent
                                  : colors.textSecondary),
                          const SizedBox(width: WorkFollowSpacing.controlGap),
                          Expanded(
                              child: Text(label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: WorkFollowMacTypography.body,
                                      color: selected
                                          ? colors.accent
                                          : colors.textPrimary))),
                          const SizedBox(width: WorkFollowSpacing.space1),
                          AppIcon(WorkFollowIcons.chevronNext,
                              size: WorkFollowMetrics.metadataIcon,
                              color: colors.textTertiary),
                        ]))))));
  }
}
