import 'migration.dart';

/// A local habit uses a deliberately small model: a name, an optional icon
/// colour, the weekdays on which it is expected, and the local dates checked
/// off by the user. There is no account, streak server or social state.
class HabitItem {
  const HabitItem({
    required this.id,
    required this.name,
    this.icon = 'check',
    this.color,
    this.schedule = const <int>{1, 2, 3, 4, 5, 6, 7},
    this.records = const <String>{},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String icon;
  final String? color;
  final Set<int> schedule;
  final Set<String> records;
  final String? createdAt;
  final String? updatedAt;

  HabitItem copyWith({
    String? name,
    String? icon,
    String? color,
    bool clearColor = false,
    Set<int>? schedule,
    Set<String>? records,
    String? updatedAt,
  }) {
    return HabitItem(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: clearColor ? null : color ?? this.color,
      schedule: schedule ?? this.schedule,
      records: records ?? this.records,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory HabitItem.fromMigration(MigrationHabitRecord record) {
    final schedule =
        record.schedule.where((day) => day >= 1 && day <= 7).toSet();
    return HabitItem(
      id: record.id,
      name: record.name,
      icon: record.icon,
      color: record.color,
      schedule: schedule.isEmpty
          ? const <int>{1, 2, 3, 4, 5, 6, 7}
          : Set.unmodifiable(schedule),
      records: Set.unmodifiable(record.records.where(_isDateKey).toSet()),
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }

  MigrationHabitRecord toMigrationRecord() => MigrationHabitRecord(
        id: id,
        name: name,
        icon: icon,
        color: color,
        schedule: schedule.toList()..sort(),
        records: records.toList()..sort(),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool isScheduledOn(DateTime day) =>
      schedule.isEmpty || schedule.contains(day.weekday);

  bool isCompletedOn(DateTime day) => records.contains(habitDateKey(day));

  int streak({DateTime? from}) {
    var day = habitStartOfDay(from ?? DateTime.now());
    var count = 0;
    // A streak walks backwards through scheduled days. Non-scheduled days do
    // not break it, which matches how personal habit trackers read weekends.
    for (var guard = 0; guard < 3660; guard++) {
      if (isScheduledOn(day)) {
        if (!isCompletedOn(day)) break;
        count += 1;
      }
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  static bool _isDateKey(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}

String habitDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime habitStartOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
