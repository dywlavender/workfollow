import 'package:flutter/material.dart';

import '../features/feedback/feedback_scope.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/calendar/calendar_month_view.dart';
import '../widgets/calendar/calendar_toolbar.dart';
import '../widgets/calendar/calendar_week_view.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/task_add_surface.dart';
import '../widgets/task_editor_popover.dart';
import '../widgets/task_floating_editor.dart';

/// The calendar.
///
/// A month you can read at a glance and edit where you are reading it: the
/// tasks are in the day cells, so the page needs no agenda underneath, and both
/// opening a task and creating one happen in surfaces anchored to the day that
/// was clicked rather than in a pane that replaces the grid.
///
/// The page keeps three pieces of state and no more — which month is on screen,
/// which day is current, and how time is presented. The toolbar, the month grid
/// and the week are separate widgets because a screen that also computed the
/// grid and drew the cells would be the only place any of it could be read.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  /// First day of the month on screen. In week mode it follows the anchor.
  late DateTime month;

  /// The page's current day: marked on the grid, the anchor of the week view,
  /// and the date the toolbar's plus button offers.
  late DateTime selectedDay;

  CalendarViewMode mode = CalendarViewMode.month;
  bool showCompleted = true;

  /// The task a floating editor is holding, so a second click while one is open
  /// cannot stack a second editor on the same page.
  String? editingTaskId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _step(int direction) {
    setState(() {
      if (mode == CalendarViewMode.month) {
        month = DateTime(month.year, month.month + direction);
        return;
      }
      // A week moves the anchor, and the month follows so that leaving week
      // mode lands on the month the user was last looking at.
      selectedDay = selectedDay.add(Duration(days: 7 * direction));
      month = DateTime(selectedDay.year, selectedDay.month);
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      month = DateTime(now.year, now.month);
      selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      selectedDay = day;
      // The grid shows the neighbouring months' closing and opening days, so a
      // click can land outside the month on screen. Following it keeps the
      // selected cell on the page instead of half off its edge.
      if (day.year != month.year || day.month != month.month) {
        month = DateTime(day.year, day.month);
      }
    });
  }

  Future<void> _openTask(String taskId, BuildContext anchor) async {
    if (editingTaskId != null) return;
    setState(() => editingTaskId = taskId);
    await showTaskFloatingEditor(
      anchor,
      controller: widget.controller,
      taskId: taskId,
    );
    if (!mounted || editingTaskId != taskId) return;
    setState(() => editingTaskId = null);
  }

  /// Opens the composer on [day].
  ///
  /// The date is not a default the composer chose for itself — it is the day
  /// the pointer was on, and it arrives as [TaskAddSurface.initialSchedule] so
  /// the user sees it and can clear it.
  Future<void> _createTask(DateTime day, BuildContext anchor) async {
    final draft = await showTaskEditorPopover<TaskAddDraft>(
      anchor,
      width: TaskSurfaceMetrics.composerWidth,
      maxHeight: TaskSurfaceMetrics.composerMaxHeight,
      placement: PopoverPlacement.bottomEnd,
      focusPolicy: PopoverFocusPolicy.searchField,
      builder: (_) => TaskAddSurface(
        controller: widget.controller,
        initialSchedule: TaskScheduleDraft.forDay(day),
      ),
    );
    if (!mounted || draft == null) return;
    final result = widget.controller.createTaskFromComposer(
      title: draft.title,
      listName: draft.listName,
      schedule: draft.schedule,
      scheduleOverridden: draft.scheduleOverridden,
      fallbackSchedule: TaskScheduleDraft.forDay(day),
      reminderAt: draft.reminderAt,
      recurrence: draft.recurrence,
      priority: draft.priority,
    );
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback != null) {
      presentTaskResult(feedback, result,
          actionVersion: widget.controller.actionVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // The page is one sheet, from the rail to the window's edges.
    //
    // The grid gets no margin and no frame of its own: a month is a continuous
    // thing, and insetting it with a border around the outside turns it into a
    // card of dates floating on the page instead of the page itself. The two
    // lines the grid's outer edge needs are already there — the rail draws the
    // one on the left, and the week header draws the one under the weekday
    // names — so nothing is missing when the frame goes. What is left to the
    // window's edge is the grid: the last column and the last row draw no line
    // of their own, which is what makes the edge read as the edge.
    return Container(
      color: tokens.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The toolbar is the one thing that keeps the page's insets. It is a
          // line of text and a row of controls rather than structure, so it
          // needs the breathing room the grid does not — and its own left inset
          // is what keeps it reading as the page's heading rather than as a
          // first cell of the grid.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                WorkFollowSpacing.pageHorizontalPadding,
                WorkFollowSpacing.pageTopPadding,
                WorkFollowSpacing.pageHorizontalPadding,
                0),
            child: CalendarToolbar(
              month: month,
              mode: mode,
              showCompleted: showCompleted,
              onPrevious: () => _step(-1),
              onToday: _goToday,
              onNext: () => _step(1),
              onAddTask: (anchor) => _createTask(selectedDay, anchor),
              onModeChanged: (value) => setState(() => mode = value),
              onToggleCompleted: () =>
                  setState(() => showCompleted = !showCompleted),
            ),
          ),
          Expanded(
            child: mode == CalendarViewMode.month
                ? CalendarMonthView(
                    month: month,
                    controller: widget.controller,
                    selectedDay: selectedDay,
                    showCompleted: showCompleted,
                    onSelectDay: _selectDay,
                    onOpenTask: _openTask,
                    onCreateTask: _createTask,
                  )
                : CalendarWeekView(
                    controller: widget.controller,
                    anchor: selectedDay,
                    onSelectDay: _selectDay,
                    onOpenTask: _openTask,
                  ),
          ),
        ],
      ),
    );
  }
}
