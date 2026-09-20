import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../theme/workfollow_color_tokens.dart';
import '../../theme/workfollow_theme.dart';

/// The visual interpretation of the semantic blocks stored in an editable
/// document Delta.
///
/// Quill stores a heading, list, or quote as an attribute on a line. It also
/// ships with a Material-oriented default for each of those attributes. An
/// editable document must not change type scale just because that fallback was
/// selected, so every block used by the document editor is defined here and
/// inherits the WorkFollow body face and primary text colour.
class DocumentStyles {
  const DocumentStyles._();

  /// The checklist marker is deliberately separate from the task-list
  /// completion checkbox. It belongs to the document's line leading, so it
  /// uses a neutral outline while open and a quiet graphite face when done;
  /// the completed line greys out through the text style.
  // Compatibility aliases for callers that used the document style catalog.
  // The values themselves belong to the shared document geometry token.
  static const double checklistSize = TaskDocumentMetrics.checklistSize;
  static const double checklistRadius = TaskDocumentMetrics.checklistRadius;
  static const double checklistBorderWidth =
      TaskDocumentMetrics.checklistBorderWidth;

  /// The text treatment used for a completed checklist line. This only
  /// returns the properties that differ from the line's existing style, which
  /// lets a completed H1 retain its heading size and weight.
  static TextStyle completedChecklistText(WorkFollowTheme tokens) => TextStyle(
        color: tokens.textSecondary,
        decoration: TextDecoration.lineThrough,
        decorationColor: tokens.textSecondary,
        decorationThickness: 1,
      );

  /// Quill calls this for line and inline attributes while it builds spans.
  /// Keeping the checked state here means every document entry point gets the
  /// same completed-line treatment without writing presentation attributes to
  /// the Delta.
  static TextStyle Function(quill.Attribute) customStyleBuilder(
      WorkFollowTheme tokens) {
    final completed = completedChecklistText(tokens);
    return (attribute) {
      if (attribute.key == quill.Attribute.list.key &&
          attribute.value == quill.Attribute.checked.value) {
        return completed;
      }
      if (attribute.key == quill.Attribute.background.key) {
        return TextStyle(
          backgroundColor: tokens.documentHighlight,
        );
      }
      return const TextStyle();
    };
  }

  /// Body text used by paragraphs, lists, checklists, and quotes.
  static TextStyle body(WorkFollowTheme tokens, {TextStyle? base}) => _text(
        tokens,
        base: base,
        fontSize: WorkFollowMacTypography.body,
        fontWeight: WorkFollowMacWeight.regular,
        height: WorkFollowMacTypography.lineBody,
      );

  /// Title of a document field.
  ///
  /// The size is the shell's call, and both shells currently resolve the same
  /// role — `detailTitle` — whether the title belongs to a task inspector's
  /// field or to a full-page note. What every document title shares is the
  /// weight, the line height, the absence of tracking, and the ink.
  ///
  /// The ink is unconditional. A title field is where a document is named and
  /// renamed, so it reads at full strength in every document state; a finished
  /// task is a quieter thing in the list it sits in, not in the field that
  /// names it. Two parameters used to be here — a strike, then a grey — and
  /// both made the inspector the one place a completed task's own title did
  /// not look like itself. Neither remains.
  static TextStyle title(
    WorkFollowTheme tokens, {
    required double fontSize,
  }) =>
      TextStyle(
        fontSize: fontSize,
        height: WorkFollowMacTypography.lineControl,
        fontWeight: WorkFollowMacWeight.semibold,
        letterSpacing: WorkFollowMacTracking.none,
        color: tokens.textPrimary,
      );

  /// Decoration of a document's title field.
  ///
  /// No chrome, dense metrics and no content padding: a title is the first line
  /// of the document, so it sits on the document's own baseline rather than on
  /// a Material field's inset one.
  static InputDecoration titleDecoration(String hintText, {Color? hintColor}) =>
      InputDecoration(
        hintText: hintText,
        hintStyle: hintColor == null ? null : TextStyle(color: hintColor),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      );

  /// First-level heading style. The larger size is the semantic difference;
  /// its colour and font family still come from the task document base.
  static TextStyle h1(WorkFollowTheme tokens, {TextStyle? base}) => _text(
        tokens,
        base: base,
        fontSize: WorkFollowMacTypography.documentH1,
        fontWeight: WorkFollowMacWeight.semibold,
        height: WorkFollowMacTypography.documentHeadingLine,
      );

  /// Second-level heading style.
  static TextStyle h2(WorkFollowTheme tokens, {TextStyle? base}) => _text(
        tokens,
        base: base,
        fontSize: WorkFollowMacTypography.documentH2,
        fontWeight: WorkFollowMacWeight.semibold,
        height: WorkFollowMacTypography.documentHeadingLine,
      );

  /// Third-level heading style.
  static TextStyle h3(WorkFollowTheme tokens, {TextStyle? base}) => _text(
        tokens,
        base: base,
        fontSize: WorkFollowMacTypography.documentH3,
        fontWeight: WorkFollowMacWeight.semibold,
        height: WorkFollowMacTypography.documentHeading3Line,
      );

  /// Link text keeps the body metrics and changes only its semantic link
  /// treatment. The colour is supplied by the theme rather than by a Delta
  /// format operation.
  static TextStyle link(WorkFollowTheme tokens, {TextStyle? base}) =>
      body(tokens, base: base).copyWith(
        color: tokens.accent,
        decoration: TextDecoration.underline,
        decorationColor: tokens.accent,
        decorationThickness: 1,
      );

  /// Code uses a stable monospace face while retaining the document body
  /// size. Inline and block code share this role; the block adds its own
  /// surface below.
  static TextStyle code(WorkFollowTheme tokens, {TextStyle? base}) =>
      body(tokens, base: base).copyWith(
        fontFamily: WorkFollowMacTypeFamily.code,
        fontFamilyFallback: WorkFollowMacTypeFamily.codeFallback,
      );

  /// Build the Quill defaults used by a task document.
  ///
  /// [base] is normally the current Theme body style. Keeping it as the
  /// starting point preserves the platform font resolution while the named
  /// document roles replace Quill's Material sizes and colours.
  static quill.DefaultStyles build(
    WorkFollowTheme tokens, {
    TextStyle? base,
    double paragraphBottom = WorkFollowSpacing.editorParagraphGap,
    double placeholderBottom = WorkFollowSpacing.editorParagraphGap,
  }) {
    final bodyStyle = body(tokens, base: base);
    final blockSpacing = const quill.HorizontalSpacing(
        WorkFollowSpacing.zero, WorkFollowSpacing.zero);
    final paragraphSpacing =
        quill.VerticalSpacing(WorkFollowSpacing.zero, paragraphBottom);
    final placeholderSpacing =
        quill.VerticalSpacing(WorkFollowSpacing.zero, placeholderBottom);

    return quill.DefaultStyles(
      h1: _block(
        h1(tokens, base: base),
        verticalSpacing: const quill.VerticalSpacing(
            WorkFollowSpacing.space3, WorkFollowSpacing.inlineGap),
      ),
      h2: _block(
        h2(tokens, base: base),
        verticalSpacing: const quill.VerticalSpacing(
            WorkFollowSpacing.controlGap, WorkFollowSpacing.denseGap),
      ),
      h3: _block(
        h3(tokens, base: base),
        verticalSpacing: const quill.VerticalSpacing(
            WorkFollowSpacing.space2, WorkFollowSpacing.space1),
      ),
      paragraph: quill.DefaultTextBlockStyle(
        bodyStyle,
        blockSpacing,
        paragraphSpacing,
        const quill.VerticalSpacing(
            WorkFollowSpacing.zero, WorkFollowSpacing.zero),
        null,
      ),
      placeHolder: quill.DefaultTextBlockStyle(
        bodyStyle.copyWith(color: tokens.textTertiary),
        blockSpacing,
        placeholderSpacing,
        const quill.VerticalSpacing(
            WorkFollowSpacing.zero, WorkFollowSpacing.zero),
        null,
      ),
      // The list marker uses this style's paragraph font size when it lays
      // out bullets, numbers, and checkboxes. Keeping it equal to body keeps
      // all three list variants visually stable.
      lists: quill.DefaultListBlockStyle(
        bodyStyle,
        blockSpacing,
        paragraphSpacing,
        const quill.VerticalSpacing(
            WorkFollowSpacing.zero, WorkFollowSpacing.zero),
        null,
        DocumentCheckboxBuilder(tokens),
      ),
      // Ordered and unordered markers (numbers and bullets) take their face
      // from `leading`; giving it the accent colour produces the TickTick
      // look where 1./2./3. and • lead the line in the brand tone while the
      // text itself stays primary. Checklist sizing reads the paragraph
      // style above instead.
      leading: _block(bodyStyle.copyWith(color: tokens.accent)),
      // Quote distinction is structural: an inset and a quiet left rule. Its
      // text remains body-sized and textPrimary so Quill never turns it grey.
      quote: _block(
        bodyStyle,
        horizontalSpacing: const quill.HorizontalSpacing(
            WorkFollowSpacing.space3, WorkFollowSpacing.zero),
        verticalSpacing: paragraphSpacing,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                width: TaskDocumentMetrics.quoteBorderWidth,
                color: tokens.borderStrong),
          ),
        ),
      ),
      // Quill resolves inline colour attributes after the block style. This
      // fallback makes malformed/unknown colour values resolve to the same
      // WorkFollow primary colour without writing a colour into the Delta.
      color: tokens.textPrimary,
      link: link(tokens, base: base),
      inlineCode: quill.InlineCodeStyle(
        style: code(tokens, base: base),
        backgroundColor: tokens.canvas,
        radius: Radius.circular(WorkFollowRadii.control),
      ),
      code: _block(
        code(tokens, base: base),
        horizontalSpacing: const quill.HorizontalSpacing(
            WorkFollowSpacing.space3, WorkFollowSpacing.space3),
        verticalSpacing: const quill.VerticalSpacing(
            WorkFollowSpacing.space2, WorkFollowSpacing.space2),
        decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        ),
      ),
    );
  }

  static TextStyle _text(
    WorkFollowTheme tokens, {
    TextStyle? base,
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
  }) =>
      (base ?? const TextStyle()).copyWith(
        // Keep Quill's line styles on the same macOS system cascade as the
        // surrounding editor. The Web client owns its Inter catalog; the
        // desktop document never inherits that family accidentally.
        fontFamily: WorkFollowMacTypeFamily.ui,
        fontFamilyFallback: WorkFollowMacTypeFamily.fallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: WorkFollowMacTracking.none,
        color: tokens.textPrimary,
      );

  static quill.DefaultTextBlockStyle _block(
    TextStyle style, {
    quill.HorizontalSpacing horizontalSpacing = const quill.HorizontalSpacing(
        WorkFollowSpacing.zero, WorkFollowSpacing.zero),
    quill.VerticalSpacing verticalSpacing = const quill.VerticalSpacing(
        WorkFollowSpacing.zero, WorkFollowSpacing.editorParagraphGap),
    quill.VerticalSpacing lineSpacing = const quill.VerticalSpacing(
        WorkFollowSpacing.zero, WorkFollowSpacing.zero),
    BoxDecoration? decoration,
  }) =>
      quill.DefaultTextBlockStyle(
        style,
        horizontalSpacing,
        verticalSpacing,
        lineSpacing,
        decoration,
      );
}

/// Draws the neutral checklist marker used by task and note documents.
///
/// Flutter Quill intentionally exposes the checkbox as a builder on
/// [quill.DefaultListBlockStyle]. Using that hook avoids replacing Quill's
/// list leading and preserves its caret/selection behaviour.
class DocumentCheckboxBuilder extends quill.QuillCheckboxBuilder {
  DocumentCheckboxBuilder(this.tokens);

  final WorkFollowTheme tokens;

  @override
  Widget build({
    required BuildContext context,
    required bool isChecked,
    required ValueChanged<bool> onChanged,
  }) =>
      _DocumentCheckbox(
        tokens: tokens,
        isChecked: isChecked,
        onChanged: onChanged,
      );
}

class _DocumentCheckbox extends StatefulWidget {
  const _DocumentCheckbox({
    required this.tokens,
    required this.isChecked,
    required this.onChanged,
  });

  final WorkFollowTheme tokens;
  final bool isChecked;
  final ValueChanged<bool> onChanged;

  @override
  State<_DocumentCheckbox> createState() => _DocumentCheckboxState();
}

class _DocumentCheckboxState extends State<_DocumentCheckbox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // A document checklist is content structure, not a success indicator.
    // Keep the unchecked marker neutral, and use a theme-owned graphite face
    // plus a contrast-safe check for the completed state.
    final checklistFill =
        WorkFollowColorTokens.documentChecklistFill(widget.tokens);
    final background = widget.isChecked ? checklistFill : Colors.transparent;
    final borderColor = widget.isChecked
        ? checklistFill
        : _hovered
            ? widget.tokens.textSecondary
            : widget.tokens.borderStrong;
    final checkColor =
        WorkFollowColorTokens.documentChecklistCheck(widget.tokens);

    final marker = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: Semantics(
        container: true,
        button: true,
        toggled: widget.isChecked,
        label: widget.isChecked ? '已完成检查项' : '未完成检查项',
        child: SizedBox(
          width: DocumentStyles.checklistSize,
          height: DocumentStyles.checklistSize,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: borderColor,
                width: DocumentStyles.checklistBorderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(DocumentStyles.checklistRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onChanged(!widget.isChecked),
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: widget.isChecked
                  ? CustomPaint(
                      painter: _ChecklistCheckPainter(checkColor),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    // Quill hands the leading widget the row's tight height and the full
    // leading width, so the marker must opt out of stretching or it renders
    // as a wide rectangle. The default QuillCheckboxPoint wraps itself the
    // same way before giving the box its natural square size.
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
            end: TaskDocumentMetrics.checklistTrailingInset),
        child: marker,
      ),
    );
  }
}

class _ChecklistCheckPainter extends CustomPainter {
  const _ChecklistCheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .22, size.height * .51)
      ..lineTo(size.width * .43, size.height * .72)
      ..lineTo(size.width * .79, size.height * .29);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = TaskDocumentMetrics.checklistCheckStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChecklistCheckPainter oldDelegate) =>
      oldDelegate.color != color;
}
