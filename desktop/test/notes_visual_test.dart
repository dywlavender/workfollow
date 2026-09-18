import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/sidebar.dart';

/// Renders the whole notes workspace — navigation column, note index and the
/// writing page — to `docs/screenshots/` for visual review:
///
/// ```bash
/// flutter test test/notes_visual_test.dart --dart-define=WORKFOLLOW_CAPTURE=true
/// ```
///
/// The window is the reference width, so the index resolves to its wide pane
/// and the review picture shows the real three-column proportion instead of a
/// squeezed editor. Font handling follows `task_list_visual_test.dart`; see the
/// notes there for why the macOS branch and a real CJK face are forced.
const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
final boundary = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!capture) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      final bytes = font.readAsBytesSync();
      for (final family in [
        'PingFang SC',
        'Hiragino Sans GB',
        '.SF Pro Text',
        '.SF Pro Display',
        'Roboto',
        'Ahem',
      ]) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  Future<void> shoot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../docs/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('NOTES-D01 capture the notes workspace', (tester) async {
    // Wide enough that the editor pane is wider than the 820pt reading
    // measure, so the picture shows the canvas and its slack rather than a
    // column that happens to fill a narrow window.
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController();
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.notes);

    // Pinned inside the body: flutter_test refuses to let a foundation debug
    // variable differ once a test returns, so it cannot be set in setUpAll.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final base = WorkFollowThemeData.light();
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Hiragino Sans GB'),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Hiragino Sans GB'))));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Row(children: [
                            AppRail(
                                controller: controller,
                                isDark: false,
                                onToggleTheme: () {},
                                onOpenSettings: () {}),
                            Expanded(
                                child: NotesScreen(controller: controller)),
                          ]))))));
      await tester.pumpAndSettle();

      await shoot(tester, 'notes-workspace');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
