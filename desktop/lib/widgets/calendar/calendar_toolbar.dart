import 'package:flutter/material.dart';

import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import '../desktop_popover.dart';

/// How the calendar presents time.
///
/// An enum rather than a flag because the toolbar renders it as a menu: adding
/// a day or an agenda later is one entry in [CalendarToolbar], not a second
/// boolean that every call site has to learn.
enum CalendarViewMode {
  month,
  week;

  String get label => switch (this) {
        CalendarViewMode.month => '月',
        CalendarViewMode.week => '周',
      };

  /// What one step backwards or forwards means in this mode, for the range
  /// control's tooltips. The control itself only reports the move.
  String get previousLabel => switch (this) {
        CalendarViewMode.month => '上个月',
        CalendarViewMode.week => '上一周',
      };

  String get nextLabel => switch (this) {
        CalendarViewMode.month => '下个月',
        CalendarViewMode.week => '下一周',
      };
}

/// The calendar's top bar.
///
/// The page has no heading of its own: the year and month *are* the heading, so
/// printing "日历" above them would name the page twice and spend a line of the
/// window saying nothing. Everything else on the bar is one control per thing
/// the page can do — create a task, choose the mode, move the range, open the
/// page's own settings — and the range control is grouped because the three
/// buttons only mean anything together.
class CalendarToolbar extends StatelessWidget {
  const CalendarToolbar({
    super.key,
    required this.month,
    required this.mode,
    required this.showCompleted,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required this.onAddTask,
    required this.onModeChanged,
    required this.onToggleCompleted,
  });

  final DateTime month;
  final CalendarViewMode mode;
  final bool showCompleted;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  /// Handed the button's own context: the composer a page opens is anchored to
  /// the control that opened it.
  final void Function(BuildContext anchor) onAddTask;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      height: CalendarMetrics.toolbarHeight,
      child: Row(
        children: [
          AppIcon(WorkFollowIcons.calendar,
              size: WorkFollowMetrics.navigationIcon,
              color: tokens.textSecondary),
          const SizedBox(width: WorkFollowSpacing.compactGap),
          Text(
            '${month.year}年${month.month}月',
            key: const ValueKey('calendar-month-title'),
            style: TextStyle(
              fontSize: WorkFollowMacTypography.pageTitle,
              fontWeight: WorkFollowMacWeight.semibold,
              height: WorkFollowMacTypography.lineTight,
              letterSpacing: WorkFollowMacTracking.none,
              color: tokens.textPrimary,
            ),
          ),
          const Spacer(),
          Builder(
            builder: (anchor) => AppIconButton(
              key: const ValueKey('calendar-add-task'),
              icon: WorkFollowIcons.add,
              tooltip: '新建任务',
              onPressed: () => onAddTask(anchor),
            ),
          ),
          const SizedBox(width: WorkFollowSpacing.space1),
          _ViewModeControl(mode: mode, onChanged: onModeChanged),
          const SizedBox(width: WorkFollowSpacing.space1),
          _RangeControl(
            mode: mode,
            onPrevious: onPrevious,
            onToday: onToday,
            onNext: onNext,
          ),
          const SizedBox(width: WorkFollowSpacing.space1),
          _CalendarMenuButton(
            showCompleted: showCompleted,
            onToggleCompleted: onToggleCompleted,
          ),
        ],
      ),
    );
  }
}

/// The bordered group every toolbar control wears, so the bar reads as one row
/// of controls rather than three unrelated shapes.
class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final radius = BorderRadius.circular(WorkFollowRadii.control);
    final body = SizedBox(height: WorkFollowMetrics.chipHeight, child: child);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: tokens.borderStrong,
            width: WorkFollowMetrics.dividerThickness),
        borderRadius: radius,
      ),
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: body,
              ),
            ),
    );
  }
}

/// One hit target inside [_ToolbarPill]; an icon or a word, never both.
class _ToolbarSegment extends StatelessWidget {
  const _ToolbarSegment({
    super.key,
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final icon = this.icon;
    final label = this.label;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.space2),
            child: Center(
              widthFactor: 1,
              child: icon != null
                  ? AppIcon(icon,
                      size: WorkFollowMetrics.metadataIcon,
                      color: tokens.textSecondary)
                  : Text(
                      label!,
                      style: TextStyle(
                        fontSize: WorkFollowMacTypography.control,
                        fontWeight: WorkFollowMacWeight.medium,
                        color: tokens.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Month / week, presented the way the rest of the app presents a choice that
/// has a current value: a labelled control that opens the alternatives. The
/// segmented control it replaces spent two visible slots saying what one word
/// already says.
class _ViewModeControl extends StatelessWidget {
  const _ViewModeControl({required this.mode, required this.onChanged});

  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Builder(
      builder: (anchor) => _ToolbarPill(
        key: const ValueKey('calendar-view-mode'),
        onTap: () => _pick(anchor),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: WorkFollowMacTypography.control,
                  fontWeight: WorkFollowMacWeight.medium,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(width: WorkFollowSpacing.denseGap),
              AppIcon(WorkFollowIcons.expandMore,
                  size: WorkFollowMetrics.metadataIcon,
                  color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// The modes travel through the menu as words rather than as the enum: the
  /// menu keys its rows by value, and `CalendarViewMode.week` reads as a key no
  /// test should have to spell out.
  static const _values = {
    'month': CalendarViewMode.month,
    'week': CalendarViewMode.week,
  };

  Future<void> _pick(BuildContext anchor) async {
    final picked = await showDesktopMenu<String>(
      anchor,
      selected: _values.entries.firstWhere((entry) => entry.value == mode).key,
      width: CalendarMetrics.viewModeMenuWidth,
      placement: PopoverPlacement.bottomEnd,
      entries: const [
        DesktopMenuEntry('month', '月', icon: WorkFollowIcons.calendar),
        DesktopMenuEntry('week', '周', icon: WorkFollowIcons.plan),
      ],
    );
    final resolved = _values[picked];
    if (resolved != null) onChanged(resolved);
  }
}

/// Back, today, forward — one group, because "today" is only meaningful
/// between the two steps that move away from it.
class _RangeControl extends StatelessWidget {
  const _RangeControl({
    required this.mode,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
  });

  final CalendarViewMode mode;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _ToolbarPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarSegment(
            key: const ValueKey('calendar-previous'),
            icon: WorkFollowIcons.chevronPrevious,
            tooltip: mode.previousLabel,
            onTap: onPrevious,
          ),
          _ToolbarSegment(
            key: const ValueKey('calendar-today'),
            label: '今天',
            tooltip: '回到今天',
            onTap: onToday,
          ),
          _ToolbarSegment(
            key: const ValueKey('calendar-next'),
            icon: WorkFollowIcons.chevronNext,
            tooltip: mode.nextLabel,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

/// The page's own settings.
///
/// One entry today — whether completed work shows in the grid — because that is
/// the only month-wide choice the page currently has. A menu that opened onto
/// nothing would be worse than no menu.
class _CalendarMenuButton extends StatelessWidget {
  const _CalendarMenuButton({
    required this.showCompleted,
    required this.onToggleCompleted,
  });

  final bool showCompleted;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => AppIconButton(
        key: const ValueKey('calendar-more-actions'),
        icon: WorkFollowIcons.more,
        tooltip: '日历设置',
        onPressed: () async {
          final picked = await showDesktopMenu<String>(
            anchor,
            selected: showCompleted ? 'completed' : null,
            placement: PopoverPlacement.bottomEnd,
            entries: const [
              DesktopMenuEntry('completed', '显示已完成任务',
                  icon: WorkFollowIcons.completed),
            ],
          );
          if (picked == 'completed') onToggleCompleted();
        },
      ),
    );
  }
}
