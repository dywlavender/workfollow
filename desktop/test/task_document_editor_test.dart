import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';
import 'package:workfollow_personal/widgets/task_list_picker.dart';

void main() {
  testWidgets('task inspector More menu stays next to the footer trigger',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('底部菜单任务');
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskInspector(
          task: controller.tasks.single,
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('task-more-actions'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final triggerRect = tester.getRect(trigger);
    final deleteRect =
        tester.getRect(find.byKey(const ValueKey('menu-option-delete')));
    expect(deleteRect.bottom, lessThanOrEqualTo(triggerRect.top));
    expect(triggerRect.top - deleteRect.bottom, lessThan(20));
    expect((triggerRect.right - deleteRect.right).abs(), lessThan(20));
  });

  testWidgets('task inspector More menu remains anchored on a Retina window',
      (tester) async {
    tester.view.physicalSize = const Size(1704, 1556);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('Retina 菜单任务');
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.dark(),
      home: Scaffold(
        body: TaskInspector(
          task: controller.tasks.single,
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final trigger = find.byKey(const ValueKey('task-more-actions'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final triggerRect = tester.getRect(trigger);
    final deleteRect =
        tester.getRect(find.byKey(const ValueKey('menu-option-delete')));
    expect(deleteRect.bottom, lessThanOrEqualTo(triggerRect.top));
    expect(triggerRect.top - deleteRect.bottom, lessThan(20));
  });

  testWidgets('inline task inspector More menu stays with its trigger',
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

  testWidgets(
      'task inspector uses a document editor without an advanced toggle',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('文档任务', listName: '收集箱');
    final task = controller.tasks.single;
    controller.selectTask(task.id);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-document-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-format-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-deadline')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-advanced-toggle')), findsNothing);
    expect(find.text('显示更多属性'), findsNothing);
  });

  testWidgets('slash menu formats a task line and offers task blocks',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('文档任务', listName: '收集箱');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('task-document-editor')))
        .controller;
    await tester.tap(find.byKey(const ValueKey('task-document-editor')));
    editor.replaceText(0, editor.document.length - 1, '/',
        const TextSelection.collapsed(offset: 1));
    await tester.pump();

    expect(find.byKey(const ValueKey('task-slash-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-slash-option-heading-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task-slash-option-checklist')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task-slash-option-subtask')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task-slash-option-attachment')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-slash-option-heading-1')));
    await tester.pump();
    final delta = editor.document.toDelta().toJson();
    expect(
        delta.any(
            (op) => op['attributes'] is Map && op['attributes']['header'] == 1),
        isTrue);
    expect(controller.tasks.single.contentJson, isNotNull);
  });

  testWidgets('slash checklist is stored as document structure',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('检查项文档');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('task-document-editor')))
        .controller;
    await tester.tap(find.byKey(const ValueKey('task-document-editor')));
    editor.replaceText(0, editor.document.length - 1, '/',
        const TextSelection.collapsed(offset: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-slash-option-checklist')));
    await tester.pump();
    final delta = editor.document.toDelta().toJson();
    expect(
        delta.any((op) =>
            op['attributes'] is Map && op['attributes']['list'] == 'checked'),
        isTrue);
    expect(controller.tasks.single.contentJson?['quillDelta'], isNotNull);
  });

  testWidgets('format toolbar applies inline formatting to selected text',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('文档任务', listName: '收集箱');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('task-document-editor')))
        .controller;
    editor.replaceText(0, editor.document.length - 1, '加粗',
        const TextSelection.collapsed(offset: 2));
    editor.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 2),
        quill.ChangeSource.local);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-format-divider')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-format-bold')));
    await tester.pump();
    expect(
        editor.document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['bold'] == true),
        isTrue);
  });

  testWidgets('attachment document block is rendered from the persisted delta',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('附件文档');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('task-document-editor')))
        .controller;
    editor.replaceText(
      0,
      editor.document.length - 1,
      quill.BlockEmbed(
          'workfollow-block',
          jsonEncode({
            'type': 'attachment',
            'attrs': {'name': '设计稿.pdf', 'localFile': '设计稿.pdf'},
          })),
      const TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(
        find.byKey(const ValueKey('task-attachment-设计稿.pdf')), findsOneWidget);
    expect(controller.tasks.single.contentJson?['quillDelta'], isNotNull);
  });

  testWidgets('slash subtask block writes real TaskSubtask records',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('带子任务的文档');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('task-document-editor')))
        .controller;
    await tester.tap(find.byKey(const ValueKey('task-document-editor')));
    editor.replaceText(0, editor.document.length - 1, '/',
        const TextSelection.collapsed(offset: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-slash-option-subtask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-subtasks-block')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('task-subtask-input')), '拆解第一步');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.tasks.single.subtasks.single.title, '拆解第一步');
  });

  testWidgets('list popover filters lists without losing current selection',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
              onPressed: () => TaskListPicker.show(context,
                  controller: controller, selected: '工作'),
              child: const Text('打开'));
        }),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-list-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-工作')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-个人')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('task-list-search')), '个人');
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-option-个人')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-工作')), findsNothing);
  });

  testWidgets('inspector More menu inserts the subtask block in context',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('更多菜单任务');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-add-subtask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-subtasks-block')), findsOneWidget);
  });

  testWidgets('inspector More menu opens the existing focus workflow',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('专注任务');
    final task = controller.tasks.single;
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskInspector(
          task: task,
          controller: controller,
          onOpenFocusTimer: () => opened = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-focus')));
    await tester.pump();
    expect(opened, isTrue);
  });
}
