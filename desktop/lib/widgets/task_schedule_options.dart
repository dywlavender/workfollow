import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/tasks/domain/chinese_work_calendar.dart';
import '../features/tasks/domain/task_draft.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_color_tokens.dart';
import '../theme/workfollow_theme_parity.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_editor_glyph.dart';
import 'task_editor_popover.dart';
import 'task_menu_style.dart';

Color scheduleFieldBackground(BuildContext context) =>
    WorkFollowColorTokens.scheduleFieldSurface(
        context, TaskMenuStyle.colors(context));

String scheduleClock(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String reminderOffsetLabel(int minutes) => switch (minutes) {
      0 => '准时',
      _ when minutes % 1440 == 0 => '提前${minutes ~/ 1440}天',
      _ when minutes % 60 == 0 => '提前${minutes ~/ 60}小时',
      _ => '提前$minutes分钟',
    };

String scheduleRepeatLabel(RecurrenceDraft rule, DateTime day) =>
    switch (rule.type) {
      'DAILY' => '每天',
      'WEEKLY' =>
        '每周 (周${'一二三四五六日'[(rule.config?['weekday'] as int? ?? day.weekday) - 1]})',
      'MONTHLY' => '每月 (${rule.config?['dayOfMonth'] ?? day.day}日)',
      'YEARLY' =>
        '每年 (${rule.config?['month'] ?? day.month}月${rule.config?['dayOfMonth'] ?? day.day}日)',
      'WEEKDAYS' => '每周一至周五',
      'WEEKENDS' => '每周六、周日',
      'WORKDAYS' => '法定工作日',
      'HOLIDAYS' => '法定休息日',
      _ => '重复',
    };

String scheduleEndLabel(RecurrenceDraft rule) {
  final date = DateTime.tryParse('${rule.config?['endDate']}');
  if (date != null) return '${date.year}年${date.month}月${date.day}日结束';
  final count = rule.config?['count'];
  return count == null ? '永不结束' : '$count次后结束';
}

/// Child menus start at the property row, so the editable/clearable active row
/// remains interactive while the menu overlays the properties below it.
Future<T?> showScheduleOptions<T>(BuildContext anchor,
    {required WidgetBuilder builder, double maxHeight = 340}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final below = MediaQuery.sizeOf(anchor).height - origin.dy - 12;
  final fits = below >= 160;
  return showTaskEditorPopover<T>(anchor,
      width: box.size.width,
      maxHeight: fits ? math.min(maxHeight, below) : maxHeight,
      anchorRect:
          fits ? Rect.fromLTWH(origin.dx, origin.dy, box.size.width, 0) : null,
      placement: PopoverPlacement(
          preferredSide: fits ? PopoverSide.bottom : PopoverSide.top,
          gap: WorkFollowSpacing.zero,
          allowFlip: false),
      scrollable: true,
      builder: (context) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: TaskMenuStyle.colors(context).accent),
            textSelectionTheme: TextSelectionThemeData(
                cursorColor: TaskMenuStyle.colors(context).accent,
                selectionColor: TaskMenuStyle.colors(context)
                    .accent
                    .withValues(alpha: .25)),
          ),
          child: Builder(builder: builder)));
}

class ScheduleOptionRow extends StatelessWidget {
  const ScheduleOptionRow(
      {super.key,
      required this.label,
      required this.onTap,
      this.selected = false,
      this.arrow = false});
  final String label;
  final VoidCallback onTap;
  final bool selected, arrow;
  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    return InkWell(
        onTap: onTap,
        child: SizedBox(
            height: TaskScheduleMetrics.optionRowHeight,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: WorkFollowSpacing.sectionGap),
                child: Row(children: [
                  Expanded(
                      child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: label.contains(' (')
                                    ? label.split(' (').first
                                    : label),
                            if (label.contains(' ('))
                              TextSpan(
                                  text: ' (${label.split(' (').last}',
                                  style: TextStyle(
                                      color: selected
                                          ? colors.accent
                                          : colors.textTertiary)),
                          ]),
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.body,
                              color: selected
                                  ? colors.accent
                                  : colors.textPrimary))),
                  if (selected || arrow)
                    TaskEditorGlyph(selected ? 'check' : 'chevron',
                        size: WorkFollowMetrics.toolbarIcon,
                        color: selected ? colors.accent : colors.textTertiary),
                ]))));
  }
}

class ScheduleOptionsHeader extends StatelessWidget {
  const ScheduleOptionsHeader(
      {super.key,
      required this.icon,
      required this.child,
      required this.onClear,
      this.active = true,
      this.collapse = false});
  final String icon;
  final Widget child;
  final VoidCallback onClear;
  final bool active, collapse;
  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    return Container(
        height: TaskScheduleMetrics.optionHeaderHeight,
        decoration: BoxDecoration(
            color: scheduleFieldBackground(context),
            borderRadius:
                BorderRadius.circular(TaskScheduleMetrics.optionHeaderRadius)),
        padding: const EdgeInsets.only(
            left: WorkFollowSpacing.relaxedGap,
            right: WorkFollowSpacing.space1),
        child: Row(children: [
          TaskEditorGlyph(icon,
              size: WorkFollowMetrics.compactFieldIcon,
              color: active ? colors.accent : colors.textSecondary),
          const SizedBox(width: WorkFollowSpacing.controlGap),
          Expanded(
              child: DefaultTextStyle(
                  style: TextStyle(
                      fontFamily: WorkFollowMacTypeFamily.ui,
                      fontFamilyFallback: WorkFollowMacTypeFamily.fallback,
                      fontSize: WorkFollowMacTypography.body,
                      height: WorkFollowMacTypography.lineBody,
                      fontWeight: WorkFollowMacWeight.regular,
                      letterSpacing: WorkFollowMacTracking.none,
                      color: active ? colors.accent : colors.textPrimary),
                  child: child)),
          IconButton(
              key: const ValueKey('schedule-option-clear'),
              tooltip: collapse ? '收起' : '清除',
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                  width: TaskScheduleMetrics.optionHeaderClearWidth,
                  height: TaskScheduleMetrics.optionHeaderClearHeight),
              icon: AppIcon(
                  collapse ? WorkFollowIcons.expandMore : WorkFollowIcons.close,
                  size: WorkFollowMetrics.metadataIcon,
                  color: colors.textTertiary))
        ]));
  }
}

class ScheduleOptionButtons extends StatelessWidget {
  const ScheduleOptionButtons({super.key, required this.onConfirm});
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    final text = TextStyle(
        fontSize: WorkFollowMacTypography.body,
        height: WorkFollowMacTypography.lineBody,
        fontWeight: WorkFollowMacWeight.regular,
        letterSpacing: WorkFollowMacTracking.none,
        color: colors.textSecondary);
    final shape = RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(TaskScheduleMetrics.optionButtonRadius));
    return Padding(
        padding: const EdgeInsets.fromLTRB(
            WorkFollowSpacing.sectionGap,
            WorkFollowSpacing.space2,
            WorkFollowSpacing.sectionGap,
            WorkFollowSpacing.space2),
        child: Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      textStyle: text,
                      side: BorderSide(color: colors.border),
                      shape: shape,
                      padding: EdgeInsets.zero,
                      minimumSize:
                          const Size(0, TaskScheduleMetrics.optionButtonHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('取消'))),
          const SizedBox(width: WorkFollowSpacing.space2),
          Expanded(
              child: FilledButton(
                  key: const ValueKey('confirm-schedule-option'),
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          WorkFollowThemeContrast.foregroundOn(colors.accent),
                      textStyle: text,
                      shape: shape,
                      padding: EdgeInsets.zero,
                      minimumSize:
                          const Size(0, TaskScheduleMetrics.optionButtonHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('确定'))),
        ]));
  }
}

class ScheduleTimeResult {
  const ScheduleTimeResult(this.time);
  final TimeOfDay? time;
}

class ScheduleTimeOptions extends StatefulWidget {
  const ScheduleTimeOptions({super.key, this.value});
  final TimeOfDay? value;
  @override
  State<ScheduleTimeOptions> createState() => _ScheduleTimeOptionsState();
}

class _ScheduleTimeOptionsState extends State<ScheduleTimeOptions> {
  late final field = TextEditingController(
      text: scheduleClock(widget.value ?? const TimeOfDay(hour: 9, minute: 0)));
  late final scroll = ScrollController(
      initialScrollOffset:
          ((widget.value?.hour ?? 9) * 2 + (widget.value?.minute ?? 0) ~/ 30)
                  .clamp(0, 40) *
              TaskScheduleMetrics.optionRowHeight);
  String? error;
  @override
  void dispose() {
    field.dispose();
    scroll.dispose();
    super.dispose();
  }

  void submit() {
    final parts = field.text.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (hour == null ||
        minute == null ||
        hour > 23 ||
        minute > 59 ||
        hour < 0 ||
        minute < 0) {
      setState(() => error = '请输入 00:00 至 23:59');
      return;
    }
    Navigator.pop(
        context, ScheduleTimeResult(TimeOfDay(hour: hour, minute: minute)));
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        ScheduleOptionsHeader(
            icon: 'clock',
            onClear: () =>
                Navigator.pop(context, const ScheduleTimeResult(null)),
            child: TextField(
                key: const ValueKey('schedule-time-input'),
                controller: field,
                autofocus: true,
                cursorColor: TaskMenuStyle.colors(context).accent,
                selectionControls: desktopTextSelectionControls,
                style: TextStyle(
                    fontSize: WorkFollowMacTypography.body,
                    color: TaskMenuStyle.colors(context).accent),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
                  LengthLimitingTextInputFormatter(5)
                ],
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onSubmitted: (_) => submit())),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(WorkFollowSpacing.space2),
              child: Text(error!)),
        SizedBox(
            height: TaskScheduleMetrics.timeOptionsHeight,
            child: ListView.builder(
                controller: scroll,
                itemCount: 48,
                padding: const EdgeInsets.symmetric(
                    vertical: WorkFollowSpacing.space1),
                itemExtent: TaskScheduleMetrics.optionRowHeight,
                itemBuilder: (context, index) {
                  final time =
                      TimeOfDay(hour: index ~/ 2, minute: index % 2 * 30);
                  return ScheduleOptionRow(
                      key: ValueKey('time-slot-${scheduleClock(time)}'),
                      label: scheduleClock(time),
                      selected: time == widget.value,
                      onTap: () =>
                          Navigator.pop(context, ScheduleTimeResult(time)));
                })),
      ]);
}

class ScheduleReminderOptions extends StatefulWidget {
  const ScheduleReminderOptions(
      {super.key, required this.offsets, required this.timed});
  final List<int> offsets;
  final bool timed;
  @override
  State<ScheduleReminderOptions> createState() =>
      _ScheduleReminderOptionsState();
}

class _ScheduleReminderOptionsState extends State<ScheduleReminderOptions> {
  late final selected = widget.offsets.toSet();
  bool custom = false;
  String? error;
  int unit = 1;
  final amount = TextEditingController(text: '10');
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  void confirm() {
    if (custom) {
      final value = int.tryParse(amount.text);
      if (value == null || value <= 0) {
        setState(() => error = '请输入大于0的数值');
        return;
      }
      selected.add(value * unit);
    }
    Navigator.pop(context, selected.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final values = {0, 5, 30, 60, 1440, ...widget.offsets}.toList()..sort();
    final chosen = selected.toList()..sort();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScheduleOptionsHeader(
              icon: 'alarm',
              child: Text(
                  chosen.isEmpty
                      ? '提醒'
                      : chosen.map(reminderOffsetLabel).join(', '),
                  overflow: TextOverflow.ellipsis),
              onClear: () => Navigator.pop(context, <int>[])),
          if (!widget.timed)
            const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: WorkFollowSpacing.sectionGap,
                    vertical: WorkFollowSpacing.inlineGap),
                child: Text('全天任务以当天09:00计算提醒',
                    style:
                        TextStyle(fontSize: WorkFollowMacTypography.caption))),
          for (final value in values)
            ScheduleOptionRow(
                key: ValueKey('reminder-offset-$value'),
                label: reminderOffsetLabel(value),
                selected: selected.contains(value),
                onTap: () => setState(() {
                      if (!selected.add(value)) selected.remove(value);
                    })),
          const Divider(height: TaskScheduleMetrics.optionDividerHeight),
          ScheduleOptionRow(
              key: const ValueKey('reminder-custom'),
              label: '自定义',
              onTap: () => setState(() => custom = !custom)),
          if (custom)
            Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: WorkFollowSpacing.sectionGap),
                child: Row(children: [
                  const Text('提前 '),
                  Expanded(
                      child: TextField(
                          key: const ValueKey('reminder-custom-amount'),
                          controller: amount,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              isDense: true, errorText: error))),
                  DropdownButton<int>(
                      value: unit,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('分钟')),
                        DropdownMenuItem(value: 60, child: Text('小时')),
                        DropdownMenuItem(value: 1440, child: Text('天')),
                      ],
                      onChanged: (value) => setState(() => unit = value!)),
                ])),
          ScheduleOptionButtons(onConfirm: confirm),
        ]);
  }
}

class ScheduleRepeatOptions extends StatefulWidget {
  const ScheduleRepeatOptions(
      {super.key, required this.rule, required this.day});
  final RecurrenceDraft rule;
  final DateTime day;
  @override
  State<ScheduleRepeatOptions> createState() => _ScheduleRepeatOptionsState();
}

class _ScheduleRepeatOptionsState extends State<ScheduleRepeatOptions> {
  String? group;
  RecurrenceDraft ruleFor(String type) => RecurrenceDraft(type: type, config: {
        if (widget.rule.config?['endDate'] != null)
          'endDate': widget.rule.config!['endDate'],
        if (widget.rule.config?['count'] != null)
          'count': widget.rule.config!['count'],
        if (type == 'WEEKLY') 'weekday': widget.day.weekday,
        if (type == 'MONTHLY' || type == 'YEARLY') 'dayOfMonth': widget.day.day,
        if (type == 'YEARLY') 'month': widget.day.month,
      }).normalized();
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        ScheduleOptionsHeader(
            icon: 'repeat',
            child: Text(scheduleRepeatLabel(widget.rule, widget.day)),
            onClear: () => Navigator.pop(context, const RecurrenceDraft())),
        if (group != null)
          ScheduleOptionRow(
              label: '‹ 返回', onTap: () => setState(() => group = null)),
        for (final type in group == null
            ? ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']
            : group == 'work'
                ? ['WEEKDAYS', 'WORKDAYS']
                : ['WEEKENDS', 'HOLIDAYS'])
          ScheduleOptionRow(
              key: ValueKey('repeat-$type'),
              label: scheduleRepeatLabel(ruleFor(type), widget.day),
              selected: widget.rule.type == type,
              onTap: () => Navigator.pop(context, ruleFor(type))),
        if (group == null) ...[
          const Divider(height: TaskScheduleMetrics.optionDividerHeight),
          ScheduleOptionRow(
              key: const ValueKey('repeat-workdays'),
              label: '工作日',
              arrow: true,
              onTap: () => setState(() => group = 'work')),
          ScheduleOptionRow(
              key: const ValueKey('repeat-holidays'),
              label: '节假日',
              arrow: true,
              onTap: () => setState(() => group = 'holiday')),
        ] else
          Padding(
              padding: const EdgeInsets.fromLTRB(
                  WorkFollowSpacing.sectionGap,
                  WorkFollowSpacing.inlineGap,
                  WorkFollowSpacing.sectionGap,
                  WorkFollowSpacing.space3),
              child: Text(
                  ChineseWorkCalendar.hasYear(widget.day.year)
                      ? '法定选项包含周末与调休安排。'
                      : '该年份尚无调休数据，法定选项暂按周一至周五／周末计算。',
                  style: TextStyle(
                      fontSize: WorkFollowMacTypography.caption,
                      color: TaskMenuStyle.colors(context).textTertiary))),
        const SizedBox(height: WorkFollowSpacing.inlineGap),
      ]);
}

class ScheduleEndOptions extends StatefulWidget {
  const ScheduleEndOptions({super.key, required this.rule, required this.day});
  final RecurrenceDraft rule;
  final DateTime day;
  @override
  State<ScheduleEndOptions> createState() => _ScheduleEndOptionsState();
}

class _ScheduleEndOptionsState extends State<ScheduleEndOptions> {
  String? edit;
  String? error;
  late DateTime date =
      DateTime.tryParse('${widget.rule.config?['endDate']}') ?? widget.day;
  late final count =
      TextEditingController(text: '${widget.rule.config?['count'] ?? 10}');
  @override
  void dispose() {
    count.dispose();
    super.dispose();
  }

  void apply(String mode) {
    final config = Map<String, dynamic>.of(widget.rule.config ?? {})
      ..remove('endDate')
      ..remove('count');
    if (mode == 'date') config['endDate'] = date.toIso8601String();
    if (mode == 'count') {
      final value = int.tryParse(count.text);
      if (value == null || value < 1) {
        setState(() => error = '次数至少为1');
        return;
      }
      config['count'] = value;
    }
    Navigator.pop(context,
        RecurrenceDraft(type: widget.rule.type, config: config).normalized());
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        ScheduleOptionsHeader(
            icon: 'repeat-end',
            active: false,
            collapse: true,
            child: Text(scheduleEndLabel(widget.rule)),
            onClear: () => Navigator.pop(context)),
        if (edit == null) ...[
          ScheduleOptionRow(
              key: const ValueKey('repeat-end-never'),
              label: '永不结束',
              selected: widget.rule.config?['endDate'] == null &&
                  widget.rule.config?['count'] == null,
              onTap: () => apply('never')),
          ScheduleOptionRow(
              key: const ValueKey('repeat-end-date'),
              label: '按日期结束',
              selected: widget.rule.config?['endDate'] != null,
              onTap: () => setState(() => edit = 'date')),
          ScheduleOptionRow(
              key: const ValueKey('repeat-end-count'),
              label: '按次数结束',
              selected: widget.rule.config?['count'] != null,
              onTap: () => setState(() => edit = 'count')),
          const SizedBox(height: WorkFollowSpacing.inlineGap),
        ] else ...[
          ScheduleOptionRow(
              label: '‹ 返回', onTap: () => setState(() => edit = null)),
          if (edit == 'date')
            CalendarDatePicker(
                initialDate: date.isBefore(widget.day) ? widget.day : date,
                firstDate: widget.day,
                lastDate: DateTime(widget.day.year + 100),
                onDateChanged: (value) => date = value)
          else
            Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: WorkFollowSpacing.sectionGap,
                    vertical: WorkFollowSpacing.space2),
                child: Column(children: [
                  TextField(
                      key: const ValueKey('repeat-end-count-input'),
                      controller: count,
                      autofocus: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: '次数', isDense: true, errorText: error),
                      onSubmitted: (_) => apply('count')),
                  const SizedBox(height: WorkFollowSpacing.inlineGap),
                  const Text('包含当前这一次任务',
                      style:
                          TextStyle(fontSize: WorkFollowMacTypography.caption)),
                ])),
          ScheduleOptionButtons(onConfirm: () => apply(edit!)),
        ]
      ]);
}
