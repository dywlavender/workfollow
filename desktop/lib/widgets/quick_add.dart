import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  void submit() {
    if (!widget.controller.addTask(text.text,
        dueAt: customDate ? selectedDate : null,
        forceUnscheduled: customDate && selectedDate == null)) return;
    final id = widget.controller.tasks.first.id;
    if (customDate)
      widget.controller.updateTaskDue(id, selectedDate, hasTime: hasTime);
    if (!widget.controller.visibleTasks.any((task) => task.id == id)) {
      final destination =
          calendarDateLabel(selectedDate, hasTime: hasTime, empty: '收集箱');
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
    });
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final expanded = focused || customDate || text.text.isNotEmpty;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            setState(() {
              text.clear();
              customDate = false;
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
                      onChanged: (_) => setState(() {}),
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
}
