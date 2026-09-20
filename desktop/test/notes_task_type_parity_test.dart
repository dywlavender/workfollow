import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

/// A note row and a task row are the same kind of row, and a note's title field
/// and a task's title field are the same kind of field.
///
/// Neither was true before: the note index resolved a heavier title than the
/// task list (semibold, and with no line height against the task row's 1.40),
/// and the note page owned a 26pt document title against the task editor's 18.
/// Both differences lived on the note side only, so a test that looked at one
/// screen could never see them. This one mounts both sides in the same file and
/// compares the resolved styles.
///
/// It compares styles rather than numbers on purpose: the type scale is allowed
/// to be re-tuned, what is not allowed is the two screens disagreeing about it.
void main() {
  const taskTitle = '整理上周的接口评审纪要';
  const taskPreview = '把结论同步给测试与运维';
  const noteTitle = '季度评审 · 叙事结构';

  Finder taskRow(String id) => find.byKey(ValueKey('task-row-surface-$id'));
  Finder noteRow(String id) => find.byKey(ValueKey('note-row-$id'));

  TextStyle styleOf(WidgetTester tester, Finder row, String text) =>
      tester
          .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
          .firstWhere((widget) => widget.data == text)
          .style!;

  Future<void> mountTasks(WidgetTester tester, WorkspaceController controller) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: AnimatedBuilder(
              animation: controller,
              builder: (_, child) => TodayScreen(
                  controller: controller, persistentInspector: false))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> mountNotes(WidgetTester tester, WorkspaceController controller) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: AnimatedBuilder(
              animation: controller,
              builder: (_, child) => NotesScreen(controller: controller))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a note row and a task row resolve the same title and preview',
      (tester) async {
    final tasks = WorkspaceController(seedData: false);
    addTearDown(tasks.dispose);
    tasks.selectView(WorkspaceView.today);
    final now = DateTime.now();
    tasks.createTask(TaskDraft(
        title: taskTitle,
        description: taskPreview,
        listName: '工作',
        schedule: TaskScheduleDraft(
            dueAt: DateTime(now.year, now.month, now.day), hasTime: false)));
    final taskId = tasks.tasks.last.id;
    await mountTasks(tester, tasks);

    final taskRowTitle = styleOf(tester, taskRow(taskId), taskTitle);
    final taskRowPreview = styleOf(tester, taskRow(taskId), taskPreview);

    // A note has no schedule, so it is created without one and never selected:
    // an unselected index is what the row contract is about.
    final notes = WorkspaceController(seedData: false);
    addTearDown(notes.dispose);
    final noteId = notes.addNote(title: noteTitle);
    await mountNotes(tester, notes);

    final noteRowTitleStyle = styleOf(tester, noteRow(noteId), noteTitle);
    final noteRowPreviewStyle =
        styleOf(tester, noteRow(noteId), '还没有内容');

    for (final pair in <List<TextStyle>>[
      <TextStyle>[noteRowTitleStyle, taskRowTitle],
      <TextStyle>[noteRowPreviewStyle, taskRowPreview],
    ]) {
      final note = pair.first, task = pair.last;
      expect(note.fontSize, task.fontSize, reason: 'title and preview sizes');
      expect(note.fontWeight, task.fontWeight, reason: 'the note index read '
          'heavier than the task list because its title was semibold');
      expect(note.height, task.height, reason: 'the note row title carried no '
          'line height while the task row title carried lineList');
      expect(note.letterSpacing, task.letterSpacing);
      expect(note.fontFamily, task.fontFamily);
    }
  });

  testWidgets('the note index header and the task list header are one role',
      (tester) async {
    final tasks = WorkspaceController(seedData: false);
    addTearDown(tasks.dispose);
    tasks.selectView(WorkspaceView.today);
    await mountTasks(tester, tasks);
    final taskHeader = tester
        .widget<Text>(find.byKey(const ValueKey('list-view-title')))
        .style!;

    final notes = WorkspaceController(seedData: false);
    addTearDown(notes.dispose);
    await mountNotes(tester, notes);
    final noteHeader = tester.widget<Text>(find.text('笔记')).style!;

    expect(noteHeader.fontSize, taskHeader.fontSize,
        reason: 'the note index header used to sit at listTitle while the list '
            'it heads sat at pageTitle');
    expect(noteHeader.fontWeight, taskHeader.fontWeight);
    expect(noteHeader.height, taskHeader.height);
    expect(noteHeader.letterSpacing, taskHeader.letterSpacing);
    expect(noteHeader.fontFamily, taskHeader.fontFamily);
  });

  testWidgets('a note title field and a task title field are one role',
      (tester) async {
    final tasks = WorkspaceController(seedData: false);
    addTearDown(tasks.dispose);
    tasks.createTask(TaskDraft(title: taskTitle, listName: '工作'));
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: AnimatedBuilder(
              animation: tasks,
              builder: (_, child) => TaskInspector(
                  task: tasks.tasks.first, controller: tasks))),
    ));
    await tester.pumpAndSettle();
    final taskField = tester
        .widget<TextField>(find.byKey(const ValueKey('task-title-editor')));

    final notes = WorkspaceController(seedData: false);
    addTearDown(notes.dispose);
    final noteId = notes.addNote(title: noteTitle);
    notes.selectNote(noteId);
    await mountNotes(tester, notes);
    final noteField = tester
        .widget<TextField>(find.byKey(const ValueKey('note-title-editor')));

    expect(noteField.style?.fontSize, taskField.style?.fontSize,
        reason: 'the note page used to own a 26pt document title');
    expect(noteField.style?.fontSize, WorkFollowMacTypography.detailTitle);
    expect(noteField.style?.fontWeight, taskField.style?.fontWeight);
    expect(noteField.style?.height, taskField.style?.height);
    expect(noteField.style?.letterSpacing, taskField.style?.letterSpacing);
    expect(noteField.style?.fontFamily, taskField.style?.fontFamily);
  });
}
