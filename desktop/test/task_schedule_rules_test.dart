import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/features/tasks/domain/recurrence_engine.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/services/notification_service.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

class Reminders implements ReminderScheduler {
  final pending = <String, (String, DateTime)>{};
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String?> authorizationStatus() async => 'authorized';
  @override
  set onNotificationClicked(void Function(String taskId)? handler) {}
  @override
  Future<void> cancelAll() async => pending.clear();
  @override
  Future<void> cancel(String taskId) async =>
      pending.removeWhere((_, value) => value.$1 == taskId);
  @override
  Future<void> schedule(
      {required String taskId,
      String? notificationId,
      required String title,
      String? body,
      required DateTime at}) async {
    pending[notificationId ?? taskId] = (taskId, at);
  }
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

TaskItem task(DateTime date, String type, [Map<String, dynamic>? config]) =>
    TaskItem(
        id: 'test',
        title: '测试',
        listName: '收集箱',
        bucket: TaskBucket.later,
        dueAt: date.toIso8601String(),
        recurrenceType: type,
        recurrenceConfig: config);

void main() {
  test(
      'yearly leap day and inclusive ending use the same preview and occurrence calculation',
      () {
    final annual = task(
        DateTime(2024, 2, 29, 11), 'YEARLY', {'month': 2, 'dayOfMonth': 29});
    expect(RecurrenceEngine.nextOccurrence(annual), DateTime(2025, 2, 28, 11));
    final weekly = task(DateTime(2026, 9, 15), 'WEEKLY',
        {'weekday': 2, 'endDate': '2026-09-29'});
    expect(RecurrenceEngine.preview(weekly, DateTime(2026, 10, 10)),
        {DateTime(2026, 9, 22), DateTime(2026, 9, 29)});
    expect(
        RecurrenceEngine.nextOccurrence(weekly.copyWith(dueAt: '2026-09-29')),
        isNull);
  });

  test('workday and holiday rules observe published adjusted working days', () {
    expect(
        RecurrenceEngine.nextOccurrence(
            task(DateTime(2026, 9, 19, 11), 'WORKDAYS')),
        DateTime(2026, 9, 20, 11));
    expect(
        RecurrenceEngine.nextOccurrence(
            task(DateTime(2026, 9, 24), 'WORKDAYS')),
        DateTime(2026, 9, 28));
    expect(
        RecurrenceEngine.nextOccurrence(
            task(DateTime(2026, 9, 24), 'HOLIDAYS')),
        DateTime(2026, 9, 25));
    expect(
        RecurrenceEngine.nextOccurrence(
            task(DateTime(2026, 9, 19), 'WEEKDAYS')),
        DateTime(2026, 9, 21));
  });

  test(
      'multiple relative reminders survive storage, date changes, completion and count ending',
      () async {
    final reminders = Reminders();
    final c =
        WorkspaceController(seedData: false, reminderScheduler: reminders);
    addTearDown(c.dispose);
    c.addTask('测试');
    final id = c.tasks.single.id;
    c.taskActions.setScheduleSettings(
        id,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(
                dueAt: DateTime(2030, 9, 15, 11), hasTime: true),
            reminderOffsets: const [0, 30],
            recurrence: const RecurrenceDraft(
                type: 'WEEKLY', config: {'weekday': 7, 'count': 2})));
    await settle();
    expect(reminders.pending.values.map((value) => value.$2).toSet(),
        {DateTime(2030, 9, 15, 10, 30), DateTime(2030, 9, 15, 11)});
    expect(reminders.pending.values.every((value) => value.$1 == id), isTrue);
    final restored = TaskItem.fromMigration(MigrationTaskRecord.fromJson(
        c.tasks.single.toMigrationRecord().toJson()));
    expect(restored.reminderOffsets, [0, 30]);
    expect(restored.recurrenceConfig?['count'], 2);
    c.updateTaskDue(id, DateTime(2030, 9, 22, 11));
    await settle();
    expect(reminders.pending.length, 2);
    expect(reminders.pending.values.map((value) => value.$2).toSet(),
        {DateTime(2030, 9, 22, 10, 30), DateTime(2030, 9, 22, 11)});
    c.taskActions.complete(id);
    await settle();
    final next = c.tasks.singleWhere((task) => !task.completed);
    expect(next.recurrenceConfig?['count'], 1);
    expect(next.reminderOffsets, [0, 30]);
    expect(reminders.pending.values.map((value) => value.$2).toSet(),
        {DateTime(2030, 9, 29, 10, 30), DateTime(2030, 9, 29, 11)});
    c.taskActions.complete(next.id);
    await settle();
    expect(c.tasks.where((task) => !task.completed), isEmpty);
    expect(reminders.pending, isEmpty);
  });

  test('all-day reminders use 09:00 and clearing removes every notification',
      () async {
    final reminders = Reminders();
    final c =
        WorkspaceController(seedData: false, reminderScheduler: reminders);
    addTearDown(c.dispose);
    c.addTask('全天');
    final id = c.tasks.single.id;
    c.taskActions.setScheduleSettings(
        id,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(dueAt: DateTime(2030, 9, 15)),
            reminderOffsets: const [0, 1440]));
    await settle();
    expect(c.tasks.single.reminderTimes,
        [DateTime(2030, 9, 14, 9), DateTime(2030, 9, 15, 9)]);
    c.taskActions.setScheduleSettings(id, const TaskScheduleSettings());
    await settle();
    expect(c.tasks.single.reminderOffsets, isEmpty);
    expect(reminders.pending, isEmpty);
  });
}
