import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/app_icon_button.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';
import 'package:workfollow_personal/widgets/task_row.dart';

void main() {
  testWidgets(
      'task rows use the compact macOS title, description and meta steps',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final task = TaskItem(
      id: 'mac-typography-row',
      title: '任务标题',
      listName: '收集箱',
      bucket: TaskBucket.today,
      description: '任务描述',
      dueAt: DateTime(2026, 9, 15, 10, 30).toIso8601String(),
      hasDueTime: true,
    );

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskRow(
          task: task,
          controller: controller,
          selected: false,
        ),
      ),
    ));
    await tester.pump();

    // Title weight stays regular: priority and state are carried by the
    // checkbox, flag and color, never by a heavier face.
    final title = tester.widget<Text>(find.text(task.title));
    expect(title.style?.fontSize, WorkFollowMacTypography.listTitle);
    expect(title.style?.fontWeight, WorkFollowMacWeight.regular);
    expect(title.style?.height, WorkFollowMacTypography.lineList);
    expect(title.style?.color, WorkFollowTheme.light.textPrimary);

    final description = tester.widget<Text>(
        find.byKey(const ValueKey('task-row-preview-mac-typography-row')));
    expect(description.style?.fontSize, WorkFollowMacTypography.listBody);
    expect(description.style?.fontWeight, WorkFollowMacWeight.regular);
    expect(description.style?.height, WorkFollowMacTypography.lineList);
    expect(description.style?.color, WorkFollowTheme.light.textSecondary);

    final date = tester.widget<Text>(
        find.byKey(const ValueKey('task-row-date-mac-typography-row')));
    expect(date.style?.fontSize, WorkFollowMacTypography.listMeta);
    expect(date.style?.fontWeight, WorkFollowMacWeight.regular);
    expect(date.style?.height, WorkFollowMacTypography.lineControl);

    final row = tester.getRect(
        find.byKey(const ValueKey('task-row-surface-mac-typography-row')));
    expect(row.height,
        greaterThanOrEqualTo(WorkFollowMetrics.taskRowComfortableHeight));
  });

  testWidgets('fixed task detail uses the macOS detail title and body roles',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('详情标题');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();

    final title = tester
        .widget<TextField>(find.byKey(const ValueKey('task-title-editor')));
    expect(title.style?.fontSize, WorkFollowMacTypography.detailTitle);
    expect(title.style?.fontWeight, WorkFollowMacWeight.semibold);
    expect(title.style?.height, WorkFollowMacTypography.lineControl);
    expect(title.style?.letterSpacing, WorkFollowMacTracking.none);

    // The body measure is the headline fix of this pass: the editor used to
    // inherit the Web document line height (1.85) and read far too loose.
    final editor = tester.widget<quill.QuillEditor>(
        find.byKey(const ValueKey('task-document-editor')));
    final paragraph = editor.config.customStyles?.paragraph?.style;
    expect(paragraph?.fontSize, WorkFollowMacTypography.body);
    expect(paragraph?.fontWeight, WorkFollowMacWeight.regular);
    expect(paragraph?.height, WorkFollowMacTypography.lineBody);
    expect(paragraph?.letterSpacing, WorkFollowMacTracking.none);
    expect(paragraph?.color, WorkFollowTheme.light.textPrimary);

    final schedule = find.descendant(
        of: find.byKey(const ValueKey('task-schedule')),
        matching: find.byType(AppIcon));
    expect(
        tester.widget<AppIcon>(schedule).size, WorkFollowMetrics.toolbarIcon);
  });

  testWidgets('inline task menu remains anchored to the footer',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('内嵌菜单任务');
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.dark(),
      home: Scaffold(
        body: ListView(
          children: [
            TaskInspector(
              task: controller.tasks.single,
              controller: controller,
              presentation: TaskInspectorPresentation.inline,
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final trigger = find.byKey(const ValueKey('task-more-actions'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final triggerRect = tester.getRect(trigger);
    await tester
        .ensureVisible(find.byKey(const ValueKey('menu-option-delete')));
    await tester.pumpAndSettle();
    final deleteRect =
        tester.getRect(find.byKey(const ValueKey('menu-option-delete')));
    expect(deleteRect.bottom, lessThanOrEqualTo(triggerRect.top));
    expect(triggerRect.top - deleteRect.bottom, lessThan(20));
  });

  test('macOS resolves to the system face instead of the Inter Web stack', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final theme = WorkFollowThemeData.light();
    expect(WorkFollowMacTypeFamily.ui, isNull,
        reason: 'null lets Flutter resolve the macOS system face');
    expect(theme.textTheme.bodyLarge?.fontFamily, isNot('Inter'));
    expect(theme.textTheme.bodyLarge?.fontFamilyFallback,
        WorkFollowMacTypeFamily.fallback);
    expect(WorkFollowMacTypeFamily.fallback, contains('PingFang SC'));
    expect(WorkFollowMacTypeFamily.fallback, isNot(contains('Noto Sans SC')));
  });

  test('the macOS type scale stays on one set of named steps', () {
    // A guard, not decoration: the app used to carry one-off sizes per widget
    // (10 / 10.5 / 11.5 / 12.5 / 13.5 / 15 / 16 / 19 / 21 / 22 / 26). A new size
    // has to be named in WorkFollowMacTypography first.
    const sizes = <double>[
      WorkFollowMacTypography.pageTitle,
      WorkFollowMacTypography.sectionTitle,
      WorkFollowMacTypography.navigation,
      WorkFollowMacTypography.navigationMeta,
      WorkFollowMacTypography.listTitle,
      WorkFollowMacTypography.listBody,
      WorkFollowMacTypography.listMeta,
      WorkFollowMacTypography.detailTitle,
      WorkFollowMacTypography.noteTitle,
      WorkFollowMacTypography.body,
      WorkFollowMacTypography.supporting,
      WorkFollowMacTypography.documentH1,
      WorkFollowMacTypography.documentH2,
      WorkFollowMacTypography.documentH3,
      WorkFollowMacTypography.control,
      WorkFollowMacTypography.menu,
      WorkFollowMacTypography.caption,
    ];
    expect(sizes.length, 17);

    // The job is unified, not the pixel. These pairs deliberately share a
    // value; they are separate names because they are separate roles, and a
    // change to one must not silently move the other.
    expect(WorkFollowMacTypography.sectionTitle, 13);
    expect(WorkFollowMacTypography.control, 13);
    expect(WorkFollowMacTypography.listMeta, 12);
    expect(WorkFollowMacTypography.supporting, 12);
    expect(WorkFollowMacTypography.navigationMeta, 12);
    expect(WorkFollowMacTypography.navigation, 14);
    expect(WorkFollowMacTypography.listTitle, 14);
    expect(WorkFollowMacTypography.body, 14);
    expect(WorkFollowMacTypography.menu, 14);
    expect(WorkFollowMacTypography.documentH1, 22);
    expect(WorkFollowMacTypography.documentH2, 19);
    expect(WorkFollowMacTypography.documentH3, 16);

    // Calibrated against the reference screenshots rather than rounded to
    // whole pixels: 20 read heavy for the page heading, and 13 was a full step
    // too prominent for the task preview under a 14pt task title.
    expect(WorkFollowMacTypography.pageTitle, 19);
    expect(WorkFollowMacTypography.listBody, 12.5);
    // The note page is a canvas, not a form: the document title owns the page
    // and sits at 26 rather than borrowing the inspector's 18, where it read as
    // one more field label above a 760pt body column.
    expect(WorkFollowMacTypography.noteTitle, 26);

    expect(WorkFollowMacWeight.regular, FontWeight.w400);
    expect(WorkFollowMacWeight.medium, FontWeight.w500);
    expect(WorkFollowMacWeight.semibold, FontWeight.w600);
    expect(WorkFollowMacTracking.none, 0);

    // Non-text display sizes are named too, so no widget carries a bare size.
    expect(WorkFollowMacDisplay.glyphLabel, 16);
    expect(WorkFollowMacDisplay.timer, 42);
  });

  test('no source file carries a bare text size, weight or tracking value', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in <String>[
        // The whole point of the batch: a size may only come from a role.
        r'fontSize: *[0-9]',
        r'FontWeight\.w[0-9]00',
        r'letterSpacing: *-',
        r'WorkFollowTypography\.web(?!UiFontFamily)',
      ]) {
        final match = RegExp(pattern).firstMatch(source);
        if (match != null) {
          offenders.add('${entity.path}: ${match.group(0)}');
        }
      }
    }
    // Two deliberate exceptions, both documented at the call site:
    //  - the theme file names the Web catalog and defines the one weight set;
    //  - sidebar's 1pt invisible automation target is not a type role.
    offenders.removeWhere(
        (line) => line.contains('lib/theme/workfollow_theme.dart'));
    offenders.removeWhere((line) =>
        line.contains('lib/widgets/sidebar.dart') &&
        line.contains('fontSize: 1'));
    expect(offenders, isEmpty);
  });
}
