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
    expect(CalendarMetrics.dayCellSize, 24);
    expect(BoardMetrics.taskCheckboxSize, 24);
    // The note index is the middle column of the notes workspace; 330 matches
    // the reference proportion next to the 196pt navigation column.
    expect(NotesMetrics.listWidth, 330);
    expect(NotesMetrics.compactListWidth, 300);
    expect(NotesMetrics.editorContentMaxWidth, 820);
    expect(SettingsMetrics.panelWidth, 720);
    expect(CommandPaletteMetrics.maxHeight, 500);
  });

  // The month grid's numbers were read off a reference rather than chosen, and
  // the ones that look "almost round" are the ones a later edit is most likely
  // to tidy up. Pinning them here is what makes that edit fail loudly instead
  // of quietly moving the grid off the reference.
  test('the month grid keeps the measurements it was drawn to', () {
    expect(CalendarMetrics.cellHorizontalPadding, 3);
    expect(CalendarMetrics.cellTopPadding, 3);
    expect(CalendarMetrics.cellBottomPadding, 4);
    expect(CalendarMetrics.dayNumberGap, 2);
    expect(CalendarMetrics.weekHeaderPadding, 8);
    expect(CalendarMetrics.taskBarHeight, 17);
    expect(CalendarMetrics.taskBarGap, 2);
    expect(CalendarMetrics.taskBarRadius, 3);
    // The strip's box, which is the product's box scaled to a strip rather
    // than to a row. Every completion box in the product shrank by a tenth,
    // so this is 90% of the 11 it was drawn at first.
    expect(CalendarMetrics.taskBarCheckboxSize, 9.9);
  });

  test('the grid tints rather than highlights', () {
    // Today is marked by its number; the cell behind it only gets a wash, and
    // a wash heavy enough to read as a fill would compete with the number.
    expect(CalendarMetrics.todayCellAlpha, lessThan(.1));
    // The drop target is a tint over the day's own bars, not a second layer of
    // colour: it has to stay legible after passing through them.
    expect(CalendarMetrics.dropHighlightAlpha, lessThan(.2));
  });
}
