import '../models/task.dart';

/// Immutable, view-independent statistics derived from the task records.
/// Nothing here invents activity: a completion contributes only when its
/// persisted `completedAt` timestamp is present and parseable.
class StatsSnapshot {
  const StatsSnapshot({
    required this.startDate,
    required this.endDate,
    required this.heatmapStartDate,
    required this.dailyCompletionCounts,
    required this.completionByDay,
    required this.completedByList,
    required this.todayCompleted,
    required this.weekCompleted,
    required this.overdue,
    required this.active,
    required this.totalCompleted,
  });

  final DateTime startDate;
  final DateTime endDate;
  final DateTime heatmapStartDate;
  final List<int> dailyCompletionCounts;
  final Map<DateTime, int> completionByDay;
  final Map<String, int> completedByList;
  final int todayCompleted;
  final int weekCompleted;
  final int overdue;
  final int active;
  final int totalCompleted;

  bool get hasCompletion => totalCompleted > 0;
}

class StatsAggregator {
  const StatsAggregator._();

  static StatsSnapshot aggregate(Iterable<TaskItem> tasks,
      {DateTime? now, int trendDays = 30, int heatmapWeeks = 16}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final safeTrendDays = trendDays.clamp(1, 366).toInt();
    final safeHeatmapWeeks = heatmapWeeks.clamp(1, 52).toInt();
    final trendStart = today.subtract(Duration(days: safeTrendDays - 1));
    final trendEnd = today.add(const Duration(days: 1));
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final heatmapStart =
        currentMonday.subtract(Duration(days: (safeHeatmapWeeks - 1) * 7));
    final daily = List<int>.filled(safeTrendDays, 0);
    final completionByDay = <DateTime, int>{};
    final completedByList = <String, int>{};
    var totalCompleted = 0;

    for (final task in tasks) {
      if (task.deletedAt != null || !task.completed) continue;
      final completedAt = localDateTimeFromStorage(task.completedAt);
      if (completedAt == null) continue;
      totalCompleted += 1;
      final day = DateTime(completedAt.year, completedAt.month, completedAt.day);
      if (!day.isBefore(heatmapStart) && day.isBefore(trendEnd)) {
        completionByDay[day] = (completionByDay[day] ?? 0) + 1;
      }
      if (!day.isBefore(trendStart) && day.isBefore(trendEnd)) {
        final index = day.difference(trendStart).inDays;
        if (index >= 0 && index < daily.length) daily[index] += 1;
      }
      completedByList[task.listName] = (completedByList[task.listName] ?? 0) + 1;
    }

    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekCompleted = tasks.where((task) {
      if (task.deletedAt != null || !task.completed) return false;
      final value = localDateTimeFromStorage(task.completedAt);
      return value != null && !value.isBefore(weekStart) && value.isBefore(trendEnd);
    }).length;
    final overdue = tasks.where((task) {
      if (task.deletedAt != null || task.completed) return false;
      final due = localDateTimeFromStorage(task.dueAt);
      if (due == null) return false;
      return DateTime(due.year, due.month, due.day).isBefore(today);
    }).length;
    final active = tasks.where((task) => task.deletedAt == null && !task.completed).length;
    final todayCompleted = completionByDay[today] ?? 0;

    return StatsSnapshot(
      startDate: trendStart,
      endDate: trendEnd,
      heatmapStartDate: heatmapStart,
      dailyCompletionCounts: List.unmodifiable(daily),
      completionByDay: Map.unmodifiable(completionByDay),
      completedByList: Map.unmodifiable(completedByList),
      todayCompleted: todayCompleted,
      weekCompleted: weekCompleted,
      overdue: overdue,
      active: active,
      totalCompleted: totalCompleted,
    );
  }
}
