import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../theme/workfollow_theme.dart';

/// Compact document formatting strip shared by task and note editors. It
/// intentionally exposes only the high-frequency actions that fit a desktop
/// workbench; document-specific actions stay in the surrounding surface.
class TaskEditorToolbar extends StatelessWidget {
  const TaskEditorToolbar({
    super.key,
    required this.controller,
    required this.onAttach,
    required this.onInsertSlash,
    required this.onInsertDivider,
    required this.onLink,
  });

  final quill.QuillController controller;
  final VoidCallback onAttach;
  final VoidCallback onInsertSlash;
  final VoidCallback onInsertDivider;
  final VoidCallback onLink;

  void _format(quill.Attribute attribute) =>
      controller.formatSelection(attribute);

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
      key: const ValueKey('task-editor-toolbar'),
      color: tokens.canvas,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(
              key: const ValueKey('task-format-heading-1'),
              label: 'H1',
              tooltip: '一级标题',
              onPressed: () => _format(quill.Attribute.h1),
            ),
            _ToolButton(
              key: const ValueKey('task-format-heading-2'),
              label: 'H2',
              tooltip: '二级标题',
              onPressed: () => _format(quill.Attribute.h2),
            ),
            _ToolButton(
              key: const ValueKey('task-format-heading-3'),
              label: 'H3',
              tooltip: '三级标题',
              onPressed: () => _format(quill.Attribute.h3),
            ),
            _divider(tokens),
            _ToolButton(
              key: const ValueKey('task-format-bold'),
              icon: Icons.format_bold_rounded,
              tooltip: '粗体',
              onPressed: () => _format(quill.Attribute.bold),
            ),
            _ToolButton(
              key: const ValueKey('task-format-italic'),
              icon: Icons.format_italic_rounded,
              tooltip: '斜体',
              onPressed: () => _format(quill.Attribute.italic),
            ),
            _ToolButton(
              key: const ValueKey('task-format-underline'),
              icon: Icons.format_underline_rounded,
              tooltip: '下划线',
              onPressed: () => _format(quill.Attribute.underline),
            ),
            _ToolButton(
              key: const ValueKey('task-format-strike'),
              icon: Icons.strikethrough_s_rounded,
              tooltip: '删除线',
              onPressed: () => _format(quill.Attribute.strikeThrough),
            ),
            _divider(tokens),
            _ToolButton(
              key: const ValueKey('task-format-highlight'),
              icon: Icons.highlight_rounded,
              tooltip: '高亮',
              onPressed: () =>
                  _format(const quill.BackgroundAttribute('#fff3a3')),
            ),
            _ToolButton(
              key: const ValueKey('task-format-checklist'),
              icon: Icons.check_box_outlined,
              tooltip: '检查项',
              onPressed: () => _format(quill.Attribute.checked),
            ),
            _ToolButton(
              key: const ValueKey('task-format-bullet'),
              icon: Icons.format_list_bulleted_rounded,
              tooltip: '无序列表',
              onPressed: () => _format(quill.Attribute.ul),
            ),
            _ToolButton(
              key: const ValueKey('task-format-ordered'),
              icon: Icons.format_list_numbered_rounded,
              tooltip: '有序列表',
              onPressed: () => _format(quill.Attribute.ol),
            ),
            _ToolButton(
              key: const ValueKey('task-format-quote'),
              icon: Icons.format_quote_rounded,
              tooltip: '引用',
              onPressed: () => _format(quill.Attribute.blockQuote),
            ),
            _ToolButton(
              key: const ValueKey('task-format-code'),
              icon: Icons.code_rounded,
              tooltip: '代码',
              onPressed: () => _format(quill.Attribute.inlineCode),
            ),
            _ToolButton(
              key: const ValueKey('task-format-divider'),
              icon: Icons.horizontal_rule_rounded,
              tooltip: '分割线',
              onPressed: onInsertDivider,
            ),
            _divider(tokens),
            _ToolButton(
              key: const ValueKey('task-format-link'),
              icon: Icons.link_rounded,
              tooltip: '链接',
              onPressed: onLink,
            ),
            _ToolButton(
              key: const ValueKey('task-format-attachment'),
              icon: Icons.attach_file_rounded,
              tooltip: '添加附件',
              onPressed: onAttach,
            ),
            _ToolButton(
              key: const ValueKey('task-format-slash'),
              icon: Icons.add_rounded,
              tooltip: '快速插入',
              onPressed: onInsertSlash,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(WorkFollowTheme tokens) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: tokens.border,
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    Key? key,
    this.icon,
    this.label,
    required this.tooltip,
    required this.onPressed,
  })  : _buttonKey = key,
        super(key: null);

  final Key? _buttonKey;
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: IconButton(
          key: _buttonKey,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: const EdgeInsets.all(5),
          onPressed: onPressed,
          icon: label != null
              ? Text(label!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary))
              : Icon(icon, size: 17, color: tokens.textSecondary),
        ),
      ),
    );
  }
}
