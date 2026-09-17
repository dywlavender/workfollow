import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/theme/workfollow_interaction_states.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  final tokens = WorkFollowTheme.light;

  test('state precedence keeps disabled and pressed independent', () {
    expect(
      WorkFollowInteractionStyles.resolve(
          {WidgetState.disabled, WidgetState.pressed, WidgetState.hovered}),
      WorkFollowInteractionState.disabled,
    );
    expect(
      WorkFollowInteractionStyles.resolve(
          {WidgetState.pressed, WidgetState.hovered},
          selected: true),
      WorkFollowInteractionState.pressed,
    );
    expect(
      WorkFollowInteractionStyles.resolve({WidgetState.hovered},
          selected: true),
      WorkFollowInteractionState.selected,
    );
  });

  test('focus has no fill and exposes an independent focus border', () {
    expect(
      WorkFollowInteractionStyles.fill(tokens, focused: true),
      isNull,
    );
    expect(
      WorkFollowInteractionStyles.focusBorder(tokens, focused: true).color,
      tokens.focusRing,
    );
    expect(
      WorkFollowInteractionStyles.focusBorder(tokens, focused: false),
      BorderSide.none,
    );
  });

  test('menus use neutral hover and destructive intent stays restrained', () {
    expect(
      WorkFollowInteractionStyles.fill(tokens, hovered: true, menu: true),
      tokens.menuSelected,
    );
    expect(
      WorkFollowInteractionStyles.fill(tokens, destructive: true),
      isNull,
    );
    final destructiveHover = WorkFollowInteractionStyles.fill(
      tokens,
      destructive: true,
      hovered: true,
    );
    expect(destructiveHover, isNotNull);
    expect(destructiveHover!.a, lessThan(1));
  });

  test(
      'material overlay keeps selected fill stable while pointer states respond',
      () {
    final overlay = WorkFollowInteractionStyles.overlay(
      tokens,
      menu: true,
    );
    expect(overlay.resolve({WidgetState.hovered}), tokens.menuSelected);
    expect(overlay.resolve({WidgetState.pressed}), tokens.listRowSelected);
    expect(
      overlay.resolve({WidgetState.focused}),
      WorkFollowInteractionStyles.focusColor(tokens),
    );
    expect(overlay.resolve({WidgetState.disabled}), isNull);
  });
}
