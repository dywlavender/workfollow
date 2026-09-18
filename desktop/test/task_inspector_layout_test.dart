import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
final boundary = GlobalKey();
Finder keyed(String key) => find.byKey(ValueKey(key));
quill.QuillEditor document(WidgetTester tester) =>
    tester.widget<quill.QuillEditor>(keyed('task-document-editor'));

Future<void> mount(WidgetTester tester, WorkspaceController controller,
    {Size size = const Size(1000, 900),
    bool narrow = false,
    VoidCallback? onBack}) async {
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
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
          body: AnimatedBuilder(
        animation: controller,
        builder: (_, child) => TaskInspector(
          key: ValueKey(controller.tasks.first.id),
          task: controller.tasks.first,
          controller: controller,
          showBack: narrow,
          onBack: onBack,
        ),
      )),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!capture) return;
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../docs/screenshots/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class RetryStore extends LocalWorkspaceStore {
  bool fail = true;
  MigrationBundle? saved;
  @override
  Future<void> save(MigrationBundle bundle) async {
    if (fail) throw const FileSystemException('disk full');
    saved = bundle;
  }
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final family in [
      'Inter',
      'Noto Sans SC',
      'Roboto',
      'Ahem',
      '.SF Pro Text',
      '.SF Pro Display'
    ]) {
      await (FontLoader(family)
            ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync()))))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets(
      'document fills the detail pane and follows resize and long content',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('测试');
    final task = c.tasks.single;
    c.selectTask(task.id);
    c.updateTaskDue(task.id, DateTime.now().subtract(const Duration(days: 8)));
    c.updateTaskDescription(task.id, '是的爱上');
    await mount(tester, c, size: const Size(1000, 1180));
    final title = tester.widget<TextField>(keyed('task-title-editor'));
    expect(title.focusNode!.hasFocus, isFalse);
    expect(document(tester).focusNode.hasFocus, isFalse);
    for (final key in [
      'task-list-summary',
      'task-tags-summary',
      'task-deadline-summary',
      'task-reminder',
      'task-repeat',
      'task-deadline',
      'save-status-indicator'
    ]) {
      expect(keyed(key), findsNothing);
    }
    expect(find.byTooltip('关闭详情'), findsNothing);
    final titleRect = tester.getRect(keyed('task-title-editor'));
    final docRect = tester.getRect(keyed('task-document-editor'));
    final footer = tester.getRect(keyed('task-inspector-footer'));
    expect(titleRect.left, 40);
    expect(
        titleRect.top - tester.getRect(keyed('task-inspector-header')).bottom,
        30);
    expect(docRect.top - titleRect.bottom, 10);
    expect(footer.top - docRect.bottom, closeTo(24, 1));
    expect(tester.getRect(keyed('task-priority')).right, 980);
    expect(tester.getRect(keyed('task-more-actions')).right, 980);
    final schedule = tester.widget<TextButton>(find.descendant(
        of: keyed('task-schedule'), matching: find.byType(TextButton)));
    final tokens = WorkFollowTheme.of(tester.element(keyed('task-schedule')));
    expect(schedule.style!.foregroundColor!.resolve({}), tokens.danger);
    expect(schedule.style!.backgroundColor!.resolve({}), Colors.transparent);
    await screenshot(tester, 'task-editor-detail');

    await tester.tapAt(Offset(docRect.left + 30, docRect.bottom - 30));
    await tester.pump();
    expect(document(tester).focusNode.hasFocus, isTrue);
    // Quill's platform text value includes its final document newline.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '是的爱上空白区域直接输入\n',
        selection: TextSelection.collapsed(offset: 12)));
    await tester.pump();
    expect(c.tasks.single.description, contains('空白区域直接输入'));

    tester.view.physicalSize = const Size(1250, 720);
    await tester.pumpAndSettle();
    expect(tester.getRect(keyed('task-title-editor')).left, 40);
    expect(
        tester.getRect(keyed('task-inspector-footer')).top -
            tester.getRect(keyed('task-document-editor')).bottom,
        closeTo(24, 1));
    final editor = document(tester).controller;
    final longText = List.filled(100, '文档内容随页面滚动').join('\n');
    editor.replaceText(0, editor.document.length - 1, longText,
        const TextSelection.collapsed(offset: 0));
    await tester.pumpAndSettle();
    final scroll =
        tester.widget<SingleChildScrollView>(keyed('task-editor-scroll'));
    final scrollable = tester.state<ScrollableState>(find
        .descendant(
            of: keyed('task-editor-scroll'), matching: find.byType(Scrollable))
        .first);
    expect(scroll.child, isNotNull);
    expect(scrollable.position.maxScrollExtent, greaterThan(1000));
    await tester.drag(keyed('task-editor-scroll'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(keyed('task-inspector-footer')).bottom, 720);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Escape dismisses slash and popovers before releasing editor focus',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('分层退出');
    c.selectTask(c.tasks.single.id);
    await mount(tester, c);
    await tester.tap(keyed('task-document-editor'));
    document(tester)
        .controller
        .replaceText(0, 0, '/', const TextSelection.collapsed(offset: 1));
    await tester.pump();
    expect(keyed('document-slash-menu'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(keyed('document-slash-menu'), findsNothing);
    expect(document(tester).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(document(tester).focusNode.hasFocus, isFalse);
    expect(c.selectedTaskId, isNotNull);

    await tester.tap(keyed('document-format-toggle'));
    await tester.pumpAndSettle();
    expect(keyed('document-editor-toolbar'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(keyed('document-editor-toolbar'), findsNothing);
    expect(c.selectedTaskId, isNotNull);
    await tester.tap(keyed('task-schedule'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(keyed('task-schedule-panel'), findsNothing);
    expect(c.selectedTaskId, isNotNull);

    c.requestInspectorTitleFocus();
    await tester.pump();
    expect(
        tester
            .widget<TextField>(keyed('task-title-editor'))
            .focusNode!
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(keyed('task-title-editor'))
            .focusNode!
            .hasFocus,
        isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.selectedTaskId, isNotNull);
  });

  testWidgets(
      'narrow detail exits editing before returning and honors pending title request',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('窄窗口长标题长标题长标题长标题');
    c.selectTask(c.tasks.single.id);
    c.requestInspectorTitleFocus();
    var returns = 0;
    await mount(tester, c,
        size: const Size(360, 700), narrow: true, onBack: () => returns++);
    expect(
        tester
            .widget<TextField>(keyed('task-title-editor'))
            .focusNode!
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(returns, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(returns, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'legacy subtask panel remains near prose and blank space below is editable',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('旧任务');
    c.addSubtask(c.tasks.single.id, '原有子任务');
    await mount(tester, c);
    final panel = tester.getRect(keyed('task-subtasks-panel'));
    final surface = tester.getRect(keyed('task-document-surface'));
    expect(panel.top - surface.top, lessThan(220));
    expect(surface.bottom - panel.bottom, greaterThan(100));
    await tester.tapAt(Offset(surface.left + 20, surface.bottom - 20));
    await tester.pump();
    expect(document(tester).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date properties update the task and active header states',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('属性归位');
    await mount(tester, c);
    Future<void> openProperty(String action) async {
      await tester.tap(keyed('task-schedule'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('schedule-$action'));
      await tester.pumpAndSettle();
    }

    await openProperty('reminder');
    await tester.tap(keyed('reminder-offset-0'));
    await tester.tap(keyed('confirm-schedule-option'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('apply-date'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.reminderAt, isNotNull);
    expect(keyed('task-reminder'), findsOneWidget);
    await tester.tap(keyed('task-reminder'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('date-clear'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.reminderAt, isNull);
    expect(keyed('task-reminder'), findsNothing);

    await openProperty('repeat');
    await tester.tap(keyed('repeat-DAILY'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('apply-date'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.recurrenceType, 'DAILY');
    expect(keyed('task-repeat'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'save failure can retry the latest document without an extra edit',
      (tester) async {
    final store = RetryStore();
    final c = WorkspaceController(seedData: false, store: store);
    addTearDown(c.dispose);
    c.addTask('重试保存');
    await mount(tester, c, size: const Size(360, 700));
    await c.waitForPendingSaves();
    await tester.pump();
    expect(keyed('save-status-indicator'), findsOneWidget);
    expect(tester.takeException(), isNull);
    store.fail = false;
    await tester.tap(keyed('save-status-indicator'));
    await tester.pumpAndSettle();
    await c.waitForPendingSaves();
    await tester.pump();
    expect(c.saveStatus, SaveStatus.saved);
    expect(store.saved!.tasks.single.title, '重试保存');
    expect(keyed('save-status-indicator'), findsNothing);
  });
}
