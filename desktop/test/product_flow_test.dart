import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/note_document.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/widgets/task_date_picker.dart';

const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
final boundary = GlobalKey();

class FolderPlatform extends PlatformFileService {
  FolderPlatform(this.folder);
  final String folder;
  @override
  Future<String?> applicationSupportDirectory() async => folder;
}

Future<void> start(WidgetTester tester,
    {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(RepaintBoundary(
      key: boundary, child: const WorkFollowApp(demoMode: true)));
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!capture) return;
  await tester.pumpAndSettle();
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../docs/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!capture) return;
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

  test(
      'DATE-007 DATE-008 new personal workspaces start empty and dates distinguish midnight from all-day',
      () async {
    final c = WorkspaceController(seedData: false);
    expect(c.tasks, isEmpty);
    expect(c.notes, isEmpty);
    c.selectView(WorkspaceView.today);
    c.addTask('准备会议');
    final id = c.tasks.single.id;
    final date = DateTime(2030, 5, 18);
    c.updateTaskDue(id, date, hasTime: true);
    c.updateTaskDeadline(id, DateTime(2030, 5, 20));
    final restored = TaskItem.fromMigration(c.tasks.single.toMigrationRecord());
    expect(restored.scheduledWithTime, isTrue);
    expect(restored.displayTimeLabel, contains('00:00'));
    expect(localDateTimeFromStorage(restored.deadlineAt)?.day, 20);
    c.updateTaskDue(id, date, hasTime: false);
    expect(c.tasks.single.scheduledWithTime, isFalse);
    expect(c.tasks.single.displayTimeLabel, isNot(contains('00:00')));
    expect(localDateTimeFromStorage(c.tasks.single.deadlineAt)?.day, 20);
    await c.waitForPendingSaves();
    c.dispose();
  });

  test(
      'RICH rich note edits retain link, list, table and current text through storage',
      () async {
    final source = <String, dynamic>{
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': '资料',
              'marks': [
                {
                  'type': 'link',
                  'attrs': {'href': 'https://example.com/reference'}
                }
              ]
            }
          ]
        },
        {
          'type': 'bulletList',
          'content': [
            {
              'type': 'listItem',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': '第一项'}
                  ]
                }
              ]
            }
          ]
        },
        {
          'type': 'table',
          'content': [
            {
              'type': 'tableRow',
              'content': [
                {
                  'type': 'tableCell',
                  'content': [
                    {
                      'type': 'paragraph',
                      'content': [
                        {'type': 'text', 'text': '表格原文'}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        },
      ]
    };
    final editor = quill.QuillController(
        document: quill.Document.fromJson(proseMirrorToDelta(source)),
        selection: const TextSelection.collapsed(offset: 0));
    editor.formatText(0, 2, quill.Attribute.bold);
    final end = editor.document.length - 1;
    editor.replaceText(
        end, 0, '新增正文', TextSelection.collapsed(offset: end + 4));
    final document = noteContentFromDelta(editor.document.toDelta().toJson());
    final encoded = jsonEncode(document);
    expect(encoded, contains('https://example.com/reference'));
    expect(encoded, contains('bulletList'));
    expect(encoded, contains('表格原文'));
    expect(encoded, contains('新增正文'));
    final note = NoteItem(
        id: 'note-rich',
        title: '记录',
        preview: '',
        updatedLabel: '',
        folder: '未归档',
        accent: const ColorValue(0),
        contentJson: document,
        plainText: editor.document.toPlainText(),
        originalContentJson: source);
    final restored = NoteItem.fromMigration(
        note.toMigrationRecord(), '未归档', const ColorValue(0));
    final reopened = quill.Document.fromJson(noteDocumentDelta(restored));
    expect(reopened.toPlainText(), editor.document.toPlainText());
    expect(jsonEncode(reopened.toDelta().toJson()), contains('"bold":true'));
    editor.dispose();
  });

  test('RICH portable export restores task data and local attachments',
      () async {
    final root = Directory.systemTemp.createTempSync('workfollow-export-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory('${root.path}/source')..createSync();
    final files = Directory('${source.path}/attachments')..createSync();
    File('${files.path}/meeting.txt').writeAsStringSync('会议记录');
    final store = LocalWorkspaceStore(platform: FolderPlatform(source.path));
    final c = WorkspaceController(store: store, seedData: false);
    c.addTask('整理会议资料');
    await c.waitForPendingSaves();
    final exportPath = '${root.path}/export.workfollow.json';
    await store.exportToPath(c.snapshot, exportPath);
    final bundle =
        MigrationBundle.fromJsonString(File(exportPath).readAsStringSync());
    expect(bundle.embeddedFiles.keys, contains('meeting.txt'));
    final destination = Directory('${root.path}/restored')..createSync();
    final restored = WorkspaceController(
        seedData: false,
        store: LocalWorkspaceStore(platform: FolderPlatform(destination.path)));
    await restored.replaceWithMigration(bundle);
    expect(restored.tasks.single.title, '整理会议资料');
    expect(
        File('${destination.path}/attachments/meeting.txt').readAsStringSync(),
        '会议记录');
    c.dispose();
    restored.dispose();
  });

  test(
      'DEADLINE-001 DEADLINE-002 BULK-002 deadlines surface today and batch time changes undo correctly',
      () async {
    final c = WorkspaceController(seedData: false);
    c.addTaskToInboxUnscheduled('交付材料');
    final id = c.tasks.single.id;
    final now = DateTime.now();
    c.updateTaskDeadline(id, now);
    c.selectView(WorkspaceView.today);
    expect(c.visibleTasks.single.id, id);
    expect(c.countFor(WorkspaceView.today), 1);
    c.updateTaskDue(id, DateTime(2030, 5, 18, 14, 30), hasTime: true);
    c.toggleMultiSelect(id);
    c.bulkRescheduleSelected(DateTime(2030, 5, 20), hasTime: false);
    expect(c.tasks.single.scheduledWithTime, false);
    expect(
        localDateTimeFromStorage(c.tasks.single.dueAt), DateTime(2030, 5, 20));
    c.undoLastAction();
    expect(c.tasks.single.scheduledWithTime, true);
    expect(localDateTimeFromStorage(c.tasks.single.dueAt),
        DateTime(2030, 5, 18, 14, 30));
    await c.waitForPendingSaves();
    c.dispose();
  });

  test(
      'RICH folder changes preserve notes and external note links escape filters',
      () async {
    final c = WorkspaceController(seedData: false);
    final folder = c.addFolder('会议')!;
    final id = c.addNote(folderId: folder.id, title: '会议记录');
    c.renameFolder(folder.id, '项目会议');
    expect(c.notes.single.folder, '项目会议');
    c.setNotesFavoritesOnly(true);
    c.openNote(id);
    expect(c.notesFavoritesOnly, false);
    expect(c.selectedNoteId, id);
    c.removeFolder(folder.id);
    expect(c.notes.single.folderId, isNull);
    expect(c.notes.single.title, '会议记录');
    await c.waitForPendingSaves();
    c.dispose();
  });

  testWidgets(
      'ROW-003 external links open the requested task and note on a narrow window',
      (tester) async {
    await start(tester, size: const Size(880, 600));
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    final c = tester.widget<TodayScreen>(find.byType(TodayScreen)).controller;
    c.openTask('task-04');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    c.setNotesFavoritesOnly(true);
    c.openNote('note-02');
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(c.selectedNoteId, 'note-02');
    c.addNoteInCurrentFolder();
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    expect(editor.document.toPlainText().trim(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'DATE-006 DATE-012 task list opens a deliberate inline editor and rescheduling has a clear destination',
      (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsNothing);
    await screenshot(tester, 'tasks-list');
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    await screenshot(tester, 'task-editor');
    await tester.ensureVisible(find.byKey(const ValueKey('task-schedule')));
    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDatePicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await screenshot(tester, 'date-picker');
    await tester.tap(find.widgetWithText(TextButton, '明天'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('apply-date')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDatePicker), findsNothing);
    expect(find.text('准备季度产品评审演示文稿'), findsNothing);
    expect(find.text('查看任务'), findsOneWidget);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    final c = tester.widget<TodayScreen>(find.byType(TodayScreen)).controller;
    expect(c.view, WorkspaceView.all);
    expect(c.selectedListName, '工作');
    c.openTask(c.tasks.firstWhere((task) => task.completed).id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
  });

  testWidgets(
      'DATE-006 DATE-007 DATE-010 DATE-011 date popup cancels edits and supports manual dates with explicit time',
      (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('给设计顾问发一封确认邮件').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('task-schedule')));
    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('date-input')), '2030-05-18');
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    final c = tester.widget<TodayScreen>(find.byType(TodayScreen)).controller;
    expect(
        localDateTimeFromStorage(
                c.tasks.firstWhere((t) => t.id == 'task-03').dueAt)
            ?.year,
        isNot(2030));
    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('date-input')), '2030-05-18');
    await tester.tap(find.descendant(
        of: find.byType(TaskDatePicker), matching: find.byType(Checkbox)));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('date-小时')), '00');
    await tester.enterText(find.byKey(const ValueKey('date-分钟')), '00');
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();
    final task = c.tasks.firstWhere((t) => t.id == 'task-03');
    expect(task.scheduledWithTime, isTrue);
    expect(localDateTimeFromStorage(task.dueAt), DateTime(2030, 5, 18));
  });

  testWidgets(
      'RICH note editor formats, edits, switches notes and restores edited content',
      (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部笔记').first);
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    editor.replaceText(0, editor.document.length - 1, '会议记录\n确认下一步行动',
        const TextSelection.collapsed(offset: 4));
    editor.formatText(0, 4, quill.Attribute.bold);
    await tester.pumpAndSettle();
    await screenshot(tester, 'notes-editor');
    await tester.tap(find.text('灵感收集 · 好的空状态').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('季度评审 · 叙事结构').first);
    await tester.pumpAndSettle();
    final reopened = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    expect(reopened.document.toPlainText().trim(), '会议记录\n确认下一步行动');
    expect(jsonEncode(reopened.document.toDelta().toJson()),
        contains('"bold":true'));
  });

  testWidgets(
      'ARCH-008 settings navigation exposes working data actions without overflow',
      (tester) async {
    await start(tester, size: const Size(1000, 700));
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据').last);
    await tester.pumpAndSettle();
    expect(find.text('导出全部数据'), findsOneWidget);
    expect(find.text('恢复备份…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ARCH-008 task and note layouts fit the minimum desktop window in dark mode',
      (tester) async {
    await start(tester, size: const Size(880, 600));
    await tester.tap(find.byTooltip('切换深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('给设计顾问发一封确认邮件').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'task-narrow-dark');
    await tester.tap(find.byTooltip('返回列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部笔记').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('季度评审 · 叙事结构').first);
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'notes-narrow-dark');
  });
}
