import 'package:flutter/material.dart';

/// Contrast and surface checks shared by the Light/Dark theme contract.
///
/// Widgets should still consume [WorkFollowTheme] roles.  This helper exists
/// for theme validation and for controls that need a readable foreground on a
/// coloured semantic surface (for example, today's calendar cell or a filled
/// action).  Keeping the choice here prevents each screen from inventing its
/// own black/white brightness branch.
class WorkFollowThemeContrast {
  const WorkFollowThemeContrast._();

  /// The dark foreground used when white would not be readable on a bright
  /// status or accent surface.  It matches the dark ColorScheme foreground.
  static const Color darkForeground = Color(0xFF111216);

  /// Returns WCAG relative contrast after compositing a translucent
  /// foreground over [background].
  static double ratio(Color foreground, Color background) {
    final resolvedForeground = foreground.a == 1
        ? foreground
        : Color.alphaBlend(foreground, background);
    final foregroundLuminance = resolvedForeground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + .05) / (darker + .05);
  }

  /// Returns the higher-contrast foreground for an opaque semantic surface.
  /// Ties prefer white, which keeps the light accent controls familiar.
  static Color foregroundOn(Color surface) {
    final whiteContrast = ratio(Colors.white, surface);
    final darkContrast = ratio(darkForeground, surface);
    return whiteContrast >= darkContrast ? Colors.white : darkForeground;
  }

  /// Relative luminance distance used for quiet hover/selected surfaces.
  static double surfaceDelta(Color first, Color second) =>
      (first.computeLuminance() - second.computeLuminance()).abs();
}
