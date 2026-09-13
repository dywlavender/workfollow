import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/services/smart_date_parser.dart';

void main() {
  const parser = SmartDateParser();

  // A fixed reference moment: 2026-09-13 (Sunday) 16:00.
  final now = DateTime(2026, 9, 13, 16, 0);
  final today = DateTime(2026, 9, 13);
  final tomorrow = DateTime(2026, 9, 14);

  SmartParseResult run(String input) => parser.parse(input, now: now);

  test('plain title parses to nothing', () {
    final result = run('买牛奶');
    expect(result.title, '买牛奶');
    expect(result.dueAt, isNull);
    expect(result.hasStructure, isFalse);
    expect(result.priority, TaskPriority.none);
    expect(result.tags, isEmpty);
    expect(result.listName, isNull);
  });

  test('relative day words', () {
    expect(run('今天交报告').dueAt, today);
    expect(run('明天交报告').dueAt, tomorrow);
    expect(run('后天交报告').dueAt, today.add(const Duration(days: 2)));
    expect(run('大后天交报告').dueAt, today.add(const Duration(days: 3)));
    expect(run('明天交报告').hasTime, isFalse);
    expect(run('明天交报告').title, '交报告');
  });

  test('weekday words pick the next occurrence', () {
    // Reference is Sunday (weekday 7). 周一 -> tomorrow.
    final monday = run('周五理账').dueAt!;
    expect(monday.day, 18); // next Friday
    expect(run('周一开会').dueAt, tomorrow);
    expect(run('下周三提交').dueAt, DateTime(2026, 9, 23));
    expect(run('下周三提交').title, '提交');
  });

  test('explicit month-day dates roll to next year when past', () {
    final result = run('9月20日取件');
    expect(result.dueAt, DateTime(2026, 9, 20));
    expect(result.hasTime, isFalse);
    // Jan 5 is before the September reference; rolls to 2027.
    expect(run('1月5号复查').dueAt, DateTime(2027, 1, 5));
  });

  test('clock time picks the next occurrence', () {
    // 16:00 now: 下午3点 is past, so it becomes tomorrow 15:00.
    final past = run('下午3点打电话');
    expect(past.dueAt, DateTime(2026, 9, 14, 15, 0));
    expect(past.hasTime, isTrue);
    expect(past.reminderAt, past.dueAt);
    // 晚上9点 is ahead today.
    expect(run('晚上9点跑步').dueAt, DateTime(2026, 9, 13, 21, 0));
    // 上午10点 is past -> tomorrow.
    expect(run('上午10点开会').dueAt, DateTime(2026, 9, 14, 10, 0));
  });

  test('numeric clock times', () {
    expect(run('18:30 晚餐').dueAt, DateTime(2026, 9, 13, 18, 30));
    expect(run('9:00站会').dueAt, DateTime(2026, 9, 14, 9, 0));
  });

  test('half hour and bare hour', () {
    expect(run('下午3点半取件').dueAt, DateTime(2026, 9, 14, 15, 30));
    final nine = run('9点提醒我');
    expect(nine.dueAt, DateTime(2026, 9, 14, 9, 0));
    expect(nine.title, '提醒我');
  });

  test('combined contractions imply time of day', () {
    expect(run('今晚8点看电影').dueAt, DateTime(2026, 9, 13, 20, 0));
    expect(run('明早9点晨会').dueAt, DateTime(2026, 9, 14, 9, 0));
    expect(run('明晚10点复盘').dueAt, DateTime(2026, 9, 14, 22, 0));
  });

  test('separate date word and clock time merge', () {
    final result = run('明天 下午3点 面试');
    expect(result.dueAt, DateTime(2026, 9, 14, 15, 0));
    expect(result.hasTime, isTrue);
    expect(result.title, '面试');
  });

  test('relative hours and minutes', () {
    expect(run('2小时后回访').dueAt, now.add(const Duration(hours: 2)));
    expect(run('半小时后取快递').dueAt, now.add(const Duration(minutes: 30)));
    expect(run('30分钟后休息').dueAt, now.add(const Duration(minutes: 30)));
    expect(run('3天后出发').dueAt, today.add(const Duration(days: 3)));
  });

  test('recurrence rules', () {
    final daily = run('每天喝水');
    expect(daily.recurrenceType, 'DAILY');
    expect(daily.title, '喝水');
    final weekly = run('每周一例会');
    expect(weekly.recurrenceType, 'WEEKLY');
    expect(weekly.recurrenceConfig, {'weekday': 1});
    final monthly = run('每月1号交租');
    expect(monthly.recurrenceType, 'MONTHLY');
    expect(monthly.recurrenceConfig, {'dayOfMonth': 1});
    expect(monthly.title, '交租');
  });

  test('recurrence plus clock time lands on the next matching day', () {
    // 每周日 + 9点: today IS Sunday but 9:00 is past -> next Sunday.
    final result = run('每周日 9点大扫除');
    expect(result.recurrenceType, 'WEEKLY');
    expect(result.recurrenceConfig, {'weekday': 7});
    expect(result.dueAt, DateTime(2026, 9, 20, 9, 0));
  });

  test('tags, list marker and priority', () {
    final result = run('#工作 准备评审');
    expect(result.tags, ['工作']);
    expect(result.title, '准备评审');

    final list = run('整理衣柜 @个人');
    expect(list.listName, '个人');
    expect(list.title, '整理衣柜');

    final priority = run('!!!立即报修');
    expect(priority.priority, TaskPriority.high);
    expect(priority.title, '立即报修');

    final mixed = run('!!中期检查 准备材料');
    expect(mixed.priority, TaskPriority.medium);
    expect(mixed.title, '中期检查 准备材料');
    expect(mixed.spans.where((span) => span.kind == SmartTokenKind.priority),
        hasLength(1));
    // A lone '!' before text is punctuation, not a priority marker.
    final stray = run('真好看!');
    expect(stray.priority, TaskPriority.none);
  });

  test('kitchen sink input keeps order and strips all tokens', () {
    final result = run('明早9点 #工作 @个人 !!!准备季度评审');
    expect(result.title, '准备季度评审');
    expect(result.dueAt, DateTime(2026, 9, 14, 9, 0));
    expect(result.hasTime, isTrue);
    expect(result.tags, ['工作']);
    expect(result.listName, '个人');
    expect(result.priority, TaskPriority.high);
    // Four recognised spans: date, tag, list, priority.
    expect(result.spans, hasLength(4));
    expect(
        result.spans.map((span) => span.kind),
        containsAllInOrder(<SmartTokenKind>[
          SmartTokenKind.date,
          SmartTokenKind.tag,
          SmartTokenKind.list,
          SmartTokenKind.priority,
        ]));
  });

  test('numbers inside the title survive parsing', () {
    final result = run('准备第3版方案');
    expect(result.title, '准备第3版方案');
    expect(result.dueAt, isNull);
  });

  test('span offsets stay valid against the original input', () {
    final input = '明天下午3点 #工作 评审';
    final result = run(input);
    for (final span in result.spans) {
      expect(input.substring(span.start, span.end), span.raw);
    }
  });

  test('invalid dates do not crash or misfire', () {
    expect(run('13月40日看看').dueAt, isNull);
    expect(run('99:99 输入').dueAt, isNull);
  });
}
