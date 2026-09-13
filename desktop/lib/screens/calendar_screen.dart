import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
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
      padding: const EdgeInsets.fromLTRB(26, 23, 26, 26),
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
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.45)),
                    const SizedBox(height: 5),
                    Text('把任务放回时间里。',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 11.5)),
                  ],
                ),
              ),
              AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '上个月',
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text('${month.year} 年 ${month.month} 月',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700))),
              AppIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: '下个月',
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1))),
              const SizedBox(width: 8),
              Material(
                color: tokens.accentFaint,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  onTap: () => setState(() {
                    month = DateTime(today.year, today.month);
                    selectedDay = DateTime(today.year, today.month, today.day);
                  }),
                  borderRadius: BorderRadius.circular(7),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: Text('回到今天',
                          style: TextStyle(
                              color: tokens.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 9),
          Expanded(
            flex: 4,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, mainAxisSpacing: 7, crossAxisSpacing: 7),
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
                  onWillAccept: (data) => data != null,
                  onAccept: (taskId) =>
                      widget.controller.rescheduleTask(taskId, date),
                  builder: (context, candidateData, rejectedData) {
                    final dragActive = candidateData.isNotEmpty;
                    return GestureDetector(
                      onTap: () => setState(() => selectedDay = date),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.fromLTRB(9, 8, 8, 7),
                        decoration: BoxDecoration(
                            color: dragActive
                                ? tokens.accentSoft
                                : (isSelected
                                    ? tokens.accentSoft
                                    : tokens.content),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isSelected || dragActive
                                    ? tokens.accent.withOpacity(.45)
                                    : tokens.border)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                    width: 23,
                                    height: 23,
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
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700))),
                                const Spacer(),
                                if (count > 0)
                                  Container(
                                      width: 5,
                                      height: 5,
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
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (selectedDay != null) ...[
            Container(height: 1, color: tokens.border),
            const SizedBox(height: 12),
            _SelectedDayAgenda(
                controller: widget.controller, day: selectedDay!),
          ],
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

Widget _agendaRow(BuildContext context, TaskItem task,
    WorkspaceController controller, WorkFollowTheme tokens, VoidCallback onOpen) {
  final listColor = Color(controller.colorValueForList(task.listName));
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(
              task.completed
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: task.completed ? tokens.success : listColor,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      task.completed ? tokens.textTertiary : tokens.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  decoration: task.completed
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${task.listName} · ${task.displayTimeLabel ?? '全天'}',
              style: TextStyle(color: tokens.textTertiary, fontSize: 10.5),
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
      height: 168,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${day.month} 月 ${day.day} 日 · 星期$weekday · ${tasks.length} 件任务',
            style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('这一天没有安排任务。',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        // Dragging an agenda row onto a day cell reschedules
                        // the task to that day.
                        child: Draggable<String>(
                          data: task.id,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: tokens.overlay,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: tokens.accent.withOpacity(.5))),
                              child: Text(task.title,
                                  style: TextStyle(
                                      color: tokens.textPrimary, fontSize: 12)),
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
