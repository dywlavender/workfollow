import 'package:flutter/material.dart';

import 'desktop_popover.dart';
import '../theme/workfollow_theme.dart';

class TaskTagPicker {
  const TaskTagPicker._();

  static Future<String?> show(BuildContext anchor, {String initial = ''}) {
    return showDesktopPopover<String>(anchor,
        width: 300,
        maxHeight: 220,
        placement: PopoverPlacement.bottomStart,
        focusPolicy: PopoverFocusPolicy.searchField,
        builder: (_) => _TaskTagEditor(initial: initial));
  }
}

class _TaskTagEditor extends StatefulWidget {
  const _TaskTagEditor({required this.initial});
  final String initial;

  @override
  State<_TaskTagEditor> createState() => _TaskTagEditorState();
}

class _TaskTagEditorState extends State<_TaskTagEditor> {
  late final text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(WorkFollowSpacing.md),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                controller: text,
                autofocus: true,
                onSubmitted: (value) => Navigator.of(context).pop(value),
                decoration: const InputDecoration(
                    hintText: '用逗号分隔，例如 工作，重要',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(text.text),
                    child: const Text('完成'))),
          ]));
}
