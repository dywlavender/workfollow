import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/widgets/desktop_popover.dart';

void main() {
  const viewport = Size(800, 600);
  const safe = EdgeInsets.all(12);

  test('bottom toolbar flips to top without changing start alignment', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(500, 550, 80, 30),
      viewport: viewport,
      desiredSize: const Size(245, 220),
      placement: PopoverPlacement.bottomStart,
      safeArea: safe,
    );

    expect(geometry.side, PopoverSide.top);
    expect(geometry.flipped, isTrue);
    expect(geometry.rect.left, 500);
    expect(geometry.rect.bottom, 544);
    expect(geometry.rect.right, lessThanOrEqualTo(viewport.width - 12));
  });

  test('top property picker stays below when there is enough room', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(40, 20, 44, 32),
      viewport: viewport,
      desiredSize: const Size(328, 300),
      placement: PopoverPlacement.bottomStart,
      safeArea: safe,
    );

    expect(geometry.side, PopoverSide.bottom);
    expect(geometry.flipped, isFalse);
    expect(geometry.rect.top, 58);
    expect(geometry.rect.left, 40);
  });

  test('top end alignment keeps a More menu attached to the right edge', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(650, 300, 40, 30),
      viewport: viewport,
      desiredSize: const Size(245, 180),
      placement: PopoverPlacement.topEnd,
      safeArea: safe,
    );

    expect(geometry.side, PopoverSide.top);
    expect(geometry.rect.right, 690);
    expect(geometry.rect.left, 445);
    expect(geometry.rect.bottom, 294);
  });

  test('a constrained picker remains inside the safe viewport', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(20, 220, 40, 30),
      viewport: viewport,
      desiredSize: const Size(328, 900),
      placement: PopoverPlacement.bottomStart,
      safeArea: safe,
    );

    expect(geometry.rect.top, greaterThanOrEqualTo(safe.top));
    expect(
        geometry.rect.bottom, lessThanOrEqualTo(viewport.height - safe.bottom));
    expect(geometry.rect.height, viewport.height - safe.vertical);
    expect(geometry.availableSpace, greaterThan(0));
  });

  test('horizontal placements support center alignment and flipping', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(360, 250, 40, 40),
      viewport: viewport,
      desiredSize: const Size(300, 160),
      placement: PopoverPlacement.rightCenter,
      safeArea: safe,
    );

    expect(geometry.side, PopoverSide.right);
    expect(geometry.rect.left, 406);
    expect(geometry.rect.top, 190);
  });

  test('allowFlip false preserves the preferred side and clamps it', () {
    final geometry = calculatePopoverGeometry(
      anchor: const Rect.fromLTWH(20, 570, 40, 20),
      viewport: viewport,
      desiredSize: const Size(200, 180),
      placement: const PopoverPlacement(
        preferredSide: PopoverSide.bottom,
        allowFlip: false,
      ),
      safeArea: safe,
    );

    expect(geometry.side, PopoverSide.bottom);
    expect(geometry.flipped, isFalse);
    expect(geometry.rect.bottom, viewport.height - safe.bottom);
  });
}
