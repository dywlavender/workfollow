import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_document_editor.dart';

/// The slash palette's 子任务 entry.
///
/// It has been a silent no-op once already: `TaskDocumentEditor` held the
/// inspector's `onAddChildTask` and never handed it to the profile, so the core
/// called `null` — the menu opened, the command closed it, and nothing was
/// written. The two cases below pin both halves of the fix: the parent's
/// palette runs the command, and a child is not offered it at all.
void main() {
  Finder option(String name) =>
      find.byKey(ValueKey('document-slash-option-$name'));

  /// Mounts the real editor, wrapped in the controller rebuild the shell
  /// normally provides — the trailing panels are decided during this build, so
  /// without it a new child could never make the panel appear.
  Future<TaskDocumentEditorState> mountEditor(
    WidgetTester tester,
    WorkspaceController controller, {
    required String taskId,
    VoidCallback? onAddChildTask,
  }) async {
    final key = GlobalKey<TaskDocumentEditorState>();
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => TaskDocumentEditor(
            key: key,
            task: controller.tasks.firstWhere((task) => task.id == taskId),
            controller: controller,
            onAddChildTask: onAddChildTask,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Future<void> typeSlash(WidgetTester tester,
      TaskDocumentEditorState state, String value) async {
    await tester.tap(find.byKey(const ValueKey('task-document-editor')));
    final slashOffset = value.lastIndexOf('/');
    final beforeSlash = value.substring(0, slashOffset);
    state.editor.replaceText(0, state.editor.document.length - 1, beforeSlash,
        TextSelection.collapsed(offset: beforeSlash.length));
    await tester.pump();
    state.editor.replaceText(beforeSlash.length, 0, '/',
        TextSelection.collapsed(offset: slashOffset + 1));
    await tester.pumpAndSettle();
  }

  void sizeUp(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('SUB-130 the parent palette adds a child and the panel shows it',
      (tester) async {
    sizeUp(tester);
    final c = WorkspaceController(seedData: false)..addTask('斜杠父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final editor = await mountEditor(tester, c,
        taskId: parentId, onAddChildTask: () => c.createChildTask(parentId));

    await typeSlash(tester, editor, '/');
    expect(option('subtask'), findsOneWidget);

    await tester.tap(option('subtask'));
    await tester.pumpAndSettle();

    // The command ran, the child is real data, and the panel that only renders
    // once a child exists is on screen with a row of its own.
    expect(c.childrenOf(parentId), hasLength(1));
    final childId = c.childrenOf(parentId).single.id;
    expect(find.byKey(const ValueKey('task-children-panel')), findsOneWidget);
    expect(find.byKey(ValueKey('task-child-row-$childId')), findsOneWidget);

    // New children are named in place: the panel claims the pending focus on
    // the frame it is first built in, which is the same frame as the notify.
    final field = tester.widget<TextField>(
        find.byKey(ValueKey('task-child-title-$childId')));
    expect(field.focusNode!.hasFocus, isTrue,
        reason: 'the new child row takes focus so it can be typed into');
  });

  testWidgets('SUB-131 a child is offered the palette without 子任务',
      (tester) async {
    sizeUp(tester);
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '子任务')!;

    // Both surfaces in one run: the rule is a difference between a parent and a
    // child, and a one-sided expectation could not see the two drift apart.
    final parent = await mountEditor(tester, c,
        taskId: parentId, onAddChildTask: () => c.createChildTask(parentId));
    await typeSlash(tester, parent, '/');
    expect(option('subtask'), findsOneWidget,
        reason: 'a parent task can still grow a child');

    final child = await mountEditor(tester, c,
        taskId: childId, onAddChildTask: () => c.createChildTask(childId));
    await typeSlash(tester, child, '/');
    expect(option('subtask'), findsNothing,
        reason: 'one nesting level: a child is not offered the command');
    // The rest of the task palette is untouched — this removes one command,
    // not the group.
    expect(option('attachment'), findsOneWidget);
    expect(option('tag'), findsOneWidget);
    expect(option('relation'), findsOneWidget);
    expect(option('heading-1'), findsOneWidget);
  });
}
