import '../models/task.dart';

/// Natural-language parser for quick entry, modelled on TickTick's 智能识别.
/// Pure Dart, fully unit-tested: "明早9点 #工作 @个人 !!!准备评审" becomes a
/// due date, reminder, tag, list and priority plus the clean title.
///
/// Every recognised fragment is reported as a [SmartSpan] with its original
/// offsets so the UI can show (and let the user remove) each chip.
enum SmartTokenKind { date, time, recurrence, tag, list, priority }

class SmartSpan {
  const SmartSpan(
      {required this.kind,
      required this.start,
      required this.end,
      required this.raw,
      required this.label});

  final SmartTokenKind kind;

  /// Offsets into the original input string ([end] exclusive).
  final int start;
  final int end;
  final String raw;

  /// Human-readable chip label, e.g. "9月15日 09:00" or "#工作".
  final String label;
}

class SmartParseResult {
  const SmartParseResult({
    required this.title,
    required this.dueAt,
    required this.hasTime,
    this.reminderAt,
    required this.recurrenceType,
    required this.recurrenceConfig,
    required this.tags,
    required this.listName,
    required this.priority,
    required this.spans,
  });

  /// Input with every recognised fragment stripped out.
  final String title;

  /// Explicitly parsed date/time. Null means "no date in the text".
  final DateTime? dueAt;

  /// True when the text carried a clock time; the scheduler then also sets a
  /// reminder at the same moment.
  final bool hasTime;

  /// A clock-bearing entry is also a reminder in the local app. Keeping the
  /// value explicit makes the parse contract usable by the menu-bar capture
  /// path without having to infer it a second time.
  final DateTime? reminderAt;
  final String recurrenceType; // NONE | DAILY | WEEKLY | MONTHLY
  final Map<String, dynamic>? recurrenceConfig;
  final List<String> tags;

  /// Raw list name after @; the caller decides whether it exists.
  final String? listName;
  final TaskPriority priority;
  final List<SmartSpan> spans;

  bool get hasStructure => spans.isNotEmpty;
}

class SmartDateParser {
  const SmartDateParser();

  static final _weekdayNames = const ['一', '二', '三', '四', '五', '六', '日'];

  static final _priorityWords = const {
    3: TaskPriority.high,
    2: TaskPriority.medium,
    1: TaskPriority.low,
  };

  static final _chineseDigits = const {
    '零': 0,
    '一': 1,
    '两': 2,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '十': 10,
  };

  SmartParseResult parse(String input, {DateTime? now}) {
    // [reference] carries the full wall-clock time so "9点" and "2小时后"
    // resolve relative to the same instant in tests and in production.
    final reference = now ?? DateTime.now();
    final today = _startOfDay(reference);
    final spans = <SmartSpan>[];
    DateTime? due;
    var hasTime = false;
    String recurrenceType = 'NONE';
    Map<String, dynamic>? recurrenceConfig;
    final tags = <String>[];
    String? listName;
    var priority = TaskPriority.none;

    final candidates = <_Candidate>[];
    void add(RegExp pattern, _CandidateFactory factory) {
      for (final match in pattern.allMatches(input)) {
        final candidate = factory(match, input);
        if (candidate != null) candidates.add(candidate);
      }
    }

    // Order matters only for overlap resolution below; longer matches win.
    add(_relativeIn, (m, s) => _relative(m, s, reference, today));
    add(_dateTime, (m, s) => _combinedDateTime(m, s, reference, today));
    add(_clockTime, (m, s) => _clock(m, s, reference, today));
    add(_numericTime, (m, s) => _clock(m, s, reference, today));
    add(_bareTime, (m, s) => _bareTimeCandidate(m, s, reference, today));
    add(_recurrence, (m, s) => _recurrenceSpan(m, s));
    add(_monthDay, (m, s) => _absoluteDate(m, s, today));
    add(_slashDate, (m, s) => _absoluteDate(m, s, today));
    add(_weekDay, (m, s) => _weekdayDate(m, s, today));
    add(_dayWord, (m, s) => _relativeDay(m, s, today));
    add(
        _tag,
        (m, s) => _marker(m, s, SmartTokenKind.tag, (raw) {
              final name = raw.substring(1).trim();
              if (name.isEmpty) return null;
              if (!tags.contains(name)) tags.add(name);
              return '#$name';
            }));
    add(
        _listMarker,
        (m, s) => _marker(m, s, SmartTokenKind.list, (raw) {
              final name = raw.substring(1).trim();
              if (name.isEmpty) return null;
              listName = name;
              return '@$name';
            }));
    add(_priority, (m, s) => _prioritySpan(m, s, (value) => priority = value));

    // Greedy, non-overlapping, longest-first inside the same start offset.
    candidates.sort((a, b) {
      if (a.start != b.start) return a.start - b.start;
      return b.end - a.end;
    });
    var cursor = -1;
    DateTime? dateOnlyDue;
    DateTime? timeOnlyDue;
    for (final candidate in candidates) {
      if (candidate.start < cursor) continue;
      spans.add(candidate.span);
      if (candidate.due != null) {
        if (candidate.span.kind == SmartTokenKind.date && !candidate.hasTime) {
          dateOnlyDue = candidate.due;
        } else if (candidate.span.kind == SmartTokenKind.time) {
          timeOnlyDue = candidate.due;
        }
        due = candidate.due;
        hasTime = candidate.hasTime;
      }
      if (candidate.recurrenceType != null) {
        recurrenceType = candidate.recurrenceType!;
        recurrenceConfig = candidate.recurrenceConfig;
      }
      cursor = candidate.end;
    }
    // "明天 下午3点" arrives as a date token plus a time token: merge them.
    if (dateOnlyDue != null && timeOnlyDue != null) {
      final merged = DateTime(dateOnlyDue.year, dateOnlyDue.month,
          dateOnlyDue.day, timeOnlyDue.hour, timeOnlyDue.minute);
      due = merged.isBefore(reference) && !dateOnlyDue.isAfter(reference)
          ? merged.add(const Duration(days: 1))
          : merged;
      hasTime = true;
    } else if (timeOnlyDue != null &&
        recurrenceType == 'WEEKLY' &&
        (recurrenceConfig?['weekday'] as num?) != null) {
      // "每周一 9点" should land on the next Monday at that time.
      final target = recurrenceConfig!['weekday'] as int;
      final delta = ((target - reference.weekday) % 7 + 7) % 7;
      final day = today.add(Duration(days: delta));
      final candidate = DateTime(
          day.year, day.month, day.day, timeOnlyDue.hour, timeOnlyDue.minute);
      due = candidate.isBefore(reference)
          ? candidate.add(const Duration(days: 7))
          : candidate;
    }

    // Rebuild the title without the recognised spans, keeping original order.
    final title = titleFromSpans(input, spans);

    return SmartParseResult(
      title: title,
      dueAt: due,
      hasTime: hasTime,
      reminderAt: hasTime ? due : null,
      recurrenceType: recurrenceType,
      recurrenceConfig: recurrenceConfig,
      tags: List.unmodifiable(tags),
      listName: listName,
      priority: priority,
      spans: List.unmodifiable(spans),
    );
  }

  /// Projects [input] into a title while removing only the supplied spans.
  /// Quick add uses this when a user dismisses one chip: the dismissed token
  /// must remain ordinary title text instead of being silently discarded.
  String titleFromSpans(String input, Iterable<SmartSpan> spans) {
    final ranges = spans.toList()..sort((a, b) => a.start - b.start);
    final buffer = StringBuffer();
    var index = 0;
    for (final range in ranges) {
      if (range.start < index) continue;
      if (range.start > index) buffer.write(input.substring(index, range.start));
      index = range.end;
    }
    if (index < input.length) buffer.write(input.substring(index));
    var title = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'^[，,、。;；\-—]+\s*'), '');
    title = title.replaceAll(RegExp(r'\s*[，,、;；。]+$'), '').trim();
    return title;
  }

  // ---- patterns -----------------------------------------------------------

  static final _relativeIn =
      RegExp(r'(\d+|半)\s*(个)?(小时|分钟)(之|以)?后|(\d+)\s*天(之|以)?后');
  static final _dateTime = RegExp(
      r'(今天|今日|明天|明日|后天|大后天|今晚|今早|明早|明晨|明晚)?\s*(早上|上午|中午|下午|晚上)?\s*(\d{1,2}|[零一两二三四五六七八九十]{1,3})\s*[点时:：]\s*(半|[0-5]?\d\s*分?)?');
  static final _clockTime = RegExp(
      r'(早上|上午|中午|下午|晚上)\s*(\d{1,2}|[零一两二三四五六七八九十]{1,3})\s*[点时](半|[0-5]?\d\s*分?)?');
  static final _numericTime = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})');
  static final _bareTime =
      RegExp(r'(\d{1,2}|[零一两二三四五六七八九十]{1,3})\s*[点时]\s*(半|[0-5]?\d\s*分?)?');
  static final _recurrence =
      RegExp(r'每天|每日|每(周|星期|礼拜)([一二三四五六日天])|每月\s*(\d{1,2})\s*[日号]?');
  static final _monthDay = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]');
  static final _slashDate = RegExp(r'(\d{1,2})/(\d{1,2})');
  static final _weekDay = RegExp(r'(下下?|本)?(周|星期|礼拜)([一二三四五六日天])');
  static final _dayWord = RegExp(r'今天|今日|明天|明日|后天|大后天');
  static final _tag = RegExp(r'#([^\s#@，,。;；！!]+)');
  static final _listMarker = RegExp(r'@([^\s#@，,。;；！!]+)');
  static final _priority = RegExp(r'(^|\s)(!{1,3})(?=\s)|(^|\s)(!{2,3})(?!!)');

  // ---- candidate helpers --------------------------------------------------

  _Candidate? _relative(
      RegExpMatch m, String input, DateTime reference, DateTime today) {
    final raw = m.group(0)!;
    final isDays = raw.contains('天');
    final amountText = m.group(1) ?? m.group(5) ?? '';
    final amount = int.tryParse(amountText) ?? 0;
    DateTime due;
    if (isDays) {
      due = today.add(Duration(days: amount));
    } else if (amountText == '半') {
      due = reference.add(const Duration(minutes: 30));
    } else if (raw.contains('小时')) {
      due = reference.add(Duration(hours: amount));
    } else {
      due = reference.add(Duration(minutes: amount));
    }
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.date,
            start: m.start,
            end: m.end,
            raw: raw,
            label: _dateLabel(due, true)),
        due: due,
        hasTime: true);
  }

  _Candidate? _combinedDateTime(
      RegExpMatch m, String input, DateTime reference, DateTime today) {
    var dayPart = m.group(1);
    var timeOfDay = m.group(2);
    final hourText = m.group(3)!;
    // Contractions carry their own time-of-day: 今晚8点 means 20:00.
    const impliedDayPart = {
      '今晚': '晚上',
      '今早': '早上',
      '明早': '早上',
      '明晨': '早上',
      '明晚': '晚上',
    };
    if (timeOfDay == null && impliedDayPart.containsKey(dayPart)) {
      timeOfDay = impliedDayPart[dayPart];
    }
    dayPart = switch (dayPart) {
      '今晚' => '今天',
      '今早' => '今天',
      '明早' => '明天',
      '明晨' => '明天',
      '明晚' => '明天',
      final other => other,
    };
    final minuteText = (m.group(4) ?? '').trim();
    // A bare hour without any date/time-of-day word is only a time; the
    // dedicated clock pattern handles context better. Avoid matching plain
    // "9点" here when it should stay a time-only token.
    if (dayPart == null && timeOfDay == null) return null;
    var hour = _hourValue(hourText);
    if (hour == null || hour > 23) return null;
    var minute = 0;
    if (minuteText == '半') {
      minute = 30;
    } else if (minuteText.isNotEmpty) {
      minute = int.tryParse(minuteText.replaceAll('分', '').trim()) ?? 0;
    }
    if (timeOfDay == '下午' || timeOfDay == '晚上') {
      if (hour < 12) hour += 12;
    } else if (timeOfDay == '中午' && hour < 11) {
      hour += 12;
    }
    var day = _resolveDayWord(dayPart, today);
    if (day == null) return null;
    var due = DateTime(day.year, day.month, day.day, hour, minute);
    if (day.isAtSameMomentAs(today) && !due.isAfter(reference)) {
      due = due.add(const Duration(days: 1));
    }
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.date,
            start: m.start,
            end: m.end,
            raw: m.group(0)!,
            label: _dateLabel(due, true)),
        due: due,
        hasTime: true);
  }

  _Candidate? _clock(
      RegExpMatch m, String input, DateTime reference, DateTime today) {
    final raw = m.group(0)!;
    // Two shapes reach this helper: "下午3点半" style (day-part word present)
    // and "9:30" numeric style. Both resolve to the next occurrence in time.
    if (m.pattern == _numericTime) {
      final h = int.tryParse(m.group(1)!);
      final minute = int.tryParse(m.group(2)!) ?? 0;
      if (h == null || h > 23 || minute > 59) return null;
      final due = _nextOccurrence(today, h, minute, reference);
      return _Candidate(
          span: SmartSpan(
              kind: SmartTokenKind.time,
              start: m.start,
              end: m.end,
              raw: raw,
              label: _dateLabel(due, true)),
          due: due,
          hasTime: true);
    }
    final timeOfDay = m.group(1);
    var hour = _hourValue(m.group(2)!);
    if (hour == null || hour > 23) return null;
    final minuteText = (m.group(3) ?? '').trim();
    var minute = 0;
    if (minuteText == '半') {
      minute = 30;
    } else if (minuteText.isNotEmpty) {
      minute = int.tryParse(minuteText.replaceAll('分', '').trim()) ?? 0;
    }
    if (timeOfDay == '下午' || timeOfDay == '晚上') {
      if (hour < 12) hour += 12;
    } else if (timeOfDay == '中午' && hour < 11) {
      hour += 12;
    }
    final due = _nextOccurrence(today, hour, minute, reference);
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.time,
            start: m.start,
            end: m.end,
            raw: raw,
            label: _dateLabel(due, true)),
        due: due,
        hasTime: true);
  }

  _Candidate? _bareTimeCandidate(
      RegExpMatch m, String input, DateTime reference, DateTime today) {
    final hour = _hourValue(m.group(1)!);
    if (hour == null || hour > 23) return null;
    final minuteText = (m.group(2) ?? '').trim();
    var minute = 0;
    if (minuteText == '半') {
      minute = 30;
    } else if (minuteText.isNotEmpty) {
      minute = int.tryParse(minuteText.replaceAll('分', '').trim()) ?? 0;
    }
    final due = _nextOccurrence(today, hour, minute, reference);
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.time,
            start: m.start,
            end: m.end,
            raw: m.group(0)!,
            label: _dateLabel(due, true)),
        due: due,
        hasTime: true);
  }

  _Candidate? _recurrenceSpan(RegExpMatch m, String input) {
    final raw = m.group(0)!;
    if (raw == '每天' || raw == '每日') {
      return _recurrenceCandidate(m, 'DAILY', null, '每天');
    }
    if (raw.startsWith('每')) {
      final weekdayChar = m.group(2);
      if (weekdayChar != null) {
        final weekday =
            _weekdayNames.indexOf(weekdayChar == '天' ? '日' : weekdayChar);
        if (weekday < 0) return null;
        return _recurrenceCandidate(m, 'WEEKLY', {'weekday': weekday + 1},
            '每周${_weekdayNames[weekday]}');
      }
      final day = int.tryParse(m.group(3) ?? '');
      if (day == null || day < 1 || day > 31) return null;
      return _recurrenceCandidate(m, 'MONTHLY', {'dayOfMonth': day}, '每月$day号');
    }
    return null;
  }

  _Candidate _recurrenceCandidate(
      RegExpMatch m, String type, Map<String, dynamic>? config, String label) {
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.recurrence,
            start: m.start,
            end: m.end,
            raw: m.group(0)!,
            label: label),
        recurrenceType: type,
        recurrenceConfig: config);
  }

  _Candidate? _absoluteDate(RegExpMatch m, String input, DateTime today) {
    final month = int.tryParse(m.group(1)!);
    final day = int.tryParse(m.group(2)!);
    if (month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final maxDay = DateTime(today.year, month + 1, 0).day;
    if (day > maxDay) return null;
    var year = today.year;
    var due = DateTime(year, month, day);
    if (due.isBefore(today)) due = DateTime(year + 1, month, day);
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.date,
            start: m.start,
            end: m.end,
            raw: m.group(0)!,
            label: _dateLabel(due, false)),
        due: due,
        hasTime: false);
  }

  _Candidate? _weekdayDate(RegExpMatch m, String input, DateTime today) {
    final prefix = m.group(1);
    final char = m.group(3)!;
    final weekday = _weekdayNames.indexOf(char == '天' ? '日' : char);
    if (weekday < 0) return null;
    final delta = ((weekday + 1 - today.weekday) % 7 + 7) % 7;
    var due = today.add(Duration(days: delta));
    if (prefix == '下') due = due.add(const Duration(days: 7));
    if (prefix == '下下') due = due.add(const Duration(days: 14));
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.date,
            start: m.start,
            end: m.end,
            raw: m.group(0)!,
            label: _dateLabel(due, false)),
        due: due,
        hasTime: false);
  }

  _Candidate? _relativeDay(RegExpMatch m, String input, DateTime today) {
    final raw = m.group(0)!;
    final day = _resolveDayWord(raw, today);
    if (day == null) return null;
    final normalized = DateTime(day.year, day.month, day.day);
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.date,
            start: m.start,
            end: m.end,
            raw: raw,
            label: _dateLabel(normalized, false)),
        due: normalized,
        hasTime: false);
  }

  _Candidate? _marker(RegExpMatch m, String input, SmartTokenKind kind,
      String? Function(String raw) apply) {
    final raw = m.group(0)!;
    final label = apply(raw);
    if (label == null) return null;
    return _Candidate(
        span: SmartSpan(
            kind: kind, start: m.start, end: m.end, raw: raw, label: label));
  }

  _Candidate? _prioritySpan(
      RegExpMatch m, String input, void Function(TaskPriority) apply) {
    final marks = _group(m, 2) ?? _group(m, 4)!;
    final priority = _priorityWords[marks.length];
    if (priority == null) return null;
    apply(priority);
    final labels = {
      TaskPriority.high: '高优先级',
      TaskPriority.medium: '中优先级',
      TaskPriority.low: '低优先级',
    };
    final prefixLength = (_group(m, 1) ?? _group(m, 3) ?? '').length;
    return _Candidate(
        span: SmartSpan(
            kind: SmartTokenKind.priority,
            start: m.start + prefixLength,
            end: m.end,
            raw: marks,
            label: labels[priority]!));
  }

  // ---- value helpers ------------------------------------------------------

  /// RegExpMatch.group throws RangeError for groups that did not participate
  /// in the match; treat those as null instead.
  String? _group(RegExpMatch match, int index) {
    try {
      return match.group(index);
    } on RangeError {
      return null;
    }
  }

  int? _hourValue(String text) {
    final arabic = int.tryParse(text);
    if (arabic != null) return arabic;
    if (text == '十') return 10;
    if (text.startsWith('十')) {
      final rest = _chineseDigits[text.substring(1)];
      return rest == null ? null : 10 + rest;
    }
    if (text.endsWith('十')) {
      final head = _chineseDigits[text.substring(0, text.length - 1)];
      return head == null ? null : head * 10;
    }
    if (text.contains('十')) {
      final parts = text.split('十');
      final head = _chineseDigits[parts[0]];
      final tail = _chineseDigits[parts[1]];
      if (head == null || tail == null) return null;
      return head * 10 + tail;
    }
    return _chineseDigits[text];
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _nextOccurrence(
      DateTime today, int hour, int minute, DateTime reference) {
    final candidate =
        DateTime(today.year, today.month, today.day, hour, minute);
    if (candidate.isAfter(reference)) return candidate;
    return candidate.add(const Duration(days: 1));
  }

  DateTime? _resolveDayWord(String? raw, DateTime today) {
    if (raw == null) return null;
    switch (raw) {
      case '今天':
      case '今日':
      case '今早':
      case '今晚':
        return today;
      case '明天':
      case '明日':
      case '明早':
      case '明晨':
      case '明晚':
        return today.add(const Duration(days: 1));
      case '后天':
        return today.add(const Duration(days: 2));
      case '大后天':
        return today.add(const Duration(days: 3));
    }
    return null;
  }

  String _dateLabel(DateTime date, bool withTime) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final base = '${date.month}月${date.day}日·周${weekdays[date.weekday - 1]}';
    if (!withTime) return base;
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$base $hh:$mm';
  }
}

typedef _CandidateFactory = _Candidate? Function(
    RegExpMatch match, String input);

class _Candidate {
  const _Candidate({
    required this.span,
    this.due,
    this.hasTime = false,
    this.recurrenceType,
    this.recurrenceConfig,
  });

  final SmartSpan span;

  /// Span offsets forwarded for the greedy overlap filter.
  int get start => span.start;
  int get end => span.end;
  final DateTime? due;
  final bool hasTime;
  final String? recurrenceType;
  final Map<String, dynamic>? recurrenceConfig;
}
