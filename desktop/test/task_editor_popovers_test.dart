import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
Finder keyed(String key) => find.byKey(ValueKey(key));
final boundary = GlobalKey();
Future<void> mount(WidgetTester tester, WorkspaceController c,
    {Size size = const Size(796, 940), bool dark = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? WorkFollowThemeData.dark() : WorkFollowThemeData.light(),
        home: Scaffold(
            body: AnimatedBuilder(
                animation: c,
                builder: (_, __) =>
                    TaskInspector(task: c.tasks.first, controller: c))),
      )));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(keyed(key));
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

Future<void> escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, String name) async {
  if (!capture) return;
  final shadows = debugDisableShadows;
  debugDisableShadows = false;
  await tester.pump();
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../docs/screenshots/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
  debugDisableShadows = shadows;
  await tester.pump();
}

WorkspaceController workspace() {
  final c = WorkspaceController(seedData: false);
  addTearDown(c.dispose);
  c.addTask('测试');
  c.selectTask(c.tasks.single.id);
  c.updateTaskDescription(c.tasks.single.id, '是的爱上');
  return c;
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    final bytes = ByteData.sublistView(
        File('/System/Library/Fonts/Hiragino Sans GB.ttc').readAsBytesSync());
    for (final family in [
      'Inter',
      'Noto Sans SC',
      'PingFang SC',
      'Roboto',
      'Ahem',
      '.SF Pro Text',
      '.SF Pro Display'
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets(
      'four inspector popovers match reference placement and expose only supported actions',
      (tester) async {
    if (capture) {
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
    }
    final c = workspace();
    c.addList('去');
    c.addList('欢迎');
    c.updateTaskDue(c.tasks.single.id, DateTime(2026, 9, 8));
    await mount(tester, c);
    for (final item in [
      ('task-list-footer', 'task-list-picker', 'task-editor-list'),
      ('task-schedule', 'task-schedule-panel', 'task-editor-date'),
      ('document-format-toggle', 'document-editor-toolbar', 'task-editor-format'),
      ('task-more-actions', 'task-more-menu', 'task-editor-more')
    ]) {
      await tap(tester, item.$1);
      final rect = tester.getRect(keyed(item.$2));
      final trigger = tester.getRect(keyed(item.$1));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(796));
      if (item.$1 == 'task-schedule') {
        expect(rect.top, greaterThan(trigger.bottom));
      } else {
        expect(rect.bottom, lessThan(trigger.top));
      }
      if (item.$1 == 'document-format-toggle')
        expect(rect.center.dx, closeTo(398, 1));
      await shot(tester, item.$3);
      expect(tester.takeException(), isNull);
      if (item.$1 == 'task-more-actions') {
        for (final excluded in [
          'duplicate',
          'copy-link',
          'open-note',
          'reminder',
          'repeat',
          'list',
          'copy'
        ]) {
          expect(keyed('menu-option-$excluded'), findsNothing);
        }
        expect(find.text('上传附件'), findsOneWidget);
        expect(find.text('任务动态'), findsNothing);
        expect(find.text('打印'), findsNothing);
      }
      await escape(tester);
    }
    await tap(tester, 'task-list-footer');
    await tester.enterText(keyed('task-list-search'), '去');
    await tester.pump();
    expect(keyed('menu-option-欢迎'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(c.tasks.single.listName, '去');
    if (capture) debugDisableShadows = true;
  });

  testWidgets(
      'date range commits time and nested repetition only on confirm; clear removes schedule',
      (tester) async {
    final c = workspace();
    final id = c.tasks.single.id;
    c.updateTaskDue(id, DateTime(2030, 9, 8));
    await mount(tester, c);
    await tap(tester, 'task-schedule');
    await tap(tester, 'schedule-repeat');
    await tap(tester, 'repeat-DAILY');
    expect(c.tasks.single.recurrenceType, 'NONE');
    await escape(tester);
    expect(c.tasks.single.recurrenceType, 'NONE');
    expect(
        localDateTimeFromStorage(c.tasks.single.dueAt), DateTime(2030, 9, 8));
    await tap(tester, 'task-schedule');
    await tap(tester, 'schedule-range-tab');
    await tap(tester, 'pick-day-2030-09-10');
    await tap(tester, 'pick-day-2030-09-12');
    await tap(tester, 'schedule-time');
    await tester.enterText(keyed('schedule-time-input'), '09:30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(tester, 'schedule-end-time');
    await tester.enterText(keyed('schedule-time-input'), '18:45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(tester, 'schedule-repeat');
    await tap(tester, 'repeat-DAILY');
    await tap(tester, 'apply-date');
    expect(localDateTimeFromStorage(c.tasks.single.dueAt),
        DateTime(2030, 9, 10, 9, 30));
    expect(localDateTimeFromStorage(c.tasks.single.dueEndAt),
        DateTime(2030, 9, 12, 18, 45));
    expect(c.tasks.single.recurrenceType, 'DAILY');
    expect(c.tasks.single.scheduledWithTime, isTrue);
    await tap(tester, 'task-schedule');
    expect(find.text('结束 9月12日'), findsOneWidget);
    await tap(tester, 'date-clear');
    expect(c.tasks.single.dueAt, isNull);
    expect(c.tasks.single.dueEndAt, isNull);
    expect(c.tasks.single.recurrenceType, 'NONE');
    expect(c.tasks.single.scheduledWithTime, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'schedule reference menus support multiple reminders, repeat ending and draft cancellation',
      (tester) async {
    if (capture) {
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
    }
    final c = workspace();
    final id = c.tasks.single.id;
    c.taskActions.setScheduleSettings(
        id,
        TaskScheduleSettings(
          schedule: TaskScheduleDraft(
              dueAt: DateTime(2026, 9, 15, 11), hasTime: true),
          reminderOffsets: const [0, 30],
          recurrence:
              const RecurrenceDraft(type: 'WEEKLY', config: {'weekday': 2}),
        ));
    await mount(tester, c);
    await tap(tester, 'task-schedule');
    await shot(tester, 'task-date-overview');
    await tap(tester, 'schedule-time');
    expect(keyed('time-slot-11:00'), findsOneWidget);
    await shot(tester, 'task-date-time');
    await tap(tester, 'time-slot-11:30');
    expect(c.tasks.single.reminderOffsets, [0, 30]);
    await tap(tester, 'schedule-reminder');
    await shot(tester, 'task-date-reminders');
    await tap(tester, 'reminder-offset-5');
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tap(tester, 'schedule-reminder');
    await tap(tester, 'reminder-offset-5');
    await tap(tester, 'confirm-schedule-option');
    await tap(tester, 'schedule-repeat');
    await shot(tester, 'task-date-repeat');
    await tap(tester, 'repeat-WEEKLY');
    await tap(tester, 'schedule-repeat-end');
    await shot(tester, 'task-date-ending');
    await tap(tester, 'repeat-end-count');
    await tester.enterText(keyed('repeat-end-count-input'), '3');
    await tap(tester, 'confirm-schedule-option');
    await tap(tester, 'apply-date');
    expect(c.tasks.single.reminderOffsets, [0, 5, 30]);
    expect(c.tasks.single.recurrenceConfig?['count'], 3);
    expect(localDateTimeFromStorage(c.tasks.single.dueAt),
        DateTime(2026, 9, 15, 11, 30));
    await tap(tester, 'task-schedule');
    await tap(tester, 'schedule-reminder');
    await tap(tester, 'schedule-option-clear');
    await escape(tester);
    expect(c.tasks.single.reminderOffsets, [0, 5, 30]);
    expect(tester.takeException(), isNull);
    if (capture) debugDisableShadows = true;
  });

  testWidgets(
      'narrow date menus accept custom reminder and inclusive ending date',
      (tester) async {
    final c = workspace();
    final id = c.tasks.single.id;
    c.updateTaskDue(id, DateTime(2030, 9, 15));
    await mount(tester, c, size: const Size(360, 640));
    await tap(tester, 'task-schedule');
    await tap(tester, 'schedule-time');
    await tester.enterText(keyed('schedule-time-input'), '25:00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('请输入 00:00 至 23:59'), findsOneWidget);
    await tester.enterText(keyed('schedule-time-input'), '10:15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(tester, 'schedule-reminder');
    await tap(tester, 'reminder-custom');
    await tester.enterText(keyed('reminder-custom-amount'), '90');
    await tap(tester, 'confirm-schedule-option');
    await tap(tester, 'schedule-repeat');
    await tap(tester, 'repeat-DAILY');
    await tap(tester, 'schedule-repeat-end');
    await tap(tester, 'repeat-end-date');
    await tester.ensureVisible(find.text('20').last);
    await tester.tap(find.text('20').last);
    await tester.pumpAndSettle();
    await tap(tester, 'confirm-schedule-option');
    await tap(tester, 'apply-date');
    expect(c.tasks.single.reminderOffsets, [90]);
    expect(c.tasks.single.reminderTimes.single, DateTime(2030, 9, 15, 8, 45));
    expect(c.tasks.single.recurrenceConfig?['endDate'],
        DateTime(2030, 9, 20).toIso8601String());
    expect(tester.takeException(), isNull);
  });

  test('schedule, range, reminder and repeat undo together', () {
    final c = workspace();
    final before = c.tasks.single;
    final result = c.taskActions.setScheduleSettings(
        before.id,
        TaskScheduleSettings(
          schedule:
              TaskScheduleDraft(dueAt: DateTime(2030, 9, 10, 9), hasTime: true),
          endAt: DateTime(2030, 9, 11, 10),
          reminderAt: DateTime(2030, 9, 10, 8),
          recurrence: const RecurrenceDraft(type: 'DAILY'),
        ));
    expect(result.success, isTrue);
    expect(c.tasks.single.dueEndAt, isNotNull);
    expect(c.tasks.single.reminderAt, isNotNull);
    c.taskActions.setSchedule(before.id,
        TaskScheduleDraft(dueAt: DateTime(2030, 9, 15, 9), hasTime: true));
    expect(localDateTimeFromStorage(c.tasks.single.dueEndAt),
        DateTime(2030, 9, 16, 10));
    c.taskActions.clearSchedule(before.id);
    expect(c.tasks.single.dueEndAt, isNull);
    result.undo!.execute();
    expect(c.tasks.single.dueAt, before.dueAt);
    expect(c.tasks.single.dueEndAt, before.dueEndAt);
    expect(c.tasks.single.reminderAt, before.reminderAt);
    expect(c.tasks.single.recurrenceType, before.recurrenceType);
  });

  testWidgets(
      'formatting toggles and all current-time formats insert at preserved caret',
      (tester) async {
    if (capture) debugDisableShadows = false;
    final c = workspace();
    await mount(tester, c);
    final editor = tester
        .widget<quill.QuillEditor>(keyed('task-document-editor'))
        .controller;
    editor.replaceText(0, editor.document.length - 1, '前后',
        const TextSelection(baseOffset: 0, extentOffset: 1));
    await tap(tester, 'document-format-toggle');
    await tap(tester, 'document-format-bold');
    expect(editor.getSelectionStyle().attributes['bold']?.value, true);
    await tap(tester, 'document-format-bold');
    expect(editor.getSelectionStyle().attributes['bold'], isNull);
    await tap(tester, 'document-format-heading');
    await tap(tester, 'document-format-heading-2');
    expect(editor.getSelectionStyle().attributes['header']?.value, 2);
    await tap(tester, 'document-format-heading');
    await tap(tester, 'document-format-heading-0');
    expect(editor.getSelectionStyle().attributes['header'], isNull);
    await tap(tester, 'document-format-checklist');
    expect(editor.getSelectionStyle().attributes['list']?.value, 'unchecked');
    await tap(tester, 'document-format-checklist');
    expect(editor.getSelectionStyle().attributes['list'], isNull);
    for (final kind in ['date', 'datetime', 'time']) {
      editor.replaceText(0, editor.document.length - 1, '前后',
          const TextSelection.collapsed(offset: 1));
      await tap(tester, 'document-format-time');
      if (kind == 'date') await shot(tester, 'task-editor-time');
      final option = keyed('document-insert-$kind');
      final value = tester
          .widget<Text>(
              find.descendant(of: option, matching: find.byType(Text)).first)
          .data!;
      await tap(tester, 'document-insert-$kind');
      expect(editor.document.toPlainText(), '前${value}后\n');
      expect(editor.selection.baseOffset, 1 + value.length);
      expect(c.tasks.single.description, contains(value));
    }
    expect(tester.takeException(), isNull);
    if (capture) debugDisableShadows = true;
  });
  testWidgets('popovers remain usable in a narrow dark inspector',
      (tester) async {
    final c = workspace();
    await mount(tester, c, size: const Size(360, 600), dark: true);
    for (final entry in [
      ('task-list-footer', 'task-list-picker'),
      ('task-schedule', 'task-schedule-panel'),
      ('document-format-toggle', 'document-editor-toolbar'),
      ('task-more-actions', 'task-more-menu')
    ]) {
      await tap(tester, entry.$1);
      final rect = tester.getRect(keyed(entry.$2));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
      await escape(tester);
    }
    // 截止日期 left the `/` palette, whose job is now the twelve
    // reference commands. The more menu does not absorb them either: it is the
    // seven-entry reference list and clears its anchor by roughly 20pt in the
    // 900x700 anchoring regression, so one extra row flips it under the
    // trigger. Their entry point is a separate decision; what this narrow
    // inspector has to keep is the seven reference rows.
    await tap(tester, 'task-more-actions');
    for (final entry in [
      'add-subtask',
      'pin',
      'abandon',
      'tags',
      'attachment',
      'convert-note',
      'delete',
    ]) {
      expect(keyed('menu-option-$entry'), findsOneWidget, reason: entry);
    }
    for (final absent in ['deadline', 'focus', 'relation']) {
      expect(keyed('menu-option-$absent'), findsNothing, reason: absent);
    }
  });
}
