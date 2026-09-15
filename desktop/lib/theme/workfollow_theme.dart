import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared geometry for the desktop design system. Components should consume
/// these values instead of inventing a new size for every screen.
class WorkFollowMetrics {
  const WorkFollowMetrics._();

  static const double railIcon = 20;
  static const double navigationIcon = 18;
  static const double headerIcon = 18;
  static const double toolbarIcon = 16;
  static const double metadataIcon = 14;
  static const double iconHitTarget = 32;
  static const double primaryButtonHeight = 36;
  static const double compactButtonHeight = 32;
  static const double chipHeight = 28;
  static const double menuRowHeight = 40;
  static const double taskRowMinHeight = 44;
  static const double editorToolbarHeight = 40;
}

class WorkFollowSpacing {
  const WorkFollowSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class WorkFollowRadii {
  const WorkFollowRadii._();

  static const double control = 7;
  static const double surface = 10;
  static const double card = 12;
  static const double popover = 12;
  static const double pill = 999;
}

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
    canvas: Color(0xFFF5F6FB),
    sidebar: Color(0xFFEEF0F7),
    content: Color(0xFFFFFFFF),
    inspector: Color(0xFFFFFFFF),
    overlay: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1F2430),
    textSecondary: Color(0xFF687285),
    textTertiary: Color(0xFF98A1B2),
    border: Color(0xFFE3E6EE),
    borderStrong: Color(0xFFD1D6E0),
    accent: Color(0xFF5B5CE2),
    accentHover: Color(0xFF4C4FCF),
    accentSoft: Color(0xFFEEF2FF),
    accentFaint: Color(0xFFF7F8FF),
    success: Color(0xFF2EAB78),
    warning: Color(0xFFC67912),
    danger: Color(0xFFE45454),
    shadow: Color(0x14161B2B),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF2F4FF), Color(0xFFF7F8FA)],
    ),
  );

  static const dark = WorkFollowTheme(
    canvas: Color(0xFF1B1D22),
    sidebar: Color(0xFF191B20),
    content: Color(0xFF202329),
    inspector: Color(0xFF202329),
    overlay: Color(0xFF2A2D34),
    textPrimary: Color(0xFFF4F5F7),
    textSecondary: Color(0xFFB8BEC9),
    textTertiary: Color(0xFF858D9A),
    border: Color(0xFF30343D),
    borderStrong: Color(0xFF4A505B),
    accent: Color(0xFF7E88FF),
    accentHover: Color(0xFF98A1FF),
    accentSoft: Color(0xFF2D355C),
    accentFaint: Color(0xFF252B4A),
    success: Color(0xFF5BCE91),
    warning: Color(0xFFF2B84B),
    danger: Color(0xFFFF6868),
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
      fontFamilyFallback: const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Arial Unicode MS',
      ],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: NoSplash.splashFactory,
      hoverColor: tokens.accentSoft,
      focusColor: tokens.accent.withValues(alpha: .22),
      dividerColor: tokens.border,
      textTheme: TextTheme(
        displaySmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: 26,
            height: 1.18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.45),
        headlineSmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3),
        titleLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -.25),
        titleMedium: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w600),
        titleSmall: TextStyle(
            color: tokens.textSecondary,
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600),
        bodyLarge:
            TextStyle(color: tokens.textPrimary, fontSize: 14, height: 1.45),
        bodyMedium:
            TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4),
        bodySmall:
            TextStyle(color: tokens.textTertiary, fontSize: 11, height: 1.35),
        labelLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w600),
        labelMedium: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600),
        labelSmall: TextStyle(
            color: tokens.textTertiary,
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w500),
      ),
      iconTheme: IconThemeData(
          color: tokens.textSecondary, size: WorkFollowMetrics.navigationIcon),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        textStyle: TextStyle(
            color: brightness == Brightness.dark
                ? tokens.textPrimary
                : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500),
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? tokens.overlay
              : const Color(0xFF2A2D34),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          minimumSize: const Size(0, WorkFollowMetrics.compactButtonHeight),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, WorkFollowMetrics.primaryButtonHeight),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, WorkFollowMetrics.compactButtonHeight),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          side: BorderSide(color: tokens.borderStrong),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          hoverColor: tokens.accentFaint,
          highlightColor: Colors.transparent,
          minimumSize: const Size(
              WorkFollowMetrics.iconHitTarget, WorkFollowMetrics.iconHitTarget),
          padding: const EdgeInsets.all(6),
          visualDensity: VisualDensity.compact,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: tokens.borderStrong, width: 1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.popover)),
        titleTextStyle: TextStyle(
            color: tokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700),
        contentTextStyle:
            TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: tokens.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.popover)),
      ),
      dividerTheme:
          DividerThemeData(color: tokens.border, thickness: 1, space: 1),
    );
  }
}
