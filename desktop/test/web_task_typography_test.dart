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
  testWidgets('task rows use the Web title, supporting and metadata roles',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final task = TaskItem(
      id: 'web-typography-row',
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

    final title = tester.widget<Text>(find.text(task.title));
    expect(title.style?.fontSize, WorkFollowTypography.webListTitleSize);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.style?.height, WorkFollowTypography.webLineHeightNormal);
    expect(title.style?.color, WorkFollowTheme.light.textPrimary);

    final description = tester.widget<Text>(
        find.byKey(const ValueKey('task-row-preview-web-typography-row')));
    expect(description.style?.fontSize,
        WorkFollowTypography.webSupportingCompactSize);
    expect(description.style?.fontWeight, FontWeight.w400);
    expect(description.style?.height, WorkFollowTypography.webLineHeightNormal);
    expect(description.style?.color, WorkFollowTheme.light.textSecondary);

    final date = tester.widget<Text>(
        find.byKey(const ValueKey('task-row-date-web-typography-row')));
    expect(date.style?.fontSize, WorkFollowTypography.webMetaSize);
    expect(date.style?.fontWeight, FontWeight.w400);
    expect(date.style?.height, WorkFollowTypography.webLineHeightNormal);

    final row = tester.getRect(find.byType(AnimatedContainer));
    expect(row.height,
        greaterThanOrEqualTo(WorkFollowMetrics.taskRowComfortableHeight));
  });

  testWidgets('fixed task detail uses Web editor title and body roles',
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
    expect(title.style?.fontSize, WorkFollowTypography.webEditorTitleSize);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.height, WorkFollowTypography.webLineHeightSnug);

    final editor = tester.widget<quill.QuillEditor>(
        find.byKey(const ValueKey('task-document-editor')));
    final paragraph = editor.config.customStyles?.paragraph?.style;
    expect(paragraph?.fontSize, WorkFollowTypography.webEditorBodySize);
    expect(paragraph?.fontWeight, FontWeight.w400);
    expect(paragraph?.height, WorkFollowTypography.webLineHeightEditor);
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
              inline: true,
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
    final deleteRect =
        tester.getRect(find.byKey(const ValueKey('menu-option-delete')));
    expect(deleteRect.bottom, lessThanOrEqualTo(triggerRect.top));
    expect(triggerRect.top - deleteRect.bottom, lessThan(20));
  });
}
