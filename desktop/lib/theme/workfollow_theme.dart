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
  // macOS task navigation uses a denser rhythm than the Web reference while
  // keeping the same icon and text roles. The hit target remains large enough
  // for pointer use, but the surrounding row no longer wastes vertical space.
  static const double compactNavigationRowHeight = 34;
  static const double compactNavigationIconHitTarget = 28;
  static const double compactNavigationSectionTop = 14;
  static const double compactNavigationSectionBottom = 2;
  static const double primaryButtonHeight = 36;
  static const double compactButtonHeight = 34;
  static const double chipHeight = 30;
  // Keep menu rows at the compact macOS rhythm; the larger field icons do not
  // need an oversized menu and this preserves the trigger-to-popover gap.
  static const double menuRowHeight = 40;
  static const double taskRowMinHeight = 44;
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

  /// Pane width. The list opens at [preferredPaneWidth], shrinks toward
  /// [minPaneWidth] only before the inspector would drop below its own
  /// minimum, and stops at [maxPaneWidth] instead of growing without bound the
  /// way a pure ratio would on a wide display.
  static const double minPaneWidth = 380;
  static const double preferredPaneWidth = 440;
  static const double maxPaneWidth = 470;

  /// One gutter for the whole page: header, add bar, group headings and rows
  /// share it, so their text starts on a single vertical.
  static const double horizontalPadding = 20;

  static const double headerHeight = 42;
  static const double headerIconSize = 18;
  static const double headerIconGap = 10;
  static const double headerTopPadding = 18;
  static const double headerBottomGap = 14;

  static const double quickAddHeight = 42;
  static const double quickAddRadius = 10;
  static const double quickAddHorizontalPadding = 14;

  static const double groupTopGap = 18;
  static const double groupHeaderHeight = 30;

  /// Chevron on a group heading. Small on purpose: it marks the group as
  /// foldable without competing with the 13pt label beside it.
  static const double groupChevronIconSize = 11;

  static const double rowHorizontalPadding = 8;
  static const double rowVerticalPadding = 7;
  static const double rowMinHeight = 42;

  /// Drawn size of the completion box, measured off the reference list.
  ///
  /// It is also the pointer target. An earlier version wrapped the 18pt box in
  /// a 24x22 target to make it easier to hit, which pushed the title 7pt right
  /// of where the reference puts it — and the whole row is clickable anyway,
  /// so the box does not have to carry an oversized hit area itself.
  static const double checkboxSize = 18;

  /// Gap between the checkbox column and the title.
  static const double checkboxTitleGap = 4;

  /// Gap between title and description.
  static const double titlePreviewGap = 4;

  /// Gap between two metadata items on the trailing edge.
  static const double metadataGap = 6;

  /// Where the row hairline starts.
  ///
  /// The reference list draws it from the checkbox column — the line runs in
  /// from just left of the box, so the box and the hairlines read as one
  /// column. The first version derived it as `checkboxLeft + box + gap` (42),
  /// which started the line under the title instead and looked nothing like
  /// the reference.
  static const double dividerLeftInset = rowHorizontalPadding - 2;

  /// Pane width for the space a list + detail row can offer.
  static double paneWidth(double available) =>
      available.clamp(minPaneWidth, preferredPaneWidth);
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

  static Color rowFocusRing(WorkFollowTheme tokens) =>
      tokens.focusRing;
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
  static const Duration pending = instant;
  static const Duration loading = fast;
  static const Duration transition = normal;
  static const Curve standard = Cubic(.2, 0, 0, 1);
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

  // Default palette accent and status values from theme.ts.
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
  static const Color danger = Color(0xFFB13F50);
  static const Color dangerHover = Color(0xFF963344);
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
  Color get textDisabled => textTertiary.withValues(alpha: .55);
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
    textTertiary: Color(0xFF94A3A7),
    border: Color(0xFFDCE6E4),
    borderStrong: Color(0xFFC5D6D2),
    accent: Color(0xFF2FAF95),
    accentHover: Color(0xFF238E79),
    accentSoft: Color(0xFFD8F2EB),
    accentFaint: Color(0xFFEFFAF7),
    menuSelected: Color(0xFFF6F6F6),
    menuDivider: Color(0xFFF2F3F3),
    listRowHover: Color(0xFFF5F7F8),
    listRowSelected: Color(0xFFEEF1F3),
    success: Color(0xFF2EAB78),
    warning: Color(0xFFC67912),
    danger: Color(0xFFE45454),
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
    listRowHover: Color(0xFF23262C),
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
      onError: Colors.white,
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
        waitDuration: const Duration(milliseconds: 450),
        textStyle: TextStyle(
            color: brightness == Brightness.dark
                ? tokens.textPrimary
                : Colors.white,
            fontSize: WorkFollowMacTypography.caption,
            fontWeight: WorkFollowMacWeight.medium),
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? tokens.overlay
              : tokens.feedbackSurface,
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
          padding: const EdgeInsets.all(6),
          visualDensity: VisualDensity.compact,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: tokens.borderStrong, width: 1.5),
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
