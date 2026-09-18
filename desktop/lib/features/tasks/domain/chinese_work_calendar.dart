/// Published mainland-China holiday schedules, kept separate from recurrence.
/// Sources: State Council notices for 2025 and 2026, linked in the acceptance doc.
class ChineseWorkCalendar {
  static bool hasYear(int year) => year == 2025 || year == 2026;
  static final Map<DateTime, bool> _overrides = _build();
  static Map<DateTime, bool> _build() {
    final result = <DateTime, bool>{};
    for (final period in [
      ('2025-01-01', 1),
      ('2025-01-28', 8),
      ('2025-04-04', 3),
      ('2025-05-01', 5),
      ('2025-05-31', 3),
      ('2025-10-01', 8),
      ('2026-01-01', 3),
      ('2026-02-15', 9),
      ('2026-04-04', 3),
      ('2026-05-01', 5),
      ('2026-06-19', 3),
      ('2026-09-25', 3),
      ('2026-10-01', 7),
    ]) {
      final start = DateTime.parse(period.$1);
      for (var day = 0; day < period.$2; day++) {
        result[DateTime(start.year, start.month, start.day + day)] = false;
      }
    }
    for (final date in [
      '2025-01-26',
      '2025-02-08',
      '2025-04-27',
      '2025-09-28',
      '2025-10-11',
      '2026-01-04',
      '2026-02-14',
      '2026-02-28',
      '2026-05-09',
      '2026-09-20',
      '2026-10-10'
    ]) {
      result[DateTime.parse(date)] = true;
    }
    return result;
  }

  static bool? overrideFor(DateTime date) =>
      _overrides[DateTime(date.year, date.month, date.day)];

  /// Years without an official table use the ordinary Monday–Friday calendar.
  static bool isWorkday(DateTime date) =>
      overrideFor(date) ?? date.weekday <= DateTime.friday;
  static String? label(DateTime date) {
    final key = '${date.month}-${date.day}';
    final fixed = {'1-1': '元旦', '5-1': '劳动节', '9-10': '教师节', '10-1': '国庆节'};
    final annual = <int, Map<String, String>>{
      2025: {
        '1-28': '除夕',
        '1-29': '春节',
        '4-4': '清明节',
        '5-31': '端午节',
        '10-6': '中秋节'
      },
      2026: {
        '2-16': '除夕',
        '2-17': '春节',
        '4-5': '清明节',
        '6-19': '端午节',
        '9-25': '中秋节'
      },
    };
    return annual[date.year]?[key] ?? fixed[key];
  }
}
