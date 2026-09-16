import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'task_editor_glyph.dart';
import 'desktop_popover.dart';
import 'task_editor_popover.dart';
import 'task_menu_style.dart';

/// Floating formatting strip; the document selection survives nested pickers.
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

  bool _active(quill.Attribute attribute) {
    final value =
        controller.getSelectionStyle().attributes[attribute.key]?.value;
    return value == attribute.value ||
        (attribute == quill.Attribute.unchecked &&
            value == quill.Attribute.checked.value);
  }

  void _format(quill.Attribute attribute) => controller.formatSelection(
      _active(attribute) ? quill.Attribute.clone(attribute, null) : attribute);

  Future<void> _heading(BuildContext anchor) async {
    final level = await showTaskEditorPopover<int>(
      anchor,
      width: 150,
      placement: PopoverPlacement.topStart,
      focusPolicy: PopoverFocusPolicy.preserveEditor,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final item in [(0, '正文'), (1, '一级标题'), (2, '二级标题'), (3, '三级标题')])
            _PickerRow(
                key: ValueKey('task-format-heading-${item.$1}'),
                label: item.$2,
                selected: (controller
                            .getSelectionStyle()
                            .attributes[quill.Attribute.header.key]
                            ?.value ??
                        0) ==
                    item.$1,
                onTap: () => Navigator.of(context).pop(item.$1)),
        ]),
      ),
    );
    if (level != null)
      controller.formatSelection(
          quill.Attribute.clone(quill.Attribute.h1, level == 0 ? null : level));
  }

  Future<void> _time(BuildContext anchor) async {
    final selection = controller.selection;
    final now = DateTime.now();
    final date = '${now.year}年${now.month}月${now.day}日';
    final time =
        '${'${now.hour}'.padLeft(2, '0')}:${'${now.minute}'.padLeft(2, '0')}';
    final value = await showTaskEditorPopover<String>(
      anchor,
      width: 222,
      placement: PopoverPlacement.topEnd,
      focusPolicy: PopoverFocusPolicy.preserveEditor,
      builder: (context) => Padding(
        key: const ValueKey('task-time-formats'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final item in [
            ('date', date),
            ('datetime', '$date $time'),
            ('time', time)
          ])
            _PickerRow(
                key: ValueKey('task-insert-${item.$1}'),
                label: item.$2,
                onTap: () => Navigator.of(context).pop(item.$2)),
        ]),
      ),
    );
    if (value == null) return;
    final at = selection.start.clamp(0, controller.document.length - 1);
    final length = selection.end.clamp(at, controller.document.length - 1) - at;
    controller.replaceText(
        at, length, value, TextSelection.collapsed(offset: at + value.length));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final colors = TaskMenuStyle.colors(context);
          Widget format(String key, String tooltip, IconData icon,
                  quill.Attribute attribute) =>
              _ToolButton(
                  key: ValueKey('task-format-$key'),
                  tooltip: tooltip,
                  icon: icon,
                  selected: _active(attribute),
                  onPressed: (_) => _format(attribute));
          Widget divider() => Container(
              width: 1,
              height: 17,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colors.border);
          return SizedBox(
            key: const ValueKey('task-editor-toolbar'),
            height: TaskEditorPopoverStyle.toolbarHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ToolButton(
                    key: const ValueKey('task-format-heading'),
                    tooltip: '标题',
                    label: 'H',
                    selected: controller
                            .getSelectionStyle()
                            .attributes[quill.Attribute.header.key]
                            ?.value !=
                        null,
                    onPressed: _heading),
                format(
                    'bold', '粗体', WorkFollowIcons.bold, quill.Attribute.bold),
                _ToolButton(
                    key: const ValueKey('task-format-highlight'),
                    tooltip: '高亮',
                    label: 'A',
                    highlight: true,
                    selected:
                        _active(const quill.BackgroundAttribute('#d4ff00')),
                    onPressed: (_) =>
                        _format(const quill.BackgroundAttribute('#d4ff00'))),
                divider(),
                format('checklist', '检查项', WorkFollowIcons.checklist,
                    quill.Attribute.unchecked),
                format('bullet', '无序列表', WorkFollowIcons.bullet,
                    quill.Attribute.ul),
                format('ordered', '有序列表', WorkFollowIcons.ordered,
                    quill.Attribute.ol),
                divider(),
                format('italic', '斜体', WorkFollowIcons.italic,
                    quill.Attribute.italic),
                format('underline', '下划线', WorkFollowIcons.underline,
                    quill.Attribute.underline),
                format('strike', '删除线', WorkFollowIcons.strike,
                    quill.Attribute.strikeThrough),
                _ToolButton(
                    key: const ValueKey('task-format-divider'),
                    tooltip: '分割线',
                    icon: WorkFollowIcons.divider,
                    onPressed: (_) => onInsertDivider()),
                _ToolButton(
                    key: const ValueKey('task-format-time'),
                    tooltip: '插入当前时间',
                    icon: Icons.history,
                    onPressed: _time),
                divider(),
                _ToolButton(
                    key: const ValueKey('task-format-link'),
                    tooltip: '链接',
                    icon: WorkFollowIcons.link,
                    onPressed: (_) => onLink()),
                format('code', '代码', WorkFollowIcons.code,
                    quill.Attribute.inlineCode),
                format('quote', '引用', WorkFollowIcons.quote,
                    quill.Attribute.blockQuote),
                divider(),
                _ToolButton(
                    key: const ValueKey('task-format-attachment'),
                    tooltip: '上传附件',
                    icon: WorkFollowIcons.attachment,
                    onPressed: (_) => onAttach()),
              ]),
            ),
          );
        },
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(
      {super.key,
      this.icon,
      this.label,
      required this.tooltip,
      required this.onPressed,
      this.selected = false,
      this.highlight = false});
  final IconData? icon;
  final String? label;
  final String tooltip;
  final void Function(BuildContext) onPressed;
  final bool selected;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    final color = selected ? colors.accent : colors.textSecondary;
    return Builder(
        builder: (anchor) => Tooltip(
              message: tooltip,
              child: Semantics(
                button: true,
                label: tooltip,
                selected: selected,
                child: InkWell(
                  onTap: () => onPressed(anchor),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 26,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: selected ? colors.accentFaint : null,
                        borderRadius: BorderRadius.circular(4)),
                    child: label != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                                color:
                                    highlight ? const Color(0xFFd4ff00) : null,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(label!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                        fontSize: WorkFollowMacDisplay.glyphLabel,
                                        height: WorkFollowMacTypography.lineTight,
                                        color: highlight
                                            ? const Color(0xFF566400)
                                            : color)),
                          )
                        : TaskEditorGlyph(
                            (key as ValueKey<String>)
                                .value
                                .replaceFirst('task-format-', ''),
                            size: 18,
                            color: color),
                  ),
                ),
              ),
            ));
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow(
      {super.key,
      required this.label,
      required this.onTap,
      this.selected = false});
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
              height: 36,
              child: Row(children: [
                Expanded(
                    child: Text(label,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                            fontSize: WorkFollowMacTypography.menu,
                            color: selected
                                ? colors.accent
                                : colors.textPrimary))),
                if (selected) Icon(Icons.check, size: 16, color: colors.accent),
              ])),
        ));
  }
}
