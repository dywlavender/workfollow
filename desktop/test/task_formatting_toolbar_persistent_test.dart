import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

void main() {
  testWidgets('format toolbar stays open across document and format actions',
      (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('持久工具栏');
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
    editor.replaceText(0, editor.document.length - 1, '这段文字',
        const TextSelection(baseOffset: 0, extentOffset: 4));
    editor.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 4),
        quill.ChangeSource.local);
    await tester.pump();

    final toggle = find.byKey(const ValueKey('task-format-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);

    final documentRect =
        tester.getRect(find.byKey(const ValueKey('task-document-editor')));
    await tester.tapAt(documentRect.topLeft + const Offset(24, 42));
    await tester.pump();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-format-bold')));
    await tester.pump();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsNothing);
  });

  testWidgets('Escape closes the toolbar before the inspector', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('Escape 工具栏');
    final task = controller.tasks.single;
    controller.selectTask(task.id);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsNothing);
    expect(controller.selectedTaskId, task.id);

    await tester.tap(find.byKey(const ValueKey('task-format-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-title-editor')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsNothing);
  });

  testWidgets('switching tasks clears the persistent toolbar overlay',
      (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('第一个任务');
    final first = controller.tasks.single;
    controller.addTask('第二个任务');
    final second = controller.tasks.first;
    final inspectorKey = GlobalKey();

    Future<void> pumpTask(TaskItem task) async {
      await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: TaskInspector(
          key: inspectorKey,
          task: task,
          controller: controller,
        )),
      ));
      await tester.pumpAndSettle();
    }

    await pumpTask(first);
    await tester.tap(find.byKey(const ValueKey('task-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsOneWidget);

    await pumpTask(second);
    expect(find.byKey(const ValueKey('task-editor-toolbar')), findsNothing);
  });

  testWidgets('format toolbar is reclamped after a window resize',
      (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('调整大小');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TaskInspector(task: task, controller: controller)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-format-toggle')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    final rect =
        tester.getRect(find.byKey(const ValueKey('task-editor-toolbar')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });
}
