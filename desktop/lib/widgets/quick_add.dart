import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../services/smart_date_parser.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';
import 'task_schedule_picker.dart';
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
      final color = _colorFor(span.kind);
      children.add(TextSpan(
          text: text.substring(span.start, end),
          style: (style ?? const TextStyle()).copyWith(
              color: color,
              backgroundColor: color.withValues(alpha: .14),
              fontWeight: FontWeight.w600)));
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }

  Color _colorFor(SmartTokenKind kind) => switch (kind) {
        SmartTokenKind.date => const Color(0xFF5B7CFA),
        SmartTokenKind.time => const Color(0xFF2F9FB5),
        SmartTokenKind.recurrence => const Color(0xFF9A63D3),
        SmartTokenKind.tag => const Color(0xFF42A66A),
        SmartTokenKind.list => const Color(0xFFE8793F),
        SmartTokenKind.priority => const Color(0xFFE35D6A),
      };
}

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
        !hasSchedulingToken && !dismissedScheduling && !customDate
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
          (_hasDismissedScheduling ? null : widget.controller.creationDate);

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

  Future<void> _pickList(BuildContext anchor) async {
    final value = await TaskListPicker.show(anchor,
        controller: widget.controller,
        selected: listOverridden ? currentDraft.listName : parse.listName);
    if (!mounted || value == null) return;
    setState(() {
      currentDraft = currentDraft.copyWith(listName: value);
      listOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickTags(BuildContext anchor) async {
    final value = await TaskTagPicker.show(anchor,
        initial: (tagsOverridden ? currentDraft.tags : parse.tags).join('，'));
    if (!mounted || value == null) return;
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
    final result = await TaskSchedulePicker.show(anchor,
        value: _effectiveDue?.toIso8601String(), hasTime: _effectiveHasTime);
    if (result != null && mounted) {
      setState(() {
        currentDraft = currentDraft.copyWith(
            schedule:
                TaskScheduleDraft(dueAt: result.date, hasTime: result.hasTime));
        scheduleOverridden = true;
        _refreshDraft(parse);
      });
    }
  }

  /// Keep the task-list add row quiet by putting secondary properties behind
  /// the same compact disclosure affordance used by TickTick. The richer
  /// home-card variant still exposes its property buttons inline.
  Future<void> _openProperties(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(anchor,
        placement: PopoverPlacement.topEnd,
        entries: const [
          DesktopMenuEntry('schedule', '安排日期…', icon: WorkFollowIcons.calendar),
          DesktopMenuEntry('priority', '优先级', icon: WorkFollowIcons.flag),
          DesktopMenuEntry('list', '清单', icon: WorkFollowIcons.inbox),
          DesktopMenuEntry('tags', '标签', icon: WorkFollowIcons.tag),
          DesktopMenuEntry('reminder', '提醒', icon: WorkFollowIcons.reminder),
          DesktopMenuEntry('repeat', '重复', icon: WorkFollowIcons.repeat),
        ]);
    if (!mounted || action == null) return;
    // Closing the first menu can rebuild the inline row (especially while the
    // field is focused), which invalidates the menu button's Builder context.
    // Re-anchor the second picker to this State's stable context instead of
    // trying to reuse a defunct overlay element.
    final pickerAnchor = context;
    switch (action) {
      case 'schedule':
        await _pickSchedule(pickerAnchor);
      case 'priority':
        await _pickPriority(pickerAnchor);
      case 'list':
        await _pickList(pickerAnchor);
      case 'tags':
        await _pickTags(pickerAnchor);
      case 'reminder':
        await _pickReminder(pickerAnchor);
      case 'repeat':
        await _pickRecurrence(pickerAnchor);
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message ?? '无法创建任务')));
      }
      return;
    }
    final id = result.taskId;
    if (id != null && result.destination != TaskDestination.current) {
      final destination = submittedDraft.schedule.normalizedDueAt == null
          ? '收集箱'
          : calendarDateLabel(submittedDraft.schedule.normalizedDueAt,
              hasTime: submittedDraft.schedule.hasTime);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message ?? '已添加到$destination'),
        action: SnackBarAction(
            label: '查看任务', onPressed: () => widget.controller.openTask(id)),
      ));
    }
    setState(_resetDraft);
    _escapePrimed = false;
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final expanded =
        focused || customDate || text.text.isNotEmpty || parse.spans.isNotEmpty;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        },
        child: Container(
          decoration: BoxDecoration(
              color: tokens.content,
              borderRadius: BorderRadius.circular(widget.listStyle
                  ? WorkFollowRadii.control
                  : WorkFollowRadii.card),
              border: Border.all(
                  color: expanded
                      ? tokens.accent.withValues(alpha: .55)
                      : tokens.borderStrong),
              boxShadow: [
                BoxShadow(
                    color: tokens.shadow,
                    blurRadius: expanded ? 16 : 8,
                    offset: const Offset(0, 2))
              ]),
          padding: EdgeInsets.symmetric(
              horizontal: widget.listStyle ? 12 : 15,
              vertical: widget.listStyle ? 5 : 7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              AppIcon(WorkFollowIcons.add,
                  size: widget.listStyle
                      ? WorkFollowMetrics.navigationIcon
                      : WorkFollowMetrics.headerIcon,
                  color: tokens.accent),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      key: const ValueKey('quick-add-title'),
                      controller: text,
                      focusNode: focus,
                      autofocus: widget.autofocus,
                      onSubmitted: (_) => submit(),
                      onChanged: (_) => _reparse(),
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                      decoration: InputDecoration(
                          hintText: widget.listStyle
                              ? '添加任务至“${widget.controller.creationTargetLabel.split(' · ').first}”'
                              : '记下下一件事…',
                          hintStyle: TextStyle(color: tokens.textTertiary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 9)))),
              if (!expanded)
                Text('⌘N',
                    style: TextStyle(fontSize: 10, color: tokens.textTertiary)),
            ]),
            if (parse.spans.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: SizedBox(
                      width: double.infinity,
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
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
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
                      padding: const EdgeInsets.only(left: 29, top: 1),
                      child: Text(_summary,
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500)))),
            if (expanded)
              Padding(
                  padding: const EdgeInsets.only(top: 5, bottom: 4),
                  child: Row(children: [
                    Expanded(
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              PropertyButton(
                                  key: const ValueKey('quick-add-schedule'),
                                  icon: WorkFollowIcons.calendar,
                                  label: calendarDateLabel(_effectiveDue,
                                      hasTime: _effectiveHasTime),
                                  active: customDate
                                      ? selectedDate != null
                                      : parse.dueAt != null ||
                                          (!_hasDismissedScheduling &&
                                              widget.controller.creationDate !=
                                                  null),
                                  onPressed: _pickSchedule),
                              if (!widget.listStyle) ...[
                                const SizedBox(width: 6),
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
                                const SizedBox(width: 6),
                                PropertyButton(
                                    key: const ValueKey('quick-add-list'),
                                    icon: WorkFollowIcons.inbox,
                                    label: currentDraft.listName ??
                                        widget.controller.creationTargetLabel
                                            .split(' · ')
                                            .first,
                                    active: currentDraft.listName != null,
                                    onPressed: _pickList),
                                const SizedBox(width: 6),
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
                                const SizedBox(width: 6),
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
                                const SizedBox(width: 6),
                                PropertyButton(
                                    key: const ValueKey('quick-add-repeat'),
                                    icon: WorkFollowIcons.repeat,
                                    label: '重复',
                                    active: currentDraft.recurrence.enabled,
                                    onPressed: _pickRecurrence),
                              ],
                            ]))),
                    if (widget.listStyle) ...[
                      const Spacer(),
                      Builder(
                          builder: (anchor) => AppIconButton(
                              key: const ValueKey('quick-add-properties'),
                              icon: WorkFollowIcons.expandMore,
                              tooltip: '更多属性',
                              onPressed: () => _openProperties(anchor),
                              size: WorkFollowMetrics.iconHitTarget,
                              iconSize: WorkFollowMetrics.toolbarIcon)),
                    ] else
                      FilledButton(
                          onPressed: text.text.trim().isEmpty ? null : submit,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(
                                  0, WorkFollowMetrics.compactButtonHeight),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text('添加任务',
                              style: TextStyle(fontSize: 12))),
                  ])),
          ]),
        ));
  }

  Color _spanColor(SmartTokenKind kind, WorkFollowTheme tokens) =>
      switch (kind) {
        SmartTokenKind.date || SmartTokenKind.time => tokens.accent,
        SmartTokenKind.recurrence => tokens.success,
        SmartTokenKind.tag => tokens.warning,
        SmartTokenKind.list || SmartTokenKind.priority => tokens.danger,
      };

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
