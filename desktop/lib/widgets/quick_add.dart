import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../services/smart_date_parser.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_color_tokens.dart';
import '../theme/workfollow_surface_tokens.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_event.dart';
import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/domain/task_schedule_settings.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';
import 'task_schedule_panel.dart';
import 'task_priority_picker.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';
import 'task_reminder_picker.dart';
import 'task_repeat_picker.dart';

String _smartSpanKey(SmartSpan span) =>
    '${span.kind.name}:${span.start}:${span.end}:${span.raw}';

/// Text controller that paints recognized smart-entry fragments in place.
/// The removable chips below the field remain the explicit dismiss affordance;
/// this span styling gives the user immediate, TickTick-like feedback without
/// replacing a normal editable TextField or interfering with IME composition.
class _SmartTextEditingController extends TextEditingController {
  List<SmartSpan> _highlights = const [];
  Set<String> _dismissed = const {};

  void setHighlights(Iterable<SmartSpan> spans, Iterable<String> dismissed) {
    _highlights = List.unmodifiable(spans);
    _dismissed = Set.unmodifiable(dismissed);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Let EditableText render an active IME composition in its native form;
    // highlighting resumes as soon as the composition is committed.
    if (text.isEmpty ||
        _highlights.isEmpty ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final spans = _highlights
        .where((span) => !_dismissed.contains(_smartSpanKey(span)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (spans.isEmpty) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in spans) {
      if (span.start < cursor || span.start >= text.length) continue;
      final end = span.end.clamp(span.start, text.length).toInt();
      if (span.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, span.start)));
      }
      final color = _colorFor(span.kind, WorkFollowTheme.of(context));
      children.add(TextSpan(
          text: text.substring(span.start, end),
          style: (style ?? const TextStyle()).copyWith(
              color: color,
              backgroundColor: color.withValues(alpha: .14),
              fontWeight: WorkFollowMacWeight.semibold)));
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }

  Color _colorFor(SmartTokenKind kind, WorkFollowTheme tokens) =>
      _smartTokenColor(kind, tokens);
}

Color _smartTokenColor(SmartTokenKind kind, WorkFollowTheme tokens) =>
    switch (kind) {
      SmartTokenKind.date => WorkFollowColorTokens.quickAddDate(tokens),
      SmartTokenKind.time => WorkFollowColorTokens.quickAddTime(tokens),
      SmartTokenKind.recurrence =>
        WorkFollowColorTokens.quickAddRecurrence(tokens),
      SmartTokenKind.tag => WorkFollowColorTokens.quickAddTag(tokens),
      SmartTokenKind.list => WorkFollowColorTokens.quickAddList(tokens),
      SmartTokenKind.priority => WorkFollowColorTokens.quickAddPriority(tokens),
    };

class QuickAddField extends StatefulWidget {
  const QuickAddField(
      {super.key,
      required this.controller,
      this.autofocus = false,
      this.listStyle = false});
  final WorkspaceController controller;
  final bool autofocus;

  /// Uses the compact inline-row treatment from the macOS list view. Home
  /// dashboard and other contexts keep the fuller card treatment.
  final bool listStyle;
  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final text = _SmartTextEditingController();
  final focus = FocusNode();
  bool focused = false;

  // Natural-language state (TickTick-style 智能识别): the draft is parsed
  // live, each recognised token shows as a removable chip, and dismissed
  // chips fall back to plain-title behaviour for their aspect.
  static const parser = SmartDateParser();
  SmartParseResult parse = _emptyParse;
  TaskDraft currentDraft = const TaskDraft(title: '');
  final Set<String> dismissedSpans = {};
  // Property values are stored in [currentDraft]. These flags only record
  // whether the user explicitly overrode a parser/default value; they do not
  // duplicate the property itself in separate widget state.
  bool scheduleOverridden = false;
  bool listOverridden = false;
  bool tagsOverridden = false;
  bool reminderOverridden = false;
  bool recurrenceOverridden = false;
  bool priorityOverridden = false;
  // The first Escape follows TickTick's editing affordance: leave the draft
  // intact but release focus.  A later Escape while the field is focused can
  // clear the draft, which keeps the shortcut layered instead of destructive
  // on the first press.
  bool _escapePrimed = false;

  // Whether the properties disclosure panel is open; keeps the row expanded
  // even though the text field has lost focus to the chevron.
  bool _propertiesOpen = false;

  // Same treatment for the date chip's schedule panel.
  bool _scheduleOpen = false;

  static const _emptyParse = SmartParseResult(
      title: '',
      dueAt: null,
      hasTime: false,
      reminderAt: null,
      recurrenceType: 'NONE',
      recurrenceConfig: null,
      tags: [],
      listName: null,
      priority: TaskPriority.none,
      spans: []);

  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
    widget.controller.addListener(_requested);
    if (widget.controller.quickAddFocusPending) {
      widget.controller.consumeQuickAddFocus();
      focus.requestFocus();
    }
  }

  void _focusChanged() {
    if (mounted) setState(() => focused = focus.hasFocus);
  }

  void _requested() {
    if (mounted && widget.controller.quickAddFocusPending) {
      widget.controller.consumeQuickAddFocus();
      focus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_requested);
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  void _reparse() {
    final rawResult = parser.parse(text.text);
    // Re-run the parser against a length-preserving input with dismissed
    // tokens masked out.  Parsing the original sentence and merely filtering
    // spans leaves a coupled date/time expression (for example
    // “明天 下午3点”) carrying the dismissed date into the remaining time
    // token.  Masking keeps the other token's own semantics intact while
    // retaining the original offsets for title/highlight rendering.
    final activeInput = _maskDismissedTokens(text.text, rawResult.spans);
    final result =
        activeInput == text.text ? rawResult : parser.parse(activeInput);
    final kept = result.spans
        .where((span) => !dismissedSpans.contains(_smartSpanKey(span)))
        .toList();
    bool keptKind(SmartTokenKind kind) => kept.any((span) => span.kind == kind);
    text.setHighlights(kept, dismissedSpans);
    final next = SmartParseResult(
        title: parser.titleFromSpans(text.text, kept),
        dueAt: keptKind(SmartTokenKind.date) || keptKind(SmartTokenKind.time)
            ? result.dueAt
            : null,
        hasTime:
            (keptKind(SmartTokenKind.date) || keptKind(SmartTokenKind.time)) &&
                result.hasTime,
        reminderAt: keptKind(SmartTokenKind.time) ||
                (keptKind(SmartTokenKind.date) && result.hasTime)
            ? result.reminderAt
            : null,
        recurrenceType: keptKind(SmartTokenKind.recurrence)
            ? result.recurrenceType
            : 'NONE',
        recurrenceConfig: keptKind(SmartTokenKind.recurrence)
            ? result.recurrenceConfig
            : null,
        tags: kept
            .where((span) => span.kind == SmartTokenKind.tag)
            .map((span) => span.label.substring(1))
            .toList(),
        listName: keptKind(SmartTokenKind.list) ? result.listName : null,
        priority: keptKind(SmartTokenKind.priority)
            ? result.priority
            : TaskPriority.none,
        spans: kept);
    setState(() {
      parse = next;
      _refreshDraft(next);
    });
  }

  String _maskDismissedTokens(String input, Iterable<SmartSpan> spans) {
    final ranges = spans
        .where((span) => dismissedSpans.contains(_smartSpanKey(span)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (ranges.isEmpty) return input;
    final output = StringBuffer();
    var cursor = 0;
    for (final span in ranges) {
      if (span.start < cursor) continue;
      if (span.start > cursor)
        output.write(input.substring(cursor, span.start));
      output.write(List.filled(span.end - span.start, ' ').join());
      cursor = span.end;
    }
    if (cursor < input.length) output.write(input.substring(cursor));
    return output.toString();
  }

  bool get customDate => scheduleOverridden;
  DateTime? get selectedDate => currentDraft.schedule.dueAt;
  bool get hasTime => currentDraft.schedule.hasTime;

  /// The list add row keeps two fixed slots right of the field,
  /// matching the TickTick reference: the date chip (defaulting to
  /// "today") and the properties disclosure. They stay visible even
  /// while the field is empty — that is what makes them fixed.
  bool get _scheduleActive => customDate
      ? selectedDate != null
      : parse.dueAt != null ||
          (!_hasDismissedScheduling &&
              !_inboxContext &&
              widget.controller.creationDate != null);

  /// TickTick rule: the inbox creates unscheduled tasks by default, so its
  /// date affordance is an icon-only entry — no "今天" label, no injected
  /// default date. Time-based views (今天 / 最近 7 天 / 计划) keep the
  /// default-today behaviour.
  bool get _inboxContext =>
      widget.controller.view == WorkspaceView.inbox;

  String _titleForValue(SmartParseResult value) {
    // An @marker only leaves the title when it does not name an existing
    // list. Keep this rule in the Draft projection as well as in submit(), so
    // there is never a second, divergent title representation in the field.
    final parsedList = value.listName != null &&
            widget.controller.lists.any((list) => list.name == value.listName)
        ? value.listName
        : null;
    // Once the user chooses a list explicitly, only that chosen marker is a
    // property token. A later, different @marker is ordinary title text;
    // silently dropping it would make the input and the created task diverge.
    final effectiveList = listOverridden ? currentDraft.listName : parsedList;
    final titleSpans = value.spans
        .where((span) =>
            span.kind != SmartTokenKind.list ||
            (effectiveList != null && span.raw == '@$effectiveList'))
        .toList(growable: false);
    return parser.titleFromSpans(text.text, titleSpans);
  }

  void _refreshDraft(SmartParseResult value) {
    final parsedList = value.listName != null &&
            widget.controller.lists.any((list) => list.name == value.listName)
        ? value.listName
        : null;
    final hasSchedulingToken = value.spans.any((span) =>
        span.kind == SmartTokenKind.date || span.kind == SmartTokenKind.time);
    final dismissedScheduling = _hasDismissedScheduling;
    final defaultDue =
        !hasSchedulingToken && !dismissedScheduling && !customDate && !_inboxContext
            ? widget.controller.creationDate
            : null;
    final parsedSchedule = TaskScheduleDraft(
      dueAt: value.dueAt ?? defaultDue,
      hasTime: value.hasTime,
    );
    currentDraft = TaskDraft(
      title: _titleForValue(value),
      listName: listOverridden ? currentDraft.listName : parsedList,
      schedule: scheduleOverridden ? currentDraft.schedule : parsedSchedule,
      reminderAt: reminderOverridden
          ? currentDraft.reminderAt
          : (!scheduleOverridden && value.hasTime ? value.reminderAt : null),
      recurrence: recurrenceOverridden
          ? currentDraft.recurrence
          : RecurrenceDraft(
              type: value.recurrenceType, config: value.recurrenceConfig),
      priority: priorityOverridden ? currentDraft.priority : value.priority,
      tags: tagsOverridden ? currentDraft.tags : value.tags,
      forceUnscheduled: (scheduleOverridden && selectedDate == null) ||
          (!hasSchedulingToken && dismissedScheduling),
    );
  }

  bool get _hasDismissedScheduling =>
      parser.parse(text.text).spans.any((span) =>
          dismissedSpans.contains(_smartSpanKey(span)) &&
          (span.kind == SmartTokenKind.date ||
              span.kind == SmartTokenKind.time));

  DateTime? get _effectiveDue => scheduleOverridden
      ? selectedDate
      : parse.dueAt ??
          (_hasDismissedScheduling || _inboxContext
              ? null
              : widget.controller.creationDate);

  bool get _effectiveHasTime => scheduleOverridden ? hasTime : parse.hasTime;

  void _dismissSpan(SmartSpan span) {
    dismissedSpans.add(_smartSpanKey(span));
    _reparse();
  }

  void _resetDraft() {
    text.clear();
    text.setHighlights(const [], const {});
    currentDraft = const TaskDraft(title: '');
    scheduleOverridden = false;
    listOverridden = false;
    tagsOverridden = false;
    reminderOverridden = false;
    recurrenceOverridden = false;
    priorityOverridden = false;
    dismissedSpans.clear();
    parse = _emptyParse;
    _propertiesOpen = false;
    _scheduleOpen = false;
  }

  void _handleEscape() {
    // A picker/popover has its own nested shortcut and gets first refusal.
    // Here Escape only handles the inline draft itself.
    if (focus.hasFocus) {
      if (_escapePrimed) {
        setState(_resetDraft);
        _escapePrimed = false;
      } else {
        _escapePrimed = true;
        focus.unfocus();
      }
      return;
    }
    // Once focus has moved to another control the draft remains available for
    // the user to resume, matching TickTick's non-destructive first Escape.
  }

  Future<void> _pickPriority(BuildContext anchor) async {
    final value = await TaskPriorityPicker.show(anchor,
        selected: priorityOverridden ? currentDraft.priority : parse.priority);
    if (!mounted || value == null) return;
    setState(() {
      currentDraft = currentDraft.copyWith(priority: value);
      priorityOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<String?> _pickList(BuildContext anchor,
      {PopoverPlacement placement = PopoverPlacement.topStart}) async {
    final value = await TaskListPicker.show(anchor,
        controller: widget.controller,
        selected: listOverridden ? currentDraft.listName : parse.listName,
        placement: placement);
    if (value == null) return null;
    if (!mounted) return value;
    setState(() {
      currentDraft = currentDraft.copyWith(listName: value);
      listOverridden = true;
      _refreshDraft(parse);
    });
    return value;
  }

  Future<String?> _pickTags(BuildContext anchor,
      {PopoverPlacement placement = PopoverPlacement.bottomStart}) async {
    final value = await TaskTagPicker.show(anchor,
        initial: (tagsOverridden ? currentDraft.tags : parse.tags).join('，'),
        availableTags: widget.controller.allTags().keys,
        placement: placement);
    if (value == null) return null;
    if (!mounted) return value;
    setState(() {
      final tags = value
          .split(RegExp('[,，]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
      currentDraft = currentDraft.copyWith(tags: tags);
      tagsOverridden = true;
      _refreshDraft(parse);
    });
    return value;
  }

  Future<void> _pickReminder(BuildContext anchor) async {
    final current =
        reminderOverridden ? currentDraft.reminderAt : parse.reminderAt;
    final value = await TaskReminderPicker.show(anchor,
        value: current?.toIso8601String());
    if (!mounted || value == null) return;
    setState(() {
      currentDraft = currentDraft.copyWith(
          reminderAt: value.date, clearReminderAt: value.date == null);
      reminderOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickRecurrence(BuildContext anchor) async {
    final recurrence = recurrenceOverridden
        ? currentDraft.recurrence
        : RecurrenceDraft(
            type: parse.recurrenceType, config: parse.recurrenceConfig);
    final task = TaskItem(
      id: 'draft',
      title: text.text.trim().isEmpty ? '新任务' : text.text.trim(),
      listName: listOverridden
          ? (currentDraft.listName ?? '收集箱')
          : parse.listName ?? '收集箱',
      bucket: TaskBucket.unscheduled,
      recurrenceType: recurrence.type,
      recurrenceConfig: recurrence.config,
      dueAt: (customDate ? selectedDate : parse.dueAt)?.toIso8601String(),
    );
    final value = await TaskRepeatPicker.show(anchor, task: task);
    if (!mounted || value == null) return;
    setState(() {
      currentDraft = currentDraft.copyWith(recurrence: value);
      recurrenceOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickSchedule(BuildContext anchor) async {
    // The chip tap moves focus off the text field; keep the row expanded for
    // the panel's lifetime and hand focus back when it closes, so the draft
    // keeps accepting typing right where it left off.
    setState(() => _scheduleOpen = true);
    final task = _schedulePanelTask();
    final result = await showTaskSchedulePanel(anchor, task,
        focusPolicy: PopoverFocusPolicy.preserveEditor);
    if (mounted) setState(() => _scheduleOpen = false);
    if (result != null && mounted) {
      final reminder = _reminderFromSchedule(result);
      setState(() {
        currentDraft = currentDraft.copyWith(
            schedule: result.schedule,
            reminderAt: reminder,
            clearReminderAt: reminder == null,
            recurrence: result.recurrence);
        scheduleOverridden = true;
        reminderOverridden = true;
        recurrenceOverridden = true;
        _refreshDraft(parse);
      });
    }
    if (mounted) focus.requestFocus();
  }

  /// The schedule editor is shared with the task inspector. Quick Add keeps
  /// its values in a Draft, so the panel receives a temporary TaskItem view of
  /// that Draft and its confirmed settings are projected back below.
  TaskItem _schedulePanelTask() {
    final recurrence = recurrenceOverridden
        ? currentDraft.recurrence
        : RecurrenceDraft(
            type: parse.recurrenceType, config: parse.recurrenceConfig);
    final reminder = reminderOverridden
        ? currentDraft.reminderAt
        : parse.reminderAt;
    return TaskItem(
      id: 'quick-add-schedule',
      title: text.text.trim().isEmpty ? '新任务' : text.text.trim(),
      listName: listOverridden
          ? (currentDraft.listName ?? '收集箱')
          : parse.listName ?? '收集箱',
      bucket: TaskBucket.unscheduled,
      dueAt: _effectiveDue?.toIso8601String(),
      hasDueTime: _effectiveDue == null ? null : _effectiveHasTime,
      reminderAt: reminder?.toIso8601String(),
      recurrenceType: recurrence.type,
      recurrenceConfig: recurrence.config,
    );
  }

  DateTime? _reminderFromSchedule(TaskScheduleSettings settings) {
    if (settings.schedule.dueAt == null) return null;
    if (settings.reminderOffsets.isEmpty) return settings.reminderAt;
    final due = settings.schedule.normalizedDueAt!;
    final base = settings.schedule.hasTime
        ? due
        : DateTime(due.year, due.month, due.day, 9);
    final offset = settings.reminderOffsets.reduce(
        (largest, value) => value > largest ? value : largest);
    return base.subtract(Duration(minutes: offset));
  }

  /// The properties disclosure opens the TickTick-style panel: a priority
  /// flag row on top (one tap commits and closes), then the secondary
  /// property entries. Date lives on the fixed chip to the left, so it is
  /// not repeated here.
  Future<void> _openProperties(BuildContext anchor) async {
    setState(() => _propertiesOpen = true);
    final result = await showDesktopPopover<Object>(anchor,
        width: QuickAddMetrics.propertiesPopoverWidth,
        placement: PopoverPlacement.bottomEnd,
        builder: (popoverContext) => _QuickAddPropertiesPanel(
              selectedPriority:
                  priorityOverridden ? currentDraft.priority : parse.priority,
              listLabel: (listOverridden
                      ? currentDraft.listName
                      : parse.listName) ??
                  widget.controller.creationTargetLabel.split(' · ').first,
              selectedTags: tagsOverridden ? currentDraft.tags : parse.tags,
              onPriority: (priority) =>
                  Navigator.of(popoverContext).pop(priority),
              onList: (rowAnchor) => _pickList(rowAnchor,
                  placement: const PopoverPlacement(
                      preferredSide: PopoverSide.right, gap: WorkFollowSpacing.space2)),
              onTags: (rowAnchor) => _pickTags(rowAnchor,
                  placement: const PopoverPlacement(
                      preferredSide: PopoverSide.right, gap: WorkFollowSpacing.space2)),
              onReminder: () =>
                  Navigator.of(popoverContext).pop('reminder'),
              onRepeat: () => Navigator.of(popoverContext).pop('repeat'),
            ));
    if (!mounted) return;
    setState(() => _propertiesOpen = false);
    // Hand focus back so the user can keep typing without a second click.
    focus.requestFocus();
    if (result is TaskPriority) {
      setState(() {
        currentDraft = currentDraft.copyWith(priority: result);
        priorityOverridden = true;
        _refreshDraft(parse);
      });
      return;
    }
    switch (result) {
      case 'list':
        await _pickList(context);
      case 'tags':
        await _pickTags(context);
      case 'reminder':
        await _pickReminder(context);
      case 'repeat':
        await _pickRecurrence(context);
    }
  }

  void submit() {
    if (text.text.trim().isEmpty) return;
    final title = _titleForValue(parse);
    if (title.isEmpty) return;
    // Every parser result and explicit picker change has already been
    // projected into this one Draft. Submission therefore cannot accidentally
    // reintroduce the old add-then-update mutation chain.
    final submittedDraft = currentDraft.copyWith(title: title);
    final result = widget.controller.taskCreator.create(submittedDraft);
    if (!result.success) {
      // A failure gets the error treatment: the message stays longer and never
      // borrows the completion tone.
      final feedback = mounted ? FeedbackScope.maybeOf(context) : null;
      feedback?.show(WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.error,
          message: result.message ?? '无法创建任务'));
      return;
    }
    final id = result.taskId;
    final feedback = mounted ? FeedbackScope.maybeOf(context) : null;
    if (id != null && result.destination != TaskDestination.current) {
      // The new task is not in this list, so say where it went and offer to
      // follow it — an undo here would be the wrong offer.
      feedback?.show(movedAwayFeedback(result,
          onOpen: () => widget.controller.openTask(id)));
    }
    // A task that landed in the list being looked at says nothing on its own:
    // the row that just appeared is the feedback. Its undo still reaches the
    // shell's catch-all watcher, which is where every unreported creation has
    // always been reported from.
    setState(_resetDraft);
    _escapePrimed = false;
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // The disclosure panel keeps the row expanded while it is open: tapping
    // the chevron moves focus out of the TextField, and without this flag the
    // row would collapse (and take the panel's anchor with it).
    final expanded = focused ||
        customDate ||
        text.text.isNotEmpty ||
        parse.spans.isNotEmpty ||
        _propertiesOpen ||
        _scheduleOpen;
    final surfaceDecoration = widget.listStyle
        ? BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(TaskListMetrics.quickAddRadius),
            border: expanded
                ? Border.all(
                    color: WorkFollowColorTokens.quickAddBorder(
                      tokens,
                      expanded: expanded,
                      listStyle: true,
                    ),
                  )
                : null,
          )
        : WorkFollowSurfaceTokens.card(
            tokens,
            color: tokens.content,
            borderColor: WorkFollowColorTokens.quickAddBorder(
              tokens,
              expanded: expanded,
              listStyle: false,
            ),
            elevated: true,
          );
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        },
        child: Container(
          // The list add bar is a quiet neutral slot: no outline, no shadow,
          // 40pt tall. The home card keeps its frame — there it is a call to
          // action, here it is the first line of a list.
          constraints: widget.listStyle
              ? const BoxConstraints(minHeight: TaskListMetrics.quickAddHeight)
              : null,
          decoration: surfaceDecoration,
          padding: EdgeInsets.symmetric(
              horizontal: widget.listStyle
                  ? TaskListMetrics.quickAddHorizontalPadding
                  : WorkFollowSpacing.quickAddFieldHorizontalPadding,
              vertical: widget.listStyle
                  ? WorkFollowSpacing.zero
                  : WorkFollowSpacing.quickAddFieldVerticalPadding),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Row(children: [
              AppIcon(WorkFollowIcons.add,
                  size: widget.listStyle
                      ? WorkFollowMetrics.toolbarIcon
                      : WorkFollowMetrics.headerIcon,
                  color: widget.listStyle
                      ? tokens.textTertiary
                      : tokens.accent),
              const SizedBox(width: WorkFollowSpacing.controlGap),
            Expanded(
                  child: TextField(
                      key: const ValueKey('quick-add-title'),
                      controller: text,
                      focusNode: focus,
                      autofocus: widget.autofocus,
                      onSubmitted: (_) => submit(),
                      onChanged: (_) => _reparse(),
                      textInputAction: TextInputAction.done,
                      // Quick add is an input control, not a task title. Sizing
                      // it with [listTitle] made the placeholder read heavier
                      // than the task rows below it, which have not been
                      // created yet.
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: tokens.textPrimary),
                      decoration: InputDecoration(
                          hintText: widget.listStyle
                              ? '添加任务至“${widget.controller.creationTargetLabel.split(' · ').first}”'
                              : '记下下一件事…',
                          hintStyle: TextStyle(color: tokens.textTertiary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: WorkFollowSpacing.compactInset)))),
              // The list add row keeps two slots right of the field, matching
              // the TickTick reference — but only while selected: an unfocused
              // row shows just "+ placeholder". The inbox shows an icon-only
              // date entry (its tasks start unscheduled); time-based views
              // show "今天" lit in the accent colour.
              if (widget.listStyle && expanded) ...[
                const SizedBox(width: WorkFollowSpacing.inlineGap),
                // Desktop Flutter drops the caret on any pointer-down outside
                // the field's tap region. These two slots are part of the
                // field's own row, so they join its group: tapping the date
                // chip or the disclosure must not end the edit.
                TextFieldTapRegion(
                    child: ExcludeFocus(
                        child: PropertyButton(
                            key: const ValueKey('quick-add-schedule'),
                            icon: WorkFollowIcons.calendar,
                            label: _inboxContext
                                ? ''
                                : calendarDateLabel(_effectiveDue,
                                    hasTime: _effectiveHasTime),
                            active: _scheduleActive,
                            onPressed: _pickSchedule))),
                const SizedBox(width: WorkFollowSpacing.microGap),
                TextFieldTapRegion(
                    child: ExcludeFocus(
                        child: Builder(
                            builder: (anchor) => AppIconButton(
                                key: const ValueKey('quick-add-properties'),
                                icon: WorkFollowIcons.expandMore,
                                tooltip: '更多属性',
                                onPressed: () => _openProperties(anchor),
                                size: WorkFollowMetrics.iconHitTarget,
                                iconSize: WorkFollowMetrics.toolbarIcon)))),
              ],
              // The shortcut still works; it just does not take a slot here. A
              // permanent ⌘N label was the loudest thing on the quiet slot.
              if (!expanded)
                Text('⌘N',
                    style: TextStyle(
                        fontSize: WorkFollowMacTypography.caption,
                        height: WorkFollowMacTypography.lineControl,
                        color: tokens.textTertiary)),
            ]),
            if (parse.spans.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: WorkFollowSpacing.space1, bottom: WorkFollowSpacing.microGap),
                  child: SizedBox(
                      width: double.infinity,
                      child: Wrap(spacing: WorkFollowSpacing.inlineGap, runSpacing: WorkFollowSpacing.inlineGap, children: [
                        for (final span in parse.spans)
                          InputChip(
                              key: ValueKey(parse.spans
                                          .where((other) =>
                                              other.kind == span.kind &&
                                              other.raw == span.raw)
                                          .length >
                                      1
                                  ? 'smart-chip-${_smartSpanKey(span)}'
                                  : 'smart-chip-${span.kind.name}-${span.raw}'),
                              label: Text(span.label,
                                  style: TextStyle(
                                      fontSize: WorkFollowMacTypography.control,
                                      height: WorkFollowMacTypography.lineControl,
                                      fontWeight: WorkFollowMacWeight.medium,
                                      color: _spanColor(span.kind, tokens))),
                              backgroundColor: _spanColor(span.kind, tokens)
                                  .withValues(alpha: .09),
                              side: BorderSide.none,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              deleteIconColor: _spanColor(span.kind, tokens),
                              deleteIcon: const AppIcon(WorkFollowIcons.close,
                                  size: WorkFollowMetrics.metadataIcon),
                              onDeleted: () => _dismissSpan(span)),
                      ]))),
            if (expanded && parse.hasStructure && _summary.isNotEmpty)
              Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.only(left: WorkFollowSpacing.nestedContentIndent, top: WorkFollowSpacing.hairlineGap),
                      child: Text(_summary,
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: WorkFollowMacTypography.supporting,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.medium)))),
            // The list add row carries its two fixed slots up in the main
            // line now, so this expanded property strip only remains on the
            // fuller home-card variant.
            if (expanded && !widget.listStyle)
              Padding(
                  padding: const EdgeInsets.only(top: WorkFollowSpacing.denseGap, bottom: WorkFollowSpacing.space1),
                  child: Row(children: [
                    Expanded(
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: TextFieldTapRegion(
                                child: ExcludeFocus(
                                    child: Row(children: [
                              PropertyButton(
                                  key: const ValueKey('quick-add-schedule'),
                                  icon: WorkFollowIcons.calendar,
                                  label: calendarDateLabel(_effectiveDue,
                                      hasTime: _effectiveHasTime),
                                  active: _scheduleActive,
                                  onPressed: _pickSchedule),
                              if (!widget.listStyle) ...[
                                const SizedBox(width: WorkFollowSpacing.inlineGap),
                                PropertyButton(
                                    key: const ValueKey('quick-add-priority'),
                                    icon: WorkFollowIcons.flag,
                                    label: currentDraft.priority ==
                                            TaskPriority.none
                                        ? '优先级'
                                        : currentDraft.priority.label,
                                    active: currentDraft.priority !=
                                        TaskPriority.none,
                                    onPressed: _pickPriority),
                                const SizedBox(width: WorkFollowSpacing.inlineGap),
                                PropertyButton(
                                    key: const ValueKey('quick-add-list'),
                                    icon: WorkFollowIcons.inbox,
                                    label: currentDraft.listName ??
                                        widget.controller.creationTargetLabel
                                            .split(' · ')
                                            .first,
                                    active: currentDraft.listName != null,
                                    onPressed: _pickList),
                                const SizedBox(width: WorkFollowSpacing.inlineGap),
                                PropertyButton(
                                    key: const ValueKey('quick-add-tags'),
                                    icon: WorkFollowIcons.tag,
                                    label: currentDraft.tags.isEmpty
                                        ? '标签'
                                        : currentDraft.tags
                                            .map((tag) => '#$tag')
                                            .join(' '),
                                    active: currentDraft.tags.isNotEmpty,
                                    onPressed: _pickTags),
                                const SizedBox(width: WorkFollowSpacing.inlineGap),
                                PropertyButton(
                                    key: const ValueKey('quick-add-reminder'),
                                    icon: WorkFollowIcons.reminder,
                                    label: currentDraft.reminderAt == null
                                        ? '提醒'
                                        : calendarDateLabel(
                                            currentDraft.reminderAt,
                                            hasTime: true),
                                    active: currentDraft.reminderAt != null,
                                    onPressed: _pickReminder),
                                const SizedBox(width: WorkFollowSpacing.inlineGap),
                                PropertyButton(
                                    key: const ValueKey('quick-add-repeat'),
                                    icon: WorkFollowIcons.repeat,
                                    label: '重复',
                                    active: currentDraft.recurrence.enabled,
                                    onPressed: _pickRecurrence),
                              ],
                            ]))))),
                    FilledButton(
                          onPressed: text.text.trim().isEmpty ? null : submit,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(
                                  0, WorkFollowMetrics.compactButtonHeight),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space3)),
                          child: const Text('添加任务',
                              style: TextStyle(
                                  fontSize: WorkFollowMacTypography.control))),
                  ])),
          ]),
        ));
  }

  Color _spanColor(SmartTokenKind kind, WorkFollowTheme tokens) =>
      _smartTokenColor(kind, tokens);

  String get _summary {
    final parts = <String>[];
    final summaryDate = _effectiveDue;
    final summaryHasTime = _effectiveHasTime;
    if (summaryDate != null) {
      parts.add(calendarDateLabel(summaryDate, hasTime: summaryHasTime));
    }
    final summaryReminder = currentDraft.reminderAt;
    if (summaryReminder != null) parts.add('提醒');
    final recurrence = currentDraft.recurrence;
    if (recurrence.enabled) {
      parts.add(switch (recurrence.type) {
        'DAILY' => '每天',
        'WEEKLY' => '每周',
        'MONTHLY' => '每月',
        _ => '重复',
      });
    }
    final summaryTags = currentDraft.tags;
    if (summaryTags.isNotEmpty)
      parts.add(summaryTags.map((tag) => '#$tag').join(' '));
    final summaryList = currentDraft.listName;
    if (summaryList != null) parts.add('@$summaryList');
    final summaryPriority = currentDraft.priority;
    if (summaryPriority != TaskPriority.none) parts.add(summaryPriority.label);
    return parts.isEmpty ? '' : '→ ${parts.join(' · ')}';
  }
}

/// The secondary-property surface for the compact list add row.
///
/// List and tag pickers are intentionally opened from their own rows instead
/// of closing this surface first. That keeps the parent menu visible while the
/// child popover is anchored to the row the user selected, matching the
/// desktop reference and making the relationship between the two surfaces
/// obvious.
class _QuickAddPropertiesPanel extends StatefulWidget {
  const _QuickAddPropertiesPanel({
    required this.selectedPriority,
    required this.listLabel,
    required this.selectedTags,
    required this.onPriority,
    required this.onList,
    required this.onTags,
    required this.onReminder,
    required this.onRepeat,
  });

  final TaskPriority selectedPriority;
  final String listLabel;
  final List<String> selectedTags;
  final ValueChanged<TaskPriority> onPriority;
  final Future<String?> Function(BuildContext) onList;
  final Future<String?> Function(BuildContext) onTags;
  final VoidCallback onReminder;
  final VoidCallback onRepeat;

  @override
  State<_QuickAddPropertiesPanel> createState() =>
      _QuickAddPropertiesPanelState();
}

class _QuickAddPropertiesPanelState extends State<_QuickAddPropertiesPanel> {
  late TaskPriority selectedPriority = widget.selectedPriority;
  late String listLabel = widget.listLabel;
  late List<String> selectedTags = List<String>.from(widget.selectedTags);
  String? openSubmenu;

  Future<void> _openList(BuildContext anchor) async {
    if (openSubmenu != null) return;
    setState(() => openSubmenu = 'list');
    final value = await widget.onList(anchor);
    if (!mounted) return;
    setState(() {
      openSubmenu = null;
      if (value != null) listLabel = value;
    });
  }

  Future<void> _openTags(BuildContext anchor) async {
    if (openSubmenu != null) return;
    setState(() => openSubmenu = 'tags');
    final value = await widget.onTags(anchor);
    if (!mounted) return;
    setState(() {
      openSubmenu = null;
      if (value != null) selectedTags = _parseTags(value);
    });
  }

  List<String> _parseTags(String value) => value
      .split(RegExp('[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // The panel is an extension of the add row, so it joins the field's tap
    // group too: setting a priority from here must not end the edit.
    return TextFieldTapRegion(
      child: Padding(
      key: const ValueKey('quick-add-properties-panel'),
      padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.relaxedGap, WorkFollowSpacing.inlineGap, WorkFollowSpacing.relaxedGap, WorkFollowSpacing.microGap),
            child: Text(
              '优先级',
              style: TextStyle(
                fontSize: WorkFollowMacTypography.supporting,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular,
                color: tokens.textTertiary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.cardInset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final priority in TaskPriority.values)
                  _priorityFlag(tokens, priority),
              ],
            ),
          ),
          const SizedBox(height: WorkFollowSpacing.inlineGap),
          _submenuRow(
            action: 'list',
            icon: WorkFollowIcons.inbox,
            label: listLabel,
            onOpen: _openList,
          ),
          _submenuRow(
            action: 'tags',
            icon: WorkFollowIcons.tag,
            label: selectedTags.isEmpty
                ? '标签'
                : selectedTags.map((tag) => '#$tag').join(' '),
            onOpen: _openTags,
          ),
          _propertiesRow(
            entryKey: 'menu-option-reminder',
            icon: WorkFollowIcons.reminder,
            label: '提醒',
            onTap: widget.onReminder,
          ),
          _propertiesRow(
            entryKey: 'menu-option-repeat',
            icon: WorkFollowIcons.repeat,
            label: '重复',
            onTap: widget.onRepeat,
          ),
        ],
      ),
      ),
    );
  }

  Widget _priorityFlag(WorkFollowTheme tokens, TaskPriority priority) {
    final color = switch (priority) {
      TaskPriority.high => tokens.danger,
      TaskPriority.medium => tokens.warning,
      TaskPriority.low => tokens.accent,
      TaskPriority.none => tokens.borderStrong,
    };
    return InkWell(
      key: ValueKey('quick-add-priority-flag-${priority.name}'),
      borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      onTap: () => widget.onPriority(priority),
      child: Container(
        width: QuickAddMetrics.priorityFlagWidth,
        height: QuickAddMetrics.priorityFlagHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: priority == selectedPriority ? tokens.listRowHover : null,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        ),
        child: AppIcon(
          WorkFollowIcons.flag,
          size: WorkFollowMetrics.fieldIcon,
          color: color,
        ),
      ),
    );
  }

  Widget _submenuRow({
    required String action,
    required IconData icon,
    required String label,
    required Future<void> Function(BuildContext) onOpen,
  }) {
    return Builder(
      builder: (rowAnchor) => _propertiesRow(
        entryKey: 'menu-option-$action',
        icon: icon,
        label: label,
        trailing: true,
        active: openSubmenu == action,
        onTap: () => onOpen(rowAnchor),
      ),
    );
  }

  Widget _propertiesRow({
    required String entryKey,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool trailing = false,
    bool active = false,
  }) {
    final tokens = WorkFollowTheme.of(context);
    return InkWell(
      key: ValueKey(entryKey),
      borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      hoverColor: tokens.listRowHover,
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: active ? tokens.listRowHover : null,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.relaxedGap, vertical: WorkFollowSpacing.compactInset),
          child: Row(
            children: [
              AppIcon(
                icon,
                size: WorkFollowMetrics.compactFieldIcon,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: WorkFollowSpacing.controlGap),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: WorkFollowMacTypography.control,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.regular,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (trailing)
                AppIcon(
                  WorkFollowIcons.next,
                  size: WorkFollowMetrics.metadataIcon,
                  color: tokens.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
