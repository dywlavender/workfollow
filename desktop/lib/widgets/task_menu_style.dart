import 'package:flutter/material.dart';
import '../theme/workfollow_theme.dart';

/// Task menu proportions and its neutral surface with blue selection accents.
class TaskMenuStyle {
  static const width = 264.0;
  static const rowHeight = 44.0;
  static const iconSize = 20.0;

  static WorkFollowTheme colors(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    if (Theme.of(context).brightness == Brightness.dark) return tokens;
    return tokens.copyWith(
      textPrimary: const Color(0xFF242424),
      textSecondary: const Color(0xFF777777),
      textTertiary: const Color(0xFF9E9E9E),
      border: const Color(0xFFEEEEEE),
      accent: const Color(0xFF4B6BFB),
      accentSoft: const Color(0xFFF1F4FF),
      accentFaint: const Color(0xFFF1F4FF),
      danger: const Color(0xFFE8332A),
      warning: const Color(0xFFFFAA00),
    );
  }
}
