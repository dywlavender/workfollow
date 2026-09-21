import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/trash_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/sidebar.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_row.dart';

/// Writes a PNG of the rail and the trash page to /private/tmp when asked:
///
/// ```bash
/// flutter test test/trash_capture_test.dart --dart-define=TRASH_CAPTURE=true
/// ```
///
/// The assertions run either way, so this is a test first and a screenshot
/// second. It is the only way to look at the pair: 已完成 and 垃圾桶 are two rows
/// of a column the shell only draws for a task view, and a trash page with
/// nothing in it — which is what a real workspace usually has — says nothing
/// about how a row reads.
const capture = bool.fromEnvironment('TRASH_CAPTURE');

/// The theme the desktop build resolves at runtime, spelled out.
///
/// macOS gets its faces from the system cascade and the test engine has none:
/// without pinning the family here every glyph is a placeholder box.
ThemeData _captureTheme() {
  final base = WorkFollowThemeData.light();
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Hiragino Sans GB'),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            textStyle: const TextStyle(fontFamily: 'Hiragino Sans GB'))),
  );
}

Future<void> _write(WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/private/tmp/$name').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final family in [
      'Inter',
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
      'Roboto',
      'Ahem',
      '.SF Pro Text',
      '.SF Pro Display',
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

  testWidgets('the rail closes on 已完成 / 垃圾桶 above a full trash',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    TaskItem removed(String id, String title, String list, DateTime at,
            {bool completed = false, String? parent}) =>
        TaskItem(
          id: id,
          title: title,
          listName: list,
          bucket: taskBucketForDate(null, now: today),
          completed: completed,
          deletedAt: at.toIso8601String(),
          parentTaskId: parent,
        );

    controller.loadTasksForTest([
      removed('t1', '把垃圾桶改成和已完成一样的列表', '工作',
          today.subtract(const Duration(minutes: 20))),
      removed('t2', '整理上周的用户反馈', '工作', today.subtract(const Duration(hours: 5))),
      removed('t3', '旧的排期表', '学习', today.subtract(const Duration(days: 1)),
          completed: true),
      removed('t4', '换季衣服收纳', '个人', today.subtract(const Duration(days: 4))),
    ]);
    final noteId = controller.addNote(title: '随手记的会议结论');
    controller.removeNote(noteId);
    controller.selectView(WorkspaceView.trash);

    final boundary = GlobalKey();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(MaterialApp(
        theme: _captureTheme(),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Row(children: [
                AppRail(
                    controller: controller,
                    isDark: false,
                    onToggleTheme: () {},
                    onOpenSettings: () {}),
                Expanded(child: TrashScreen(controller: controller)),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Both pages are on screen: the column the pair closes, and the list the
      // pair leads to.
      expect(find.byKey(const ValueKey('rail-navigation-item-已完成')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('rail-navigation-item-垃圾桶')),
          findsOneWidget);
      expect(find.byType(TaskListRowFrame), findsNWidgets(5));
      expect(find.text('随手记的会议结论'), findsOneWidget);

      if (capture) await _write(tester, boundary, 'trash-page.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
