import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/workfollow_surface_tokens.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// Shared surfaces for the redesigned workspace pages: cards float on the
/// canvas, page headers share one hero rhythm, and empty states get one
/// friendly voice instead of per-screen improvisation.

/// A rounded card that floats on the canvas background.
class AppCard extends StatelessWidget {
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(WorkFollowSpacing.space4),
      this.radius = WorkFollowRadii.card,
      this.color,
      this.borderColor,
      this.elevated = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      decoration: WorkFollowSurfaceTokens.card(
        tokens,
        color: color ?? tokens.content,
        borderColor: borderColor ?? tokens.border,
        elevated: elevated,
      ).copyWith(borderRadius: BorderRadius.circular(radius)),
      child:
          ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

/// Standard page header: an optional eyebrow pill, a large title and a
/// subtitle, with room for trailing content (progress, quick stats).
class PageHeader extends StatelessWidget {
  const PageHeader(
      {super.key,
      required this.title,
      this.subtitle,
      this.eyebrow,
      this.trailing,
      this.eyebrowColor,
      this.dense = false,
      this.icon});

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final Color? eyebrowColor;
  final Widget? trailing;

  /// Compact layout for short windows: drops the eyebrow, smaller title.
  final bool dense;

  /// Optional leading symbol used by task-list headers.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final iconData = icon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null && !dense) ...[
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.compactInset, vertical: WorkFollowSpacing.space1),
                    decoration: BoxDecoration(
                        color: (eyebrowColor ?? tokens.accent)
                            .withValues(alpha: .10),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.pill)),
                    child: Text(eyebrow!,
                        style: TextStyle(
                            color: eyebrowColor ?? tokens.accent,
                            fontSize: WorkFollowMacTypography.caption,
                            height: WorkFollowMacTypography.lineControl,
                            fontWeight: WorkFollowMacWeight.medium,
                            letterSpacing: WorkFollowMacTracking.none))),
                const SizedBox(height: WorkFollowSpacing.controlGap),
              ],
              if (iconData == null)
                Text(title,
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: WorkFollowMacTypography.pageTitle,
                        fontWeight: WorkFollowMacWeight.semibold,
                        letterSpacing: WorkFollowMacTracking.none,
                        height: WorkFollowMacTypography.lineTight))
              else
                Row(
                  children: [
                    AppIcon(iconData,
                        key: const ValueKey('list-view-icon'),
                        size: dense
                            ? WorkFollowMetrics.navigationIcon
                            : WorkFollowMetrics.headerIcon + 4,
                        color: tokens.textSecondary),
                    const SizedBox(width: WorkFollowSpacing.compactInset),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: WorkFollowMacTypography.pageTitle,
                              fontWeight: WorkFollowMacWeight.semibold,
                              letterSpacing: WorkFollowMacTracking.none,
                              height: WorkFollowMacTypography.lineTight)),
                    ),
                  ],
                ),
              if (subtitle != null) ...[
                SizedBox(height: dense ? WorkFollowSpacing.space1 : WorkFollowSpacing.compactGap),
                Text(subtitle!,
                    style: TextStyle(
                        color: tokens.textTertiary,
                        fontSize: WorkFollowMacTypography.supporting,
                        height: WorkFollowMacTypography.lineList)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: WorkFollowSpacing.space4),
          trailing!,
        ],
      ],
    );
  }
}

/// A thin circular progress indicator for "how far along is this view".
class ProgressRing extends StatelessWidget {
  const ProgressRing(
      {super.key,
      required this.value,
      required this.done,
      required this.total,
      this.size = 54});

  final double value;
  final int done;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
            value: value.clamp(0.0, 1.0),
            track: tokens.accent.withValues(alpha: .14),
            color: tokens.accent),
        child: Center(
          child: Text(
            total == 0 ? '—' : '$done',
            style: TextStyle(
                color: tokens.textPrimary,
                fontSize:
                    size >= 50 ? WorkFollowMacTypography.body : WorkFollowMacTypography.control,
                fontWeight: WorkFollowMacWeight.semibold),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.min(5.0, size.shortestSide / 10);
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2 + 1);
    canvas.drawArc(
        inset,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (value <= 0) return;
    canvas.drawArc(
        inset,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

/// Shared empty state: soft icon disc, one reassuring line, one hint.
class EmptyHint extends StatelessWidget {
  const EmptyHint(
      {super.key,
      required this.icon,
      required this.title,
      required this.hint,
      this.actionLabel,
      this.onAction});

  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: WorkFollowSpacing.emptyStateVerticalPadding,
          horizontal: WorkFollowSpacing.lg),
      child: Column(
        children: [
          Container(
              width: AppSurfaceMetrics.emptyStateIconSize,
              height: AppSurfaceMetrics.emptyStateIconSize,
              decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .09),
                  shape: BoxShape.circle),
              child: AppIcon(icon,
                  size: WorkFollowMetrics.headerIcon + 8,
                  color: tokens.accent)),
          const SizedBox(height: WorkFollowSpacing.space4),
          Text(title,
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.listTitle,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.semibold)),
          const SizedBox(height: WorkFollowSpacing.inlineGap),
          Text(hint,
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.supporting,
                  height: WorkFollowMacTypography.lineList)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: WorkFollowSpacing.space4),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Compact statistic card used on the home dashboard.
class StatCard extends StatelessWidget {
  const StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final body = Row(
      children: [
        Container(
            width: AppSurfaceMetrics.statisticIconSurfaceSize,
            height: AppSurfaceMetrics.statisticIconSurfaceSize,
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(WorkFollowRadii.surface)),
            child: AppIcon(icon,
                size: WorkFollowMetrics.toolbarIcon + 1, color: color)),
        const SizedBox(width: WorkFollowSpacing.controlGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: WorkFollowMacTypography.pageTitle,
                      fontWeight: WorkFollowMacWeight.semibold,
                      letterSpacing: WorkFollowMacTracking.none,
                      height: WorkFollowMacTypography.lineTight)),
              const SizedBox(height: WorkFollowSpacing.tightGap),
              Text(label,
                  style: TextStyle(
                      color: tokens.textTertiary,
                      fontSize: WorkFollowMacTypography.supporting,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.medium)),
            ],
          ),
        ),
      ],
    );
    final card = AppCard(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.relaxedGap, WorkFollowSpacing.controlInset, WorkFollowSpacing.relaxedGap, WorkFollowSpacing.space3),
      child: body,
    );
    if (onTap == null) return card;
    return Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(WorkFollowRadii.card),
            onTap: onTap,
            child: card));
  }
}
