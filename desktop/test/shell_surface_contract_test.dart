// Contract: the shell is one working plane.
//
// The navigation column and the detail pane used to carry greys of their own,
// so a task page with nothing selected broke into three surfaces beside the
// white list, and the matrix board sat on the panel grey. These are pixel
// assertions against the whole shell rather than widget-config ones: the
// contract is about what the window shows, and the coordinates below are the
// column boundaries the shell actually resolves to at this width.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/features/matrix/matrix_models.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_color_tokens.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/theme/workfollow_theme_parity.dart';

const _content = Color(0xFFFFFFFF);

Future<Color> _pixel(
    WidgetTester tester, GlobalKey boundary, int x, int y) async {
  late Color color;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgba = data.buffer.asUint8List();
    final i = (y * image.width + x) * 4;
    color = Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
    image.dispose();
  });
  return color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      final bytes = font.readAsBytesSync();
      for (final family in [
        'PingFang SC',
        'Hiragino Sans GB',
        '.SF Pro Text',
        '.SF Pro Display',
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

  Future<GlobalKey> mountShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary, child: const WorkFollowApp(demoMode: true)));
    await tester.pumpAndSettle();
    return boundary;
  }

  testWidgets('SHELL-S01 the task page is white in every column',
      (tester) async {
    final boundary = await mountShell(tester);
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    // x: 120 navigation column, 450 list pane, 1000 detail pane — the three
    // columns the index and the inspector share. y=880 is below the last row
    // of every column, so the sample never lands on a row fill.
    final navigation = await _pixel(tester, boundary, 120, 880);
    final list = await _pixel(tester, boundary, 450, 880);
    final detail = await _pixel(tester, boundary, 1000, 880);

    expect(navigation, _content,
        reason: 'the navigation column carries the content surface');
    expect(list, _content, reason: 'the task list stays white');
    expect(detail, _content,
        reason: 'the empty detail pane is the list\'s peer, not a grey field');
  });

  testWidgets('SHELL-S02 the notes page is white in every column',
      (tester) async {
    final boundary = await mountShell(tester);
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();

    final navigation = await _pixel(tester, boundary, 120, 880);
    final index = await _pixel(tester, boundary, 450, 880);
    final editor = await _pixel(tester, boundary, 1300, 880);

    expect(navigation, _content,
        reason: 'the note folders sit on the content surface too');
    expect(index, _content, reason: 'the note index stays white');
    expect(editor, _content, reason: 'the empty editor page stays white');
  });

  testWidgets('SHELL-S03 the matrix board sits one step off its cards',
      (tester) async {
    final boundary = await mountShell(tester);
    await tester.tap(find.byTooltip('四象限'));
    await tester.pumpAndSettle();

    // Above the board, inside the page header's free space, and inside the
    // board's own padding below it.
    final belowTitle = await _pixel(tester, boundary, 300, 6);
    final boardInset = await _pixel(tester, boundary, 300, 892);
    expect(belowTitle, WorkFollowColors.neutral50);
    expect(boardInset, WorkFollowColors.neutral50,
        reason: 'the board\'s gutters are the page surface, not the canvas');

    // The numeral inside each marker is the same white for all four.
    for (final numeral in const ['I', 'II', 'III', 'IV']) {
      final text = tester.widget<Text>(find.text(numeral));
      expect(text.style?.color, WorkFollowThemeContrast.markerForeground,
          reason: 'numeral $numeral is a cut-out in its disc');
    }
  });

  testWidgets('SHELL-S04 the matrix backdrop keeps its separation',
      (tester) async {
    // The role resolves off the active brightness, like every other component
    // palette in this file, so each branch is read under its own theme. The
    // theme is applied with a bare Theme rather than through MaterialApp: the
    // latter animates between themes, so one pump still reports the old one.
    Future<Color?> backdropUnder(ThemeData theme, WorkFollowTheme tokens) async {
      Color? value;
      await tester.pumpWidget(Theme(
        data: theme,
        child: Builder(builder: (context) {
          value = WorkFollowColorTokens.matrixBackdrop(context, tokens);
          return const SizedBox.shrink();
        }),
      ));
      return value;
    }

    final tokens = WorkFollowTheme.light;
    final light = await backdropUnder(WorkFollowThemeData.light(), tokens);
    final dark =
        await backdropUnder(WorkFollowThemeData.dark(), WorkFollowTheme.dark);

    expect(light, WorkFollowColors.neutral50);
    // Lighter than the panel canvas it replaced, and still a step below the
    // white cards, which is the whole point of the surface.
    expect(light!.computeLuminance(),
        greaterThan(tokens.canvas.computeLuminance()));
    expect(light.computeLuminance(),
        lessThan(tokens.content.computeLuminance()));
    expect(dark, WorkFollowTheme.dark.canvas);
  });

  test('SHELL-S05 the quadrant headers wear the macOS system palette', () {
    final colors = [
      for (final quadrant in MatrixQuadrant.values)
        MatrixQuadrantStyle.forQuadrant(quadrant).color,
    ];
    expect(colors, const [
      Color(0xFFFF3B30), // systemRed
      Color(0xFFFFCC00), // systemYellow
      Color(0xFF007AFF), // systemBlue
      Color(0xFF34C759), // systemGreen
    ]);
  });

  test('SHELL-S06 navigation selection is neutral like every other row', () {
    // The column shares the content surface now, so its rows cannot use the
    // inverted white chip that only worked against a grey column.
    final source =
        File('lib/widgets/sidebar.dart').readAsStringSync();
    expect(source, isNot(contains('content.withValues')));
    expect(source, contains('selectedColor: tokens.listRowSelected'));
  });
}
