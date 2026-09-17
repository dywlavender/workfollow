import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('desktop spacing keeps the shared primitive scale', () {
    expect(
      <double>[
        WorkFollowSpacing.zero,
        WorkFollowSpacing.space1,
        WorkFollowSpacing.space2,
        WorkFollowSpacing.space3,
        WorkFollowSpacing.space4,
        WorkFollowSpacing.space5,
        WorkFollowSpacing.space6,
        WorkFollowSpacing.space7,
        WorkFollowSpacing.space8,
      ],
      <double>[0, 4, 8, 12, 16, 20, 24, 28, 32],
    );
  });

  test('recurring component rhythm delegates to semantic spacing roles', () {
    expect(TaskListMetrics.horizontalPadding, WorkFollowSpacing.space5);
    expect(TaskListMetrics.rowHorizontalPadding,
        WorkFollowSpacing.taskRowHorizontalPadding);
    expect(TaskListMetrics.rowVerticalPadding,
        WorkFollowSpacing.taskRowVerticalPadding);
    expect(TaskListMetrics.checkboxTitleGap, WorkFollowSpacing.space1);
    expect(TaskListMetrics.titlePreviewGap,
        WorkFollowSpacing.taskTitleBodyGap);
    expect(TaskListMetrics.metadataGap, WorkFollowSpacing.taskMetadataGap);

    expect(WorkFollowSpacing.menuItemPadding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 6));
    expect(WorkFollowSpacing.popoverPadding,
        const EdgeInsets.all(WorkFollowSpacing.space4));
    expect(WorkFollowSpacing.toolbarItemGap, WorkFollowSpacing.space2);
    expect(WorkFollowSpacing.editorParagraphGap, 7);
  });
}
