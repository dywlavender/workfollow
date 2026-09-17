import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime month;
  DateTime? selectedDay;
  bool weekView = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstDay.weekday - 1;
    final cellCount = ((leading + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageTopPadding, WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageScreenBottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日历',
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.pageTitle,
                            fontWeight: WorkFollowMacWeight.semibold,
                            height: WorkFollowMacTypography.lineTight,
                            letterSpacing: WorkFollowMacTracking.none)),
                    const SizedBox(height: WorkFollowSpacing.denseGap),
                    Text('把任务放回时间里。',
                        style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: WorkFollowMacTypography.supporting,
                            height: WorkFollowMacTypography.lineList)),
                  ],
                ),
              ),
              AppIconButton(
                  icon: WorkFollowIcons.chevronPrevious,
                  tooltip: '上个月',
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.denseGap),
                  child: Text('${month.year} 年 ${month.month} 月',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: WorkFollowMacTypography.sectionTitle,
                          fontWeight: WorkFollowMacWeight.semibold))),
              AppIconButton(
                  icon: WorkFollowIcons.chevronNext,
                  tooltip: '下个月',
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1))),
              const SizedBox(width: WorkFollowSpacing.space2),
              Material(
                color: tokens.accentFaint,
                borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                child: InkWell(
                  onTap: () => setState(() {
                    month = DateTime(today.year, today.month);
                    selectedDay = DateTime(today.year, today.month, today.day);
                  }),
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal:
                              WorkFollowSpacing.calendarTodayHorizontalPadding,
                          vertical:
                              WorkFollowSpacing.calendarTodayVerticalPadding),
                      child: Text('回到今天',
                          style: TextStyle(
                              color: tokens.accent,
                              fontSize: WorkFollowMacTypography.control,
                              fontWeight: WorkFollowMacWeight.semibold))),
                ),
              ),
              const SizedBox(width: WorkFollowSpacing.space2),
              _CalendarModeSegment(
                  week: weekView,
                  onChanged: (value) => setState(() => weekView = value)),
            ],
          ),
          const SizedBox(height: WorkFollowSpacing.space5),
          if (!weekView) ...[
            Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: WorkFollowMacTypography.caption,
                            fontWeight: WorkFollowMacWeight.semibold,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: WorkFollowSpacing.compactInset),
            Expanded(
              flex: 4,
              child: LayoutBuilder(builder: (context, constraints) {
                final rows = cellCount ~/ 7;
                final available = constraints.maxHeight - 7 * (rows - 1);
                final rowHeight = (available / rows).clamp(1.0, 240.0);
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: rowHeight,
                      mainAxisSpacing: WorkFollowSpacing.compactGap,
                      crossAxisSpacing: WorkFollowSpacing.compactGap),
                  itemCount: cellCount,
                  itemBuilder: (context, index) {
                    final dayNumber = index - leading + 1;
                    final inMonth = dayNumber > 0 && dayNumber <= daysInMonth;
                    if (!inMonth) return const SizedBox.shrink();
                    final date = DateTime(month.year, month.month, dayNumber);
                    final isToday = _sameDay(date, today);
                    final isSelected =
                        selectedDay != null && _sameDay(date, selectedDay!);
                    // Counts come from the real task dates, not the current view.
                    final dayTasks = widget.controller.tasksForDay(date);
                    final count = dayTasks.length;
                    final dayColor = dayTasks.isEmpty
                        ? tokens.accent
                        : Color(widget.controller
                            .colorValueForList(dayTasks.first.listName));
                    return DragTarget<String>(
                      // Dropping an agenda row (or a dragged task id) here
                      // reschedules it to this day, keeping its clock time.
                      onWillAcceptWithDetails: (details) =>
                          details.data.isNotEmpty,
                      onAcceptWithDetails: (details) =>
                          widget.controller.rescheduleTask(details.data, date),
                      builder: (context, candidateData, rejectedData) {
                        final dragActive = candidateData.isNotEmpty;
                        return GestureDetector(
                          onTap: () => setState(() => selectedDay = date),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.compactInset, WorkFollowSpacing.space2, WorkFollowSpacing.space2, WorkFollowSpacing.compactGap),
                            decoration: BoxDecoration(
                                color: dragActive
                                    ? tokens.accentSoft
                                    : (isSelected
                                        ? tokens.accentSoft
                                        : tokens.content),
                                borderRadius:
                                    BorderRadius.circular(WorkFollowRadii.card),
                                border: Border.all(
                                    color: isSelected || dragActive
                                        ? tokens.accent.withValues(alpha: .45)
                                        : tokens.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                        width: CalendarMetrics.dayCellSize,
                                        height: CalendarMetrics.dayCellSize,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: isToday
                                                ? tokens.accent
                                                : Colors.transparent,
                                            shape: BoxShape.circle),
                                        child: Text('$dayNumber',
                                            style: TextStyle(
                                                color: isToday
                                                    ? Colors.white
                                                    : (isSelected
                                                        ? tokens.accent
                                                        : tokens.textSecondary),
                                                fontSize: WorkFollowMacTypography.listBody,
                                                fontWeight: WorkFollowMacWeight.semibold))),
                                    const Spacer(),
                                    if (count > 0)
                                      Container(
                                          width: CalendarMetrics.dayDotSize,
                                          height: CalendarMetrics.dayDotSize,
                                          decoration: BoxDecoration(
                                              color: dayColor,
                                              shape: BoxShape.circle)),
                                  ],
                                ),
                                const Spacer(),
                                if (count > 0)
                                  Text('$count 件任务',
                                      style: TextStyle(
                                          color: tokens.textTertiary,
                                          fontSize: WorkFollowMacTypography.caption,
                                          fontWeight: WorkFollowMacWeight.medium)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }),
            ),
            if (selectedDay != null) ...[
              Container(height: 1, color: tokens.border),
              const SizedBox(height: WorkFollowSpacing.space3),
              _SelectedDayAgenda(
                  controller: widget.controller, day: selectedDay!),
            ],
          ] else
            Expanded(
              child: _WeekCalendar(
                controller: widget.controller,
                anchor: selectedDay ?? DateTime.now(),
                onSelectDay: (day) => setState(() => selectedDay = day),
              ),
            ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CalendarModeSegment extends StatelessWidget {
  const _CalendarModeSegment({required this.week, required this.onChanged});

  final bool week;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WorkFollowSpacing.microGap),
      decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: Border.all(color: tokens.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final option in const [(false, '月'), (true, '周')])
          InkWell(
            onTap: () => onChanged(option.$1),
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.denseGap),
              decoration: BoxDecoration(
                  color: week == option.$1
                      ? tokens.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
              child: Text(option.$2,
                  style: TextStyle(
                      color: week == option.$1
                          ? tokens.accent
                          : tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.control,
                      fontWeight: WorkFollowMacWeight.semibold)),
            ),
          ),
      ]),
    );
  }
}

class _WeekCalendar extends StatelessWidget {
  const _WeekCalendar(
      {required this.controller,
      required this.anchor,
      required this.onSelectDay});

  final WorkspaceController controller;
  final DateTime anchor;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final normalized = DateTime(anchor.year, anchor.month, anchor.day);
    final start = normalized.subtract(Duration(days: normalized.weekday - 1));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: _WeekDayColumn(
              controller: controller,
              day: start.add(Duration(days: index)),
              accent: tokens.accent,
              onSelectDay: onSelectDay,
            ),
          ),
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn(
      {required this.controller,
      required this.day,
      required this.accent,
      required this.onSelectDay});

  final WorkspaceController controller;
  final DateTime day;
  final Color accent;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final today = DateTime.now();
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final tasks = controller.tasksForDay(day);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) =>
          controller.rescheduleTask(details.data, day),
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () => onSelectDay(day),
          child: Container(
            margin: const EdgeInsets.only(right: WorkFollowSpacing.space2),
            padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.compactInset, WorkFollowSpacing.compactInset, WorkFollowSpacing.compactInset, WorkFollowSpacing.space2),
            decoration: BoxDecoration(
                color: active ? tokens.accentSoft : tokens.content,
                borderRadius: BorderRadius.circular(WorkFollowRadii.card),
                border: Border.all(
                    color: active
                        ? tokens.accent.withValues(alpha: .6)
                        : tokens.border)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '周${_weekday(day.weekday)} ${day.month}/${day.day}',
                        style: TextStyle(
                            color: isToday ? accent : tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.sectionTitle,
                            fontWeight: WorkFollowMacWeight.semibold))),
                if (tasks.isNotEmpty)
                  Text('${tasks.length}',
                      style: TextStyle(color: accent, fontSize: WorkFollowMacTypography.caption)),
              ]),
              const SizedBox(height: WorkFollowSpacing.space2),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text('没有安排',
                            style: TextStyle(
                                color: tokens.textTertiary, fontSize: WorkFollowMacTypography.caption)))
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: WorkFollowSpacing.denseGap),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final listColor = Color(
                              controller.colorValueForList(task.listName));
                          return Draggable<String>(
                            data: task.id,
                            feedback: Material(
                              color: Colors.transparent,
                              child: _WeekTaskPill(
                                  task: task, color: listColor, tokens: tokens),
                            ),
                            childWhenDragging: Opacity(
                                opacity: .3,
                                child: _WeekTaskPill(
                                    task: task,
                                    color: listColor,
                                    tokens: tokens)),
                            child: _WeekTaskPill(
                                task: task,
                                color: listColor,
                                tokens: tokens,
                                onTap: () => controller.openTask(task.id)),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  static String _weekday(int value) =>
      const ['一', '二', '三', '四', '五', '六', '日'][value - 1];
}

class _WeekTaskPill extends StatelessWidget {
  const _WeekTaskPill(
      {required this.task,
      required this.color,
      required this.tokens,
      this.onTap});

  final TaskItem task;
  final Color color;
  final WorkFollowTheme tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.compactGap, vertical: WorkFollowSpacing.inlineGap),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            border: Border.all(color: color.withValues(alpha: .34))),
        child: Text(task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color:
                    task.completed ? tokens.textTertiary : tokens.textPrimary,
                fontSize: WorkFollowMacTypography.caption,
                height: WorkFollowMacTypography.lineTight,
                decoration:
                    task.completed ? TextDecoration.lineThrough : null)),
      ),
    );
  }
}

Widget _agendaRow(
    BuildContext context,
    TaskItem task,
    WorkspaceController controller,
    WorkFollowTheme tokens,
    VoidCallback onOpen) {
  final listColor = Color(controller.colorValueForList(task.listName));
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.inlineGap),
        child: Row(
          children: [
            AppIcon(
              task.completed
                  ? WorkFollowIcons.completed
                  : WorkFollowIcons.unchecked,
              size: WorkFollowMetrics.metadataIcon,
              color: task.completed ? tokens.success : listColor,
            ),
            const SizedBox(width: WorkFollowSpacing.compactInset),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      task.completed ? tokens.textTertiary : tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.listTitle,
                  fontWeight: WorkFollowMacWeight.medium,
                  decoration: task.completed
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: WorkFollowSpacing.controlGap),
            Text(
              '${task.listName} · ${task.displayTimeLabel ?? '全天'}',
              style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectedDayAgenda extends StatelessWidget {
  const _SelectedDayAgenda({required this.controller, required this.day});

  final WorkspaceController controller;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks = controller.tasksForDay(day);
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1];
    return SizedBox(
      height: CalendarMetrics.agendaPanelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${day.month} 月 ${day.day} 日 · 星期$weekday · ${tasks.length} 件任务',
            style: TextStyle(
                color: tokens.textPrimary,
                fontSize: WorkFollowMacTypography.sectionTitle,
                fontWeight: WorkFollowMacWeight.semibold),
          ),
          const SizedBox(height: WorkFollowSpacing.space2),
          Expanded(
            child: tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.cardInset),
                    child: Text('这一天没有安排任务。',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: WorkFollowMacTypography.supporting)),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: WorkFollowSpacing.space1),
                        // Dragging an agenda row onto a day cell reschedules
                        // the task to that day.
                        child: Draggable<String>(
                          data: task.id,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: WorkFollowSpacing
                                      .calendarDragFeedbackHorizontalPadding,
                                  vertical: WorkFollowSpacing
                                      .calendarDragFeedbackVerticalPadding),
                              decoration: BoxDecoration(
                                  color: tokens.overlay,
                                  borderRadius: BorderRadius.circular(
                                      WorkFollowRadii.surface),
                                  border: Border.all(
                                      color: tokens.accent.withValues(alpha: .5))),
                              child: Text(task.title,
                                  style: TextStyle(
                                      color: tokens.textPrimary, fontSize: WorkFollowMacTypography.listTitle)),
                            ),
                          ),
                          childWhenDragging: Opacity(
                              opacity: .35,
                              child: _agendaRow(context, task, controller,
                                  tokens, () => controller.openTask(task.id))),
                          child: _agendaRow(context, task, controller, tokens,
                              () => controller.openTask(task.id)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
