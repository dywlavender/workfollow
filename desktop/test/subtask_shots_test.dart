import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
final boundary = GlobalKey();

/// S9 visual baseline: one scripted parent/child scene, eight canonical
/// captures under docs/screenshots/subtask-*.png. Run with
/// `flutter test --dart-define=WORKFOLLOW_CAPTURE=true test/subtask_shots_test.dart`.
void main() {
  setUpAll(() async {
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      for (final family in [
        'Roboto',
        'Ahem',
        '.SF Pro Text',
        '.SF Pro Display'
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('subtask visual baseline', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(RepaintBoundary(
        key: boundary, child: const WorkFollowApp(demoMode: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有任务').first);
    await tester.pumpAndSettle();
    final c = tester.widget<TodayScreen>(find.byType(TodayScreen)).controller;

    Future<void> shot(String name) async {
      if (!capture) return;
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../docs/screenshots/subtask-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    // Scene: parent with an empty child, a future child, a completed child
    // and an overdue child — every date color in one frame.
    c.addTask('2', forceUnscheduled: true);
    final parentId = c.tasks.first.id;
    c.taskActions.setContent(
        parentId,
        const {
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': '伙伴'}
              ]
            }
          ]
        },
        '伙伴');
    final empty = c.createChildTask(parentId)!;
    final done = c.createChildTask(parentId, title: '什么')!;
    final overdue = c.createChildTask(parentId, title: '问问')!;
    final future = c.createChildTask(parentId, title: '无标题 9月30日')!;
    c.taskActions.setScheduleSettings(
        done,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(
                dueAt: DateTime(2030, 10, 2), hasTime: false)));
    c.taskActions.complete(done);
    c.taskActions.setScheduleSettings(
        overdue,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(
                dueAt: DateTime(2030, 9, 4), hasTime: false)));
    c.taskActions.setScheduleSettings(
        future,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(
                dueAt: DateTime(2030, 9, 30), hasTime: false)));
    c.taskActions.setContent(
        overdue,
        const {
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': '呜呜呜'}
              ]
            }
          ]
        },
        '呜呜呜');
    c.openTask(parentId);
    await tester.pumpAndSettle();

    await shot('parent-filled');
    await shot('list-expanded');

    // Empty child detail.
    c.openTask(empty);
    await tester.pumpAndSettle();
    await shot('child-empty');

    // Child with title and body.
    c.openTask(overdue);
    await tester.pumpAndSettle();
    await shot('child-detail');

    // Fold the parent: the list tree collapses.
    c.openTask(parentId);
    await tester.pumpAndSettle();
    c.toggleTaskExpanded(parentId);
    await tester.pumpAndSettle();
    await shot('list-collapsed');
    c.toggleTaskExpanded(parentId);
    await tester.pumpAndSettle();

    // Fresh parent with only the empty child just added.
    c.addTask('刚创建的父任务', forceUnscheduled: true);
    final freshId = c.tasks.first.id;
    c.createChildTask(freshId);
    c.openTask(freshId);
    await tester.pumpAndSettle();
    await shot('parent-empty');
  });
}
