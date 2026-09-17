import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('global controls resolve one geometry contract', () {
    expect(WorkFollowMetrics.inputHeight,
        WorkFollowMetrics.primaryButtonHeight);
    expect(WorkFollowMetrics.compactMenuRowHeight,
        WorkFollowMetrics.compactButtonHeight);
    expect(WorkFollowMetrics.pickerRowHeight, 36);
    expect(WorkFollowMetrics.toolbarControlWidth, 26);
    expect(WorkFollowMetrics.toolbarControlHeight, 28);
    expect(WorkFollowMetrics.iconHitTarget, 32);
    expect(WorkFollowMetrics.menuRowHeight, 40);
    expect(WorkFollowMetrics.dividerThickness, 1);
  });

  test('task list and workspace panes have explicit ownership', () {
    expect(WorkFollowMetrics.taskRowMinHeight,
        TaskListMetrics.rowMinHeight);
    expect(TaskListMetrics.checkboxSize, greaterThan(0));
    expect(TaskListMetrics.rowMinHeight, greaterThan(0));
    expect(WorkFollowLayout.compactTaskListWidth,
        TaskListMetrics.preferredPaneWidth);
    expect(WorkFollowLayout.compactTaskListMinWidth,
        TaskListMetrics.minPaneWidth);
    expect(WorkFollowLayout.taskListDividerWidth, 1);
    expect(WorkFollowLayout.taskDetailMinWidth, greaterThan(0));
  });

  test('editor, picker and menu popovers delegate to named metrics', () {
    expect(TaskEditorMetrics.popoverRowHeight,
        WorkFollowMetrics.compactMenuRowHeight);
    expect(TaskEditorMetrics.pickerRowHeight,
        WorkFollowMetrics.pickerRowHeight);
    expect(TaskEditorMetrics.toolbarButtonWidth, 26);
    expect(TaskEditorMetrics.toolbarButtonHeight, 28);
    expect(TaskPickerMetrics.datePickerWidth, 328);
    expect(TaskPickerMetrics.listPickerMinHeight, 204);
    expect(TaskPickerMetrics.timeFieldWidth, 43);
    expect(TaskMenuMetrics.rowHeight, WorkFollowMetrics.menuRowHeight);
    expect(TaskMenuMetrics.dateGridCellHeight, WorkFollowMetrics.menuRowHeight);
  });

  test('screen-specific geometry remains explicit and stable', () {
    expect(MatrixMetrics.pageHeaderHeight, 56);
    expect(CalendarMetrics.dayCellSize, 23);
    expect(BoardMetrics.taskCheckboxSize, 24);
    expect(NotesMetrics.listWidth, 300);
    expect(SettingsMetrics.panelWidth, 720);
    expect(CommandPaletteMetrics.maxHeight, 500);
  });
}
