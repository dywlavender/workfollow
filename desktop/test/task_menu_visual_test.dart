import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_context_menu.dart';

const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');

void main() {
  setUpAll(() async {
    if (!capture) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final name in [
      'Inter',
      'PingFang SC',
      'Roboto',
      'Ahem',
      '.SF Pro Text',
      '.SF Pro Display'
    ]) {
      final loader = FontLoader(name)
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final dark in [false, true]) {
    testWidgets(
        'menu ${dark ? 'dark' : 'light'} shows nested tags and requested actions',
        (tester) async {
      if (capture) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
      }
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = WorkspaceController(seedData: false);
      addTearDown(c.dispose);
      c.addTask('准备本周工作计划', forceUnscheduled: true);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme:
                dark ? WorkFollowThemeData.dark() : WorkFollowThemeData.light(),
            home: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.only(left: 180, top: 64),
                    child: Builder(
                        builder: (context) => TextButton(
                              key: const ValueKey('open-menu'),
                              onPressed: () => TaskContextMenu.show(context,
                                  task: c.tasks.single, controller: c),
                              child: Text('准备本周工作计划  ···',
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            )))),
          )));
      await tester.tap(find.byKey(const ValueKey('open-menu')));
      await tester.pumpAndSettle();
      for (final excluded in ['duplicate', 'copy-link', 'open-note']) {
        expect(find.byKey(ValueKey('menu-option-$excluded')), findsNothing);
      }
      for (final enabled in ['pin', 'abandon', 'convert-note']) {
        final row = tester
            .widget<InkWell>(find.byKey(ValueKey('menu-option-$enabled')));
        expect(row.onTap, isNotNull);
      }
      await tester.tap(find.byKey(const ValueKey('menu-option-tags')));
      await tester.pumpAndSettle();
      expect(find.text('没有标签'), findsOneWidget);
      final parent =
          tester.getRect(find.byKey(const ValueKey('task-context-menu-panel')));
      final child =
          tester.getRect(find.byKey(const ValueKey('task-tag-picker')));
      expect(child.left, greaterThanOrEqualTo(parent.right));
      expect(tester.takeException(), isNull);
      if (capture) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '../docs/screenshots/task-menu-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-context-menu-panel')),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      if (capture) debugDisableShadows = true;
    });
  }
}
