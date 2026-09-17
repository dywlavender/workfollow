import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_surface_tokens.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('surface roles expose one radius and shadow tier each', () {
    expect(
        WorkFollowSurfaceTokens.radius(WorkFollowSurfaceRole.input),
        BorderRadius.circular(WorkFollowRadii.control));
    expect(
        WorkFollowSurfaceTokens.radius(WorkFollowSurfaceRole.card),
        BorderRadius.circular(WorkFollowRadii.card));
    expect(
        WorkFollowSurfaceTokens.radius(WorkFollowSurfaceRole.popover),
        BorderRadius.circular(WorkFollowRadii.popover));

    final light = WorkFollowTheme.light;
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.surface, light), isNull);
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.input, light), isNull);
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.card, light), hasLength(1));
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.popover, light), hasLength(1));
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.dialog, light), hasLength(1));
    expect(WorkFollowSurfaceTokens.shadows(
        WorkFollowSurfaceRole.toast, light), hasLength(1));
  });

  test('surface decorations pair border and shadow by role', () {
    final light = WorkFollowTheme.light;
    final card = WorkFollowSurfaceTokens.card(light, elevated: true);
    final input = WorkFollowSurfaceTokens.input(light);
    final popover = WorkFollowSurfaceTokens.popover(light);
    final toast = WorkFollowSurfaceTokens.toast(light);

    expect(card.border, isNotNull);
    expect(card.boxShadow, hasLength(1));
    expect(input.border, isNotNull);
    expect(input.boxShadow, isNull);
    expect(popover.border, isNotNull);
    expect(popover.boxShadow, hasLength(1));
    expect(toast.border, isNull);
    expect(toast.boxShadow, hasLength(1));
  });

  test('shadow levels stay ordered for raised desktop surfaces', () {
    expect(WorkFollowShadows.level0Elevation, 0);
    expect(WorkFollowShadows.level1Elevation,
        lessThan(WorkFollowShadows.level2Elevation));
    expect(WorkFollowShadows.level2Elevation,
        lessThan(WorkFollowShadows.level3Elevation));
    expect(WorkFollowShadows.level3Elevation,
        lessThan(WorkFollowShadows.level4Elevation));
  });
}
