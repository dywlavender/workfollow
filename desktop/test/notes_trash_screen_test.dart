import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/notes_trash_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/app_icon_button.dart';
import 'package:workfollow_personal/widgets/sidebar.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_header.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_row.dart';

final DateTime noteTrashAnchor = DateTime(2030, 6, 10, 9);

NoteItem deletedNote(String id, String title, DateTime? deletedAt,
        {String body = '', String folder = '未归档'}) =>
    NoteItem(
      id: id,
      title: title,
      preview: body,
      plainText: body,
      updatedLabel: '刚刚',
      folder: folder,
      deletedAt: deletedAt?.toIso8601String(),
      updatedAt:
          deletedAt?.toIso8601String() ?? noteTrashAnchor.toIso8601String(),
    );

TaskItem deletedTask(String id) => TaskItem(
      id: id,
      title: id,
      listName: '工作',
      bucket: taskBucketForDate(null, now: noteTrashAnchor),
      deletedAt: noteTrashAnchor.toIso8601String(),
    );

Future<void> pumpNotesTrash(WidgetTester tester, WorkspaceController controller,
    {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  controller.selectView(WorkspaceView.notesTrash);
  await tester.pumpWidget(MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Row(children: [
          AppRail(
            controller: controller,
            isDark: false,
            onToggleTheme: () {},
            onOpenSettings: () {},
          ),
          Expanded(child: NotesTrashScreen(controller: controller)),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder noteSurface(String id) =>
    find.byKey(ValueKey('notes-trash-row-surface-$id'));

void main() {
  testWidgets('NOTE-TRASH-001 is separate and newest deleted note comes first',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([deletedTask('deleted-task-only')]);
    controller.loadNotesForTest([
      deletedNote('older', '较早删除的笔记', DateTime(2030, 6, 8), body: '较早内容'),
      deletedNote('newer', '较晚删除的笔记', DateTime(2030, 6, 9),
          body: '较晚内容', folder: '工作灵感'),
      deletedNote('active', '不在垃圾桶的笔记', null),
    ]);
    await pumpNotesTrash(tester, controller);

    expect(find.byType(TaskListHeader), findsOneWidget);
    expect(
        find.byKey(const ValueKey('rail-navigation-item-垃圾桶')), findsOneWidget);
    expect(controller.countFor(WorkspaceView.notesTrash), 2);
    expect(controller.countFor(WorkspaceView.trash), 1);
    expect(find.byType(TaskListRowFrame), findsNWidgets(2));
    expect(find.text('较早删除的笔记'), findsOneWidget);
    expect(find.text('较晚删除的笔记'), findsNWidgets(2));
    expect(find.text('deleted-task-only'), findsNothing);
    expect(find.text('不在垃圾桶的笔记'), findsNothing);
    expect(tester.getTopLeft(noteSurface('newer')).dy,
        lessThan(tester.getTopLeft(noteSurface('older')).dy));
    expect(find.text('较晚内容'), findsNWidgets(2));
  });

  testWidgets('NOTE-TRASH-002 restore and permanent delete affect notes only',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([deletedTask('still-deleted-task')]);
    controller.loadNotesForTest([
      deletedNote('restore-me', '恢复我', DateTime(2030, 6, 9)),
      deletedNote('purge-me', '永久删除我', DateTime(2030, 6, 8)),
    ]);
    await pumpNotesTrash(tester, controller);

    await tester.tap(find.descendant(
        of: noteSurface('restore-me'), matching: find.byTooltip('恢复笔记')));
    await tester.pumpAndSettle();
    expect(controller.deletedNotes.map((note) => note.id), ['purge-me']);
    expect(controller.activeNotes.map((note) => note.id), ['restore-me']);
    expect(
        controller.deletedTasks.map((task) => task.id), ['still-deleted-task']);

    await tester.tap(find.descendant(
        of: noteSurface('purge-me'), matching: find.byTooltip('永久删除笔记')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除这条笔记？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(controller.deletedNotes, isEmpty);
    expect(
        controller.deletedTasks.map((task) => task.id), ['still-deleted-task']);
  });

  testWidgets('NOTE-TRASH-003 clear confirmation leaves task trash alone',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([deletedTask('preserved-task')]);
    controller.loadNotesForTest([
      deletedNote('note-1', '待清空笔记', DateTime(2030, 6, 9)),
      deletedNote('note-active', '仍保留的笔记', null),
    ]);
    await pumpNotesTrash(tester, controller);

    await tester.tap(find.byTooltip('清空笔记垃圾桶'));
    await tester.pumpAndSettle();
    expect(find.text('清空笔记垃圾桶'), findsOneWidget);
    expect(find.text('笔记垃圾桶中的内容将被永久删除，确定清空笔记垃圾桶吗？'), findsOneWidget);
    final dialogSize =
        tester.getSize(find.byKey(const ValueKey('clear-trash-dialog')));
    expect(dialogSize.width, lessThanOrEqualTo(440));
    expect(dialogSize.height, lessThanOrEqualTo(240));

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(controller.deletedNotes, isEmpty);
    expect(controller.activeNotes.map((note) => note.id), ['note-active']);
    expect(controller.deletedTasks.map((task) => task.id), ['preserved-task']);
  });

  testWidgets('NOTE-TRASH-004 empty notes trash does not enable clearing',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await pumpNotesTrash(tester, controller);

    expect(find.text('笔记垃圾桶是空的'), findsOneWidget);
    expect(find.byType(TaskListRowFrame), findsNothing);
    expect(
        tester
            .widget<AppIconButton>(
                find.byKey(const ValueKey('empty-notes-trash-button')))
            .onPressed,
        isNull);
  });

  testWidgets('NOTE-TRASH-005 narrow layout opens the note detail and returns',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadNotesForTest([
      deletedNote('narrow-note', '窄屏笔记', DateTime(2030, 6, 9), body: '笔记正文'),
    ]);
    await pumpNotesTrash(tester, controller, size: const Size(650, 900));

    expect(noteSurface('narrow-note'), findsOneWidget);
    await tester.tap(noteSurface('narrow-note'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回笔记垃圾桶'), findsOneWidget);
    expect(find.text('窄屏笔记'), findsOneWidget);

    await tester.tap(find.byTooltip('返回笔记垃圾桶'));
    await tester.pumpAndSettle();
    expect(noteSurface('narrow-note'), findsOneWidget);
  });
}
