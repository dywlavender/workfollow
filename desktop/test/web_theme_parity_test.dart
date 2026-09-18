import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('Web spacing and shape primitives are preserved', () {
    expect(
      [
        WorkFollowSpacing.zero,
        WorkFollowSpacing.space1,
        WorkFollowSpacing.space2,
        WorkFollowSpacing.space3,
        WorkFollowSpacing.space4,
        WorkFollowSpacing.space5,
        WorkFollowSpacing.space6,
        WorkFollowSpacing.space7,
        WorkFollowSpacing.space8,
      ],
      [0, 4, 8, 12, 16, 20, 24, 28, 32],
    );
    expect(WorkFollowRadii.none, 0);
    expect(WorkFollowRadii.xs, 4);
    expect(WorkFollowRadii.sm, 6);
    expect(WorkFollowRadii.md, 8);
    expect(WorkFollowRadii.lg, 12);
    expect(WorkFollowRadii.full, 999);
  });

  test('Web typography primitive and role mappings stay in sync', () {
    expect(WorkFollowTypography.webUiFontFamily, 'Inter');
    expect(WorkFollowTypography.webMonoFontFamily, 'JetBrains Mono');
    expect(
      WorkFollowTypography.webFontFallback,
      containsAll(<String>[
        'Noto Sans SC',
        'PingFang SC',
        'Microsoft YaHei',
      ]),
    );
    expect(
      [
        WorkFollowTypography.webMicro,
        WorkFollowTypography.webCaption,
        WorkFollowTypography.webLabel,
        WorkFollowTypography.webBodySmall,
        WorkFollowTypography.webBody,
        WorkFollowTypography.webTitleSmall,
        WorkFollowTypography.webTitle,
        WorkFollowTypography.webHeadingSmall,
        WorkFollowTypography.webHeading,
        WorkFollowTypography.webHeadingLarge,
        WorkFollowTypography.webDisplaySmall,
        WorkFollowTypography.webDisplay,
      ],
      [10, 11, 12, 13, 14, 16, 18, 20, 22, 24, 28, 32],
    );
    expect(
        WorkFollowTypography.webPageTitleSize, WorkFollowTypography.webHeading);
    expect(WorkFollowTypography.webNavigationSize,
        WorkFollowTypography.webBodySmall);
    expect(
        WorkFollowTypography.webEditorBodySize, WorkFollowTypography.webBody);
    expect(WorkFollowTypography.webLineHeightEditor, 1.85);
    expect(WorkFollowTypography.webTrackingHeading, -.02);
  });

  test('neutral surface roles match the Web fallback preset', () {
    const light = WorkFollowSurfaceSet.neutralLight;
    final dark = WorkFollowSurfaceSet.neutralDark;

    expect(light.page, WorkFollowColors.neutral50);
    expect(light.rail, WorkFollowColors.neutral100);
    expect(light.navigation, WorkFollowColors.neutral100);
    expect(light.list, Colors.white);
    expect(light.detail, Colors.white);
    expect(light.input, const Color(0xFFFAFBFC));
    expect(light.borderLight, const Color(0xFFEAECF0));
    expect(light.borderNormal, WorkFollowColors.neutral200);

    expect(dark.page, const Color(0xFF111318));
    expect(dark.rail, const Color(0xFF16191F));
    expect(dark.navigation, const Color(0xFF181B22));
    expect(dark.list, const Color(0xFF191C23));
    expect(dark.detail, const Color(0xFF1C2027));
    expect(dark.borderNormal, const Color(0xFF343A46));
  });

  test('default Web palette primitives preserve interaction semantics', () {
    expect(WorkFollowColors.accent, const Color(0xFF4F46E5));
    expect(WorkFollowColors.accentHover, const Color(0xFF4338CA));
    expect(WorkFollowColors.accentActive, const Color(0xFF3730A3));
    expect(WorkFollowColors.accentSoft, const Color(0xFFEEF2FF));
    expect(WorkFollowColors.success, const Color(0xFF237A57));
    expect(WorkFollowColors.warning, const Color(0xFFA15C08));
    // Desktop intentionally diverges from the Web theme.ts danger token:
    // a brighter status red so overdue/destructive reads as true red (2026-09-19).
    expect(WorkFollowColors.danger, const Color(0xFFFF4D4F));
    expect(WorkFollowColors.dangerHover, const Color(0xFFD94143));
    expect(WorkFollowColors.overlay, const Color(0x47111827));
  });

  test('desktop layout contract mirrors Web breakpoints and columns', () {
    expect(WorkFollowLayout.appHeaderHeight, 76);
    expect(WorkFollowLayout.pageGutterMin, 16);
    expect(WorkFollowLayout.pageGutterMax, 24);
    expect(WorkFollowLayout.contentMaxWidth, 1280);
    expect(WorkFollowLayout.readingMaxWidth, 1040);
    expect(WorkFollowLayout.workspaceRailWidth, 152);
    expect(WorkFollowLayout.taskNavigationWidth, 218);
    expect(WorkFollowLayout.taskListWidth, 430);
    expect(WorkFollowLayout.taskListMinWidth, 360);
    expect(WorkFollowLayout.taskListDividerWidth, 1);
    expect(WorkFollowLayout.taskDetailMinWidth, 320);
    expect(WorkFollowLayout.narrowTaskListMinWidth, 300);
    expect(WorkFollowLayout.narrowTaskDetailMinWidth, 280);
    expect(WorkFollowLayout.taskDetailEmptyPadding, 32);
  });

  test('motion, glass and layer roles are named shared contracts', () {
    expect(WorkFollowMotion.instant, const Duration(milliseconds: 80));
    expect(WorkFollowMotion.fast, const Duration(milliseconds: 160));
    expect(WorkFollowMotion.normal, const Duration(milliseconds: 240));
    expect(WorkFollowGlass.railBlur, 4);
    expect(WorkFollowGlass.detailBlur, 5);
    expect(WorkFollowGlass.menuBlur, 7);
    expect(WorkFollowLayers.rail, 20);
    expect(WorkFollowLayers.popover, 90);
    expect(WorkFollowLayers.toast, 220);
  });

  test('ThemeData keeps the Web face on non-macOS targets', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final theme = WorkFollowThemeData.light();
    debugDefaultTargetPlatformOverride = null;

    expect(theme.textTheme.bodyLarge?.fontFamily,
        WorkFollowTypography.webUiFontFamily);
    expect(theme.textTheme.bodyLarge?.fontFamilyFallback,
        containsAll(<String>['Noto Sans SC', 'PingFang SC']));
  });

  test('the role scale resolves to the macOS profile on every platform', () {
    // The Web ladder still exists as a token catalog for the browser client,
    // but the desktop shell no longer renders its sizes: ThemeData now maps
    // every role onto WorkFollowMacTypography, so a leftover Web-sized call site
    // cannot reintroduce the browser scale on one platform only.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final theme = WorkFollowThemeData.light();
    debugDefaultTargetPlatformOverride = null;

    expect(theme.textTheme.displaySmall?.fontSize, WorkFollowMacTypography.pageTitle);
    expect(
        theme.textTheme.headlineSmall?.fontSize, WorkFollowMacTypography.detailTitle);
    expect(theme.textTheme.bodyLarge?.fontSize, WorkFollowMacTypography.body);
    expect(theme.textTheme.bodyMedium?.fontSize, WorkFollowMacTypography.control);
    expect(theme.textTheme.labelLarge?.fontSize, WorkFollowMacTypography.control);
  });
}
