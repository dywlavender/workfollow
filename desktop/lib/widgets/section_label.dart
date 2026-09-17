import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(
      {super.key, required this.label, required this.count, this.color});

  final String label;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.relaxedGap,
          WorkFollowSpacing.space5, WorkFollowSpacing.relaxedGap,
          WorkFollowSpacing.compactGap),
      child: Row(
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: color ?? tokens.textTertiary, shape: BoxShape.circle)),
          const SizedBox(width: WorkFollowSpacing.xs),
          Text(label,
              style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: WorkFollowMacTypography.sectionTitle,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.semibold,
                  letterSpacing: WorkFollowMacTracking.none)),
          const SizedBox(width: WorkFollowSpacing.inlineGap),
          Text('$count',
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.listMeta,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.medium)),
        ],
      ),
    );
  }
}
