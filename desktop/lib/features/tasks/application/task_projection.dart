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
    final source = tasks.where((task) => viewName == 'trash'
        ? task.deletedAt != null
        : task.deletedAt == null && !task.isSkipped);
    final tagged = selectedTagName == null
        ? source
        : source.where((task) => task.tags.contains(selectedTagName));
    if (viewName == 'trash') return List.unmodifiable(tagged);
    if (selectedListName != null && viewName == 'all') {
      return List.unmodifiable(
          tagged.where((task) => task.listName == selectedListName));
    }
    final filtered = switch (viewName) {
      'home' => tagged,
      'recent' => tagged.where((task) =>
          !task.completed && isInRecentWindow(task, reference: reference)),
      'today' =>
        tagged.where((task) => needsAttentionToday(task, reference: reference)),
      'overdue' => tagged.where(
          (task) => !task.completed && isOverdue(task, reference: reference)),
      'inbox' => tagged.where((task) => task.listName == '收集箱'),
      'plan' => tagged.where((task) => task.bucket == TaskBucket.later),
      'all' => tagged,
      'completed' => tagged.where((task) => task.completed),
      'work' => tagged.where((task) => task.listName == '工作'),
      'study' => tagged.where((task) => task.listName == '学习'),
      'personal' => tagged.where((task) => task.listName == '个人'),
      _ => const <TaskItem>[],
    };
    return List.unmodifiable(filtered);
  }

  int count({
    required Iterable<TaskItem> tasks,
    required Object view,
    DateTime? reference,
  }) {
    final viewName = _viewName(view);
    final active =
        tasks.where((task) => task.deletedAt == null && !task.isSkipped);
    final dueTodayOrOverdue =
        (TaskItem task) => needsAttentionToday(task, reference: reference);
    return switch (viewName) {
      'home' => active
          .where((task) => !task.completed && dueTodayOrOverdue(task))
          .length,
      'recent' => active
          .where((task) =>
              !task.completed && isInRecentWindow(task, reference: reference))
          .length,
      'today' => active
          .where((task) => !task.completed && dueTodayOrOverdue(task))
          .length,
      'overdue' => active
          .where((task) =>
              !task.completed && isOverdue(task, reference: reference))
          .length,
      'inbox' => active
          .where((task) => task.listName == '收集箱' && !task.completed)
          .length,
      'plan' => active
          .where((task) => task.bucket == TaskBucket.later && !task.completed)
          .length,
      'all' => active.where((task) => !task.completed).length,
      'completed' => active.where((task) => task.completed).length,
      'work' =>
        active.where((task) => task.listName == '工作' && !task.completed).length,
      'study' =>
        active.where((task) => task.listName == '学习' && !task.completed).length,
      'personal' =>
        active.where((task) => task.listName == '个人' && !task.completed).length,
      'trash' => tasks.where((task) => task.deletedAt != null).length,
      _ => 0,
    };
  }

  List<TaskItem> forDay(Iterable<TaskItem> tasks, DateTime day) {
    return List.unmodifiable(tasks.where((task) {
      final due = localDateTimeFromStorage(task.dueAt);
      return task.deletedAt == null &&
          !task.isSkipped &&
          due != null &&
          due.year == day.year &&
          due.month == day.month &&
          due.day == day.day;
    }));
  }

  Map<String, int> tagCounts(Iterable<TaskItem> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      if (task.deletedAt != null || task.isSkipped) continue;
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
          !task.completed &&
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

  String _viewName(Object view) {
    final raw = view.toString();
    final dot = raw.lastIndexOf('.');
    return (dot < 0 ? raw : raw.substring(dot + 1)).toLowerCase();
  }
}
