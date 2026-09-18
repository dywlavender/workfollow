import 'package:flutter/material.dart';

import 'workfollow_theme.dart';
import 'workfollow_theme_parity.dart';

/// Color roles that do not belong to the base light/dark theme extension.
///
/// Most UI colors live directly on [WorkFollowTheme]. This catalog holds the
/// few component palettes that need a stable semantic role of their own:
/// navigation's neutral light profile, the matrix's four category colors and
/// the persisted Quill highlight marker. Widgets consume these names instead
/// of carrying a private hex palette.
class WorkFollowColorTokens {
  const WorkFollowColorTokens._();

  // The light navigation profile follows the macOS reference rail. These are
  // component tokens, so the values stay in the design layer rather than in
  // sidebar.dart.
  static const Color lightNavigationRail = Color(0xFFF1F3F6);
  static const Color lightNavigationSurface = Color(0xFFF7F8FA);
  static const Color lightNavigationSelected = Color(0xFFEEF0FF);
  static const Color lightNavigationAccent = Color(0xFF5B5CEB);
  static const Color lightNavigationForeground = Color(0xFF697386);
  static const Color lightNavigationForegroundMuted = Color(0xFF98A1AF);
  static const Color lightNavigationBorder = Color(0xFFE5E7EB);

  // Matrix categories are a fixed visual palette for a derived view. They
  // are data-viz colors, not task title/row colors.
  static const Color matrixDoNow = Color(0xFFFF5D68);
  static const Color matrixSchedule = Color(0xFFFFAB00);
  static const Color matrixDelegate = Color(0xFF5C7CFA);
  static const Color matrixLater = Color(0xFF1DC8A0);

  /// Quill stores this marker in existing document Deltas. Rendering is
  /// overridden by DocumentStyles to use the theme's highlight surface;
  /// the string remains here only for backwards-compatible document data.
  static const String documentHighlightAttribute = '#d4ff00';

  static Color navigationRail(BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationRail
          : tokens.rail;

  static Color navigationSurface(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationSurface
          : tokens.sidebar;

  static Color navigationSelected(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationSelected
          : tokens.accentSoft;

  /// Selected fill for a row in the navigation column: neutral, never tinted.
  ///
  /// The column's own surface is already grey, so the neutral counterpart of
  /// the reference's light-grey chip is *lighter* than the surface here rather
  /// than darker. An accent-tinted fill made a selected row read as a colour
  /// instead of as a state, and pulled the accent onto the row's words too.
  static Color navigationSelectedNeutral(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? tokens.content
          : tokens.listRowSelected;

  static Color navigationAccent(BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationAccent
          : tokens.accent;

  static Color navigationForeground(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationForeground
          : tokens.railForeground;

  static Color navigationForegroundMuted(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationForegroundMuted
          : tokens.railForegroundMuted;

  static Color navigationBorder(BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationBorder
          : tokens.railBorder;

  /// Navigation interaction fills keep their light reference profile while
  /// resolving the actual foreground from the active theme. Widgets should
  /// ask for the semantic state instead of branching on brightness themselves.
  static Color navigationHover(BuildContext context, WorkFollowTheme tokens) {
    final light = Theme.of(context).brightness == Brightness.light;
    return navigationForeground(context, tokens)
        .withValues(alpha: light ? .10 : .12);
  }

  static Color navigationPressed(BuildContext context, WorkFollowTheme tokens) {
    final light = Theme.of(context).brightness == Brightness.light;
    return navigationForeground(context, tokens)
        .withValues(alpha: light ? .16 : .20);
  }

  /// Selected fill for the compact rail button. The light reference uses a
  /// quiet navigation fill; the dark rail uses its own active surface.
  static Color navigationRailSelected(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationSelected
          : tokens.railActive;

  /// Surface behind the rail footer controls.
  static Color navigationFooterSurface(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationSelected
          : tokens.railSurface;

  static LinearGradient navigationGradient(
      BuildContext context, WorkFollowTheme tokens) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return tokens.sidebarGradient;
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lightNavigationSurface, lightNavigationRail],
    );
  }

  /// The schedule property field uses the same neutral selected surface as
  /// the rest of the menu system. Dark mode keeps the existing canvas depth.
  static Color scheduleFieldSurface(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.dark
          ? tokens.canvas
          : tokens.menuSelected;

  static Color documentHighlightBackground(WorkFollowTheme tokens) =>
      tokens.accentSoft;

  static Color documentHighlightForeground(WorkFollowTheme tokens) =>
      tokens.textPrimary;

  /// Neutral document checklist face. A completed checklist is content state,
  /// not a success badge, so it deliberately does not use the brand accent or
  /// success colour. Light surfaces use the secondary graphite role; dark
  /// surfaces use the stronger neutral border role so the marker stays quiet
  /// without disappearing into the editor surface.
  static Color documentChecklistFill(WorkFollowTheme tokens) =>
      tokens.content.computeLuminance() > .5
          ? tokens.textSecondary
          : tokens.borderStrong;

  /// Foreground for the completed marker's check stroke. Keeping the contrast
  /// choice here gives both editor profiles the same Light/Dark behaviour.
  static Color documentChecklistCheck(WorkFollowTheme tokens) =>
      WorkFollowThemeContrast.foregroundOn(documentChecklistFill(tokens));

  /// Smart-entry fragments use existing semantic roles rather than a second
  /// per-kind palette. The roles intentionally remain distinct in the field.
  static Color quickAddDate(WorkFollowTheme tokens) => tokens.accent;
  static Color quickAddTime(WorkFollowTheme tokens) => tokens.accentHover;
  static Color quickAddRecurrence(WorkFollowTheme tokens) =>
      tokens.textSecondary;
  static Color quickAddTag(WorkFollowTheme tokens) => tokens.success;
  static Color quickAddList(WorkFollowTheme tokens) => tokens.warning;
  static Color quickAddPriority(WorkFollowTheme tokens) => tokens.danger;

  /// Frame for the two Quick Add presentations. The list variant is an
  /// unraised input slot; the dashboard variant is a raised card. Expanded
  /// state uses the same accent focus treatment in both places.
  static Color quickAddBorder(
    WorkFollowTheme tokens, {
    required bool expanded,
    required bool listStyle,
  }) {
    if (listStyle) {
      return expanded
          ? tokens.accent.withValues(alpha: .45)
          : Colors.transparent;
    }
    return expanded
        ? tokens.accent.withValues(alpha: .55)
        : tokens.borderStrong;
  }
}
