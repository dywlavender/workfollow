import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared geometry for the desktop design system. Components should consume
/// these values instead of inventing a new size for every screen.
class WorkFollowMetrics {
  const WorkFollowMetrics._();

  static const double railIcon = 22;
  static const double navigationIcon = 20;
  static const double headerIcon = 20;
  static const double toolbarIcon = 18;
  // Property controls are deliberately a little larger than metadata. This
  // keeps date/list/tag fields legible at a glance, matching the dedicated
  // field affordances in TickTick's detail pane.
  static const double fieldIcon = 20;
  static const double compactFieldIcon = 17;
  static const double metadataIcon = 15;
  static const double iconHitTarget = 32;

  /// Shared stroke used by compact completion controls and the Material
  /// checkbox theme. Custom painted controls may opt out when their path has
  /// a documented visual reason to use a different stroke.
  static const double checkboxBorderWidth = 1.5;

  /// The side of the box Flutter's own `Checkbox` paints, before the tap
  /// target is grown around it. Anywhere that control is kept for its input
  /// behaviour, its corner is scaled from this, so it stays the same shape as
  /// the boxes drawn elsewhere.
  static const double platformCheckboxSize = 18;

  /// The side the product draws a completion box at.
  ///
  /// One box, one size, wherever a task is marked: the list row, the
  /// editor's header and its child rows, a quadrant row, a note's linked
  /// task, the home card and the date picker's toggle. The calendar strip
  /// and the document editor's checklist marker are the only two that are
  /// their own, because a bar and a line of prose are not a row.
  static const double completionBoxSize = 14.58;

  /// What a control built on Flutter's own `Checkbox` is scaled by to
  /// draw at [completionBoxSize].
  ///
  /// That control paints a box of [platformCheckboxSize] and takes no
  /// size argument, so an enclosing `SizedBox` moves the slot and never
  /// the box; scaling the control is what reaches the drawn side.
  static const double completionBoxScale =
      completionBoxSize / platformCheckboxSize;
  // macOS task navigation uses a denser rhythm than the Web reference while
  // keeping the same icon and text roles. The hit target remains large enough
  // for pointer use, but the surrounding row no longer wastes vertical space.
  static const double compactNavigationRowHeight = 34;
  static const double compactNavigationIconHitTarget = 28;
  static const double compactNavigationSectionTop = 14;
  static const double compactNavigationSectionBottom = 2;
  static const double primaryButtonHeight = 36;
  static const double compactButtonHeight = 34;

  /// The shared height for ordinary text inputs and primary controls. Keeping
  /// this role beside the button roles makes a field and its action row align
  /// without making callers guess between 34, 36 and 38.
  static const double inputHeight = primaryButtonHeight;
  static const double chipHeight = 30;
  // Keep menu rows at the compact macOS rhythm; the larger field icons do not
  // need an oversized menu and this preserves the trigger-to-popover gap.
  static const double menuRowHeight = 40;
  static const double compactMenuRowHeight = compactButtonHeight;
  static const double pickerRowHeight = 36;
  static const double toolbarControlWidth = 26;
  static const double toolbarControlHeight = 28;
  static const double dividerThickness = 1;
  static const double popoverMaxHeight = 560;

  /// Native task rows use the task-list contract below. The alias prevents a
  /// second 44pt row definition from surviving in the global catalog while
  /// [WorkFollowLayout.taskRowComfortableHeight] remains the Web contract.
  static const double taskRowMinHeight = TaskListMetrics.rowMinHeight;
  static const double editorToolbarHeight = 42;
  // List/category rows are intentionally narrower than the full navigation
  // column, leaving the right edge quiet like the TickTick reference.
  static const double listItemMaxWidth = 172;

  // Web layout contract. These values mirror the desktop rules in
  // frontend/src/layout.css; keep them here so Flutter screens can consume
  // the same geometry without repeating literal widths.
  static const double workspaceRailWidth = WorkFollowLayout.workspaceRailWidth;
  static const double taskNavigationWidth =
      WorkFollowLayout.taskNavigationWidth;
  static const double taskListWidth = WorkFollowLayout.taskListWidth;
  static const double taskListMinWidth = WorkFollowLayout.taskListMinWidth;
  static const double taskDetailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double taskListDividerWidth =
      WorkFollowLayout.taskListDividerWidth;
  static const double taskRowComfortableHeight =
      WorkFollowLayout.taskRowComfortableHeight;
}

/// Geometry for the shared task-list surface.
///
/// Every task list — 最近 7 天 / 今天 / 计划 / 过期 / 收集箱 / 全部 / 已完成 /
/// 单个清单 — resolves the same pane width, page gutter, row padding, checkbox
/// size and divider inset from here. A list screen decides *which groups
/// exist*; it never decides how wide the pane is or where the hairline starts.
/// One page inventing its own `8` or `41` is how these views drifted apart.
class TaskListMetrics {
  const TaskListMetrics._();

  /// Tree geometry for the parent/child list (S6). One indentation step for
  /// child rows, and the fixed gutter that keeps checkbox columns aligned
  /// whether or not a row carries a disclosure chevron.
  static const double hierarchyIndent = 24;
  static const double disclosureWidth = 22;
  static const double disclosureTitleGap = 2;

  /// Pane width. The list opens at [preferredPaneWidth], shrinks toward
  /// [minPaneWidth] only before the inspector would drop below its own
  /// minimum, and stops at [maxPaneWidth] instead of growing without bound the
  /// way a pure ratio would on a wide display.
  static const double minPaneWidth = 380;
  static const double preferredPaneWidth = 440;
  static const double maxPaneWidth = 470;

  /// One gutter for the whole page: header, add bar, group headings and rows
  /// share it, so their text starts on a single vertical.
  static const double horizontalPadding = WorkFollowSpacing.space5;

  static const double headerHeight = 42;
  static const double headerIconSize = 18;
  static const double headerIconGap = WorkFollowSpacing.controlGap;
  static const double headerTopPadding = WorkFollowSpacing.sectionGap;
  static const double headerBottomGap = WorkFollowSpacing.relaxedGap;

  static const double quickAddHeight = 42;
  static const double quickAddRadius = 10;
  static const double quickAddHorizontalPadding = WorkFollowSpacing.relaxedGap;

  /// Drag affordances used by every task-list surface.
  static const double dragMarkerHeight = 3;
  static const double dragMarkerRadius = WorkFollowRadii.marker;
  static const double dragPreviewWidth = 360;
  static const double dragPreviewRadius = WorkFollowRadii.surface;

  static const double groupTopGap = WorkFollowSpacing.sectionGap;
  static const double groupHeaderHeight = 30;

  /// Chevron on a group heading. Small on purpose: it marks the group as
  /// foldable without competing with the 13pt label beside it.
  static const double groupChevronIconSize = 11;

  // Row height follows the TickTick reference list: a single-line row reads
  // about 50pt tall with the box at 20pt. Earlier values (7/42/18) made the
  // list read cramped against the same screenshot.
  static const double rowHorizontalPadding =
      WorkFollowSpacing.taskRowHorizontalPadding;
  static const double rowVerticalPadding =
      WorkFollowSpacing.taskRowVerticalPadding;
  static const double rowMinHeight = 50;

  /// The row's box: the slot the control sits in, and the size the corner
  /// fraction is quoted against (`WorkFollowRadii.checkbox` of this).
  ///
  /// It is also the pointer target. An earlier version wrapped the box in
  /// a 24x22 target to make it easier to hit, which pushed the title right
  /// of where the reference puts it — and the whole row is clickable anyway,
  /// so the box does not have to carry an oversized hit area itself.
  static const double checkboxSize = 18;

  /// Gap between the checkbox column and the title.
  static const double checkboxTitleGap = WorkFollowSpacing.space1;

  /// Gap between title and description.
  static const double titlePreviewGap = WorkFollowSpacing.taskTitleBodyGap;

  /// Gap between two metadata items on the trailing edge.
  static const double metadataGap = WorkFollowSpacing.taskMetadataGap;

  /// Keep the trailing column from taking the title down to a few characters
  /// when a task carries several properties. The row still lets the metadata
  /// wrap inside this column; the title owns the rest of the pane.
  static const double metadataMaxWidth = 180;

  /// A collapsed row is allowed to show a few secondary indicators. The
  /// inspector remains the complete property surface, so repeating every
  /// reminder, attachment and content marker in the list only adds noise.
  static const int secondaryMetadataLimit = 3;

  /// Where the row hairline starts.
  ///
  /// The reference list draws it from the checkbox column — the line runs in
  /// from just left of the box, so the box and the hairlines read as one
  /// column. The first version derived it as `checkboxLeft + box + gap` (42),
  /// which started the line under the title instead and looked nothing like
  /// the reference.
  static const double dividerLeftInset =
      rowHorizontalPadding - WorkFollowSpacing.microGap;

  /// Pane width for the space a list + detail row can offer.
  static double paneWidth(double available) =>
      available.clamp(minPaneWidth, preferredPaneWidth);
}

/// Geometry for document formatting controls and their anchored popovers.
/// Values are shared by the task editor, note editor and every entry point
/// that opens the document toolbar.
class TaskEditorMetrics {
  const TaskEditorMetrics._();

  static const double headingPickerWidth = 150;
  static const double timePickerWidth = 222;
  static const double listPopoverWidth = 196;
  static const double datePopoverWidth = 260;
  static const double morePopoverWidth = 164;
  static const double toolbarPopoverWidth = 444;
  static const double toolbarPopoverHeight = 38;
  static const double selectionToolbarWidth = 144;
  static const double selectionToolbarHeight = 40;
  static const double commandMenuWidth = 160;
  static const double commandMenuMaxHeight = 425;
  static const double commandGlyphSlot = 14;
  static const double popoverRowHeight = WorkFollowMetrics.compactMenuRowHeight;
  static const double pickerRowHeight = WorkFollowMetrics.pickerRowHeight;
  static const double toolbarButtonWidth =
      WorkFollowMetrics.toolbarControlWidth;
  static const double toolbarButtonHeight =
      WorkFollowMetrics.toolbarControlHeight;
  static const double toolbarDividerHeight = 17;
  static const double horizontalRuleHeight = 26;
  static const double subtaskProgressHeight = 4;
}

/// Geometry shared by task date, list, tag and repeat pickers.
class TaskPickerMetrics {
  const TaskPickerMetrics._();

  static const double datePickerWidth = 328;
  static const double datePickerMaxHeight = 590;
  static const double listPickerMaxHeight = 440;
  static const double listPickerMinHeight = 204;
  static const double tagPickerWidth = 264;
  static const double tagPickerMaxHeight = 360;
  static const double repeatPickerWidth = 300;
  static const double repeatPickerMaxHeight = 290;
  static const double listPrefixMinWidth = 28;
  static const double fieldPrefixMinWidth = 32;
  static const double dateTimeToggleWidth = 21.06;
  static const double dateTimeToggleHeight = 22.68;
  static const double timeFieldWidth = 43;
}

/// Geometry for the task context menu shared by list, board and inspector.
class TaskMenuMetrics {
  const TaskMenuMetrics._();

  static const double width = 264;
  static const double rowHeight = WorkFollowMetrics.menuRowHeight;

  /// Divider height includes the quiet vertical breathing room around the
  /// one-pixel hairline in the context menu.
  static const double dividerHeight = 13;
  static const double dateGridCellHeight = WorkFollowMetrics.menuRowHeight;
  static const double maxHeight = 660;
}

/// Geometry of the task inspector's overlay and persistent footer/header.
class TaskInspectorMetrics {
  const TaskInspectorMetrics._();

  static const double overlayWidth = 330;
  static const double overlayMaxHeight = 420;
  static const double headerMinHeight = 58;
  static const double footerMinHeight = 52;
  static const double listLabelMaxWidth = 130;
  static const double propertyLabelMaxWidth = 320;
  static const double headerDividerWidth = WorkFollowMetrics.dividerThickness;
  static const double headerDividerHeight = 20;
}

/// Geometry for schedule/date controls embedded in the task editor.
class TaskScheduleMetrics {
  const TaskScheduleMetrics._();

  static const double panelWidth = TaskEditorMetrics.datePopoverWidth;
  static const double panelMaxHeight = 650;
  static const double reminderMaxHeight = 410;
  static const double repeatEndMaxHeight = 470;
  static const double tabHeight = 28;
  static const double propertyRowHeight = WorkFollowMetrics.inputHeight;
  static const double dateShortcutSize = WorkFollowMetrics.iconHitTarget;
  static const double headerControlSize = WorkFollowMetrics.iconHitTarget;
  static const double propertyIndicatorSize = 9;

  /// Shared geometry for the nested date, reminder and repeat option sheets.
  static const double optionRowHeight = 34;
  static const double optionHeaderHeight = 36;
  static const double optionHeaderRadius = 10;
  static const double optionHeaderClearWidth = 26;
  static const double optionHeaderClearHeight = 30;
  static const double optionButtonRadius = WorkFollowRadii.md;
  static const double optionButtonHeight = 28;
  static const double timeOptionsHeight = 280;
  static const double optionDividerHeight = WorkFollowMetrics.dividerThickness;
}

/// Geometry for the command palette and its keyboard shortcut affordance.
class CommandPaletteMetrics {
  const CommandPaletteMetrics._();

  static const double width = 560;
  static const double maxHeight = 500;
  static const double shortcutChipSize = WorkFollowMetrics.chipHeight;
}

/// Geometry for the compact icon rail and navigation-only dialogs.
class SidebarMetrics {
  const SidebarMetrics._();

  static const double footerButtonSize = WorkFollowMetrics.compactButtonHeight;
  static const double railButtonSize = 38;
  static const double folderMoreWidth = 22;
  static const double folderMoreHeight = 20;
  static const double listColorPickerWidth = 270;
  static const double colorSwatchSize = WorkFollowMetrics.chipHeight;
  static const double listColorDotSize = 8;
}

/// Geometry of the month calendar.
///
/// The month is one continuous grid, not a board of cards: every cell is the
/// same size, cells share single hairline edges, and the space a cell leaves
/// over goes to task bars rather than to padding. The numbers here are the
/// cells' own rhythm, so a day can hold as many bars as it has room for.
class CalendarMetrics {
  const CalendarMetrics._();

  /// Top bar: the year and month on the leading edge, the view controls on the
  /// trailing one.
  static const double toolbarHeight = 52;

  /// Weekday header above the grid — 周日 through 周六.
  static const double weekHeaderHeight = 32;

  /// Diameter of the day-number circle. Today is a filled circle behind the
  /// number only; the cell behind it stays nearly white.
  static const double dayCellSize = 24;

  /// Inset from a cell's edge to its day number and its task bars.
  ///
  /// The number and the bars share this one value because they share one
  /// column: a bar starts under the number and runs as wide as the cell
  /// allows, so an inset that moved one of them would step the other.
  static const double cellHorizontalPadding = 3;
  static const double cellTopPadding = 3;
  static const double cellBottomPadding = 4;

  /// Between the day number and the first task bar.
  static const double dayNumberGap = 2;

  /// Inset from a weekday column's edge to its label. The header does not
  /// share [cellHorizontalPadding]: it is a row of words above the grid
  /// rather than the first line of a cell.
  static const double weekHeaderPadding = 8;

  /// One task bar, and the gap that separates it from the next.
  static const double taskBarHeight = 17;
  static const double taskBarGap = 2;

  /// A bar is a rounded box, and a multiple-day task is one box rather than a
  /// row of segments, so the radius is the bar's own corner and not a styling
  /// detail of its ends.
  static const double taskBarRadius = 3;

  /// The completion box on a calendar task — the month grid's bar and the week
  /// column's item both draw one. Sized to the strip it sits in rather than to
  /// the box a full task row gives its own.
  ///
  /// It is the one box that does not follow [WorkFollowMetrics.completionBoxSize]
  /// when the family is resized. A bar is 17pt tall, so a box that tracks a row's
  /// side stops reading as a mark on a strip and starts filling it.
  static const double taskBarCheckboxSize = 9.9;

  /// The tint a month cell takes while a task is dragged over it.
  static const double dropHighlightAlpha = .12;

  /// The wash on today's cell. It is painted over the cell's contents, so a
  /// task bar that crosses today is tinted by it too — that is what makes the
  /// day read as one band rather than as a cell with bars sitting on it.
  static const double todayCellAlpha = .05;

  /// The month/week menu. It holds two words, so it is not the width of the
  /// app's ordinary command menus.
  static const double viewModeMenuWidth = 132;
}

/// Geometry of Board cards and their compact completion controls.
class BoardMetrics {
  const BoardMetrics._();

  static const double compactColumnWidth = 250;
  static const double columnStatusDotSize = 8;
  static const double listMarkerWidth = 3;
  static const double listMarkerHeight = 30;
  static const double taskCheckboxSize = 24;
  static const double relationPreviewWidth = 235;
}

/// Geometry of Matrix headers and draggable rows.
class MatrixMetrics {
  const MatrixMetrics._();

  static const double pageHeaderHeight = 56;

  /// Geometry for the quadrant header and draggable rows.
  static const double quadrantRadius = WorkFollowRadii.card;
  static const double quadrantHeaderMarkerSize = 22;
  static const double groupRowHeight = 34;
  static const double taskRowDividerHeight = WorkFollowMetrics.dividerThickness;
  static const double taskRowDragPreviewWidth = 280;
  static const double taskRowDragPreviewRadius = WorkFollowRadii.md;
  static const double taskRowCheckboxHitTarget = 17.01;
  static const double taskRowCheckboxSize =
      WorkFollowMetrics.completionBoxSize;
}

/// Geometry of the two surfaces a page opens *over* itself: the floating task
/// editor and the compact new-task composer.
///
/// Both are shared — the Matrix and Calendar pages open the same editor on a
/// task and the same composer to create one — so their sizes live beside
/// [WorkFollowMetrics] rather than inside a single page's block. The sizes are
/// the surface's, not the page's: the same 400pt editor has to look the same
/// wherever it is anchored.
class TaskSurfaceMetrics {
  const TaskSurfaceMetrics._();

  /// Measured off the reference popup this surface imitates: 400 × 356, a
  /// card that holds a title and a few lines without reading as a page.
  /// Longer documents scroll inside it rather than growing it.
  static const double editorWidth = 400;
  static const double editorMinHeight = 356;
  static const double editorMaxHeight = 356;
  static const double editorViewportMargin = 48;

  static const double composerWidth = 320;
  static const double composerMaxHeight = 280;
  static const double composerRowHeight = 42;
  static const double composerBodyHeight = 126;
  static const double composerRadius = WorkFollowRadii.md;
}

/// Geometry for document-only controls that do not share the task-list box.
class TaskDocumentMetrics {
  const TaskDocumentMetrics._();

  static const double checklistSize = 12.96;

  /// The checklist marker is the row's box scaled to a line of prose,
  /// not the row's box: its corner is a fraction of *its* side (0.3125),
  /// which is a rounder shape than a task's 0.25 because a marker sitting
  /// beside 12.5pt text reads as a bullet at the task box's corner. The
  /// value used to be read from `WorkFollowRadii.checkbox`, which was the
  /// same number only as long as both shrank together — changing either
  /// alone would have moved the other's shape.
  static const double checklistRadius = 4.05;
  static const double checklistBorderWidth = 1.053;
  static const double checklistTrailingInset = 7;
  static const double checklistCheckStrokeWidth = 1.62;
  static const double quoteBorderWidth = 3;

  /// Height a task document reserves when a legacy panel follows the prose.
  ///
  /// Subtasks, attachments and the source note sit under the document, so the
  /// prose keeps this floor instead of growing to the inspector's viewport —
  /// which would push the panels out of view. Without them the document takes
  /// the full viewport and the surface below it accepts clicks.
  static const double documentMinHeight = 150;
}

/// Geometry of the note index and linked-task controls.
class NotesMetrics {
  const NotesMetrics._();

  /// Note index pane. It is the middle column of a three-column workspace
  /// (navigation 196 + index 330 + the writing page), so it stays near the
  /// reference width instead of stretching with the window.
  static const double listWidth = 330;
  static const double compactListWidth = 300;

  /// Index header. The title and the compose action share one line; the search
  /// field and the sort control share the line below it. The header used to
  /// stack four rows — title, count, search, sort — which cost about 40pt of
  /// list height for no information.
  static const double headerHeight = 44;
  static const double searchHeight = 34;

  /// One note row. Rows are list rows, not cards: a 12pt inset, a 61pt
  /// height, an 8pt selection radius and a hairline between rows.
  static const double rowHorizontalPadding = WorkFollowSpacing.space3;
  static const double rowVerticalPadding = WorkFollowSpacing.cardInset;

  /// The row's height, which is the height of what it holds.
  ///
  /// A row is a title, a 4pt gap and one preview line — 41pt — with the 10pt
  /// inset above and below it. This was 88, read off the reference list
  /// without checking the content: the floor was taller than the row, and
  /// because the row aligns its text to the top the difference did not read
  /// as padding, it read as blank space under every note. A floor above the
  /// content adds a gap, not air.
  ///
  /// The floor stays, because it keeps rows uniform if a style changes under
  /// them; it just has to be what the content measures. Changing what a row
  /// holds means measuring this again rather than assuming it.
  static const double rowMinHeight = 61;
  static const double rowRadius = WorkFollowRadii.md;
  static const double rowDividerInset = rowHorizontalPadding;

  /// The note row's trailing metadata column.
  ///
  /// The task rows already answer "where and when" in one right-aligned
  /// column; the note index repeats that arrangement rather than laying its
  /// date across the full width of the row, so the two lists scan the same way.
  static const double rowMetaGap = WorkFollowSpacing.space3;
  static const double rowMetaMaxWidth = 96;

  /// The note page's own header bar: move-to-folder on the leading edge,
  /// favourite and more on the trailing edge.
  static const double editorHeaderHeight = 44;
  static const double editorHeaderHorizontalPadding = WorkFollowSpacing.space5;

  /// The reading measure of the note page.
  ///
  /// The pane is a canvas: the document column stays centred at 820 and the
  /// slack grows on both sides. At 960 in a 1080pt pane the column was wide
  /// enough to reach the pane edges, so the page read as a form that filled the
  /// window — and got emptier the wider the window grew.
  static const double editorContentMaxWidth = 820;

  static const double sortControlHeight = WorkFollowMetrics.iconHitTarget;
  static const double newNoteButtonSize = WorkFollowMetrics.iconHitTarget;
  static const double emptyStateIconSize = 60;
  static const double linkedTaskCheckboxWidth = 26;
  static const double linkedTaskCheckboxHeight = 30;

  /// Floor for the note's prose, in points — the *document's* floor, not the
  /// writing canvas.
  ///
  /// These are two different heights and must stay separate. The note page is a
  /// scrolling column, so the page owns the blank area under the last line and
  /// routes taps in it back into the editor. Inflating the document so that
  /// area becomes clickable is what pushed the related-task list into the
  /// middle of a one-line note; the previous value here was 330, which reserved
  /// most of the pane for an empty line of text.
  static const double editorContentMinHeight = 80;

  static const double imageMaxHeight = 420;
}

/// Geometry of the settings window and import preview.
class SettingsMetrics {
  const SettingsMetrics._();

  static const double importPreviewWidth = 380;
  static const double panelWidth = 720;
  static const double panelHeight = 520;
  static const double navigationWidth = 165;
}

/// Geometry for the trash empty state.
class TrashMetrics {
  const TrashMetrics._();

  static const double emptyStateIconSize = 52;
}

/// Geometry for the home dashboard's repeated panels and quick add field.
class HomeMetrics {
  const HomeMetrics._();

  static const double quickAddWidth = 300;
  static const double panelHeight = 250;
  static const double reviewIconSize = WorkFollowMetrics.iconHitTarget;
  static const double panelIconSize = WorkFollowMetrics.chipHeight;
  static const double emptyIconSize = 40;
  static const double taskMarkerWidth = 4;
  static const double taskMarkerHeight = 22;
  static const double taskCheckboxHitTarget = 19.44;
  static const double taskCheckboxVisualSize =
      WorkFollowMetrics.completionBoxSize;
  static const double noteDotSize = 7;
  static const double miniCalendarDotSize = 3;
}

/// Geometry for reusable empty-state and statistic surfaces.
class AppSurfaceMetrics {
  const AppSurfaceMetrics._();

  static const double emptyStateIconSize = 56;
  static const double statisticIconSurfaceSize = 34;
}

/// Geometry for the small status marker used by section labels.
class SectionLabelMetrics {
  const SectionLabelMetrics._();

  static const double dotSize = 6;
}

/// Geometry for Quick Add's secondary properties surface.
class QuickAddMetrics {
  const QuickAddMetrics._();

  static const double propertiesPopoverWidth = 245;
  static const double priorityFlagWidth = 44;
  static const double priorityFlagHeight =
      WorkFollowMetrics.compactButtonHeight;
}

/// Row-state fills for the task list.
///
/// Selection is neutral. A task row is not a brand-coloured card, and a hover
/// must not read as a selection — the two used to share one tinted fill, which
/// is exactly why a row the pointer merely crossed looked clicked. Only the
/// keyboard keeps a ring, so a mouse click never leaves an outline behind.
class TaskListColors {
  const TaskListColors._();

  static Color rowFill(WorkFollowTheme tokens,
      {required bool selected, required bool hovering}) {
    if (selected) return tokens.listRowSelected;
    if (hovering) return tokens.listRowHover;
    return Colors.transparent;
  }

  static Color rowFocusRing(WorkFollowTheme tokens) => tokens.focusRing;
}

/// Row-state fills for the note index.
///
/// The note index does not follow the task list here, and the difference is
/// deliberate. A task row's selection is a neutral grey because the checkbox —
/// not the row — is the state the user is tracking. The note index has no
/// checkbox: the row *is* the selection, and the page beside it carries the
/// state. It marks the open note with a soft primary fill, and its hover stays
/// neutral so a pointer crossing the list never looks selected.
class NotesColors {
  const NotesColors._();

  static Color rowFill(WorkFollowTheme tokens,
      {required bool selected, required bool hovering}) {
    if (selected) return tokens.accentSoft;
    if (hovering) return tokens.listRowHover;
    return Colors.transparent;
  }
}

class WorkFollowSpacing {
  const WorkFollowSpacing._();

  // Primitive scale from frontend/src/design-tokens.css.
  static const double zero = 0;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 28;
  static const double space8 = 32;

  // Existing semantic aliases are kept for source compatibility.
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  // Semantic spacing roles. The primitive scale above is the default for new
  // surfaces; these names make recurring component rhythm explicit at call
  // sites. Values outside the primitive scale are named by role and retained
  // only where the existing macOS layout has a measured reason to sit between
  // primitive steps.
  static const double pageHorizontalPadding = 26;
  static const double pageTopPadding = 23;
  static const double pageScreenBottomPadding = 26;
  static const double pageVerticalPadding = 24;
  static const double pageBottomPadding = 24;
  static const double sectionGap = 18;
  static const double contentGap = space3;

  static const double taskRowHorizontalPadding = space2;
  static const double taskRowVerticalPadding = 11;
  static const double taskTitleBodyGap = 6;
  static const double taskMetadataGap = 6;

  static const double menuItemHorizontalPadding = space4;
  static const double menuItemVerticalPadding = 6;
  static const double contextMenuHorizontalPadding = space3;
  static const EdgeInsets menuItemPadding = EdgeInsets.symmetric(
      horizontal: menuItemHorizontalPadding, vertical: menuItemVerticalPadding);
  static const double menuItemIconGap = space2;
  static const double menuSectionGap = space2;

  static const EdgeInsets popoverPadding = EdgeInsets.all(space4);
  static const double popoverSafeArea = space3;
  static const double inspectorContentHorizontalPadding = 40;
  static const double inspectorInlineHorizontalPadding = space5;
  static const double inspectorContentTopPadding = 30;
  static const double inspectorInlineTopPadding = space4;
  static const double inspectorContentBottomPadding = space6;
  static const double editorParagraphGap = 7;
  static const double toolbarItemGap = space2;

  // Small control rhythm used by dense metadata and picker rows.
  static const double hairlineGap = 1;
  static const double microGap = 2;
  static const double tightGap = 3;
  static const double denseGap = 5;
  static const double inlineGap = 6;
  static const double compactGap = 7;
  static const double controlGap = 10;
  static const double compactInset = 9;
  static const double iconLabelGap = 11;
  static const double navigationContentInset = 11;
  static const double compactFieldInset = 11;
  static const double controlInset = 13;
  static const double relaxedGap = 14;
  static const double statusGap = 15;
  static const double fieldGap = 17;
  static const double headingGap = 22;
  static const double nestedContentIndent = 29;
  static const double emptyStateGap = 30;
  static const double pageBottomSpace = 36;
  static const double editorBottomPadding = 44;

  // Calibrated component padding that recurs in a single desktop surface.
  // Keeping the measured value named prevents it from becoming a new inline
  // literal while leaving geometry and control heights to their own round.
  static const double commandPaletteInputLeading = 19;
  static const double commandPaletteRowHorizontalMargin = space2;
  static const double commandPaletteRowVerticalMargin = microGap;
  static const double commandPaletteRowHorizontalPadding = iconLabelGap;
  static const double commandPaletteRowVerticalPadding = controlGap;
  static const double calendarTodayHorizontalPadding = controlGap;
  static const double calendarTodayVerticalPadding = compactGap;
  static const double calendarDragFeedbackHorizontalPadding = controlGap;
  static const double calendarDragFeedbackVerticalPadding = inlineGap;
  static const double noteFolderBadgeHorizontalPadding = denseGap;
  static const double noteFolderBadgeVerticalPadding = hairlineGap;
  static const double quickAddFieldHorizontalPadding = statusGap;
  static const double quickAddFieldVerticalPadding = compactGap;
  static const double navigationScrollHorizontalPadding = compactInset;
  static const double navigationScrollTopPadding = inlineGap;
  static const double railItemHorizontalInset = compactInset;
  static const double railItemTrailingInset = space2;
  static const double settingsShortcutRowVerticalPadding = controlGap;
  static const double compactActionHorizontalPadding = space1;
  static const double compactActionVerticalPadding = inlineGap;
  static const double emptyStateVerticalPadding = 44;

  static const double cardInset = controlGap;
}

/// The macOS text system.
///
/// This is the single type contract for the whole desktop app, not a profile
/// for one screen. [WorkFollowTypography] below stays the contract for the Web
/// client (an `Inter` primary face and a browser-sized ladder), but no macOS
/// widget may borrow it: an `Inter` face plus Web line heights (`1.85` for
/// editor body) reads like a page in a browser.
///
/// What is unified here is the **semantic role**, not the pixel value. Every
/// surface — task list, notes, calendar, board, matrix, habits, stats,
/// settings, search, menus — resolves the same role for the same job, so the
/// app cannot drift into "the task page looks native, the notes page looks
/// like a web page". Several roles deliberately share a value (13 is used by
/// [sectionTitle] and [control]); they are separate names because they are
/// separate jobs, and a change to one must not silently move another.
///
/// Two values are calibrated against the reference screenshots rather than
/// rounded to whole pixels:
///
/// - [pageTitle] is 19, not 20. At 20 with semibold the page heading read
///   heavier than the reference; 18 overshoots the other way.
/// - [listBody] is 12.5, not 13. The task preview sat slightly too prominent
///   next to the task title; 12 would drop it a full step.
///
/// Hierarchy comes from three weights ([WorkFollowMacWeight]) and four line
/// heights, never from a long ladder of one-off sizes. Chinese strings keep
/// [WorkFollowMacTracking.none].
class WorkFollowMacTypography {
  const WorkFollowMacTypography._();

  // App shell / page.
  static const double pageTitle = 19;
  static const double sectionTitle = 13;

  // Navigation.
  static const double navigation = 14;
  static const double navigationMeta = 12;

  // List.
  static const double listTitle = 14;
  static const double listBody = 12.5;
  static const double listMeta = 12;

  // Detail / editor.
  static const double detailTitle = 18;

  /// The note document's own title on the note page.
  ///
  /// Not [detailTitle]: the task inspector's title is a field in a 330pt panel,
  /// while this is the heading of a page whose body column is 760pt wide. At 18
  /// it read as one more field label with a large empty page under it rather
  /// than as the page's centre. Measured off the reference note page.
  static const double noteTitle = 26;

  static const double body = 14;
  static const double supporting = 12;

  // Task document blocks. These are semantic document roles rather than
  // Quill's Material defaults, so changing the editor never changes stored
  // Delta attributes.
  static const double documentH1 = 22;
  static const double documentH2 = 19;
  static const double documentH3 = 16;

  // Controls.
  static const double control = 13;
  static const double menu = 14;
  static const double caption = 11;

  /// Tiny labels within the 30-point calendar cells (holiday name and 班／休).
  static const double calendarAnnotation = 6;

  /// The result HUD's message (see `features/feedback`).
  ///
  /// 15 rather than [body]'s 14 is deliberate, and it is a role rather than a
  /// one-off: the HUD is the only surface in the app that is dark in both
  /// themes, and it is read at a glance while the pointer is elsewhere. 14 read
  /// as a second-tier caption on that field; 16 pushed it into a heading. The
  /// value is calibrated against the reference HUD, so do not round it to 14.
  static const double feedback = 15;

  // Line heights.
  static const double lineNone = 1;
  static const double lineTight = 1.25;
  static const double lineControl = 1.35;
  static const double lineList = 1.40;
  static const double lineBody = 1.50;
  static const double documentHeadingLine = 1.35;
  static const double documentHeading3Line = 1.40;
}

/// The only three weights the macOS app uses. Semibold is the ceiling:
/// Chinese text turns heavy and hard the moment bold becomes a habit.
class WorkFollowMacWeight {
  const WorkFollowMacWeight._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
}

/// Sizes that are not type roles.
///
/// [WorkFollowMacTypography] answers "which text role is this". These two
/// elements have no text role: the toolbar label stands in for an icon, and the
/// focus timer is a display readout. Sizing them from the type scale would
/// either shrink them out of alignment with their siblings or force a fake role
/// name, so they live here and stay out of the hierarchy.
class WorkFollowMacDisplay {
  const WorkFollowMacDisplay._();

  /// Toolbar labels drawn as text because there is no icon for them
  /// (`B` / `I` / `H1` / `1.`). Kept level with the drawn `TaskEditorGlyph`
  /// siblings so a text label and an icon label sit at the same size.
  static const double glyphLabel = 16;

  /// The focus timer countdown.
  static const double timer = 42;

  /// Invisible accessibility target kept in the icon rail for automation and
  /// screen readers. It is intentionally outside the visible type ladder.
  static const double accessibilityHidden = 1;

  /// The `H` of the slash menu's `H₁ / H₂ / H₃` leading glyphs. Drawn as text
  /// because no icon carries the level: Material's `title` / `text_fields` /
  /// `short_text` only read as "some heading". Measured off the reference
  /// menu, where the `H` cap height is 21px at 2x — 15pt in the system face.
  static const double slashHeading = 15;

  /// The subscript level of the same glyphs. Sits on the `H` baseline.
  static const double slashHeadingIndex = 9;

  /// The stacked `1 2 3` inside the ordered-list glyph. Part of the drawn
  /// icon rather than a text role: at this size it is a mark, not a letter.
  static const double slashOrderedNumeral = 4.5;
}

/// Letter spacing for the macOS surface.
class WorkFollowMacTracking {
  const WorkFollowMacTracking._();

  /// Default for every Chinese UI string. Negative tracking belongs to large
  /// Latin display type, which this profile does not use.
  static const double none = 0;

  /// The focus timer uses a small positive tracking value so the fixed-width
  /// digits remain visually separated in its display surface.
  static const double timer = 1.2;
}

/// Font resolution for the macOS surface.
class WorkFollowMacTypeFamily {
  const WorkFollowMacTypeFamily._();

  /// `null` lets Flutter resolve the platform default face, which on macOS is
  /// the system UI font: SF Pro for Latin and digits, PingFang SC for Chinese
  /// through the system cascade. Hard-coding `Inter` here is what made the
  /// shell look like a Web page.
  static const String? ui = null;

  /// Safety net when the platform cascade cannot resolve a glyph.
  static const List<String> fallback = ['PingFang SC', 'Hiragino Sans GB'];

  /// Monospace face for code blocks and inline code. The regular UI face is
  /// deliberately never reused here: code needs stable character widths and
  /// a visibly separate surface in the document.
  static const String code = 'SFMono-Regular';
  static const List<String> codeFallback = ['Menlo', 'monospace'];
}

/// The Web token catalog.
///
/// This mirrors `frontend/src/design-tokens.css` and exists for the browser
/// client. No macOS widget may read it: the desktop app resolves every text
/// role from [WorkFollowMacTypography]. The class is kept, not deleted, so the
/// two clients' tokens can be compared in one place — but it is a catalog, not
/// a second live scale, and it has no role aliases pointing back into the
/// desktop scale.
class WorkFollowTypography {
  const WorkFollowTypography._();

  // Primitive type scale from frontend/src/design-tokens.css.
  static const String webUiFontFamily = 'Inter';
  static const String webMonoFontFamily = 'JetBrains Mono';
  static const List<String> webFontFallback = [
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Arial Unicode MS',
  ];
  static const double webMicro = 10;
  static const double webCaption = 11;
  static const double webLabel = 12;
  static const double webBodySmall = 13;
  static const double webBody = 14;
  static const double webTitleSmall = 16;
  static const double webTitle = 18;
  static const double webHeadingSmall = 20;
  static const double webHeading = 22;
  static const double webHeadingLarge = 24;
  static const double webDisplaySmall = 28;
  static const double webDisplay = 32;

  static const double webWeightRegular = 400;
  static const double webWeightMedium = 500;
  static const double webWeightSemibold = 600;
  static const double webWeightBold = 700;

  static const double webLineHeightNone = 1;
  static const double webLineHeightCompact = 1.2;
  static const double webLineHeightTight = 1.25;
  static const double webLineHeightSnug = 1.35;
  static const double webLineHeightNormal = 1.5;
  static const double webLineHeightBody = 1.6;
  static const double webLineHeightRelaxed = 1.7;
  static const double webLineHeightDocument = 1.8;
  static const double webLineHeightEditor = 1.85;

  static const double webTrackingNormal = 0;
  static const double webTrackingSection = -.015;
  static const double webTrackingHeading = -.02;
  static const double webTrackingTight = -.025;
  static const double webTrackingDisplay = -.035;
  static const double webTrackingLabel = .04;
  static const double webTrackingWide = .05;
  static const double webTrackingCaps = .08;

  // Semantic role mappings from the Web token layer.
  static const double webBodySize = webBody;
  static const double webPageTitleSize = webHeading;
  static const double webSectionTitleSize = webTitleSmall;
  static const double webPanelTitleSize = webBody;
  static const double webNavigationSize = webBodySmall;
  static const double webListTitleSize = webBodySmall;
  static const double webSupportingSize = webLabel;
  static const double webSupportingCompactSize = webCaption;
  static const double webMetaSize = webMicro;
  static const double webControlSize = webLabel;
  static const double webEditorTitleSize = webHeadingSmall;
  static const double webEditorBodySize = webBody;

  // The legacy role aliases (pageTitle / taskTitle / field / metadata / …) that
  // used to live here are gone. They were a second set of names for the same
  // sizes, so a reader could not tell which one was authoritative, and after the
  // macOS migration they were both unused and resolving to the desktop scale.
  // Desktop code names WorkFollowMacTypography directly; the Web* primitives
  // above remain the browser contract.
}

class WorkFollowRadii {
  const WorkFollowRadii._();

  // Primitive radius scale from frontend/src/design-tokens.css.
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double full = 999;
  static const double circle = .5;

  // Existing semantic aliases are kept for source compatibility.
  static const double control = 7;
  static const double surface = 10;
  static const double card = 12;
  static const double popover = 12;
  static const double pill = 999;

  // Component exceptions are still named roles, so feature widgets do not
  // carry their own numeric corner values for custom checkboxes or markers.
  static const double checkbox = 4.5;
  static const double marker = 2;
}

/// Desktop geometry copied from the Web layout contract.
///
/// Flutter does not have CSS's `clamp()` or viewport units, so the values are
/// exposed as stable bounds and proportions. A screen can combine them with
/// `LayoutBuilder` while retaining the same breakpoints as the Web client.
class WorkFollowLayout {
  const WorkFollowLayout._();

  static const double appHeaderHeight = 76;
  static const double pageGutterMin = 16;
  static const double pageGutterMax = 24;
  static const double pageBottomSpace = 48;
  static const double contentMaxWidth = 1280;
  static const double readingMaxWidth = 1040;
  static const double settingsMaxWidth = 1440;
  static const double taskViewWidth = 260;
  static const double detailWidthMin = 390;
  static const double detailWidthViewportFraction = .30;
  static const double detailWidthMax = 560;

  static const double workspaceRailWidth = 152;
  static const double taskNavigationWidth = 218;
  static const double taskListWidth = 430;
  static const double taskListMinWidth = 360;
  // Native macOS compact profile. The Web values above remain the migration
  // contract; these values are the deliberate local-shell density choice.
  static const double compactTaskNavigationWidth = 196;
  // The native list pane resolves its width from [TaskListMetrics], so every
  // task list shares one pane. The old 380 was wide enough for a navigation
  // column and not for a task row: titles ellipsised early, the trailing
  // metadata crowded the title, and the whole list read as a narrow sidebar.
  static const double compactTaskListWidth = TaskListMetrics.preferredPaneWidth;
  static const double compactTaskListMinWidth = TaskListMetrics.minPaneWidth;
  static const double taskListDividerWidth = 1;
  static const double taskDetailMinWidth = 320;
  static const double narrowTaskListMinWidth = 300;
  static const double narrowTaskDetailMinWidth = 280;
  static const double taskDetailEmptyPadding = 32;
  static const double taskDetailEmptyContentMaxWidth = 240;
  // `.tasks-page .todo-row { min-height: 48px; }` in redesign.css.
  static const double taskRowComfortableHeight = 48;
}

/// Motion values from the Web token layer. `Duration` constants make the
/// timing contract usable by Flutter animations without local conversions.
class WorkFollowMotion {
  const WorkFollowMotion._();

  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration tooltipWait = Duration(milliseconds: 450);
  static const Duration submenuIntent = Duration(milliseconds: 220);
  static const Duration dragStartDelay = Duration(milliseconds: 300);

  /// Task rows use a shorter state transition than panels. It is long enough
  /// to make completion/restoration legible, while keeping a rapid checkbox
  /// pass from making the list feel behind the pointer.
  static const Duration taskRow = Duration(milliseconds: 220);
  static const Duration pending = instant;
  static const Duration loading = fast;
  static const Duration transition = normal;
  static const Curve standard = Cubic(.2, 0, 0, 1);
  static const Curve taskRowExit = Curves.easeInCubic;
  static const double taskRowSlide = .04;
}

/// Material and stacking values shared by atmosphere-enabled surfaces.
class WorkFollowGlass {
  const WorkFollowGlass._();

  static const double railBlur = 4;
  static const double navigationBlur = 4;
  static const double panelBlur = 5;
  static const double detailBlur = 5;
  static const double editorBlur = 5;
  static const double controlBlur = 4;
  static const double dialogBlur = 8;
  static const double menuBlur = 7;
  static const double atmosphereAuroraBlur = 40;
  static const double atmosphereWispBlur = 5;

  static const double railSaturation = 1.08;
  static const double navigationSaturation = 1.06;
  static const double panelSaturation = 1.04;
  static const double detailSaturation = 1.06;
  static const double editorSaturation = 1.05;
  static const double controlSaturation = 1.03;
  static const double dialogSaturation = 1.08;
  static const double menuSaturation = 1.08;
}

class WorkFollowLayers {
  const WorkFollowLayers._();

  static const int atmosphere = 0;
  static const int shell = 10;
  static const int rail = 20;
  static const int seasonFall = 30;
  static const int localOverlay = 60;
  static const int popover = 90;
  static const int dialog = 100;
  static const int search = 110;
  static const int toast = 220;
}

/// A complete set of Web surface roles. Keeping the roles together prevents a
/// caller from accidentally pairing a page surface from one appearance with
/// a list surface from another one.
@immutable
class WorkFollowSurfaceSet {
  const WorkFollowSurfaceSet({
    required this.page,
    required this.rail,
    required this.navigation,
    required this.list,
    required this.detail,
    required this.input,
    required this.hover,
    required this.muted,
    required this.borderLight,
    required this.borderNormal,
  });

  final Color page;
  final Color rail;
  final Color navigation;
  final Color list;
  final Color detail;
  final Color input;
  final Color hover;
  final Color muted;
  final Color borderLight;
  final Color borderNormal;

  /// CSS `neutral` background preset (the default no-atmosphere baseline).
  static const neutralLight = WorkFollowSurfaceSet(
    page: WorkFollowColors.neutral50,
    rail: WorkFollowColors.neutral100,
    navigation: WorkFollowColors.neutral100,
    list: WorkFollowColors.neutral0,
    detail: WorkFollowColors.neutral0,
    input: Color(0xFFFAFBFC),
    hover: WorkFollowColors.neutral100,
    muted: Color(0xFFFAFBFC),
    borderLight: Color(0xFFEAECF0),
    borderNormal: WorkFollowColors.neutral200,
  );

  static const neutralDark = WorkFollowSurfaceSet(
    page: Color(0xFF111318),
    rail: Color(0xFF16191F),
    navigation: Color(0xFF181B22),
    list: Color(0xFF191C23),
    detail: Color(0xFF1C2027),
    input: Color(0xFF20232B),
    hover: Color(0xFF222630),
    muted: Color(0xFF1D2028),
    borderLight: Color(0xFF272C35),
    borderNormal: Color(0xFF343A46),
  );

  /// `default` palette surfaces from `frontend/src/modules/theme.ts` when
  /// the appearance background is set to `theme`.
  static const defaultLight = WorkFollowSurfaceSet(
    page: Color(0xFFF7F8FC),
    rail: Color(0xFFEEF0FB),
    navigation: Color(0xFFF2F4FC),
    list: Color(0xFFFFFFFF),
    detail: Color(0xFFFEFEFF),
    input: Color(0xFFF8F9FE),
    hover: Color(0xFFEEF1FA),
    muted: Color(0xFFF9FAFD),
    borderLight: Color(0xFFE4E7F0),
    borderNormal: Color(0xFFD8DDE8),
  );

  static const defaultDark = WorkFollowSurfaceSet(
    page: Color(0xFF111318),
    rail: Color(0xFF151725),
    navigation: Color(0xFF181B29),
    list: Color(0xFF191C23),
    detail: Color(0xFF1C2029),
    input: Color(0xFF202430),
    hover: Color(0xFF252A38),
    muted: Color(0xFF1E222C),
    borderLight: Color(0xFF292F3D),
    borderNormal: Color(0xFF384153),
  );
}

/// Component-role aliases from the Web token layer. These are deliberately
/// semantic names: individual widgets should not need to know whether a
/// button is currently backed by the default or a seasonal palette.
class WorkFollowComponentTokens {
  const WorkFollowComponentTokens._();

  static const double buttonRadius = WorkFollowRadii.md;
  static const double inputRadius = WorkFollowRadii.md;
  static const double cardRadius = WorkFollowRadii.lg;
  static const double dialogRadius = WorkFollowRadii.lg;
  static const double popoverRadius = WorkFollowRadii.lg;
  // The duplicated font-size aliases (buttonFontSize / inputFontSize /
  // listTitleFontSize / taskNavigationFontSize / taskMetaFontSize /
  // editorTitleFontSize / editorBodyFontSize) were removed for the same reason
  // as the Typography aliases: they were a second naming of the same steps and
  // had no call sites left. Sizes live in WorkFollowMacTypography only.
  static const double editorContentPaddingTop = WorkFollowSpacing.space2;
  static const double detailShadowOffset = -16;
  static const double detailShadowBlur = 44;
}

/// Primitive and semantic colors exported by the Web token layer.
///
/// `WorkFollowTheme` remains the runtime ThemeExtension used by the current
/// app. This catalog keeps the Web source values available to Flutter
/// components and makes palette migration explicit instead of hiding values
/// in individual widgets.
class WorkFollowColors {
  const WorkFollowColors._();

  // Neutral primitives.
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF7F8FA);
  static const Color neutral100 = Color(0xFFF1F3F6);
  static const Color neutral200 = Color(0xFFDDE1E7);
  static const Color neutral500 = Color(0xFF6B7280);
  static const Color neutral700 = Color(0xFF5F6672);
  static const Color neutral900 = Color(0xFF171A21);
  static const Color neutralCompleted = Color(0xFFAEB5BF);
  static const Color neutralAbandoned = Color(0xFF817A76);
  static const Color neutralAbandonedBorder = Color(0xFFA99C94);

  // Neutral background preset from theme.ts / design-tokens.css.
  static const Color lightPage = neutral50;
  static const Color lightRail = neutral100;
  static const Color lightNavigation = neutral100;
  static const Color lightList = neutral0;
  static const Color lightDetail = neutral0;
  static const Color lightInput = Color(0xFFFAFBFC);
  static const Color lightHover = neutral100;
  static const Color lightMuted = Color(0xFFFAFBFC);
  static const Color lightSelected = Color(0xFFEEF2FF);
  static const Color lightBorderSubtle = Color(0xFFEAECF0);
  static const Color lightBorder = neutral200;

  static const Color darkPage = Color(0xFF111318);
  static const Color darkRail = Color(0xFF16191F);
  static const Color darkNavigation = Color(0xFF181B22);
  static const Color darkList = Color(0xFF191C23);
  static const Color darkDetail = Color(0xFF1C2027);
  static const Color darkInput = Color(0xFF20232B);
  static const Color darkHover = Color(0xFF222630);
  static const Color darkMuted = Color(0xFF1D2028);
  static const Color darkBorderSubtle = Color(0xFF272C35);
  static const Color darkBorder = Color(0xFF343A46);

  // Default palette accent and status values from theme.ts. Danger
  // intentionally diverges from the Web token: desktop light uses a brighter
  // status red so overdue/destructive states read as true red on white.
  static const Color accent = Color(0xFF4F46E5);
  static const Color accentHover = Color(0xFF4338CA);
  static const Color accentActive = Color(0xFF3730A3);
  static const Color accentSoft = Color(0xFFEEF2FF);
  static const Color accentSoftHover = Color(0xFFE0E7FF);
  static const Color focus = Color(0x334F46E5);
  static const Color success = Color(0xFF237A57);
  static const Color successSoft = Color(0xFFE8F5EE);
  static const Color warning = Color(0xFFA15C08);
  static const Color warningSoft = Color(0xFFFFF5DF);
  static const Color danger = Color(0xFFFF4D4F);
  static const Color dangerHover = Color(0xFFD94143);
  static const Color dangerSoft = Color(0xFFFFF0F2);
  static const Color overlay = Color(0x47111827);
}

@immutable
class WorkFollowTheme extends ThemeExtension<WorkFollowTheme> {
  const WorkFollowTheme({
    required this.canvas,
    required this.sidebar,
    required this.sidebarGradient,
    required this.rail,
    required this.railActive,
    required this.railForeground,
    required this.railForegroundMuted,
    required this.railSurface,
    required this.railBorder,
    required this.content,
    required this.inspector,
    required this.overlay,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentFaint,
    required this.menuSelected,
    required this.menuDivider,
    required this.listRowHover,
    required this.listRowSelected,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.seasonalSky,
    required this.feedbackSurface,
    required this.feedbackText,
    required this.feedbackAction,
  });

  final Color canvas;
  final Color sidebar;

  /// Gradient used by the readable second navigation column.
  final LinearGradient sidebarGradient;

  /// Solid first-level rail color. TickTick treats this as a separate visual
  /// plane rather than another gray sidebar.
  final Color rail;
  final Color railActive;
  final Color railForeground;
  final Color railForegroundMuted;
  final Color railSurface;
  final Color railBorder;
  final Color content;
  final Color inspector;
  final Color overlay;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Derived roles keep disabled and focus treatments semantic without
  /// adding another near-duplicate palette entry to every light/dark theme.
  // Disabled text remains visibly related to tertiary text in both themes;
  // the stronger semantic alpha avoids disappearing on light surfaces.
  Color get textDisabled => textTertiary.withValues(alpha: .72);
  Color get focusRing => accent.withValues(alpha: .35);
  Color get documentHighlight => accentSoft;
  Color get documentHighlightText => textPrimary;

  final Color border;
  final Color borderStrong;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color accentFaint;

  /// Neutral hover/selected fills for command surfaces — the slash menu, the
  /// more menu, the command palette.
  ///
  /// Menus used to reuse `accentFaint`, which tinted every hover with brand
  /// teal and made a command list read as an actionable card. A menu is a
  /// neutral surface: selection is a quiet grey, and the icon and label keep
  /// their colour and weight so the row does not "jump" as the pointer moves.
  final Color menuSelected;

  /// Hairline between menu sections. Weaker than [border] on purpose: a menu
  /// divider separates, it does not frame.
  final Color menuDivider;

  /// Row-state fills for the task list: a quiet grey hover and a slightly
  /// deeper, still neutral selection. Kept as (0) state tokens rather than
  /// tints of [accent] so a row never wears the brand colour.
  final Color listRowHover;
  final Color listRowSelected;

  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final LinearGradient seasonalSky;

  /// The result HUD — the one surface that is dark in *both* themes.
  ///
  /// A transient system message deliberately does not participate in the
  /// light/dark adaptation the rest of the app does: it is a HUD, it reads the
  /// same over either background, and keeping it one colour is what makes
  /// [feedbackAction] legible against it. [overlay] is the wrong token here —
  /// it inverts between themes and carries a border.
  final Color feedbackSurface;
  final Color feedbackText;

  /// Warm, unlike [accent]: the HUD already owns a cool neutral field, and the
  /// undo affordance has to separate from the message at 15pt.
  final Color feedbackAction;

  static const light = WorkFollowTheme(
    canvas: Color(0xFFF2F4F8),
    sidebar: Color(0xFFEAF7F3),
    sidebarGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDDF5EE), Color(0xFFF2FAF8)],
    ),
    rail: Color(0xFF42C8A8),
    railActive: Color(0xFFFFFFFF),
    railForeground: Color(0xFFFFFFFF),
    railForegroundMuted: Color(0xC8FFFFFF),
    railSurface: Color(0x24FFFFFF),
    railBorder: Color(0x35FFFFFF),
    content: Color(0xFFFFFFFF),
    inspector: Color(0xFFFFFFFF),
    overlay: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF20272C),
    textSecondary: Color(0xFF5D6B75),
    textTertiary: Color(0xFF7F8D92),
    // Hairlines are neutral. The teal-tinted greys belonged to the old accent
    // and read as a second colour in every divider once the primary moved.
    border: Color(0xFFE6E7EB),
    borderStrong: Color(0xFFD3D5DC),
    // One primary for the product, matching the navigation column's indigo.
    // The previous light accent was a teal-green, which put the compose button,
    // the sort control and every folder chip in one colour family and the
    // navigation selection beside them in another. Green is now reserved for
    // completion and saved state ([success], and the check marks that read it).
    accent: Color(0xFF5B5CEB),
    accentHover: Color(0xFF4B4CD9),
    accentSoft: Color(0xFFEEF0FF),
    accentFaint: Color(0xFFF6F7FF),
    menuSelected: Color(0xFFF6F6F6),
    menuDivider: Color(0xFFF2F3F3),
    listRowHover: Color(0xFFF5F7F8),
    listRowSelected: Color(0xFFEEF1F3),
    success: Color(0xFF237A57),
    warning: Color(0xFFA15C08),
    danger: Color(0xFFFF4D4F),
    shadow: Color(0x14161B2B),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF2F4FF), Color(0xFFF7F8FA)],
    ),
    feedbackSurface: Color(0xFF2C2C2E),
    feedbackText: Color(0xF5FFFFFF),
    feedbackAction: Color(0xFFF0B37E),
  );

  static const dark = WorkFollowTheme(
    canvas: Color(0xFF1B1D22),
    sidebar: Color(0xFF191B20),
    sidebarGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF202925), Color(0xFF191B20)],
    ),
    rail: Color(0xFF24433D),
    railActive: Color(0xFFE8FFF8),
    railForeground: Color(0xFFE8FFF8),
    railForegroundMuted: Color(0xB8E8FFF8),
    railSurface: Color(0x1FE8FFF8),
    railBorder: Color(0x32E8FFF8),
    content: Color(0xFF202329),
    inspector: Color(0xFF202329),
    overlay: Color(0xFF2A2D34),
    textPrimary: Color(0xFFF4F5F7),
    textSecondary: Color(0xFFB8BEC9),
    textTertiary: Color(0xFF858D9A),
    border: Color(0xFF30343D),
    borderStrong: Color(0xFF4A505B),
    accent: Color(0xFF7E88FF),
    accentHover: Color(0xFF98A1FF),
    accentSoft: Color(0xFF2D355C),
    accentFaint: Color(0xFF252B4A),
    menuSelected: Color(0xFF363A42),
    menuDivider: Color(0xFF3A3E47),
    listRowHover: Color(0xFF272B32),
    listRowSelected: Color(0xFF2A2E35),
    success: Color(0xFF5BCE91),
    warning: Color(0xFFF2B84B),
    danger: Color(0xFFFF6868),
    shadow: Color(0x88000000),
    seasonalSky: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF202124), Color(0xFF1B1C1E)],
    ),
    // Same HUD in both themes; see the field docs.
    feedbackSurface: Color(0xFF2C2C2E),
    feedbackText: Color(0xF5FFFFFF),
    feedbackAction: Color(0xFFF0B37E),
  );

  static WorkFollowTheme of(BuildContext context) {
    return Theme.of(context).extension<WorkFollowTheme>() ??
        WorkFollowTheme.light;
  }

  @override
  WorkFollowTheme copyWith({
    Color? canvas,
    Color? sidebar,
    LinearGradient? sidebarGradient,
    Color? rail,
    Color? railActive,
    Color? railForeground,
    Color? railForegroundMuted,
    Color? railSurface,
    Color? railBorder,
    Color? content,
    Color? inspector,
    Color? overlay,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? accentFaint,
    Color? menuSelected,
    Color? menuDivider,
    Color? listRowHover,
    Color? listRowSelected,
    Color? success,
    Color? warning,
    Color? danger,
    Color? shadow,
    LinearGradient? seasonalSky,
    Color? feedbackSurface,
    Color? feedbackText,
    Color? feedbackAction,
  }) {
    return WorkFollowTheme(
      canvas: canvas ?? this.canvas,
      sidebar: sidebar ?? this.sidebar,
      sidebarGradient: sidebarGradient ?? this.sidebarGradient,
      rail: rail ?? this.rail,
      railActive: railActive ?? this.railActive,
      railForeground: railForeground ?? this.railForeground,
      railForegroundMuted: railForegroundMuted ?? this.railForegroundMuted,
      railSurface: railSurface ?? this.railSurface,
      railBorder: railBorder ?? this.railBorder,
      content: content ?? this.content,
      inspector: inspector ?? this.inspector,
      overlay: overlay ?? this.overlay,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      accentFaint: accentFaint ?? this.accentFaint,
      menuSelected: menuSelected ?? this.menuSelected,
      menuDivider: menuDivider ?? this.menuDivider,
      listRowHover: listRowHover ?? this.listRowHover,
      listRowSelected: listRowSelected ?? this.listRowSelected,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      shadow: shadow ?? this.shadow,
      seasonalSky: seasonalSky ?? this.seasonalSky,
      feedbackSurface: feedbackSurface ?? this.feedbackSurface,
      feedbackText: feedbackText ?? this.feedbackText,
      feedbackAction: feedbackAction ?? this.feedbackAction,
    );
  }

  @override
  WorkFollowTheme lerp(covariant WorkFollowTheme? other, double t) {
    if (other == null) return this;
    return WorkFollowTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarGradient: t < .5 ? sidebarGradient : other.sidebarGradient,
      rail: Color.lerp(rail, other.rail, t)!,
      railActive: Color.lerp(railActive, other.railActive, t)!,
      railForeground: Color.lerp(railForeground, other.railForeground, t)!,
      railForegroundMuted:
          Color.lerp(railForegroundMuted, other.railForegroundMuted, t)!,
      railSurface: Color.lerp(railSurface, other.railSurface, t)!,
      railBorder: Color.lerp(railBorder, other.railBorder, t)!,
      content: Color.lerp(content, other.content, t)!,
      inspector: Color.lerp(inspector, other.inspector, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentFaint: Color.lerp(accentFaint, other.accentFaint, t)!,
      menuSelected: Color.lerp(menuSelected, other.menuSelected, t)!,
      menuDivider: Color.lerp(menuDivider, other.menuDivider, t)!,
      listRowHover: Color.lerp(listRowHover, other.listRowHover, t)!,
      listRowSelected: Color.lerp(listRowSelected, other.listRowSelected, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      seasonalSky: t < .5 ? seasonalSky : other.seasonalSky,
      feedbackSurface: Color.lerp(feedbackSurface, other.feedbackSurface, t)!,
      feedbackText: Color.lerp(feedbackText, other.feedbackText, t)!,
      feedbackAction: Color.lerp(feedbackAction, other.feedbackAction, t)!,
    );
  }
}

class WorkFollowThemeData {
  const WorkFollowThemeData._();

  static ThemeData light() => _build(WorkFollowTheme.light, Brightness.light);

  static ThemeData dark() => _build(WorkFollowTheme.dark, Brightness.dark);

  static ThemeData _build(WorkFollowTheme tokens, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF111216),
      secondary: tokens.accent,
      onSecondary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF111216),
      error: tokens.danger,
      onError: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF111216),
      surface: tokens.content,
      onSurface: tokens.textPrimary,
    );

    // The desktop shell resolves to the macOS system face; only the Web build
    // keeps the Inter + Noto Sans SC stack.
    final macOS = defaultTargetPlatform == TargetPlatform.macOS;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: macOS
          ? WorkFollowMacTypeFamily.ui
          : WorkFollowTypography.webUiFontFamily,
      fontFamilyFallback: macOS
          ? WorkFollowMacTypeFamily.fallback
          : WorkFollowTypography.webFontFallback,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: NoSplash.splashFactory,
      // Hover is a neutral interaction state. Accent is reserved for active
      // controls, links and focus, so a pointer crossing a menu or row never
      // paints a brand-coloured surface.
      hoverColor: tokens.listRowHover,
      focusColor: tokens.accent.withValues(alpha: .22),
      dividerColor: tokens.border,
      // macOS profile: one page-title step, three weights, no tracking. Sizes
      // come from WorkFollowMacTypography so a widget never invents its own
      // step.
      textTheme: TextTheme(
        displaySmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.pageTitle,
            height: WorkFollowMacTypography.lineTight,
            fontWeight: WorkFollowMacWeight.semibold,
            letterSpacing: WorkFollowMacTracking.none),
        headlineSmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.detailTitle,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.semibold,
            letterSpacing: WorkFollowMacTracking.none),
        titleLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.listTitle,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.semibold,
            letterSpacing: WorkFollowMacTracking.none),
        titleMedium: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.sectionTitle,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.semibold,
            letterSpacing: WorkFollowMacTracking.none),
        titleSmall: TextStyle(
            color: tokens.textSecondary,
            fontSize: WorkFollowMacTypography.sectionTitle,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.medium,
            letterSpacing: WorkFollowMacTracking.none),
        bodyLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.body,
            height: WorkFollowMacTypography.lineBody,
            fontWeight: WorkFollowMacWeight.regular,
            letterSpacing: WorkFollowMacTracking.none),
        bodyMedium: TextStyle(
            color: tokens.textSecondary,
            fontSize: WorkFollowMacTypography.control,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.regular,
            letterSpacing: WorkFollowMacTracking.none),
        bodySmall: TextStyle(
            color: tokens.textTertiary,
            fontSize: WorkFollowMacTypography.supporting,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.regular,
            letterSpacing: WorkFollowMacTracking.none),
        labelLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.control,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.medium,
            letterSpacing: WorkFollowMacTracking.none),
        labelMedium: TextStyle(
            color: tokens.textSecondary,
            fontSize: WorkFollowMacTypography.listMeta,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.medium,
            letterSpacing: WorkFollowMacTracking.none),
        labelSmall: TextStyle(
            color: tokens.textTertiary,
            fontSize: WorkFollowMacTypography.caption,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.regular,
            letterSpacing: WorkFollowMacTracking.none),
      ),
      iconTheme: IconThemeData(
          color: tokens.textSecondary, size: WorkFollowMetrics.navigationIcon),
      tooltipTheme: TooltipThemeData(
        waitDuration: WorkFollowMotion.tooltipWait,
        textStyle: TextStyle(
            color: tokens.feedbackText,
            fontSize: WorkFollowMacTypography.caption,
            fontWeight: WorkFollowMacWeight.medium),
        decoration: BoxDecoration(
          color: tokens.feedbackSurface,
          borderRadius: BorderRadius.circular(WorkFollowRadii.sm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          textStyle: const TextStyle(
              fontSize: WorkFollowMacTypography.control,
              fontWeight: WorkFollowMacWeight.medium),
          minimumSize: const Size(0, WorkFollowMetrics.compactButtonHeight),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, WorkFollowMetrics.primaryButtonHeight),
          textStyle: const TextStyle(
              fontSize: WorkFollowMacTypography.control,
              fontWeight: WorkFollowMacWeight.medium),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, WorkFollowMetrics.compactButtonHeight),
          textStyle: const TextStyle(
              fontSize: WorkFollowMacTypography.control,
              fontWeight: WorkFollowMacWeight.medium),
          side: BorderSide(color: tokens.borderStrong),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          hoverColor: tokens.menuSelected,
          highlightColor: Colors.transparent,
          minimumSize: const Size(
              WorkFollowMetrics.iconHitTarget, WorkFollowMetrics.iconHitTarget),
          padding: const EdgeInsets.all(WorkFollowSpacing.inlineGap),
          visualDensity: VisualDensity.compact,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.checkbox)),
        side: BorderSide(
            color: tokens.borderStrong,
            width: WorkFollowMetrics.checkboxBorderWidth),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.popover)),
        titleTextStyle: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.detailTitle,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.semibold,
            letterSpacing: WorkFollowMacTracking.none),
        contentTextStyle: TextStyle(
            color: tokens.textSecondary,
            fontSize: WorkFollowMacTypography.control,
            height: WorkFollowMacTypography.lineList),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.menu,
            height: WorkFollowMacTypography.lineControl,
            fontWeight: WorkFollowMacWeight.regular),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkFollowRadii.popover)),
      ),
      dividerTheme:
          DividerThemeData(color: tokens.border, thickness: 1, space: 1),
    );
  }
}
