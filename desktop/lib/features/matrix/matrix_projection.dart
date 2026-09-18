import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import 'matrix_models.dart';

/// Converts the flat task store into the two-level structure the matrix UI
/// renders: list groups for active tasks and one completed group per quadrant.
///
/// The projection is pure. It does not mutate tasks, and the UI does not need
/// to know how urgency, list ordering or metadata are derived.
class MatrixProjection {
  const MatrixProjection._();

  static List<MatrixQuadrantViewModel> project({
    required Iterable<TaskItem> tasks,
    required MatrixQuadrant Function(TaskItem task) quadrantFor,
    required Iterable<String> listOrder,
    bool includeCompleted = true,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final order = <String>[];
    final seenLists = <String>{};
    for (final rawName in listOrder) {
      final name = rawName.trim();
      if (name.isNotEmpty && seenLists.add(name)) order.add(name);
    }

    final activeByQuadrant = <MatrixQuadrant, Map<String, List<TaskItem>>>{
      for (final quadrant in MatrixQuadrant.values) quadrant: {},
    };
    final completedByQuadrant = <MatrixQuadrant, List<TaskItem>>{
      for (final quadrant in MatrixQuadrant.values) quadrant: [],
    };

    for (final task in tasks) {
      if (task.deletedAt != null ||
          task.isSkipped ||
          task.isAbandoned ||
          task.isConverted ||
          (!includeCompleted && task.completed)) {
        continue;
      }
      final quadrant = quadrantFor(task);
      if (task.completed) {
        completedByQuadrant[quadrant]!.add(task);
        continue;
      }
      final listName = task.listName.trim().isEmpty ? '收集箱' : task.listName;
      final groups = activeByQuadrant[quadrant]!;
      groups.putIfAbsent(listName, () => []).add(task);
      if (seenLists.add(listName)) order.add(listName);
    }

    return [
      for (final quadrant in MatrixQuadrant.values)
        _quadrant(
          quadrant,
          activeByQuadrant[quadrant]!,
          completedByQuadrant[quadrant]!,
          order,
          reference,
        ),
    ];
  }

  static MatrixQuadrantViewModel _quadrant(
    MatrixQuadrant quadrant,
    Map<String, List<TaskItem>> active,
    List<TaskItem> completed,
    List<String> listOrder,
    DateTime now,
  ) {
    final groups = <MatrixGroupViewModel>[];
    for (final listName in listOrder) {
      final tasks = active[listName];
      if (tasks == null || tasks.isEmpty) continue;
      groups.add(MatrixGroupViewModel(
        id: '${quadrant.name}:list:$listName',
        title: listName,
        count: tasks.length,
        completedGroup: false,
        tasks: List.unmodifiable(tasks.map((task) => _task(task, now))),
      ));
    }
    if (completed.isNotEmpty) {
      groups.add(MatrixGroupViewModel(
        id: '${quadrant.name}:completed',
        title: '已完成',
        count: completed.length,
        completedGroup: true,
        tasks: List.unmodifiable(completed.map((task) => _task(task, now))),
      ));
    }
    return MatrixQuadrantViewModel(
      quadrant: quadrant,
      groups: List.unmodifiable(groups),
    );
  }

  static MatrixTaskViewModel _task(TaskItem task, DateTime now) {
    final due = localDateTimeFromStorage(task.dueAt);
    final date = due ??
        (task.completed ? localDateTimeFromStorage(task.completedAt) : null);
    final day = _day(date);
    final today = _day(now)!;
    return MatrixTaskViewModel(
      task: task,
      listName: task.listName.trim().isEmpty ? '收集箱' : task.listName,
      dateLabel: _dateLabel(date, now),
      overdue: !task.completed && day != null && day.isBefore(today),
      hasNote: _hasNote(task),
      hasSubtasks: task.subtaskTotal > 0,
      hasReminder: task.reminderTimes.isNotEmpty || task.reminderAt != null,
      recurring: task.recurrenceType.toUpperCase() != 'NONE',
    );
  }

  static bool _hasNote(TaskItem task) {
    final description = task.description ?? task.note;
    return (description != null && description.trim().isNotEmpty) ||
        task.contentJson != null;
  }

  static DateTime? _day(DateTime? value) => value == null
      ? null
      : DateTime(value.year, value.month, value.day);

  /// A compact row label: relative days first, then weekday, then a calendar
  /// date. The weekday form is what keeps the target's `下周二` metadata short
  /// enough to share a row with list and property icons.
  static String? _dateLabel(DateTime? date, DateTime now) {
    if (date == null) return null;
    final today = _day(now)!;
    final target = _day(date)!;
    final difference = target.difference(today).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '明天';
    if (difference == -1) return '昨天';

    final weekday = '一二三四五六日'[date.weekday - 1];
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = target.difference(monday).inDays ~/ 7;
    if (week == 0) return '周$weekday';
    if (week == 1) return '下周$weekday';

    final year = date.year == now.year ? '' : '${date.year}年';
    return '$year${date.month}月${date.day}日';
  }
}
