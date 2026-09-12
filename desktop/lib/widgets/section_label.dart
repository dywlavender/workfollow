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
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 7),
      child: Row(
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: color ?? tokens.textTertiary, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3)),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
