import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.size = WorkFollowMetrics.iconHitTarget,
    this.iconSize = WorkFollowMetrics.toolbarIcon,
    this.iconColor,
    this.activeBackgroundColor,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double size;
  final double iconSize;

  /// Optional override for icon-only surfaces such as the colored app rail.
  /// Ordinary controls continue to derive their color from the shared theme.
  final Color? iconColor;
  final Color? activeBackgroundColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final child = Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? tooltip,
      child: Material(
        color: active
            ? (activeBackgroundColor ?? tokens.accentSoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          child: SizedBox(
            width: size,
            height: size,
            child: AppIcon(
              icon,
              size: iconSize,
              color: iconColor ??
                  (onPressed == null
                      ? tokens.textTertiary
                      : (active ? tokens.accent : tokens.textSecondary)),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null || onPressed == null) return child;
    return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 450),
        child: child);
  }
}

class SoftPill extends StatelessWidget {
  const SoftPill({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.icon,
  });

  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      constraints:
          const BoxConstraints(minHeight: WorkFollowMetrics.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.space1),
      decoration: BoxDecoration(
        color: color ?? tokens.accentFaint,
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!,
                size: WorkFollowMetrics.metadataIcon,
                color: textColor ?? tokens.textSecondary),
            const SizedBox(width: WorkFollowSpacing.space1),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor ?? tokens.textSecondary,
              fontSize: WorkFollowMacTypography.control,
              fontWeight: WorkFollowMacWeight.semibold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small semantic wrapper used when an icon is not interactive.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = WorkFollowMetrics.navigationIcon,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(
        icon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
}
