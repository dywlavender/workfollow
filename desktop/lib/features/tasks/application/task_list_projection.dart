import '../../../models/task.dart';
import 'task_projection.dart';

/// What a group is, apart from the words in its heading.
///
/// The projection decides where the breaks are; the screen decides how a date
/// is spelled. Keeping the date *out* of the projection is what lets
/// `calendarGroupLabel` stay the only place that writes 今天, 周三 — a second
/// date formatter inside this layer is exactly how two lists would start
/// disagreeing about the same day.
enum TaskListGroupKind {
  /// Pinned open tasks, lifted above every other group.
  pinned,

  /// Open tasks whose day has already passed.
  overdue,

  /// Open tasks due today.
  today,

  /// Open tasks due on one later day — see [TaskListGroup.day].
  day,

  /// Open tasks due after today but inside the recent window.
  upcoming,

  /// Open tasks due beyond the recent window.
  later,

  /// Open tasks that carry no date at all.
  undated,

  /// Finished tasks — completed, abandoned, or both.
  closed,

  /// Everything else, under a heading the screen does not draw.
  plain,
}

/// One titled block of a task list: a heading, a count, and the rows under it.
///
/// [tasks] are *roots*. A group hands its rows to the tree projection the way
/// an ungrouped list always did, so a parent and its children are never split
/// across two headings.
class TaskListGroup {
  const TaskListGroup({
    required this.id,
    required this.kind,
    required this.tasks,
    this.day,
    this.label,
  });

  /// Stable identity, used for folding and for the list menu's
  /// 展开/收起已完成. Deliberately not the heading: a group that ends up
  /// holding both finished and abandoned tasks is renamed for its content, and
  /// folding must not be lost to a rename.
  final String id;

  final TaskListGroupKind kind;

  final List<TaskItem> tasks;

  /// The single day a [TaskListGroupKind.day] or [TaskListGroupKind.today]
  /// group stands for. Null for groups named by a rule instead.
  final DateTime? day;

  /// The heading, for groups whose name is a rule rather than a date. Null
  /// means "name me by [day]".
  final String? label;

  @override
  String toString() => 'TaskListGroup($id, ${tasks.length})';
}

/// Turns the tasks a view matches into the groups the list draws.
///
/// Grouping used to live in `TodayScreen._build` as a chain of `if (view == …)`
/// branches, with the 已放弃 / 已完成 rows appended afterwards by a second
/// pass. Two consequences: a fifth view meant a fifth branch, and the "where
/// does this row go" question was answered inside a widget, where nothing could
/// test it without a pump. The rules now live here, the screen only renders,
/// and every rule below is a plain function of (view, tasks, today).
///
/// The four dated views and their groups:
///
/// * 今天 — 已过期 / 今天 / (finished)
/// * 最近 7 天 — 已过期 / 今天 / one group per later day, ascending / (finished)
/// * 所有任务 — 已过期 / 今天 / 最近 7 天 / 更远 / 无日期 / (finished)
/// * 已完成 — one group per day the tasks were closed on, newest first
///
/// 置顶 leads wherever open tasks are listed, and a named list or a tag stays a
/// plain list: that order is the user's own, and date headings would slice it
/// into fragments they did not ask for.
class TaskListProjection {
  const TaskListProjection({this.projection = const TaskProjection()});

  final TaskProjection projection;

  static const String pinnedId = 'pinned';
  static const String overdueId = 'overdue';
  static const String todayId = 'today';
  static const String upcomingId = 'upcoming';
  static const String laterId = 'later';
  static const String undatedId = 'undated';
  static const String closedId = 'closed';
  static const String plainId = 'plain';

  /// The group that holds [TaskItem]s with no closing date to file them under.
  static const String undatedCloseId = 'closed-undated';

  static const String pinnedLabel = '置顶';
  static const String overdueLabel = '已过期';
  static const String upcomingLabel = '最近 7 天';
  static const String laterLabel = '更远';
  static const String undatedLabel = '无日期';
  static const String completedLabel = '已完成';
  static const String abandonedLabel = '已放弃';

  /// The heading a group of finished tasks carries.
  ///
  /// One group holds both kinds — a task that was given up on and a task that
  /// was seen through are both "no longer on my plate", and two headings for
  /// them made the same list end twice. The name follows the content, so a
  /// group that happens to hold only abandoned tasks says so instead of
  /// claiming they were finished.
  static String closedLabel(
      {required bool completed, required bool abandoned}) {
    if (completed && abandoned) return '$completedLabel&$abandonedLabel';
    return abandoned ? abandonedLabel : completedLabel;
  }

  /// The day a bare `yyyy-MM-dd` group id is built from.
  static String dayId(DateTime day) => 'day:${_dayKey(day)}';

  /// The id of the group a [TaskItem] closed on [day] belongs to.
  static String closedDayId(DateTime day) => 'closed:${_dayKey(day)}';

  List<TaskListGroup> groupsFor({
    required Object view,
    required Iterable<TaskItem> tasks,
    String? selectedListName,
    String? selectedTagName,
    DateTime? reference,
  }) {
    final name = TaskProjection.viewNameOf(view);
    final rows = projection.listRows(
      tasks: tasks,
      view: view,
      selectedListName: selectedListName,
      selectedTagName: selectedTagName,
      reference: reference,
    );
    // The trash is one flat list. A row removed from a finished task is a row
    // in the trash; filing it under 已完成 a second time would claim the task
    // finished again when all that happened is that it was thrown away.
    if (name == 'trash') return [_plain(rows)];
    if (name == 'completed') return _byCloseDate(rows, reference);
    final open = rows.where((task) => !task.isClosed).toList();
    final pinned = open.where((task) => task.isPinned).toList();
    final ordinary = open.where((task) => !task.isPinned).toList();
    final closed = _closedOf(
      name: name,
      tasks: tasks,
      selectedListName: selectedListName,
      selectedTagName: selectedTagName,
      reference: reference,
      openIds: {for (final task in open) task.id},
    );
    final dated = selectedListName == null &&
        selectedTagName == null &&
        _datedViews.contains(name);
    return [
      if (pinned.isNotEmpty)
        _group(pinnedId, TaskListGroupKind.pinned, pinned, label: pinnedLabel),
      if (dated)
        ..._dated(ordinary, name, reference: reference)
      else if (ordinary.isNotEmpty)
        _group(plainId, TaskListGroupKind.plain, ordinary, label: ''),
      if (closed.isNotEmpty) _closed(closed),
    ];
  }

  /// The finished tasks this view is about.
  ///
  /// Taken from the view's *scope* rather than from the rows it shows, because
  /// the rows have already dropped them: 最近 7 天 filters out closed tasks and
  /// 今天 happens to keep the ones it matched, and a group that inherited
  /// whatever survived would show a different set depending on which view the
  /// user happened to be standing in. "The view would have shown this task"
  /// is the rule, and it is the same rule in all of them.
  List<TaskItem> _closedOf({
    required String name,
    required Iterable<TaskItem> tasks,
    required String? selectedListName,
    required String? selectedTagName,
    required DateTime? reference,
    required Set<String> openIds,
  }) {
    final scoped = projection.scope(
      tasks: tasks,
      view: name,
      selectedListName: selectedListName,
      selectedTagName: selectedTagName,
    );
    return projection
        .dedupChildren(
            scoped.where((task) => task.isClosed && _hits(name, task, reference)),
            parents: openIds)
        .toList();
  }

  /// Whether [task] is what [viewName] is about, ignoring whether it is
  /// finished. This is the view's own filter with the closed-ness clause taken
  /// out, and it is the only definition of "the view would have shown it".
  bool _hits(String viewName, TaskItem task, DateTime? reference) {
    switch (viewName) {
      case 'today':
        return !task.isAbandoned &&
            projection.needsAttentionToday(task, reference: reference);
      case 'recent':
        return projection.isInRecentWindow(task, reference: reference);
      default:
        return true;
    }
  }

  /// The views whose open tasks are cut by date. A named list or a tag is not
  /// one of them: those are lists the user built, and their order is the
  /// answer, not a date heading.
  static const Set<String> _datedViews = {'today', 'recent', 'all'};

  List<TaskListGroup> _dated(List<TaskItem> tasks, String name,
      {DateTime? reference}) {
    final today = _dayOf(reference ?? projection.now);
    final overdue = tasks
        .where((task) => projection.isOverdue(task, reference: reference))
        .toList();
    final due = tasks
        .where((task) => !projection.isOverdue(task, reference: reference))
        .toList();
    final onToday = due.where((task) => _isToday(task, today)).toList();
    final soon = due.where((task) => _isSoon(task, today)).toList();
    final beyond = due.where((task) => _isBeyond(task, today)).toList();
    final undated = due.where((task) => _dueDay(task) == null).toList();
    final overdueGroup = overdue.isEmpty
        ? null
        : _group(overdueId, TaskListGroupKind.overdue, overdue,
            label: overdueLabel);
    switch (name) {
      case 'today':
        // 今天 is emitted even when empty: it is the page's own day, and a
        // heading that vanishes the moment the last task is ticked reads as the
        // list having lost something. The list still skips empty groups, so
        // nothing is drawn for it.
        return [
          if (overdueGroup != null) overdueGroup,
          _group(todayId, TaskListGroupKind.today, onToday, day: today),
        ];
      case 'recent':
        return [
          if (overdueGroup != null) overdueGroup,
          // The whole point of the view: the week ahead, earliest day first.
          ..._byDay([...onToday, ...soon], today),
        ];
      default:
        return [
          if (overdueGroup != null) overdueGroup,
          if (onToday.isNotEmpty)
            _group(todayId, TaskListGroupKind.today, onToday, day: today),
          if (soon.isNotEmpty)
            _group(upcomingId, TaskListGroupKind.upcoming, _sortedByDay(soon),
                label: upcomingLabel),
          if (beyond.isNotEmpty)
            _group(laterId, TaskListGroupKind.later, _sortedByDay(beyond),
                label: laterLabel),
          if (undated.isNotEmpty)
            _group(undatedId, TaskListGroupKind.undated, undated,
                label: undatedLabel),
        ];
    }
  }

  /// One group per day, oldest first — the order a week is read in, which is
  /// not the order the tasks happen to sit in.
  List<TaskListGroup> _byDay(List<TaskItem> tasks, DateTime today) {
    final buckets = <DateTime, List<TaskItem>>{};
    for (final task in tasks) {
      final day = _dueDay(task);
      if (day == null) continue;
      buckets.putIfAbsent(day, () => <TaskItem>[]).add(task);
    }
    final days = buckets.keys.toList()..sort();
    return [
      for (final day in days)
        if (_sameDay(day, today))
          _group(todayId, TaskListGroupKind.today, buckets[day]!, day: day)
        else
          _group(TaskListProjection.dayId(day), TaskListGroupKind.day,
              buckets[day]!,
              day: day),
    ];
  }

  /// The same tasks in day order. Ties keep the order they arrived in, so a
  /// manual order inside one day is not quietly reshuffled.
  List<TaskItem> _sortedByDay(List<TaskItem> tasks) {
    final indexed = <(int, TaskItem)>[
      for (var i = 0; i < tasks.length; i++) (i, tasks[i]),
    ]..sort((a, b) {
        final byDay = _dueDay(a.$2)!.compareTo(_dueDay(b.$2)!);
        return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  /// One group per closing day, newest first, which is the order the user
  /// remembers finishing things in.
  List<TaskListGroup> _byCloseDate(Iterable<TaskItem> rows, DateTime? reference) {
    final buckets = <DateTime, List<TaskItem>>{};
    final undated = <TaskItem>[];
    for (final task in rows) {
      final closedAt = _closedAt(task);
      if (closedAt == null) {
        undated.add(task);
        continue;
      }
      final day = _dayOf(closedAt);
      buckets.putIfAbsent(day, () => <TaskItem>[]).add(task);
    }
    for (final tasks in buckets.values) {
      tasks.sort((a, b) => _closedAt(b)!.compareTo(_closedAt(a)!));
    }
    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        _group(TaskListProjection.closedDayId(day), TaskListGroupKind.closed,
            buckets[day]!,
            day: day),
      if (undated.isNotEmpty)
        _group(undatedCloseId, TaskListGroupKind.closed, undated,
            label: undatedLabel),
    ];
  }

  TaskListGroup _closed(List<TaskItem> tasks) {
    final completed = tasks.any((task) => task.completed);
    final abandoned = tasks.any((task) => task.isAbandoned);
    final sorted = [...tasks]..sort((a, b) {
        final aAt = _closedAt(a);
        final bAt = _closedAt(b);
        if (aAt == null || bAt == null) return aAt == null ? 1 : -1;
        return bAt.compareTo(aAt);
      });
    return _group(closedId, TaskListGroupKind.closed, sorted,
        label: closedLabel(completed: completed, abandoned: abandoned));
  }

  TaskListGroup _plain(Iterable<TaskItem> tasks) => _group(
      plainId, TaskListGroupKind.plain, tasks.toList(),
      label: '');

  TaskListGroup _group(String id, TaskListGroupKind kind, List<TaskItem> tasks,
          {DateTime? day, String? label}) =>
      TaskListGroup(
          id: id,
          kind: kind,
          tasks: List.unmodifiable(tasks),
          day: day,
          label: label);

  /// The day a finished task was closed on: when it was completed, or — for a
  /// task given up on — when it was abandoned.
  static DateTime? _closedAt(TaskItem task) => localDateTimeFromStorage(
      task.completed ? task.completedAt : task.abandonedAt);

  /// The date half of a task's `dueAt`, which is the day a list files it under.
  static DateTime? _dueDay(TaskItem task) {
    final due = localDateTimeFromStorage(task.dueAt);
    return due == null ? null : DateTime(due.year, due.month, due.day);
  }

  static bool _isToday(TaskItem task, DateTime today) =>
      _sameDay(_dueDay(task), today);

  /// Inside the recent window, which is the same window 最近 7 天 projects by:
  /// after today, and short of seven days out.
  static bool _isSoon(TaskItem task, DateTime today) {
    final day = _dueDay(task);
    return day != null &&
        day.isAfter(today) &&
        day.isBefore(today.add(const Duration(days: 7)));
  }

  /// Dated, and past the recent window — the far side 所有任务 files as 更远.
  /// It has to be a *dated* comparison: an undated task is not far away, it is
  /// unpinned, and it has its own 无日期 group to land in.
  static bool _isBeyond(TaskItem task, DateTime today) {
    final day = _dueDay(task);
    return day != null && !day.isBefore(today.add(const Duration(days: 7)));
  }

  static bool _sameDay(DateTime? day, DateTime other) =>
      day != null && _dayKey(day) == _dayKey(other);

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
