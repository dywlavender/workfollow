import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime month;
  DateTime? selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstDay.weekday - 1;
    final cellCount = ((leading + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();
    return Container(
      color: tokens.content,
      padding: const EdgeInsets.fromLTRB(26, 23, 26, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日历', style: TextStyle(color: tokens.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.45)),
                    const SizedBox(height: 5),
                    Text('把任务放回时间里。', style: TextStyle(color: tokens.textTertiary, fontSize: 11.5)),
                  ],
                ),
              ),
              AppIconButton(icon: Icons.chevron_left_rounded, tooltip: '上个月', onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text('${month.year} 年 ${month.month} 月', style: TextStyle(color: tokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))),
              AppIconButton(icon: Icons.chevron_right_rounded, tooltip: '下个月', onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
              const SizedBox(width: 8),
              Material(
                color: tokens.accentFaint,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  onTap: () => setState(() {
                    month = DateTime(today.year, today.month);
                    selectedDay = DateTime(today.year, today.month, today.day);
                  }),
                  borderRadius: BorderRadius.circular(7),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), child: Text('回到今天', style: TextStyle(color: tokens.accent, fontSize: 11, fontWeight: FontWeight.w700))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 27),
          Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 9),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 7, crossAxisSpacing: 7),
              itemCount: cellCount,
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                final inMonth = dayNumber > 0 && dayNumber <= daysInMonth;
                if (!inMonth) return const SizedBox.shrink();
                final date = DateTime(month.year, month.month, dayNumber);
                final isToday = _sameDay(date, today);
                final isSelected = selectedDay != null && _sameDay(date, selectedDay!);
                final count = _taskCountFor(dayNumber);
                return GestureDetector(
                  onTap: () => setState(() => selectedDay = date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.fromLTRB(9, 8, 8, 7),
                    decoration: BoxDecoration(color: isSelected ? tokens.accentSoft : tokens.inspector, borderRadius: BorderRadius.circular(9), border: Border.all(color: isSelected ? tokens.accent.withOpacity(.28) : tokens.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 23, height: 23, alignment: Alignment.center, decoration: BoxDecoration(color: isToday ? tokens.accent : Colors.transparent, shape: BoxShape.circle), child: Text('$dayNumber', style: TextStyle(color: isToday ? Colors.white : (isSelected ? tokens.accent : tokens.textSecondary), fontSize: 12, fontWeight: FontWeight.w700))),
                            const Spacer(),
                            if (count > 0) Container(width: 5, height: 5, decoration: BoxDecoration(color: tokens.accent, shape: BoxShape.circle)),
                          ],
                        ),
                        const Spacer(),
                        if (count > 0) Text('$count 件任务', style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _taskCountFor(int day) {
    final count = widget.controller.visibleTasks.length;
    if (count == 0) return 0;
    if (day == DateTime.now().day) return count.clamp(1, 4).toInt();
    if (day == 3 || day == 12 || day == 18) return 2;
    return 0;
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
