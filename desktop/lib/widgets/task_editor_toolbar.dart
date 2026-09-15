import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

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
      color: tokens.content,
      child: SizedBox(
        height: WorkFollowMetrics.editorToolbarHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                icon: WorkFollowIcons.bold,
                tooltip: '粗体',
                onPressed: () => _format(quill.Attribute.bold),
              ),
              _ToolButton(
                key: const ValueKey('task-format-italic'),
                icon: WorkFollowIcons.italic,
                tooltip: '斜体',
                onPressed: () => _format(quill.Attribute.italic),
              ),
              _ToolButton(
                key: const ValueKey('task-format-underline'),
                icon: WorkFollowIcons.underline,
                tooltip: '下划线',
                onPressed: () => _format(quill.Attribute.underline),
              ),
              _ToolButton(
                key: const ValueKey('task-format-strike'),
                icon: WorkFollowIcons.strike,
                tooltip: '删除线',
                onPressed: () => _format(quill.Attribute.strikeThrough),
              ),
              _divider(tokens),
              _ToolButton(
                key: const ValueKey('task-format-highlight'),
                icon: WorkFollowIcons.highlight,
                tooltip: '高亮',
                onPressed: () =>
                    _format(const quill.BackgroundAttribute('#fff3a3')),
              ),
              _ToolButton(
                key: const ValueKey('task-format-checklist'),
                icon: WorkFollowIcons.checklist,
                tooltip: '检查项',
                onPressed: () => _format(quill.Attribute.checked),
              ),
              _ToolButton(
                key: const ValueKey('task-format-bullet'),
                icon: WorkFollowIcons.bullet,
                tooltip: '无序列表',
                onPressed: () => _format(quill.Attribute.ul),
              ),
              _ToolButton(
                key: const ValueKey('task-format-ordered'),
                icon: WorkFollowIcons.ordered,
                tooltip: '有序列表',
                onPressed: () => _format(quill.Attribute.ol),
              ),
              _ToolButton(
                key: const ValueKey('task-format-quote'),
                icon: WorkFollowIcons.quote,
                tooltip: '引用',
                onPressed: () => _format(quill.Attribute.blockQuote),
              ),
              _ToolButton(
                key: const ValueKey('task-format-code'),
                icon: WorkFollowIcons.code,
                tooltip: '代码',
                onPressed: () => _format(quill.Attribute.inlineCode),
              ),
              _ToolButton(
                key: const ValueKey('task-format-divider'),
                icon: WorkFollowIcons.divider,
                tooltip: '分割线',
                onPressed: onInsertDivider,
              ),
              _divider(tokens),
              _ToolButton(
                key: const ValueKey('task-format-link'),
                icon: WorkFollowIcons.link,
                tooltip: '链接',
                onPressed: onLink,
              ),
              _ToolButton(
                key: const ValueKey('task-format-attachment'),
                icon: WorkFollowIcons.attachment,
                tooltip: '添加附件',
                onPressed: onAttach,
              ),
              _ToolButton(
                key: const ValueKey('task-format-slash'),
                icon: WorkFollowIcons.add,
                tooltip: '快速插入',
                onPressed: onInsertSlash,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(WorkFollowTheme tokens) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 5),
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
          constraints: const BoxConstraints(
              minWidth: WorkFollowMetrics.iconHitTarget,
              minHeight: WorkFollowMetrics.iconHitTarget),
          padding: const EdgeInsets.all(4),
          splashColor: Colors.transparent,
          hoverColor: tokens.accentFaint,
          onPressed: onPressed,
          icon: label != null
              ? Text(label!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary))
              : AppIcon(icon!,
                  size: WorkFollowMetrics.toolbarIcon,
                  color: tokens.textSecondary),
        ),
      ),
    );
  }
}
