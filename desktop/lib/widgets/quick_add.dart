import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../services/smart_date_parser.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_draft.dart';
import '../features/tasks/domain/task_schedule.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';
import 'task_schedule_picker.dart';
import 'task_priority_picker.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';
import 'task_reminder_picker.dart';
import 'task_repeat_picker.dart';

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
        .where((span) => !_dismissed.contains(span.raw))
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
  bool customDate = false;
  DateTime? selectedDate;
  bool hasTime = false;

  // Natural-language state (TickTick-style 智能识别): the draft is parsed
  // live, each recognised token shows as a removable chip, and dismissed
  // chips fall back to plain-title behaviour for their aspect.
  static const parser = SmartDateParser();
  SmartParseResult parse = _emptyParse;
  TaskDraft currentDraft = const TaskDraft(title: '');
  final Set<String> dismissedSpans = {};
  TaskPriority? manualPriority;
  String? manualListName;
  List<String>? manualTags;
  DateTime? manualReminder;
  RecurrenceDraft? manualRecurrence;
  bool listOverridden = false;
  bool tagsOverridden = false;
  bool reminderOverridden = false;
  bool recurrenceOverridden = false;
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
        .where((span) => !dismissedSpans.contains(span.raw))
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
        .where((span) => dismissedSpans.contains(span.raw))
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
    currentDraft = TaskDraft(
      title: value.title,
      listName: listOverridden ? manualListName : parsedList,
      schedule: TaskScheduleDraft(
        dueAt: customDate ? selectedDate : value.dueAt ?? defaultDue,
        hasTime: customDate ? hasTime : value.hasTime,
      ),
      reminderAt: reminderOverridden
          ? manualReminder
          : (!customDate && value.hasTime ? value.reminderAt : null),
      recurrence: recurrenceOverridden
          ? (manualRecurrence ?? const RecurrenceDraft())
          : RecurrenceDraft(
              type: value.recurrenceType, config: value.recurrenceConfig),
      priority: manualPriority ?? value.priority,
      tags: tagsOverridden ? (manualTags ?? const <String>[]) : value.tags,
      forceUnscheduled: (customDate && selectedDate == null) ||
          (!hasSchedulingToken && dismissedScheduling),
    );
  }

  bool get _hasDismissedScheduling =>
      dismissedSpans.any((raw) => parser.parse(raw).spans.any((span) =>
          span.kind == SmartTokenKind.date ||
          span.kind == SmartTokenKind.time));

  DateTime? get _effectiveDue => customDate
      ? selectedDate
      : parse.dueAt ??
          (_hasDismissedScheduling ? null : widget.controller.creationDate);

  bool get _effectiveHasTime => customDate ? hasTime : parse.hasTime;

  void _dismissSpan(SmartSpan span) {
    dismissedSpans.add(span.raw);
    _reparse();
  }

  void _resetDraft() {
    text.clear();
    text.setHighlights(const [], const {});
    customDate = false;
    selectedDate = null;
    hasTime = false;
    manualPriority = null;
    manualListName = null;
    manualTags = null;
    manualReminder = null;
    manualRecurrence = null;
    listOverridden = false;
    tagsOverridden = false;
    reminderOverridden = false;
    recurrenceOverridden = false;
    dismissedSpans.clear();
    parse = _emptyParse;
    currentDraft = const TaskDraft(title: '');
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
        selected: manualPriority ?? parse.priority);
    if (!mounted || value == null) return;
    setState(() {
      manualPriority = value;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickList(BuildContext anchor) async {
    final value = await TaskListPicker.show(anchor,
        controller: widget.controller,
        selected: manualListName ?? parse.listName);
    if (!mounted || value == null) return;
    setState(() {
      manualListName = value;
      listOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickTags(BuildContext anchor) async {
    final value = await TaskTagPicker.show(anchor,
        initial: (manualTags ?? parse.tags).join('，'));
    if (!mounted || value == null) return;
    setState(() {
      manualTags = value
          .split(RegExp('[,，]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
      tagsOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickReminder(BuildContext anchor) async {
    final current = manualReminder ?? parse.reminderAt;
    final value = await TaskReminderPicker.show(anchor,
        value: current?.toIso8601String());
    if (!mounted || value == null) return;
    setState(() {
      manualReminder = value.date;
      reminderOverridden = true;
      _refreshDraft(parse);
    });
  }

  Future<void> _pickRecurrence(BuildContext anchor) async {
    final recurrence = manualRecurrence ??
        RecurrenceDraft(
            type: parse.recurrenceType, config: parse.recurrenceConfig);
    final task = TaskItem(
      id: 'draft',
      title: text.text.trim().isEmpty ? '新任务' : text.text.trim(),
      listName: manualListName ?? parse.listName ?? '收集箱',
      bucket: TaskBucket.unscheduled,
      recurrenceType: recurrence.type,
      recurrenceConfig: recurrence.config,
      dueAt: (customDate ? selectedDate : parse.dueAt)?.toIso8601String(),
    );
    final value = await TaskRepeatPicker.show(anchor, task: task);
    if (!mounted || value == null) return;
    setState(() {
      manualRecurrence = value;
      recurrenceOverridden = true;
      _refreshDraft(parse);
    });
  }

  void submit() {
    final draft = text.text.trim();
    if (draft.isEmpty) return;
    final parsed = parse;
    // Only trust a list token that matches an existing list, so typos never
    // create lists implicitly.
    final parsedListName = parsed.listName != null &&
            widget.controller.lists.any((list) => list.name == parsed.listName)
        ? parsed.listName
        : null;
    final listName = listOverridden ? manualListName : parsedListName;
    // An unknown @marker is not allowed to create a list, but it remains in
    // the title so a typo is never silently lost.
    final titleSpans = parsed.spans
        .where((span) =>
            span.kind != SmartTokenKind.list ||
            (listName != null && span.raw == '@$listName'))
        .toList();
    final title = parser.titleFromSpans(text.text, titleSpans);
    final smartDue = parsed.dueAt;
    final manualDue = customDate ? selectedDate : null;
    final dismissedScheduling = _hasDismissedScheduling;
    final effectiveDue = _effectiveDue;
    if (title.isEmpty) return;
    final finalPriority = manualPriority ?? parsed.priority;
    final finalTags =
        tagsOverridden ? (manualTags ?? const <String>[]) : parsed.tags;
    final finalRecurrence = recurrenceOverridden
        ? (manualRecurrence ?? const RecurrenceDraft())
        : RecurrenceDraft(
            type: parsed.recurrenceType, config: parsed.recurrenceConfig);
    final finalReminder = reminderOverridden
        ? manualReminder
        : (!customDate && parsed.hasTime
            ? parsed.reminderAt ?? smartDue
            : null);
    currentDraft = TaskDraft(
      title: title,
      listName: listName,
      schedule: TaskScheduleDraft(
        dueAt: effectiveDue,
        hasTime: _effectiveHasTime,
      ),
      reminderAt: finalReminder,
      recurrence: finalRecurrence,
      priority: finalPriority,
      tags: finalTags,
      forceUnscheduled: (customDate && manualDue == null && smartDue == null) ||
          (dismissedScheduling && manualDue == null && smartDue == null),
    );
    final result = widget.controller.taskCreator.create(currentDraft);
    if (!result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message ?? '无法创建任务')));
      }
      return;
    }
    final id = result.taskId;
    if (id != null && result.destination != TaskDestination.current) {
      final destination = effectiveDue == null
          ? '收集箱'
          : calendarDateLabel(effectiveDue, hasTime: parsed.hasTime || hasTime);
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
              borderRadius: BorderRadius.circular(widget.listStyle ? 9 : 12),
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
              Icon(Icons.add,
                  size: widget.listStyle ? 18 : 19, color: tokens.accent),
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
                              key: ValueKey(
                                  'smart-chip-${span.kind.name}-${span.raw}'),
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
                              deleteIcon: const Icon(Icons.close, size: 13),
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
                                  icon: Icons.calendar_today_outlined,
                                  label: calendarDateLabel(_effectiveDue,
                                      hasTime: _effectiveHasTime),
                                  active: customDate
                                      ? selectedDate != null
                                      : parse.dueAt != null ||
                                          (!_hasDismissedScheduling &&
                                              widget.controller.creationDate !=
                                                  null),
                                  onPressed: (anchor) async {
                                    final result =
                                        await TaskSchedulePicker.show(anchor,
                                            value: _effectiveDue
                                                ?.toIso8601String(),
                                            hasTime: _effectiveHasTime);
                                    if (result != null && mounted)
                                      setState(() {
                                        customDate = true;
                                        selectedDate = result.date;
                                        hasTime = result.hasTime;
                                        _refreshDraft(parse);
                                      });
                                  }),
                              const SizedBox(width: 6),
                              PropertyButton(
                                  key: const ValueKey('quick-add-priority'),
                                  icon: Icons.flag_outlined,
                                  label: (manualPriority ?? parse.priority) ==
                                          TaskPriority.none
                                      ? '优先级'
                                      : (manualPriority ?? parse.priority)
                                          .label,
                                  active: (manualPriority ?? parse.priority) !=
                                      TaskPriority.none,
                                  onPressed: _pickPriority),
                              const SizedBox(width: 6),
                              PropertyButton(
                                  key: const ValueKey('quick-add-list'),
                                  icon: Icons.inbox_outlined,
                                  label: manualListName ??
                                      parse.listName ??
                                      widget.controller.creationTargetLabel
                                          .split(' · ')
                                          .first,
                                  active:
                                      listOverridden || parse.listName != null,
                                  onPressed: _pickList),
                              const SizedBox(width: 6),
                              PropertyButton(
                                  key: const ValueKey('quick-add-tags'),
                                  icon: Icons.tag_rounded,
                                  label: (manualTags ?? parse.tags).isEmpty
                                      ? '标签'
                                      : (manualTags ?? parse.tags)
                                          .map((tag) => '#$tag')
                                          .join(' '),
                                  active: tagsOverridden
                                      ? (manualTags?.isNotEmpty ?? false)
                                      : parse.tags.isNotEmpty,
                                  onPressed: _pickTags),
                              const SizedBox(width: 6),
                              PropertyButton(
                                  key: const ValueKey('quick-add-reminder'),
                                  icon: Icons.notifications_none_rounded,
                                  label: reminderOverridden
                                      ? (manualReminder == null
                                          ? '提醒'
                                          : calendarDateLabel(manualReminder,
                                              hasTime: true))
                                      : (parse.reminderAt == null
                                          ? '提醒'
                                          : calendarDateLabel(parse.reminderAt,
                                              hasTime: true)),
                                  active: reminderOverridden
                                      ? manualReminder != null
                                      : parse.reminderAt != null,
                                  onPressed: _pickReminder),
                              const SizedBox(width: 6),
                              PropertyButton(
                                  key: const ValueKey('quick-add-repeat'),
                                  icon: Icons.repeat_rounded,
                                  label: (manualRecurrence?.enabled ??
                                          (parse.recurrenceType != 'NONE'))
                                      ? '重复'
                                      : '重复',
                                  active: manualRecurrence?.enabled ??
                                      parse.recurrenceType != 'NONE',
                                  onPressed: _pickRecurrence),
                            ]))),
                    if (widget.listStyle)
                      Text('Return 添加',
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500))
                    else
                      FilledButton(
                          onPressed: text.text.trim().isEmpty ? null : submit,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 30),
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
    final summaryReminder =
        reminderOverridden ? manualReminder : parse.reminderAt;
    if (summaryReminder != null) parts.add('提醒');
    final recurrence = manualRecurrence ??
        RecurrenceDraft(
            type: parse.recurrenceType, config: parse.recurrenceConfig);
    if (recurrence.enabled) {
      parts.add(switch (recurrence.type) {
        'DAILY' => '每天',
        'WEEKLY' => '每周',
        'MONTHLY' => '每月',
        _ => '重复',
      });
    }
    final summaryTags =
        tagsOverridden ? (manualTags ?? const <String>[]) : parse.tags;
    if (summaryTags.isNotEmpty)
      parts.add(summaryTags.map((tag) => '#$tag').join(' '));
    final summaryList = listOverridden ? manualListName : parse.listName;
    if (summaryList != null) parts.add('@$summaryList');
    final summaryPriority = manualPriority ?? parse.priority;
    if (summaryPriority != TaskPriority.none) parts.add(summaryPriority.label);
    return parts.isEmpty ? '' : '→ ${parts.join(' · ')}';
  }
}
