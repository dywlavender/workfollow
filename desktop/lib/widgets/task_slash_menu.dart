import 'package:flutter/material.dart';

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';

enum TaskSlashAction {
  heading1,
  heading2,
  heading3,
  bullet,
  ordered,
  checklist,
  quote,
  divider,
  subtask,
  tag,
  relation,
  attachment,
  deadline,
  focus,
}

extension TaskSlashActionLabel on TaskSlashAction {
  String get label => switch (this) {
        TaskSlashAction.heading1 => '一级标题',
        TaskSlashAction.heading2 => '二级标题',
        TaskSlashAction.heading3 => '三级标题',
        TaskSlashAction.bullet => '无序列表',
        TaskSlashAction.ordered => '有序列表',
        TaskSlashAction.checklist => '检查项',
        TaskSlashAction.quote => '引用',
        TaskSlashAction.divider => '水平分割线',
        TaskSlashAction.subtask => '子任务',
        TaskSlashAction.tag => '标签',
        TaskSlashAction.relation => '关联任务/笔记',
        TaskSlashAction.attachment => '附件',
        TaskSlashAction.deadline => '截止日期',
        TaskSlashAction.focus => '专注记录',
      };

  String get keyName => switch (this) {
        TaskSlashAction.heading1 => 'heading-1',
        TaskSlashAction.heading2 => 'heading-2',
        TaskSlashAction.heading3 => 'heading-3',
        TaskSlashAction.bullet => 'bullet',
        TaskSlashAction.ordered => 'ordered',
        TaskSlashAction.checklist => 'checklist',
        TaskSlashAction.quote => 'quote',
        TaskSlashAction.divider => 'divider',
        TaskSlashAction.subtask => 'subtask',
        TaskSlashAction.tag => 'tag',
        TaskSlashAction.relation => 'relation',
        TaskSlashAction.attachment => 'attachment',
        TaskSlashAction.deadline => 'deadline',
        TaskSlashAction.focus => 'focus',
      };
}

/// Geometry of the command palette, measured off the reference menu at 2x.
///
/// The numbers are deliberately compact: a 160pt palette with 34pt rows is a
/// command list, and the old 276 x 40 surface read as a settings panel. Every
/// value here has a counterpart in the measurement table, so a later
/// "looks a bit off" pass can compare rather than guess.
class TaskSlashMenuMetrics {
  const TaskSlashMenuMetrics._();

  static const double width = TaskEditorMetrics.commandMenuWidth;

  /// Natural height of the full 12-item palette. The editor lowers it when the
  /// window cannot hold it, and the palette scrolls instead of clipping.
  static const double maxHeight = TaskEditorMetrics.commandMenuMaxHeight;

  static const double padding = WorkFollowSpacing.space1;
  static const double itemInset = WorkFollowSpacing.space1;
  static const double itemHeight = WorkFollowMetrics.compactMenuRowHeight;
  static const double itemLeading = WorkFollowSpacing.relaxedGap;
  static const double itemTrailing = WorkFollowSpacing.space3;
  static const double glyphSlot = TaskEditorMetrics.commandGlyphSlot;
  static const double glyphGap = WorkFollowSpacing.iconLabelGap;

  /// 4 above the hairline, 1 for the hairline, 4 below.
  static const double dividerBlock = WorkFollowSpacing.compactInset;

  /// Material shapes that already match the reference, sized so their ink
  /// lands on the same 12.5pt square as the hand-drawn siblings. The paperclip
  /// and the two WorkFollow-only commands keep their font glyph.
  static const double fontGlyph = 15;
}

/// The `/` command palette of a document surface.
///
/// Structure, order and glyph language follow the reference menu: eight text
/// commands, a hairline, then the four task commands in the order
/// attachment → subtask → tag → relation. WorkFollow's own `deadline` and
/// `focus` actions are still rendered when a caller asks for them by name, but
/// they are not part of the task editor's default palette: they belong to the
/// row context menu, and `deadline` also to the inspector's date property row.
/// The command stays, the entry point does not — the palette and the more menu
/// both have a reference to match, so neither grows because a feature exists.
class TaskSlashMenu extends StatefulWidget {
  const TaskSlashMenu({
    super.key,
    required this.onSelected,
    this.actions,
    this.maxHeight = TaskSlashMenuMetrics.maxHeight,
  });

  final ValueChanged<TaskSlashAction> onSelected;

  /// Optional subset for other document surfaces such as Notes. The palette
  /// keeps the full task set when this is omitted.
  final List<TaskSlashAction>? actions;

  /// Cap handed down by the anchor owner, which is the only layer that knows
  /// how much room the caret has.
  final double maxHeight;

  static const textActions = <TaskSlashAction>[
    TaskSlashAction.heading1,
    TaskSlashAction.heading2,
    TaskSlashAction.heading3,
    TaskSlashAction.bullet,
    TaskSlashAction.ordered,
    TaskSlashAction.checklist,
    TaskSlashAction.quote,
    TaskSlashAction.divider,
  ];

  static const taskActions = <TaskSlashAction>[
    TaskSlashAction.attachment,
    TaskSlashAction.subtask,
    TaskSlashAction.tag,
    TaskSlashAction.relation,
  ];

  /// Splits a caller's subset into the two rendered groups, preserving the
  /// palette order rather than the caller's.
  static ({List<TaskSlashAction> text, List<TaskSlashAction> task}) groupsFor(
      List<TaskSlashAction>? actions) {
    if (actions == null) {
      return (text: textActions, task: taskActions);
    }
    return (
      text: actions.where(textActions.contains).toList(growable: false),
      task: actions.where(taskActions.contains).toList(growable: false),
    );
  }

  /// Exact height [actions] will occupy, so the caller can place the palette
  /// without measuring it.
  static double heightFor(List<TaskSlashAction>? actions) {
    final groups = groupsFor(actions);
    final count = groups.text.length + groups.task.length;
    final divider =
        groups.text.isNotEmpty && groups.task.isNotEmpty ? 1.0 : 0.0;
    return count * TaskSlashMenuMetrics.itemHeight +
        divider * TaskSlashMenuMetrics.dividerBlock +
        TaskSlashMenuMetrics.padding * 2;
  }

  @override
  State<TaskSlashMenu> createState() => TaskSlashMenuState();
}

/// Holds the command-palette selection model.
///
/// The palette never takes focus — the caret stays in the document — so the
/// editor routes ↑/↓/Enter here through a [GlobalKey] instead of stealing the
/// focus. That is why the selection has to live in a public state class.
class TaskSlashMenuState extends State<TaskSlashMenu> {
  final _scroll = ScrollController();
  int _focused = 0;

  /// Index of the highlighted row. Starts on the first command, which is what
  /// the user sees the moment `/` opens the palette.
  int get focusedIndex => _focused;

  List<TaskSlashAction> get _visible {
    final groups = TaskSlashMenu.groupsFor(widget.actions);
    return [...groups.text, ...groups.task];
  }

  List<TaskSlashAction> get _text =>
      TaskSlashMenu.groupsFor(widget.actions).text;
  List<TaskSlashAction> get _task =>
      TaskSlashMenu.groupsFor(widget.actions).task;

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
    final text = _text;
    if (index < text.length) {
      return TaskSlashMenuMetrics.padding +
          index * TaskSlashMenuMetrics.itemHeight;
    }
    final divider = text.isEmpty ? 0.0 : TaskSlashMenuMetrics.dividerBlock;
    return TaskSlashMenuMetrics.padding +
        text.length * TaskSlashMenuMetrics.itemHeight +
        divider +
        (index - text.length) * TaskSlashMenuMetrics.itemHeight;
  }

  /// Keeps the highlighted row inside a palette that had to shrink.
  void _revealFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final top = _offsetOf(_focused);
      final bottom = top + TaskSlashMenuMetrics.itemHeight;
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
    final text = _text;
    final task = _task;
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Material(
        key: const ValueKey('task-slash-menu'),
        elevation: 8,
        shadowColor: tokens.shadow,
        color: tokens.overlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkFollowRadii.popover),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: TaskSlashMenuMetrics.width,
              maxHeight: widget.maxHeight),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(
                vertical: TaskSlashMenuMetrics.padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < text.length; i++) _item(i, text[i], tokens),
                if (text.isNotEmpty && task.isNotEmpty) _divider(tokens),
                for (var i = 0; i < task.length; i++)
                  _item(text.length + i, task[i], tokens),
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
        height: TaskSlashMenuMetrics.dividerBlock,
        child: Center(child: Container(height: 1, color: tokens.menuDivider)),
      );

  Widget _item(int index, TaskSlashAction action, WorkFollowTheme tokens) {
    final selected = index == _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: TaskSlashMenuMetrics.itemInset),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _hover(index),
        child: GestureDetector(
          key: ValueKey('task-slash-option-${action.keyName}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelected(action),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? tokens.menuSelected : null,
              borderRadius: BorderRadius.circular(WorkFollowRadii.sm),
            ),
            child: SizedBox(
              height: TaskSlashMenuMetrics.itemHeight,
              child: Row(
                children: [
                  const SizedBox(width: TaskSlashMenuMetrics.itemLeading),
                  _leading(action, tokens),
                  const SizedBox(width: TaskSlashMenuMetrics.glyphGap),
                  Expanded(
                    child: Text(
                      action.label,
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
                  const SizedBox(width: TaskSlashMenuMetrics.itemTrailing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(TaskSlashAction action, WorkFollowTheme tokens) {
    final glyph = switch (action) {
      TaskSlashAction.attachment => WorkFollowIcons.attachment,
      TaskSlashAction.deadline => WorkFollowIcons.deadline,
      TaskSlashAction.focus => WorkFollowIcons.focus,
      _ => null,
    };
    if (glyph != null) {
      return SizedBox(
        width: TaskSlashMenuMetrics.glyphSlot,
        height: TaskSlashMenuMetrics.glyphSlot,
        child: Center(
          child: Icon(glyph,
              size: TaskSlashMenuMetrics.fontGlyph, color: tokens.textPrimary),
        ),
      );
    }
    return SizedBox(
      width: TaskSlashMenuMetrics.glyphSlot,
      height: TaskSlashMenuMetrics.glyphSlot,
      child: CustomPaint(painter: _SlashMenuGlyph(action, tokens.textPrimary)),
    );
  }
}

/// Draws one leading glyph on a 14 x 14 grid.
///
/// The reference palette draws its own icon set — three-dot bullets, `1 2 3`
/// numbering, a stacked divider, a task branch, two linked rectangles — and no
/// Material glyph stands in for those without changing the language. The two
/// heading levels are text, not icons: `H₁ / H₂ / H₃` is the level, and
/// `title` / `text_fields` / `short_text` only say "some heading".
class _SlashMenuGlyph extends CustomPainter {
  const _SlashMenuGlyph(this.action, this.color);

  final TaskSlashAction action;
  final Color color;

  static const double _box = TaskSlashMenuMetrics.glyphSlot;
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

    switch (action) {
      case TaskSlashAction.heading1:
        _heading(canvas, 1);
      case TaskSlashAction.heading2:
        _heading(canvas, 2);
      case TaskSlashAction.heading3:
        _heading(canvas, 3);
      case TaskSlashAction.bullet:
        _bullet(canvas, line, fill);
      case TaskSlashAction.ordered:
        _ordered(canvas, line);
      case TaskSlashAction.checklist:
        _checklist(canvas, line);
      case TaskSlashAction.quote:
        _quote(canvas, fill);
      case TaskSlashAction.divider:
        _divider(canvas, line);
      case TaskSlashAction.subtask:
        _subtask(canvas, trunk, fill);
      case TaskSlashAction.tag:
        _tag(canvas, line, fill);
      case TaskSlashAction.relation:
        _relation(canvas, line);
      case TaskSlashAction.attachment:
      case TaskSlashAction.deadline:
      case TaskSlashAction.focus:
        // Drawn as font glyphs by the caller; the palette never reaches this
        // branch for the two WorkFollow-only commands.
        break;
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
  void _subtask(Canvas canvas, Paint trunk, Paint fill) {
    canvas.drawLine(const Offset(1.75, .75), const Offset(1.75, 11.75), trunk);
    canvas.drawLine(const Offset(1.75, 4.5), const Offset(8, 4.5), trunk);
    canvas.drawLine(const Offset(1.75, 11), const Offset(8.5, 11), trunk);
    canvas.drawCircle(const Offset(11.4, 4.5), 1.3, fill);
    canvas.drawCircle(const Offset(11.4, 11), 1.3, fill);
  }

  void _tag(Canvas canvas, Paint line, Paint fill) {
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

  void _relation(Canvas canvas, Paint line) {
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
      oldDelegate.action != action || oldDelegate.color != color;
}
