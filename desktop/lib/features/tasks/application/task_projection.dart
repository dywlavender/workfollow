import '../../../models/task.dart';

/// Pure task projection used by the sidebar, list, board and calendar. The
/// view argument accepts either a string or WorkspaceView-like enum; keeping
/// this layer free of controller imports avoids a dependency cycle.
class TaskProjection {
  const TaskProjection({this.clock = DateTime.now});

  final DateTime Function() clock;

  DateTime get now => clock();

  List<TaskItem> visible({
    required Iterable<TaskItem> tasks,
    required Object view,
    String? selectedListName,
    String? selectedTagName,
    DateTime? reference,
  }) {
    final viewName = _viewName(view);
    final tagged = scope(
        tasks: tasks,
        view: view,
        selectedListName: selectedListName,
        selectedTagName: selectedTagName);
    if (viewName == 'trash') return List.unmodifiable(tagged);
    if (selectedListName != null && viewName == 'all') {
      return List.unmodifiable(tagged);
    }
    final filtered = switch (viewName) {
      'home' => tagged,
      'recent' => tagged.where((task) =>
          !task.isClosed && isInRecentWindow(task, reference: reference)),
      'today' => tagged.where((task) =>
          !task.isAbandoned && needsAttentionToday(task, reference: reference)),
      'inbox' => tagged.where((task) => task.listName == '收集箱'),
      'all' => tagged,
      'completed' => tagged.where((task) => task.isClosed),
      'work' => tagged.where((task) => task.listName == '工作'),
      'study' => tagged.where((task) => task.listName == '学习'),
      'personal' => tagged.where((task) => task.listName == '个人'),
      _ => const <TaskItem>[],
    };
    return List.unmodifiable(filtered);
  }

  /// The tasks a view is *about*, before the view decides what to do about the
  /// finished ones.
  ///
  /// [visible] narrows this; the list grouping cannot, because a view's closing
  /// group is "the finished tasks this view is about" and [visible] has already
  /// dropped them by the time it returns. Keeping the first half of the
  /// projection in one place is what stops the two from disagreeing about a
  /// task that is on screen but outside every group.
  Iterable<TaskItem> scope({
    required Iterable<TaskItem> tasks,
    required Object view,
    String? selectedListName,
    String? selectedTagName,
  }) {
    final viewName = _viewName(view);
    final source = tasks.where((task) => viewName == 'trash'
        ? task.deletedAt != null
        : task.deletedAt == null && !task.isSkipped && !task.isConverted);
    final tagged = selectedTagName == null
        ? source
        : source.where((task) => task.tags.contains(selectedTagName));
    if (viewName == 'all' && selectedListName != null) {
      return tagged.where((task) => task.listName == selectedListName);
    }
    return tagged;
  }

  /// The rows a list draws for [view]: [visible] with a child whose parent is
  /// on the same list folded under that parent instead of repeating at the top.
  List<TaskItem> listRows({
    required Iterable<TaskItem> tasks,
    required Object view,
    String? selectedListName,
    String? selectedTagName,
    DateTime? reference,
  }) =>
      dedupChildren(visible(
        tasks: tasks,
        view: view,
        selectedListName: selectedListName,
        selectedTagName: selectedTagName,
        reference: reference,
      ));

  /// Drops a child whose parent is on the same list: it renders nested under
  /// the parent, and drawing it a second time at the top level would show the
  /// task twice.
  ///
  /// [parents] adds ids that belong to the list but are not in [rows] — a
  /// parent filed under another heading still owns its children, so a child
  /// must not be promoted to a row of its own just because the two ended up in
  /// different groups.
  List<TaskItem> dedupChildren(Iterable<TaskItem> rows,
      {Set<String> parents = const {}}) {
    final list = rows.toList();
    final ids = {for (final task in list) task.id, ...parents};
    return List.unmodifiable(list
        .where((task) => !task.isChildTask || !ids.contains(task.parentTaskId)));
  }

  int count({
    required Iterable<TaskItem> tasks,
    required Object view,
    DateTime? reference,
  }) {
    final viewName = _viewName(view);
    final active = tasks.where((task) =>
        task.deletedAt == null && !task.isSkipped && !task.isConverted);
    final dueTodayOrOverdue =
        (TaskItem task) => needsAttentionToday(task, reference: reference);
    return switch (viewName) {
      'home' => active
          .where((task) => !task.isClosed && dueTodayOrOverdue(task))
          .length,
      'recent' => active
          .where((task) =>
              !task.isClosed && isInRecentWindow(task, reference: reference))
          .length,
      'today' => active
          .where((task) => !task.isClosed && dueTodayOrOverdue(task))
          .length,
      'inbox' =>
        active.where((task) => task.listName == '收集箱' && !task.isClosed).length,
      'all' => active.where((task) => !task.isClosed).length,
      'completed' => active.where((task) => task.completed).length,
      'work' =>
        active.where((task) => task.listName == '工作' && !task.isClosed).length,
      'study' =>
        active.where((task) => task.listName == '学习' && !task.isClosed).length,
      'personal' =>
        active.where((task) => task.listName == '个人' && !task.isClosed).length,
      'trash' => tasks.where((task) => task.deletedAt != null).length,
      _ => 0,
    };
  }

  /// The tasks a month cell draws under its own number: everything that
  /// begins on [day].
  ///
  /// A task that runs across days is *not* filtered out here — the lists, the
  /// board and the week view all read a multi-day task by the day it starts,
  /// and dropping it would hide the task from every one of them. The month
  /// grid asks for [singleDayForDay] instead, because it draws the range
  /// itself and would otherwise show the same task twice.
  List<TaskItem> forDay(Iterable<TaskItem> tasks, DateTime day) {
    return List.unmodifiable(tasks.where((task) {
      final start = startDayOf(task);
      return _appearsInDay(task) &&
          start != null &&
          start.year == day.year &&
          start.month == day.month &&
          start.day == day.day;
    }));
  }

  /// The tasks that begin on [day] and finish there — the ones a month cell
  /// has to draw for itself, because no band is going to cover them.
  List<TaskItem> singleDayForDay(Iterable<TaskItem> tasks, DateTime day) {
    return List.unmodifiable(
        forDay(tasks, day).where((task) => !spansMultipleDays(task)));
  }

  /// The day a task starts on: the date half of `dueAt`.
  DateTime? startDayOf(TaskItem task) {
    final due = localDateTimeFromStorage(task.dueAt);
    return due == null ? null : DateTime(due.year, due.month, due.day);
  }

  /// The last day a task covers.
  ///
  /// A range is recognised by its two dates disagreeing — there is no flag for
  /// it and nothing to migrate, because `dueEndAt` already means two things and
  /// the dates tell them apart. When the end falls on the start's own day it is
  /// the *time* the task finishes ("14:00 – 15:00", which is what the schedule
  /// panel writes by default), not a second day, so the task ends where it
  /// starts. A missing end is the same case.
  DateTime? endDayOf(TaskItem task) {
    final start = startDayOf(task);
    if (start == null) return null;
    final end = localDateTimeFromStorage(task.dueEndAt);
    if (end == null) return start;
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.isAfter(start) ? endDay : start;
  }

  /// Whether a task covers more than the day it begins on.
  bool spansMultipleDays(TaskItem task) {
    final start = startDayOf(task);
    return start != null && endDayOf(task)!.isAfter(start);
  }

  /// The multi-day tasks whose range touches `first .. last`, ready for a week
  /// row to lay out.
  ///
  /// The order is the order a row should try to place them in: earlier starts
  /// first, and among tasks that begin on the same day the longer one first, so
  /// a five-day band ends up above a two-day band that opened beside it rather
  /// than the other way round.
  List<TaskItem> multiDayWithin(
    Iterable<TaskItem> tasks,
    DateTime first,
    DateTime last,
  ) {
    final lo = DateTime(first.year, first.month, first.day);
    final hi = DateTime(last.year, last.month, last.day);
    final hits = tasks.where((task) {
      if (!_appearsInDay(task) || !spansMultipleDays(task)) return false;
      final start = startDayOf(task)!;
      final end = endDayOf(task)!;
      return !end.isBefore(lo) && !start.isAfter(hi);
    }).toList();
    hits.sort((a, b) {
      final startA = startDayOf(a)!;
      final startB = startDayOf(b)!;
      final byStart = startA.compareTo(startB);
      if (byStart != 0) return byStart;
      return endDayOf(b)!
          .difference(startB)
          .compareTo(endDayOf(a)!.difference(startA));
    });
    return List.unmodifiable(hits);
  }

  /// Whether a task can be shown in a day at all. The same condition [forDay]
  /// has always applied, lifted out so the range queries cannot drift from it.
  bool _appearsInDay(TaskItem task) =>
      task.deletedAt == null &&
      !task.isSkipped &&
      !task.isConverted &&
      !task.isAbandoned;

  Map<String, int> tagCounts(Iterable<TaskItem> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      if (task.deletedAt != null || task.isSkipped || task.isConverted)
        continue;
      for (final raw in task.tags) {
        final tag = raw.trim();
        if (tag.isEmpty) continue;
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return Map<String, int>.fromEntries(entries);
  }

  int countForList(Iterable<TaskItem> tasks, String listName) => tasks
      .where((task) =>
          task.deletedAt == null &&
          !task.isSkipped &&
          !task.isConverted &&
          !task.isAbandoned &&
          !task.isClosed &&
          task.listName == listName)
      .length;

  bool needsAttentionToday(TaskItem task, {DateTime? reference}) {
    if (task.bucket == TaskBucket.today || task.bucket == TaskBucket.overdue) {
      return true;
    }
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final value = reference ?? now;
    final start = DateTime(value.year, value.month, value.day);
    return deadline != null && !deadline.isAfter(start);
  }

  bool isOverdue(TaskItem task, {DateTime? reference}) {
    final due = localDateTimeFromStorage(task.dueAt);
    if (due == null) return false;
    final value = reference ?? now;
    final today = DateTime(value.year, value.month, value.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  bool isInRecentWindow(TaskItem task, {DateTime? reference}) {
    final due = localDateTimeFromStorage(task.dueAt);
    if (due == null) return false;
    final value = reference ?? now;
    final today = DateTime(value.year, value.month, value.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    return dueDay.isBefore(today.add(const Duration(days: 7)));
  }

  String _viewName(Object view) => viewNameOf(view);

  /// The lower-case view name a projection switch dispatches on.
  ///
  /// Public because the list grouping layer resolves the same names, and two
  /// copies of "take the text after the last dot, lower-case it" would drift
  /// the day one of them met a view it had not seen before.
  static String viewNameOf(Object view) {
    final raw = view.toString();
    final dot = raw.lastIndexOf('.');
    return (dot < 0 ? raw : raw.substring(dot + 1)).toLowerCase();
  }
}
