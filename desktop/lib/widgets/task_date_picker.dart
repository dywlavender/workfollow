import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';

class TaskDateSelection {
  const TaskDateSelection(this.date, {this.hasTime = false});
  final DateTime? date;
  final bool hasTime;
}

String calendarDateLabel(DateTime? date,
    {bool hasTime = false, String empty = '安排日期'}) {
  if (date == null) return empty;
  final now = DateTime.now();
  final difference = DateTime(date.year, date.month, date.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final day = switch (difference) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ =>
      '${date.year == now.year ? '' : '${date.year} 年 '}${date.month} 月 ${date.day} 日',
  };
  return hasTime
      ? '$day ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : day;
}

Future<TaskDateSelection?> showTaskDatePicker(
  BuildContext anchor, {
  String? value,
  String title = '安排日期',
  bool? hasTime,
  bool reminder = false,
  bool allowTime = true,
}) =>
    showDesktopPopover<TaskDateSelection>(anchor,
        width: 328,
        maxHeight: 590,
        placement: PopoverPlacement.bottomStart,
        focusPolicy: PopoverFocusPolicy.firstItem,
        scrollable: true,
        builder: (_) => TaskDatePicker(
              initialDate: localDateTimeFromStorage(value),
              title: title,
              initialHasTime: hasTime,
              reminder: reminder,
              allowTime: allowTime,
            ));

class TaskDatePicker extends StatefulWidget {
  const TaskDatePicker(
      {super.key,
      this.initialDate,
      this.initialHasTime,
      this.title = '安排日期',
      this.reminder = false,
      this.allowTime = true});
  final DateTime? initialDate;
  final bool? initialHasTime;
  final String title;
  final bool reminder;
  final bool allowTime;

  @override
  State<TaskDatePicker> createState() => _TaskDatePickerState();
}

class _TaskDatePickerState extends State<TaskDatePicker> {
  late DateTime selected;
  late DateTime month;
  late bool timed;
  late final TextEditingController dateText;
  late final TextEditingController hour;
  late final TextEditingController minute;
  String? error;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialDate ?? DateTime.now().add(const Duration(hours: 1));
    selected = DateTime(initial.year, initial.month, initial.day);
    month = DateTime(initial.year, initial.month);
    timed = widget.allowTime &&
        (widget.reminder ||
            (widget.initialHasTime ??
                (widget.initialDate != null &&
                    (initial.hour != 0 || initial.minute != 0))));
    dateText = TextEditingController(text: _iso(selected));
    hour = TextEditingController(
        text: (widget.initialDate?.hour ?? 9).toString().padLeft(2, '0'));
    minute = TextEditingController(
        text: (widget.initialDate?.minute ?? 0).toString().padLeft(2, '0'));
    if (widget.reminder && widget.initialDate == null) {
      hour.text = initial.hour.toString().padLeft(2, '0');
      minute.text = initial.minute.toString().padLeft(2, '0');
    }
  }

  String _iso(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void choose(DateTime date) => setState(() {
        selected = DateTime(date.year, date.month, date.day);
        month = DateTime(date.year, date.month);
        dateText.text = _iso(selected);
        error = null;
      });

  void apply() {
    final text = dateText.text.trim();
    final parsed = DateTime.tryParse(text);
    if (parsed == null || _iso(parsed) != text) {
      setState(() => error = '请输入有效日期，例如 2026-09-18');
      return;
    }
    final h = int.tryParse(hour.text), m = int.tryParse(minute.text);
    if (timed &&
        (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59)) {
      setState(() => error = '时间范围为 00:00 至 23:59');
      return;
    }
    final value = DateTime(
        parsed.year, parsed.month, parsed.day, timed ? h! : 0, timed ? m! : 0);
    if (widget.reminder && !value.isAfter(DateTime.now())) {
      setState(() => error = '提醒时间需要晚于现在');
      return;
    }
    Navigator.of(context).pop(TaskDateSelection(value, hasTime: timed));
  }

  @override
  void dispose() {
    dateText.dispose();
    hour.dispose();
    minute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final today = DateTime.now();
    final leading = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final count = ((leading + days) / 7).ceil() * 7;
    return Padding(
      padding: const EdgeInsets.all(WorkFollowSpacing.md),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: WorkFollowMacTypography.sectionTitle, fontWeight: WorkFollowMacWeight.semibold))),
              TextButton(
                  key: const ValueKey('date-clear'),
                  onPressed: () =>
                      Navigator.of(context).pop(const TaskDateSelection(null)),
                  child: Text(widget.reminder ? '取消提醒' : '清除日期',
                      style: const TextStyle(fontSize: WorkFollowMacTypography.control))),
            ]),
            const SizedBox(height: 8),
            TextField(
                key: const ValueKey('date-input'),
                controller: dateText,
                autofocus: true,
                style: const TextStyle(fontSize: WorkFollowMacTypography.body),
                onSubmitted: (_) => apply(),
                decoration: const InputDecoration(
                    labelText: '日期',
                    hintText: 'YYYY-MM-DD',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              for (final shortcut in <(String, DateTime)>[
                ('今天', today),
                ('明天', today.add(const Duration(days: 1))),
                (
                  '下周一',
                  DateTime(
                      today.year, today.month, today.day + 8 - today.weekday)
                ),
              ]) ...[
                Expanded(
                    child: TextButton(
                        key: ValueKey('date-shortcut-${shortcut.$1}'),
                        onPressed: () => choose(shortcut.$2),
                        style: TextButton.styleFrom(
                            backgroundColor: tokens.canvas,
                            foregroundColor: tokens.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: const Size(
                                0, WorkFollowMetrics.compactButtonHeight)),
                        child: Text(shortcut.$1,
                            style: const TextStyle(fontSize: WorkFollowMacTypography.control)))),
                if (shortcut.$1 != '下周一') const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Text('${month.year} 年 ${month.month} 月',
                      style: const TextStyle(
                          fontSize: WorkFollowMacTypography.sectionTitle, fontWeight: WorkFollowMacWeight.semibold))),
              IconButton(
                  key: const ValueKey('date-prev-month'),
                  tooltip: '上个月',
                  visualDensity: VisualDensity.compact,
                  icon: const AppIcon(WorkFollowIcons.collapse,
                      size: WorkFollowMetrics.headerIcon),
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1))),
              IconButton(
                  key: const ValueKey('date-next-month'),
                  tooltip: '下个月',
                  visualDensity: VisualDensity.compact,
                  icon: const AppIcon(WorkFollowIcons.chevronNext,
                      size: WorkFollowMetrics.headerIcon),
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1))),
            ]),
            Row(children: [
              for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                    child: Center(
                        child: Text(day,
                            style: TextStyle(
                                fontSize: WorkFollowMacTypography.caption, color: tokens.textTertiary))))
            ]),
            const SizedBox(height: 6),
            GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 34,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 2),
                itemCount: count,
                itemBuilder: (context, index) {
                  final day = index - leading + 1;
                  if (day < 1 || day > days) return const SizedBox.shrink();
                  final date = DateTime(month.year, month.month, day);
                  final isSelected = DateUtils.isSameDay(date, selected);
                  return TextButton(
                      key: ValueKey('pick-day-${_iso(date)}'),
                      onPressed: () => choose(date),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          backgroundColor:
                              isSelected ? tokens.accent : Colors.transparent,
                          foregroundColor: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : DateUtils.isSameDay(date, today)
                                  ? tokens.accent
                                  : tokens.textPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  WorkFollowRadii.control))),
                      child:
                          Text('$day', style: const TextStyle(fontSize: WorkFollowMacTypography.listBody)));
                }),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (widget.allowTime)
              Row(children: [
                if (!widget.reminder)
                  SizedBox(
                      width: 26,
                      height: 28,
                      child: Checkbox(
                          key: const ValueKey('date-time-toggle'),
                          value: timed,
                          onChanged: (value) =>
                              setState(() => timed = value!))),
                const SizedBox(width: 5),
                Expanded(
                    child: Text(widget.reminder ? '提醒时间' : '指定时间',
                        style: const TextStyle(fontSize: WorkFollowMacTypography.control))),
                if (timed) ...[
                  _timeField(hour, '小时'),
                  const Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(':')),
                  _timeField(minute, '分钟'),
                ] else
                  Text('全天',
                      style:
                          TextStyle(fontSize: WorkFollowMacTypography.control, color: tokens.textTertiary)),
              ]),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: TextStyle(fontSize: WorkFollowMacTypography.supporting, color: tokens.danger))),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  key: const ValueKey('date-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                  key: const ValueKey('apply-date'),
                  onPressed: apply,
                  child: const Text('确定')),
            ]),
          ]),
    );
  }

  Widget _timeField(TextEditingController controller, String label) => SizedBox(
      width: 43,
      child: TextField(
          controller: controller,
          key: ValueKey('date-$label'),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2)
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: WorkFollowMacTypography.control),
          onSubmitted: (_) => apply(),
          decoration: InputDecoration(
              isDense: true,
              hintText: '00',
              semanticCounterText: label,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: const OutlineInputBorder())));
}
