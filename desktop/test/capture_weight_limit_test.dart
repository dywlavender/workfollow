import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';

/// The capture channel cannot see a font weight, and this pins that down.
///
/// Every other visual question in this suite is answered from a capture: mount
/// the widget, read the pixels, compare them to the reference. Weight is the one
/// that cannot be — and it is worth a test, because the failure is silent and
/// looks like success. A nav row drawn at w400 and the same row at w500 come out
/// of `RepaintBoundary.toImage` **bit-for-bit identical**, so a capture diff
/// reads "nothing changed" no matter what the source says.
///
/// The reason is how the capture tests get their fonts. macOS resolves faces
/// through the system cascade; the test engine has none, so `setUpAll` registers
/// one `.ttc` per family name with `FontLoader`. That registers the *asset*, not
/// the faces inside it, and the engine picks one face per family and does not
/// synthesise a heavier one. `Hiragino Sans GB.ttc` carries W3 and W6 and is
/// still a single face here; the machine has no loose PingFang faces to load
/// separately, and `FontLoader` has no weight parameter to load them with.
///
/// So: weight is verified two other ways. The resolved `TextStyle.fontWeight` is
/// read off the mounted widget tree (`workfollow_widget_test.dart`,
/// `web_layout_parity_test.dart`), which is a real resolution and not a source
/// scan; and what that weight *looks like* is measured from the running app
/// against the reference with the same engine (see the
/// `reference-screenshot-spec-extraction` skill).
///
/// If this test ever fails, the limitation is gone — delete the note in that
/// skill and start using captures for weight.
void main() {
  setUpAll(() async {
    // The same registration the capture tests do, so the test measures the
    // channel they actually use rather than a different one.
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final family in [
      'Hiragino Sans GB',
      'PingFang SC',
      '.SF Pro Text',
      'Ahem',
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

  testWidgets('every weight rasterises to the same face in a capture',
      (tester) async {
    double inkOf(List<int> rgba) {
      var sum = 0.0;
      for (var i = 0; i + 3 < rgba.length; i += 4) {
        final luma =
            rgba[i] * 0.299 + rgba[i + 1] * 0.587 + rgba[i + 2] * 0.114;
        sum += 255 - luma;
      }
      return sum;
    }

    // The column asks for one of these families depending on the platform
    // branch; all of them have to be checked, or "it works for PingFang" would
    // be mistaken for "it works".
    for (final family in ['Hiragino Sans GB', 'PingFang SC', '.SF Pro Text']) {
      final ink = <FontWeight, double>{};
      for (final weight in [FontWeight.w400, FontWeight.w500]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: WorkFollowThemeData.light(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Text('收集箱',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        fontFamily: family,
                        color: const Color(0xFF000000),
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: weight)),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          ink[weight] = inkOf(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      final regular = ink[FontWeight.w400]!;
      final medium = ink[FontWeight.w500]!;
      // The first half of the guard: the string has to actually be on the
      // canvas, or "identical" would be two blank rasters agreeing with
      // each other.
      expect(regular, greaterThan(0),
          reason: '文字没画出来，这个断言就没有在量任何东西');
      expect(medium, regular,
          reason: '$family 在捕获通道里 w400 与 w500 落笔相同 —— 这条一旦变红说明通道能分辨字重了，'
              '应当改用捕获图去核字重，并同步修掉 reference-screenshot-spec-extraction 技能里的说明');
    }
  });
}
