import 'package:flutter/material.dart';

import 'workfollow_theme.dart';

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
  static const Color lightNavigationSelected = Color(0xFFEEF2FF);
  static const Color lightNavigationAccent = Color(0xFF635BFF);
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
  /// overridden by TaskDocumentStyles to use the theme's highlight surface;
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

  static Color navigationAccent(
          BuildContext context, WorkFollowTheme tokens) =>
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

  static Color navigationBorder(
          BuildContext context, WorkFollowTheme tokens) =>
      Theme.of(context).brightness == Brightness.light
          ? lightNavigationBorder
          : tokens.railBorder;

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

  /// Smart-entry fragments use existing semantic roles rather than a second
  /// per-kind palette. The roles intentionally remain distinct in the field.
  static Color quickAddDate(WorkFollowTheme tokens) => tokens.accent;
  static Color quickAddTime(WorkFollowTheme tokens) => tokens.accentHover;
  static Color quickAddRecurrence(WorkFollowTheme tokens) => tokens.textSecondary;
  static Color quickAddTag(WorkFollowTheme tokens) => tokens.success;
  static Color quickAddList(WorkFollowTheme tokens) => tokens.warning;
  static Color quickAddPriority(WorkFollowTheme tokens) => tokens.danger;
}
