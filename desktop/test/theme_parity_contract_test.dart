import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_surface_tokens.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/theme/workfollow_theme_parity.dart';

void main() {
  const themes = <WorkFollowTheme>[
    WorkFollowTheme.light,
    WorkFollowTheme.dark,
  ];

  test('text and status roles remain readable on both content surfaces', () {
    for (final tokens in themes) {
      for (final surface in [tokens.content, tokens.overlay]) {
        expect(
          WorkFollowThemeContrast.ratio(tokens.textPrimary, surface),
          greaterThanOrEqualTo(7),
          reason: 'primary text must remain a strong reading level',
        );
        expect(
          WorkFollowThemeContrast.ratio(tokens.textSecondary, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'secondary text must remain legible',
        );
        expect(
          WorkFollowThemeContrast.ratio(tokens.textTertiary, surface),
          greaterThanOrEqualTo(3),
          reason: 'tertiary text must not disappear',
        );
        expect(
          WorkFollowThemeContrast.ratio(tokens.textDisabled, surface),
          greaterThanOrEqualTo(2),
          reason: 'disabled controls still need a visible affordance',
        );
        for (final status in [
          tokens.accent,
          tokens.success,
          tokens.warning,
          tokens.danger,
        ]) {
          // Danger is deliberately a bright status red on desktop
          // (2026-09-19): it reads as a state glyph at large-text grade
          // (≥3.0) rather than body-copy grade, matching the reference app.
          final floor = status == tokens.danger ? 3.0 : 4.4;
          expect(
            WorkFollowThemeContrast.ratio(status, surface),
            greaterThanOrEqualTo(floor),
            reason: 'status and link colors must work on both surfaces',
          );
        }
      }
    }
  });

  test('quiet surfaces still expose interaction and material hierarchy', () {
    for (final tokens in themes) {
      expect(
        WorkFollowThemeContrast.surfaceDelta(
            tokens.listRowHover, tokens.content),
        greaterThanOrEqualTo(.005),
      );
      expect(
        WorkFollowThemeContrast.surfaceDelta(
            tokens.listRowSelected, tokens.content),
        greaterThanOrEqualTo(.008),
      );
      expect(
        WorkFollowThemeContrast.surfaceDelta(
            tokens.menuSelected, tokens.overlay),
        greaterThanOrEqualTo(.01),
      );
      expect(
        WorkFollowThemeContrast.surfaceDelta(
            tokens.menuDivider, tokens.overlay),
        greaterThanOrEqualTo(.01),
      );
      expect(
        WorkFollowThemeContrast.surfaceDelta(
            tokens.borderStrong, tokens.content),
        greaterThan(
          WorkFollowThemeContrast.surfaceDelta(tokens.border, tokens.content),
        ),
      );

      // Light content and overlay intentionally share a white fill; their
      // popover role remains separated by the shared border/material contract.
      if (tokens.content == tokens.overlay) {
        expect(WorkFollowSurfaceTokens.hasBorder(WorkFollowSurfaceRole.popover),
            isTrue);
      } else {
        expect(
          WorkFollowThemeContrast.surfaceDelta(tokens.content, tokens.overlay),
          greaterThanOrEqualTo(.009),
        );
      }
    }
  });

  test('filled surfaces choose a readable foreground centrally', () {
    expect(
      WorkFollowThemeContrast.foregroundOn(WorkFollowTheme.light.accent),
      Colors.white,
    );
    expect(
      WorkFollowThemeContrast.foregroundOn(WorkFollowTheme.dark.accent),
      WorkFollowThemeContrast.darkForeground,
    );
    expect(
      WorkFollowThemeContrast.foregroundOn(WorkFollowTheme.light.success),
      Colors.white,
    );
    expect(
      WorkFollowThemeContrast.foregroundOn(WorkFollowTheme.dark.success),
      WorkFollowThemeContrast.darkForeground,
    );
  });

  test('feedback HUD is deliberately identical in Light and Dark', () {
    expect(WorkFollowTheme.light.feedbackSurface,
        WorkFollowTheme.dark.feedbackSurface);
    expect(
        WorkFollowTheme.light.feedbackText, WorkFollowTheme.dark.feedbackText);
    expect(WorkFollowTheme.light.feedbackAction,
        WorkFollowTheme.dark.feedbackAction);
    expect(
      WorkFollowThemeContrast.ratio(
        WorkFollowTheme.light.feedbackText,
        WorkFollowTheme.light.feedbackSurface,
      ),
      greaterThanOrEqualTo(7),
    );
    expect(
      WorkFollowThemeContrast.ratio(
        WorkFollowTheme.light.feedbackAction,
        WorkFollowTheme.light.feedbackSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
      'ThemeData keeps overlay, tooltip and error foreground semantics aligned',
      () {
    final light = WorkFollowThemeData.light();
    final dark = WorkFollowThemeData.dark();

    for (final entry in <(ThemeData, WorkFollowTheme)>[
      (light, WorkFollowTheme.light),
      (dark, WorkFollowTheme.dark),
    ]) {
      final data = entry.$1;
      final tokens = entry.$2;
      final tooltipDecoration = data.tooltipTheme.decoration as BoxDecoration;

      expect(data.colorScheme.surface, tokens.content);
      expect(data.colorScheme.onSurface, tokens.textPrimary);
      expect(data.dialogTheme.backgroundColor, tokens.overlay);
      expect(data.popupMenuTheme.color, tokens.overlay);
      expect(tooltipDecoration.color, tokens.feedbackSurface);
      expect(data.tooltipTheme.textStyle?.color, tokens.feedbackText);
      expect(
        WorkFollowThemeContrast.ratio(
          data.colorScheme.onPrimary,
          tokens.accent,
        ),
        greaterThanOrEqualTo(4.4),
      );
      expect(
        WorkFollowThemeContrast.ratio(
          data.colorScheme.onError,
          tokens.danger,
        ),
        greaterThanOrEqualTo(3.0),
        reason: 'danger foreground pairs with the bright status red',
      );
    }
  });
}
