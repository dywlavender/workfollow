import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../services/smart_date_parser.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';

class QuickAddField extends StatefulWidget {
  const QuickAddField(
      {super.key, required this.controller, this.autofocus = false});
  final WorkspaceController controller;
  final bool autofocus;
  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final text = TextEditingController();
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
  final Set<String> dismissedSpans = {};

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
    final result = parser.parse(text.text);
    final kept = result.spans
        .where((span) => !dismissedSpans.contains(span.raw))
        .toList();
    bool keptKind(SmartTokenKind kind) =>
        kept.any((span) => span.kind == kind);
    setState(() => parse = SmartParseResult(
        title: parser.titleFromSpans(text.text, kept),
        dueAt: keptKind(SmartTokenKind.date) || keptKind(SmartTokenKind.time)
            ? result.dueAt
            : null,
        hasTime:
            (keptKind(SmartTokenKind.date) || keptKind(SmartTokenKind.time)) &&
                result.hasTime,
        reminderAt:
            keptKind(SmartTokenKind.time) ||
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
        listName:
            keptKind(SmartTokenKind.list) ? result.listName : null,
        priority: keptKind(SmartTokenKind.priority)
            ? result.priority
            : TaskPriority.none,
        spans: kept));
  }

  void _dismissSpan(SmartSpan span) {
    dismissedSpans.add(span.raw);
    _reparse();
  }

  void submit() {
    final draft = text.text.trim();
    if (draft.isEmpty) return;
    final parsed = parse;
    // Only trust a list token that matches an existing list, so typos never
    // create lists implicitly.
    final listName = parsed.listName != null &&
            widget.controller.lists.any((list) => list.name == parsed.listName)
        ? parsed.listName
        : null;
    // An unknown @marker is not allowed to create a list, but it remains in
    // the title so a typo is never silently lost.
    final titleSpans = parsed.spans
        .where((span) =>
            span.kind != SmartTokenKind.list || span.raw == '@$listName')
        .toList();
    final title = parser.titleFromSpans(text.text, titleSpans);
    final smartDue = parsed.dueAt;
    final manualDue = customDate ? selectedDate : null;
    final effectiveDue = smartDue ?? manualDue;
    final dismissedScheduling = parser
        .parse(text.text)
        .spans
        .any((span) =>
            (span.kind == SmartTokenKind.date ||
                span.kind == SmartTokenKind.time) &&
            dismissedSpans.contains(span.raw));
    if (title.isEmpty) return;
    if (!widget.controller.addTask(title,
        listName: listName,
        dueAt: effectiveDue,
        forceUnscheduled:
            (customDate && manualDue == null && smartDue == null) ||
                (dismissedScheduling &&
                    manualDue == null &&
                    smartDue == null))) {
      return;
    }
    final id = widget.controller.tasks.first.id;
    final c = widget.controller;
    if (parsed.recurrenceType != 'NONE') {
      c.updateTaskRecurrence(id, parsed.recurrenceType,
          config: parsed.recurrenceConfig);
    }
    if (parsed.priority != TaskPriority.none) {
      c.updateTaskPriority(id, parsed.priority);
    }
    if (parsed.tags.isNotEmpty) c.updateTaskTags(id, parsed.tags);
    if (parsed.hasTime && smartDue != null) {
      c.updateTaskDue(id, smartDue, hasTime: true);
      c.updateTaskReminder(id, parsed.reminderAt ?? smartDue);
    }
    if (!c.visibleTasks.any((task) => task.id == id)) {
      final destination = effectiveDue == null
          ? '收集箱'
          : calendarDateLabel(effectiveDue,
              hasTime: parsed.hasTime || hasTime);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已添加到$destination'),
        action: SnackBarAction(
            label: '查看任务', onPressed: () => widget.controller.openTask(id)),
      ));
    }
    setState(() {
      text.clear();
      customDate = false;
      selectedDate = null;
      hasTime = false;
      dismissedSpans.clear();
      parse = _emptyParse;
    });
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final expanded = focused ||
        customDate ||
        text.text.isNotEmpty ||
        parse.spans.isNotEmpty;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            setState(() {
              text.clear();
              customDate = false;
              dismissedSpans.clear();
              parse = _emptyParse;
            });
            focus.unfocus();
          }
        },
        child: Container(
          decoration: BoxDecoration(
              color: tokens.content,
              borderRadius: BorderRadius.circular(12),
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
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.add, size: 19, color: tokens.accent),
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
                          hintText: '记下下一件事…',
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
                      child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final span in parse.spans)
                              InputChip(
                                  key: ValueKey(
                                      'smart-chip-${span.kind.name}-${span.raw}'),
                                  label: Text(span.label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _spanColor(span.kind, tokens))),
                                  backgroundColor:
                                      _spanColor(span.kind, tokens)
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
                    Flexible(
                        child: PropertyButton(
                            icon: Icons.calendar_today_outlined,
                            label: calendarDateLabel(
                                customDate
                                    ? selectedDate
                                    : widget.controller.creationDate,
                                hasTime: hasTime),
                            active: customDate
                                ? selectedDate != null
                                : widget.controller.creationDate != null,
                            onPressed: (anchor) async {
                              final result = await showTaskDatePicker(anchor,
                                  value: (customDate
                                          ? selectedDate
                                          : widget.controller.creationDate)
                                      ?.toIso8601String(),
                                  hasTime: hasTime);
                              if (result != null && mounted)
                                setState(() {
                                  customDate = true;
                                  selectedDate = result.date;
                                  hasTime = result.hasTime;
                                });
                            })),
                    const Spacer(),
                    FilledButton(
                        onPressed: text.text.trim().isEmpty ? null : submit,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 30),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12)),
                        child:
                            const Text('添加任务', style: TextStyle(fontSize: 12))),
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
    if (parse.dueAt != null) {
      parts.add(calendarDateLabel(parse.dueAt, hasTime: parse.hasTime));
    }
    if (parse.reminderAt != null) parts.add('提醒');
    if (parse.recurrenceType != 'NONE') {
      parts.add(switch (parse.recurrenceType) {
        'DAILY' => '每天',
        'WEEKLY' => '每周',
        'MONTHLY' => '每月',
        _ => '重复',
      });
    }
    if (parse.tags.isNotEmpty) parts.add(parse.tags.map((tag) => '#$tag').join(' '));
    if (parse.listName != null) parts.add('@${parse.listName}');
    if (parse.priority != TaskPriority.none) parts.add(parse.priority.label);
    return parts.isEmpty ? '' : '→ ${parts.join(' · ')}';
  }
}
