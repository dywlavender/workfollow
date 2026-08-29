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
    canvas: Color(0xFFF7F6F8),
    sidebar: Color(0xFFF0EEF3),
    content: Color(0xFFFCFBFD),
    inspector: Color(0xFFF8F7FA),
    overlay: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF28262D),
    textSecondary: Color(0xFF696570),
    textTertiary: Color(0xFF96919B),
    border: Color(0xFFE6E3E9),
    borderStrong: Color(0xFFD9D5DF),
    accent: Color(0xFF6257B8),
    accentHover: Color(0xFF51479E),
    accentSoft: Color(0xFFECEAF8),
    accentFaint: Color(0xFFF5F3FC),
    success: Color(0xFF278A65),
    warning: Color(0xFFA36310),
    danger: Color(0xFFB7485C),
    shadow: Color(0x1A2D2639),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8ECF2), Color(0xFFF0EEF8)],
    ),
  );

  static const dark = WorkFollowTheme(
    canvas: Color(0xFF151419),
    sidebar: Color(0xFF1B1921),
    content: Color(0xFF1B1A20),
    inspector: Color(0xFF19181E),
    overlay: Color(0xFF25232C),
    textPrimary: Color(0xFFF5F2F7),
    textSecondary: Color(0xFFB7B1BE),
    textTertiary: Color(0xFF817B88),
    border: Color(0xFF302D38),
    borderStrong: Color(0xFF403B49),
    accent: Color(0xFFA79CF2),
    accentHover: Color(0xFFC1B9FF),
    accentSoft: Color(0xFF302C4B),
    accentFaint: Color(0xFF242137),
    success: Color(0xFF65C69B),
    warning: Color(0xFFF0B763),
    danger: Color(0xFFF28A9D),
    shadow: Color(0x66000000),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF211821), Color(0xFF1B1C2B)],
    ),
  );

  static WorkFollowTheme of(BuildContext context) {
    return Theme.of(context).extension<WorkFollowTheme>() ?? WorkFollowTheme.light;
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
      onPrimary: brightness == Brightness.light ? Colors.white : const Color(0xFF1C1731),
      secondary: tokens.accent,
      onSecondary: brightness == Brightness.light ? Colors.white : const Color(0xFF1C1731),
      error: tokens.danger,
      onError: Colors.white,
      surface: tokens.content,
      onSurface: tokens.textPrimary,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: NoSplash.splashFactory,
      hoverColor: tokens.accentSoft,
      focusColor: tokens.accent.withOpacity(.22),
      dividerColor: tokens.border,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: tokens.textPrimary, fontSize: 14, height: 1.45),
        bodyMedium: TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4),
        bodySmall: TextStyle(color: tokens.textTertiary, fontSize: 11, height: 1.35),
        titleLarge: TextStyle(color: tokens.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.45),
        titleMedium: TextStyle(color: tokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -.1),
        titleSmall: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: tokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 18),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1, space: 1),
    );
  }
}
