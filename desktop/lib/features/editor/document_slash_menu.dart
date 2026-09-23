import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_interaction_states.dart';
import '../../theme/workfollow_surface_tokens.dart';
import '../../theme/workfollow_theme.dart';
import 'document_commands.dart';

/// Commands are grouped by their role in the palette, not by document type.
enum DocumentSlashGroup { formatting, insert }

/// Visual marks used by slash command descriptors. These names describe the
/// shape, not the behavior represented by a command.
enum DocumentSlashGlyphKind {
  heading1,
  heading2,
  heading3,
  bullet,
  ordered,
  checklist,
  quote,
  divider,
  nestedItems,
  labelTag,
  linkedCards,
}

/// A hand-drawn glyph that a command descriptor can supply to the menu.
class DocumentSlashGlyph extends StatelessWidget {
  const DocumentSlashGlyph({
    super.key,
    required this.kind,
    required this.color,
  });

  final DocumentSlashGlyphKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SlashMenuGlyph(kind, color));
}

/// Values supplied to a slash command when the user selects it.
class DocumentSlashInvocation {
  const DocumentSlashInvocation({
    required this.anchor,
    required this.commands,
    required this.slashOffset,
    required this.lineStart,
  });

  /// The editor surface context used to anchor document-specific pickers.
  final BuildContext anchor;

  /// Shared document mutation API.
  final DocumentCommands commands;

  /// Offset where the `/` was typed, retained after the trigger is removed.
  final int slashOffset;

  /// Start of the paragraph containing the trigger.
  final int lineStart;
}

/// A palette entry provided by the profile for the document being edited.
///
/// The menu renders the descriptor and returns it unchanged. It does not
/// infer behavior from the id; the callback owns the behavior.
class DocumentSlashCommand {
  const DocumentSlashCommand({
    required this.id,
    required this.label,
    required this.group,
    required this.onInvoke,
    this.icon,
    this.leadingBuilder,
  }) : assert(icon == null || leadingBuilder == null);

  final String id;
  final String label;
  final DocumentSlashGroup group;
  final FutureOr<void> Function(DocumentSlashInvocation invocation) onInvoke;

  /// Optional standard icon for commands that use a standard glyph.
  final IconData? icon;

  /// Optional leading visual. When present, it takes precedence over [icon].
  final Widget Function(BuildContext context, Color color)? leadingBuilder;

  static Widget Function(BuildContext, Color) _glyph(
    DocumentSlashGlyphKind kind,
  ) =>
      (context, color) => DocumentSlashGlyph(kind: kind, color: color);

  static List<DocumentSlashCommand> sharedDocumentCommands() => [
        DocumentSlashCommand(
          id: 'heading-1',
          label: '一级标题',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.heading1),
          onInvoke: (invocation) =>
              invocation.commands.setHeading1(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'heading-2',
          label: '二级标题',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.heading2),
          onInvoke: (invocation) =>
              invocation.commands.setHeading2(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'heading-3',
          label: '三级标题',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.heading3),
          onInvoke: (invocation) =>
              invocation.commands.setHeading3(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'bullet',
          label: '无序列表',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.bullet),
          onInvoke: (invocation) => invocation.commands
              .toggleBulletList(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'ordered',
          label: '有序列表',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.ordered),
          onInvoke: (invocation) => invocation.commands
              .toggleOrderedList(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'checklist',
          label: '检查项',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.checklist),
          onInvoke: (invocation) => invocation.commands
              .toggleChecklist(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'quote',
          label: '引用',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.quote),
          onInvoke: (invocation) =>
              invocation.commands.toggleQuote(lineStart: invocation.lineStart),
        ),
        DocumentSlashCommand(
          id: 'divider',
          label: '水平分割线',
          group: DocumentSlashGroup.formatting,
          leadingBuilder: _glyph(DocumentSlashGlyphKind.divider),
          onInvoke: (invocation) =>
              invocation.commands.insertDivider(at: invocation.slashOffset),
        ),
        DocumentSlashCommand(
          id: 'attachment',
          label: '附件',
          group: DocumentSlashGroup.insert,
          icon: WorkFollowIcons.attachment,
          onInvoke: (invocation) async {
            await invocation.commands
                .insertAttachment(at: invocation.slashOffset);
          },
        ),
      ];
}

/// Geometry of the command palette, measured off the reference menu at 2x.
///
/// The numbers are deliberately compact: a 160pt palette with 34pt rows is a
/// command list, and the old 276 x 40 surface read as a settings panel. Every
/// value here has a counterpart in the measurement table, so a later
/// "looks a bit off" pass can compare rather than guess.
class DocumentSlashMenuMetrics {
  const DocumentSlashMenuMetrics._();

  static const double width = DocumentEditorMetrics.commandMenuWidth;

  /// Natural height of the full 12-item palette. The editor lowers it when the
  /// window cannot hold it, and the palette scrolls instead of clipping.
  static const double maxHeight = DocumentEditorMetrics.commandMenuMaxHeight;

  static const double padding = WorkFollowSpacing.space1;
  static const double itemInset = WorkFollowSpacing.space1;
  static const double itemHeight = WorkFollowMetrics.compactMenuRowHeight;
  static const double itemLeading = WorkFollowSpacing.relaxedGap;
  static const double itemTrailing = WorkFollowSpacing.space3;
  static const double glyphSlot = DocumentEditorMetrics.commandGlyphSlot;
  static const double glyphGap = WorkFollowSpacing.iconLabelGap;

  /// 4 above the hairline, 1 for the hairline, 4 below.
  static const double dividerBlock = WorkFollowSpacing.compactInset;

  /// Size of icon-led entries, matched to the hand-drawn glyphs' visual area.
  static const double fontGlyph = 15;
}

/// The `/` command palette of a document surface.
///
/// The profile supplies ordered command descriptors. The menu only separates
/// the formatting and insertion groups and handles their visual navigation.
class DocumentSlashMenu extends StatefulWidget {
  const DocumentSlashMenu({
    super.key,
    required this.commands,
    required this.onSelected,
    this.maxHeight = DocumentSlashMenuMetrics.maxHeight,
  });

  final List<DocumentSlashCommand> commands;
  final ValueChanged<DocumentSlashCommand> onSelected;

  /// Cap handed down by the anchor owner, which is the only layer that knows
  /// how much room the caret has.
  final double maxHeight;

  /// Splits the supplied descriptors while preserving their order per group.
  static ({
    List<DocumentSlashCommand> formatting,
    List<DocumentSlashCommand> insert,
  }) groupsFor(List<DocumentSlashCommand> commands) => (
        formatting: commands
            .where((command) => command.group == DocumentSlashGroup.formatting)
            .toList(growable: false),
        insert: commands
            .where((command) => command.group == DocumentSlashGroup.insert)
            .toList(growable: false),
      );

  /// Exact height [commands] will occupy, so the caller can place the palette
  /// without measuring it.
  static double heightFor(List<DocumentSlashCommand> commands) {
    final groups = groupsFor(commands);
    final count = groups.formatting.length + groups.insert.length;
    final divider =
        groups.formatting.isNotEmpty && groups.insert.isNotEmpty ? 1.0 : 0.0;
    return count * DocumentSlashMenuMetrics.itemHeight +
        divider * DocumentSlashMenuMetrics.dividerBlock +
        DocumentSlashMenuMetrics.padding * 2;
  }

  @override
  State<DocumentSlashMenu> createState() => DocumentSlashMenuState();
}

/// Holds the command-palette selection model.
///
/// The palette never takes focus — the caret stays in the document — so the
/// editor routes ↑/↓/Enter here through a [GlobalKey] instead of stealing the
/// focus. That is why the selection has to live in a public state class.
class DocumentSlashMenuState extends State<DocumentSlashMenu> {
  final _scroll = ScrollController();
  int _focused = 0;

  /// Index of the highlighted row. Starts on the first command, which is what
  /// the user sees the moment `/` opens the palette.
  int get focusedIndex => _focused;

  List<DocumentSlashCommand> get _visible => [
        ..._formatting,
        ..._insert,
      ];

  List<DocumentSlashCommand> get _formatting =>
      DocumentSlashMenu.groupsFor(widget.commands).formatting;
  List<DocumentSlashCommand> get _insert =>
      DocumentSlashMenu.groupsFor(widget.commands).insert;

  /// Moves the highlight by [delta] rows, wrapping at the ends.
  ///
  /// Wrapping is what a command palette does: ↓ on the last row returns to the
  /// top instead of parking on the same row, which is also the only way to
  /// reach the first row with the keyboard after a hover moved the highlight.
  bool moveSelection(int delta) {
    final items = _visible;
    if (items.isEmpty) return false;
    // Dart's % keeps the sign of the dividend, so a step up from the first row
    // has to be folded back to the end of the list.
    final next = (_focused + delta) % items.length;
    setState(() => _focused = next < 0 ? next + items.length : next);
    _revealFocused();
    return true;
  }

  /// Runs the highlighted command.
  bool activateFocused() {
    final items = _visible;
    if (items.isEmpty) return false;
    widget.onSelected(items[_focused.clamp(0, items.length - 1)]);
    return true;
  }

  void _hover(int index) {
    if (_focused == index) return;
    // Pointing at a row moves the selection onto it. Hover and keyboard
    // selection are therefore the same single highlight, never two bars.
    setState(() => _focused = index);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _offsetOf(int index) {
    final formatting = _formatting;
    if (index < formatting.length) {
      return DocumentSlashMenuMetrics.padding +
          index * DocumentSlashMenuMetrics.itemHeight;
    }
    final divider =
        formatting.isEmpty ? 0.0 : DocumentSlashMenuMetrics.dividerBlock;
    return DocumentSlashMenuMetrics.padding +
        formatting.length * DocumentSlashMenuMetrics.itemHeight +
        divider +
        (index - formatting.length) * DocumentSlashMenuMetrics.itemHeight;
  }

  /// Keeps the highlighted row inside a palette that had to shrink.
  void _revealFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final top = _offsetOf(_focused);
      final bottom = top + DocumentSlashMenuMetrics.itemHeight;
      var target = position.pixels;
      if (top < target) {
        target = top;
      } else if (bottom > target + position.viewportDimension) {
        target = bottom - position.viewportDimension;
      }
      if (target == position.pixels) return;
      position.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final formatting = _formatting;
    final insert = _insert;
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Material(
        key: const ValueKey('document-slash-menu'),
        elevation: WorkFollowShadows.level2Elevation,
        shadowColor: tokens.shadow,
        color: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkFollowRadii.popover),
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: DocumentSlashMenuMetrics.width,
              maxHeight: widget.maxHeight),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(
                vertical: DocumentSlashMenuMetrics.padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < formatting.length; i++)
                  _item(i, formatting[i], tokens),
                if (formatting.isNotEmpty && insert.isNotEmpty)
                  _divider(tokens),
                for (var i = 0; i < insert.length; i++)
                  _item(formatting.length + i, insert[i], tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A full-bleed hairline. The reference separates the two sections with a
  /// line that spans the palette, not one inset to the rows.
  Widget _divider(WorkFollowTheme tokens) => SizedBox(
        height: DocumentSlashMenuMetrics.dividerBlock,
        child: Center(
            child: Container(
                height: WorkFollowMetrics.dividerThickness,
                color: tokens.menuDivider)),
      );

  Widget _item(
      int index, DocumentSlashCommand command, WorkFollowTheme tokens) {
    final selected = index == _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DocumentSlashMenuMetrics.itemInset),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _hover(index),
        child: InkWell(
          key: ValueKey('document-slash-option-${command.id}'),
          onTap: () => widget.onSelected(command),
          overlayColor: WorkFollowInteractionStyles.overlay(
            tokens,
            menu: true,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: WorkFollowInteractionStyles.fill(
                tokens,
                selected: selected,
                menu: true,
              ),
              border: Border.fromBorderSide(
                WorkFollowInteractionStyles.focusBorder(
                  tokens,
                  focused: selected,
                ),
              ),
              borderRadius: BorderRadius.circular(WorkFollowRadii.sm),
            ),
            child: SizedBox(
              height: DocumentSlashMenuMetrics.itemHeight,
              child: Row(
                children: [
                  const SizedBox(width: DocumentSlashMenuMetrics.itemLeading),
                  _leading(context, command, tokens),
                  const SizedBox(width: DocumentSlashMenuMetrics.glyphGap),
                  Expanded(
                    child: Text(
                      command.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        // A command row is menu text, one step below the task
                        // title: 13/regular here, so the list reads as labels
                        // rather than as a set of actions competing with the
                        // document behind it.
                        fontSize: WorkFollowMacTypography.control,
                        height: WorkFollowMacTypography.lineControl,
                        fontWeight: WorkFollowMacWeight.regular,
                        letterSpacing: WorkFollowMacTracking.none,
                        // Selection is a quiet grey fill; the label keeps its
                        // colour and weight so the row does not shift.
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: DocumentSlashMenuMetrics.itemTrailing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(
    BuildContext context,
    DocumentSlashCommand command,
    WorkFollowTheme tokens,
  ) {
    final builder = command.leadingBuilder;
    if (builder != null) {
      return SizedBox(
        width: DocumentSlashMenuMetrics.glyphSlot,
        height: DocumentSlashMenuMetrics.glyphSlot,
        child: builder(context, tokens.textPrimary),
      );
    }
    final glyph = command.icon;
    if (glyph != null) {
      return SizedBox(
        width: DocumentSlashMenuMetrics.glyphSlot,
        height: DocumentSlashMenuMetrics.glyphSlot,
        child: Center(
          child: Icon(glyph,
              size: DocumentSlashMenuMetrics.fontGlyph,
              color: tokens.textPrimary),
        ),
      );
    }
    return SizedBox(
      width: DocumentSlashMenuMetrics.glyphSlot,
      height: DocumentSlashMenuMetrics.glyphSlot,
    );
  }
}

/// Draws one leading glyph on a 14 x 14 grid.
///
/// The reference palette draws its own icon set — three-dot bullets, `1 2 3`
/// numbering, a stacked divider, a nested-item branch, two linked rectangles — and no
/// Material glyph stands in for those without changing the language. The two
/// heading levels are text, not icons: `H₁ / H₂ / H₃` is the level, and
/// `title` / `text_fields` / `short_text` only say "some heading".
class _SlashMenuGlyph extends CustomPainter {
  const _SlashMenuGlyph(this.kind, this.color);

  final DocumentSlashGlyphKind kind;
  final Color color;

  static const double _box = DocumentSlashMenuMetrics.glyphSlot;
  static const double _stroke = 1.2;
  static const double _trunk = 1.5;

  /// Row centres shared by the bullet, numbered and divider glyphs.
  static const _rows = <double>[2.25, 6.5, 10.75];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.shortestSide / _box);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final trunk = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trunk
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;

    switch (kind) {
      case DocumentSlashGlyphKind.heading1:
        _heading(canvas, 1);
      case DocumentSlashGlyphKind.heading2:
        _heading(canvas, 2);
      case DocumentSlashGlyphKind.heading3:
        _heading(canvas, 3);
      case DocumentSlashGlyphKind.bullet:
        _bullet(canvas, line, fill);
      case DocumentSlashGlyphKind.ordered:
        _ordered(canvas, line);
      case DocumentSlashGlyphKind.checklist:
        _checklist(canvas, line);
      case DocumentSlashGlyphKind.quote:
        _quote(canvas, fill);
      case DocumentSlashGlyphKind.divider:
        _divider(canvas, line);
      case DocumentSlashGlyphKind.nestedItems:
        _nestedItems(canvas, trunk, fill);
      case DocumentSlashGlyphKind.labelTag:
        _labelTag(canvas, line, fill);
      case DocumentSlashGlyphKind.linkedCards:
        _linkedCards(canvas, line);
    }
    canvas.restore();
  }

  void _heading(Canvas canvas, int level) {
    _text(canvas, 'H', WorkFollowMacDisplay.slashHeading,
        WorkFollowMacWeight.regular, 0.2, 11.25);
    _text(canvas, '$level', WorkFollowMacDisplay.slashHeadingIndex,
        WorkFollowMacWeight.medium, 9.8, 11.75);
  }

  /// Paints [text] with its alphabetic baseline on [baseline].
  void _text(Canvas canvas, String text, double size, FontWeight weight,
      double x, double baseline) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: WorkFollowMacTracking.none,
            color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas,
        Offset(
            x,
            baseline -
                painter
                    .computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  void _bullet(Canvas canvas, Paint line, Paint fill) {
    for (final y in _rows) {
      canvas.drawCircle(Offset(2, y), 1, fill);
      canvas.drawLine(Offset(4.4, y), Offset(12.5, y), line);
    }
  }

  void _ordered(Canvas canvas, Paint line) {
    for (var i = 0; i < _rows.length; i++) {
      final y = _rows[i];
      canvas.drawLine(Offset(4.4, y), Offset(12.5, y), line);
      // The numeral is centred on the row line rather than sitting on a
      // baseline: at this size it reads as a mark beside the rule.
      _text(canvas, '${i + 1}', WorkFollowMacDisplay.slashOrderedNumeral,
          WorkFollowMacWeight.medium, 0.9, y + 1.6);
    }
  }

  void _checklist(Canvas canvas, Paint line) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTRB(1, .75, 12.5, 12.25), const Radius.circular(2.5)),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(3.7, 6.5)
        ..lineTo(5.6, 8.6)
        ..lineTo(9.7, 4),
      line,
    );
  }

  void _quote(Canvas canvas, Paint fill) {
    for (final origin in const [Offset(.5, 1.6), Offset(7.5, 7.1)]) {
      _quoteMark(canvas, origin, fill);
      _quoteMark(canvas, origin + const Offset(3.5, 0), fill);
    }
  }

  /// One quote mark: a head and a tail, which is all a `“` is at 2.5pt.
  void _quoteMark(Canvas canvas, Offset origin, Paint fill) {
    canvas.drawCircle(Offset(origin.dx + 1.25, origin.dy + 1.2), 1.2, fill);
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx + 2.4, origin.dy + 1.2)
        ..lineTo(origin.dx + .2, origin.dy + 4.5)
        ..lineTo(origin.dx + 2.4, origin.dy + 4.5)
        ..close(),
      fill,
    );
  }

  void _divider(Canvas canvas, Paint line) {
    for (final y in const [1.6, 6.5, 11.3]) {
      canvas.drawLine(Offset(1, y), Offset(12.6, y), line);
    }
  }

  /// A trunk with two branches and a node on each, i.e. a task with children.
  void _nestedItems(Canvas canvas, Paint trunk, Paint fill) {
    canvas.drawLine(const Offset(1.75, .75), const Offset(1.75, 11.75), trunk);
    canvas.drawLine(const Offset(1.75, 4.5), const Offset(8, 4.5), trunk);
    canvas.drawLine(const Offset(1.75, 11), const Offset(8.5, 11), trunk);
    canvas.drawCircle(const Offset(11.4, 4.5), 1.3, fill);
    canvas.drawCircle(const Offset(11.4, 11), 1.3, fill);
  }

  void _labelTag(Canvas canvas, Paint line, Paint fill) {
    canvas.drawPath(
      Path()
        ..moveTo(.1, 6.9)
        ..lineTo(.1, 1.8)
        ..quadraticBezierTo(.1, .1, 1.8, .1)
        ..lineTo(5.4, .1)
        ..lineTo(13.4, 8.1)
        ..lineTo(8, 13.5)
        ..close(),
      line,
    );
    canvas.drawCircle(const Offset(4, 4), 1.25, fill);
  }

  void _linkedCards(Canvas canvas, Paint line) {
    const radius = Radius.circular(2.5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(4, .25, 13.5, 9.25), radius),
        line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(0, 4.25, 9.5, 13.75), radius),
        line);
  }

  @override
  bool shouldRepaint(covariant _SlashMenuGlyph oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
