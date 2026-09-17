import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/stats_aggregator.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_surfaces.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool weeklyRange = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final stats = StatsAggregator.aggregate(widget.controller.activeTasks,
        // The weekly chart is week-to-date: Monday contributes one bar, and
        // each following day adds one more bar through Sunday.
        trendDays: weeklyRange ? DateTime.now().weekday : 30);
    final total =
        stats.completedByList.values.fold<int>(0, (sum, value) => sum + value);
    return Container(
      color: tokens.canvas,
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.space6, WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageBottomSpace),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: StatsMetrics.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: '统计',
                  subtitle: stats.hasCompletion
                      ? '看见自己的节奏，再决定下一步。'
                      : '完成第一件事后，这里会开始长出你的节奏。',
                  trailing: _RangeSegment(
                      weekly: weeklyRange,
                      onChanged: (value) =>
                          setState(() => weeklyRange = value)),
                ),
                const SizedBox(height: WorkFollowSpacing.sectionGap),
                Wrap(
                  spacing: WorkFollowSpacing.space3,
                  runSpacing: WorkFollowSpacing.space3,
                  children: [
                    SizedBox(
                        width: narrow ? double.infinity : 190,
                        child: StatCard(
                            label: '今日完成',
                            value: '${stats.todayCompleted}',
                            icon: WorkFollowIcons.statToday,
                            color: tokens.accent)),
                    SizedBox(
                        width: narrow ? double.infinity : 190,
                        child: StatCard(
                            label: '本周完成',
                            value: '${stats.weekCompleted}',
                            icon: WorkFollowIcons.trend,
                            color: tokens.success)),
                    SizedBox(
                        width: narrow ? double.infinity : 190,
                        child: StatCard(
                            label: '逾期',
                            value: '${stats.overdue}',
                            icon: WorkFollowIcons.historyToggle,
                            color: tokens.warning)),
                    SizedBox(
                        width: narrow ? double.infinity : 190,
                        child: StatCard(
                            label: '进行中',
                            value: '${stats.active}',
                            icon: WorkFollowIcons.unchecked,
                            color: tokens.accent)),
                    SizedBox(
                        width: narrow ? double.infinity : 190,
                        child: StatCard(
                            label: '专注番茄',
                            value: '${stats.focusSessions}',
                            icon: WorkFollowIcons.focus,
                            color: tokens.accentHover)),
                  ],
                ),
                const SizedBox(height: WorkFollowSpacing.relaxedGap),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.sectionGap, WorkFollowSpacing.space4, WorkFollowSpacing.sectionGap, WorkFollowSpacing.relaxedGap),
                  child: SizedBox(
                    height: StatsMetrics.summaryCardHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CardTitle(
                            title: '完成趋势',
                            subtitle: weeklyRange
                                ? '本周截至今日 · 每日完成数'
                                : '最近 30 天 · 每日完成数'),
                        const SizedBox(height: WorkFollowSpacing.statusGap),
                        Expanded(
                            child: CustomPaint(
                                painter: _TrendPainter(
                                    values: stats.dailyCompletionCounts,
                                    color: tokens.accent,
                                    grid: tokens.border),
                                child: const SizedBox.expand())),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: WorkFollowSpacing.relaxedGap),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.sectionGap, WorkFollowSpacing.space4, WorkFollowSpacing.sectionGap, WorkFollowSpacing.relaxedGap),
                  child: SizedBox(
                    height: StatsMetrics.chartCardHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CardTitle(
                            title: '完成热力图', subtitle: '近 16 周 · 每个格子代表一天'),
                        const SizedBox(height: WorkFollowSpacing.space3),
                        Expanded(
                            child: CustomPaint(
                                painter: _HeatmapPainter(
                                    counts: stats.completionByDay,
                                    startDate: stats.heatmapStartDate,
                                    color: tokens.accent,
                                    empty:
                                        tokens.border.withValues(alpha: .45)),
                                child: const SizedBox.expand())),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: WorkFollowSpacing.relaxedGap),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.sectionGap, WorkFollowSpacing.space4, WorkFollowSpacing.sectionGap, WorkFollowSpacing.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardTitle(title: '清单分布', subtitle: '按完成记录统计'),
                      const SizedBox(height: WorkFollowSpacing.space4),
                      if (total == 0)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: WorkFollowSpacing.sectionGap),
                            child: Text('暂时还没有可统计的完成记录。'))
                      else
                        _Distribution(
                            controller: widget.controller,
                            values: stats.completedByList,
                            total: total),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Row(children: [
      Text(title,
          style: TextStyle(
              color: tokens.textPrimary,
              fontSize: WorkFollowMacTypography.sectionTitle,
              fontWeight: WorkFollowMacWeight.semibold)),
      const SizedBox(width: WorkFollowSpacing.space2),
      Text(subtitle,
          style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta)),
    ]);
  }
}

class _RangeSegment extends StatelessWidget {
  const _RangeSegment({required this.weekly, required this.onChanged});

  final bool weekly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WorkFollowSpacing.microGap),
      decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: Border.all(color: tokens.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final option in const [(false, '近30天'), (true, '本周')])
          InkWell(
              onTap: () => onChanged(option.$1),
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.compactInset, vertical: WorkFollowSpacing.denseGap),
                  decoration: BoxDecoration(
                      color: weekly == option.$1
                          ? tokens.accentSoft
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(WorkFollowRadii.control)),
                  child: Text(option.$2,
                      style: TextStyle(
                          color: weekly == option.$1
                              ? tokens.accent
                              : tokens.textSecondary,
                          fontSize: WorkFollowMacTypography.control,
                          fontWeight: WorkFollowMacWeight.semibold)))),
      ]),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(
      {required this.values, required this.color, required this.grid});

  final List<int> values;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - 2;
    final maxValue = values.fold<int>(0, math.max);
    final gap = values.isEmpty ? 0.0 : 3.0;
    final barWidth = values.isEmpty
        ? 0.0
        : math.max(
            1.0, (size.width - gap * (values.length - 1)) / values.length);
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), line);
    if (maxValue == 0) return;
    for (var i = 0; i < values.length; i++) {
      final amount = values[i];
      final height = amount == 0 ? 2.0 : (size.height - 10) * amount / maxValue;
      final left = i * (barWidth + gap);
      final rect = Rect.fromLTWH(left, baseline - height, barWidth, height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = color.withValues(alpha: amount == 0 ? .10 : .82));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid;
}

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.counts,
    required this.startDate,
    required this.color,
    required this.empty,
  });

  final Map<DateTime, int> counts;
  final DateTime startDate;
  final Color color;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    const columns = 16;
    const rows = 7;
    final gap = 4.0;
    final cell = math.min((size.width - gap * (columns - 1)) / columns,
        (size.height - gap * (rows - 1)) / rows);
    final width = columns * cell + (columns - 1) * gap;
    final offsetX = math.max(0, (size.width - width) / 2);
    var maxCount = 0;
    for (final count in counts.values) {
      if (count > maxCount) maxCount = count;
    }
    final first = startDate.subtract(Duration(days: startDate.weekday - 1));
    for (var column = 0; column < columns; column++) {
      for (var row = 0; row < rows; row++) {
        final day = first.add(Duration(days: column * 7 + row));
        final count = counts[DateTime(day.year, day.month, day.day)] ?? 0;
        final opacity = maxCount == 0 ? .08 : .13 + .82 * count / maxCount;
        final rect = Rect.fromLTWH(
            offsetX + column * (cell + gap), row * (cell + gap), cell, cell);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()
              ..color = count == 0 ? empty : color.withValues(alpha: opacity));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.counts != counts ||
      oldDelegate.startDate != startDate ||
      oldDelegate.color != color;
}

class _Distribution extends StatelessWidget {
  const _Distribution(
      {required this.controller, required this.values, required this.total});

  final WorkspaceController controller;
  final Map<String, int> values;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final ordered = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: StatsMetrics.donutSize,
          height: StatsMetrics.donutSize,
          child: CustomPaint(
              painter: _DonutPainter(
                  entries: ordered,
                  total: total,
                  colorFor: (name) => Color(controller.colorValueForList(name)),
                  track: tokens.border))),
      const SizedBox(width: WorkFollowSpacing.headingGap),
      Expanded(
          child: Wrap(spacing: WorkFollowSpacing.sectionGap, runSpacing: WorkFollowSpacing.controlGap, children: [
        for (final entry in ordered)
          Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: StatsMetrics.legendDotSize,
                height: StatsMetrics.legendDotSize,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(controller.colorValueForList(entry.key)))),
            const SizedBox(width: WorkFollowSpacing.inlineGap),
            Text('${entry.key}  ${((entry.value / total) * 100).round()}%',
                style: TextStyle(color: tokens.textSecondary, fontSize: WorkFollowMacTypography.listMeta)),
          ]),
      ])),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(
      {required this.entries,
      required this.total,
      required this.colorFor,
      required this.track});

  final List<MapEntry<String, int>> entries;
  final int total;
  final Color Function(String name) colorFor;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.min(13.0, size.shortestSide / 5);
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    canvas.drawArc(
        inset,
        -math.pi / 2,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    var start = -math.pi / 2;
    for (final entry in entries) {
      final sweep = math.pi * 2 * entry.value / total;
      canvas.drawArc(
          inset,
          start,
          sweep,
          false,
          Paint()
            ..color = colorFor(entry.key)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.entries != entries || oldDelegate.total != total;
}
