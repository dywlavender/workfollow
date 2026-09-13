import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class WorkFollowTheme extends ThemeExtension<WorkFollowTheme> {
  const WorkFollowTheme({
    required this.canvas,
    required this.sidebar,
    required this.content,
    required this.inspector,
    required this.overlay,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentFaint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.seasonalSky,
  });

  final Color canvas;
  final Color sidebar;
  final Color content;
  final Color inspector;
  final Color overlay;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderStrong;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color accentFaint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final LinearGradient seasonalSky;

  static const light = WorkFollowTheme(
    canvas: Color(0xFFF2F3F8),
    sidebar: Color(0xFFECEEF4),
    content: Color(0xFFFFFFFF),
    inspector: Color(0xFFF8F9FC),
    overlay: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF171A21),
    textSecondary: Color(0xFF5F6672),
    textTertiary: Color(0xFF6B7280),
    border: Color(0xFFE6E8EF),
    borderStrong: Color(0xFFD7DBE4),
    accent: Color(0xFF4F46E5),
    accentHover: Color(0xFF4338CA),
    accentSoft: Color(0xFFEEF2FF),
    accentFaint: Color(0xFFF5F6FF),
    success: Color(0xFF237A57),
    warning: Color(0xFFA15C08),
    danger: Color(0xFFB13F50),
    shadow: Color(0x14111827),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF2F4FF), Color(0xFFF7F8FA)],
    ),
  );

  static const dark = WorkFollowTheme(
    canvas: Color(0xFF1B1C1E),
    sidebar: Color(0xFF18191B),
    content: Color(0xFF202124),
    inspector: Color(0xFF1D1E20),
    overlay: Color(0xFF2B2C2F),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFFB5B5B8),
    textTertiary: Color(0xFF85858B),
    border: Color(0xFF303135),
    borderStrong: Color(0xFF48494E),
    accent: Color(0xFF7192FF),
    accentHover: Color(0xFF91AAFF),
    accentSoft: Color(0xFF2D3A5C),
    accentFaint: Color(0xFF252F4A),
    success: Color(0xFF5ACB8A),
    warning: Color(0xFFF2B84B),
    danger: Color(0xFFFF5A5F),
    shadow: Color(0x88000000),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF202124), Color(0xFF1B1C1E)],
    ),
  );

  static WorkFollowTheme of(BuildContext context) {
    return Theme.of(context).extension<WorkFollowTheme>() ??
        WorkFollowTheme.light;
  }

  @override
  WorkFollowTheme copyWith({
    Color? canvas,
    Color? sidebar,
    Color? content,
    Color? inspector,
    Color? overlay,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? accentFaint,
    Color? success,
    Color? warning,
    Color? danger,
    Color? shadow,
    LinearGradient? seasonalSky,
  }) {
    return WorkFollowTheme(
      canvas: canvas ?? this.canvas,
      sidebar: sidebar ?? this.sidebar,
      content: content ?? this.content,
      inspector: inspector ?? this.inspector,
      overlay: overlay ?? this.overlay,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      accentFaint: accentFaint ?? this.accentFaint,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      shadow: shadow ?? this.shadow,
      seasonalSky: seasonalSky ?? this.seasonalSky,
    );
  }

  @override
  WorkFollowTheme lerp(covariant WorkFollowTheme? other, double t) {
    if (other == null) return this;
    return WorkFollowTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      content: Color.lerp(content, other.content, t)!,
      inspector: Color.lerp(inspector, other.inspector, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentFaint: Color.lerp(accentFaint, other.accentFaint, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      seasonalSky: t < .5 ? seasonalSky : other.seasonalSky,
    );
  }
}

class WorkFollowThemeData {
  const WorkFollowThemeData._();

  static ThemeData light() => _build(WorkFollowTheme.light, Brightness.light);

  static ThemeData dark() => _build(WorkFollowTheme.dark, Brightness.dark);

  static ThemeData _build(WorkFollowTheme tokens, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF111216),
      secondary: tokens.accent,
      onSecondary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF111216),
      error: tokens.danger,
      onError: Colors.white,
      surface: tokens.content,
      onSurface: tokens.textPrimary,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily:
          defaultTargetPlatform == TargetPlatform.macOS ? '.SF Pro Text' : null,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: NoSplash.splashFactory,
      hoverColor: tokens.accentSoft,
      focusColor: tokens.accent.withValues(alpha: .22),
      dividerColor: tokens.border,
      textTheme: TextTheme(
        bodyLarge:
            TextStyle(color: tokens.textPrimary, fontSize: 14, height: 1.45),
        bodyMedium:
            TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4),
        bodySmall:
            TextStyle(color: tokens.textTertiary, fontSize: 11, height: 1.35),
        titleLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6),
        titleMedium: TextStyle(
            color: tokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.1),
        titleSmall: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600),
        labelLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
        labelMedium: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600),
        labelSmall: TextStyle(
            color: tokens.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 18),
      dividerTheme:
          DividerThemeData(color: tokens.border, thickness: 1, space: 1),
    );
  }
}
