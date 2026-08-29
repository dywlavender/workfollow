import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';

class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.controller, this.autofocus = false});

  final WorkspaceController controller;
  final bool autofocus;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  late final TextEditingController textController;
  late final FocusNode focusNode;
  bool focused = false;

  @override
  void initState() {
    super.initState();
    textController = TextEditingController();
    focusNode = FocusNode();
    focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    textController.dispose();
    super.dispose();
  }

  void _handleFocusChange() => setState(() => focused = focusNode.hasFocus);

  void _submit() {
    if (widget.controller.addTask(textController.text)) {
      textController.clear();
      focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 44,
      decoration: BoxDecoration(
        color: focused ? tokens.overlay : tokens.accentFaint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: focused ? tokens.accent.withOpacity(.56) : tokens.border.withOpacity(.7)),
        boxShadow: focused ? [BoxShadow(color: tokens.accent.withOpacity(.08), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.add_rounded, size: 18, color: focused ? tokens.accent : tokens.textTertiary),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: tokens.accent,
              style: TextStyle(color: tokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: '记下下一件事…',
                hintStyle: TextStyle(color: tokens.textTertiary, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: focused ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('Return', style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
