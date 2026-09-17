import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/widgets/desktop_popover.dart';

void main() {
  test('overlay policies express the shared layer and focus contract', () {
    const menu = DesktopOverlayPolicy.menu();
    const picker = DesktopOverlayPolicy.picker();
    const toolbar = DesktopOverlayPolicy.toolbar();

    expect(menu.layer, DesktopOverlayLayer.menu);
    expect(menu.focusPolicy, PopoverFocusPolicy.firstItem);
    expect(menu.dismissOnTapOutside, isTrue);
    expect(picker.layer, DesktopOverlayLayer.picker);
    expect(picker.focusPolicy, PopoverFocusPolicy.searchField);
    expect(toolbar.layer, DesktopOverlayLayer.toolbar);
    expect(toolbar.preservesEditorSelection, isTrue);
    expect(toolbar.dismissOnTapOutside, isFalse);
  });

  test('anchored placement flips and clamps to the safe viewport', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(18, 8, 24, 20),
      viewport: const Size(320, 240),
      desiredSize: const Size(220, 170),
      placement: PopoverPlacement.topStart,
    );

    expect(geometry.side, PopoverSide.bottom);
    expect(geometry.isFlipped, isTrue);
    expect(geometry.rect.left, greaterThanOrEqualTo(0));
    expect(geometry.rect.top, greaterThanOrEqualTo(0));
    expect(geometry.rect.right, lessThanOrEqualTo(320));
    expect(geometry.rect.bottom, lessThanOrEqualTo(240));
  });
}
