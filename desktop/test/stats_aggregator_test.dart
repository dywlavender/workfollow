import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/services/stats_aggregator.dart';

TaskItem task(String id, {
  bool completed = false,
  String? completedAt,
  String listName = '工作',
  String? dueAt,
}) => TaskItem(
      id: id,
      title: id,
      listName: listName,
      bucket: TaskBucket.today,
      completed: completed,
      completedAt: completedAt,
      dueAt: dueAt,
    );

void main() {
  test('aggregates real completion timestamps by day and list', () {
    final now = DateTime(2026, 9, 13, 16);
    final snapshot = StatsAggregator.aggregate([
      task('a', completed: true, completedAt: '2026-09-13T08:00:00'),
      task('b', completed: true, completedAt: '2026-09-12T08:00:00', listName: '个人'),
      task('c', completed: true),
      task('d', dueAt: '2026-09-10T09:00:00'),
    ], now: now);

    expect(snapshot.todayCompleted, 1);
    expect(snapshot.completedByList, {'工作': 1, '个人': 1});
    expect(snapshot.weekCompleted, 2);
    expect(snapshot.overdue, 1);
    expect(snapshot.active, 1);
    expect(snapshot.totalCompleted, 2);
    expect(snapshot.dailyCompletionCounts.last, 1);
  });

  test('empty data produces an explicit empty trend', () {
    final snapshot = StatsAggregator.aggregate(const [], now: DateTime(2026, 9, 13));
    expect(snapshot.hasCompletion, isFalse);
    expect(snapshot.dailyCompletionCounts, everyElement(0));
    expect(snapshot.completionByDay, isEmpty);
  });
}

