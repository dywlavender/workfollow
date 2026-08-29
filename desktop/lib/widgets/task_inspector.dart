import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

class TaskInspector extends StatefulWidget {
  const TaskInspector({super.key, required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  State<TaskInspector> createState() => _TaskInspectorState();
}

class _TaskInspectorState extends State<TaskInspector> {
  late final TextEditingController titleController;
  late final FocusNode titleFocusNode;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.task.title);
    titleFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant TaskInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id && !titleFocusNode.hasFocus) {
      titleController.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    titleFocusNode.dispose();
    titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final task = widget.task;
    return Container(
      color: tokens.inspector,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 13),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: _listColor(task.listName, tokens)),
                      const SizedBox(width: 7),
                      Text(task.listName, style: TextStyle(color: tokens.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.chevron_right_rounded, size: 14, color: tokens.textTertiary)),
                      Text('今天', style: TextStyle(color: tokens.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                AppIconButton(icon: Icons.share_outlined, tooltip: '导出任务', size: 28, iconSize: 16, onPressed: () {}),
                AppIconButton(icon: Icons.more_horiz_rounded, tooltip: '更多操作', size: 28, iconSize: 17, onPressed: () {}),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 7, 22, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    focusNode: titleFocusNode,
                    onSubmitted: widget.controller.updateSelectedTitle,
                    onEditingComplete: () => widget.controller.updateSelectedTitle(titleController.text),
                    cursorColor: tokens.accent,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(color: tokens.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -.45),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                  ),
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorPrimaryAction(
                          label: task.completed ? '标记未完成' : '标记完成',
                          icon: task.completed ? Icons.undo_rounded : Icons.check_rounded,
                          completed: task.completed,
                          onPressed: () => widget.controller.toggleTask(task.id),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppIconButton(icon: Icons.calendar_today_outlined, tooltip: '安排日期', size: 36, iconSize: 17, onPressed: () {}),
                    ],
                  ),
                  const SizedBox(height: 25),
                  _InspectorSection(
                    label: '安排',
                    child: Column(
                      children: [
                        _InspectorProperty(icon: Icons.calendar_today_outlined, label: '日期', value: task.timeLabel ?? '未安排'),
                        _InspectorProperty(icon: Icons.notifications_none_rounded, label: '提醒', value: '不提醒'),
                        _InspectorProperty(icon: Icons.repeat_rounded, label: '重复', value: '不重复'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 23),
                  _InspectorSection(
                    label: '描述',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                      decoration: BoxDecoration(color: tokens.content, borderRadius: BorderRadius.circular(9), border: Border.all(color: tokens.border)),
                      child: Text(task.note ?? '添加一段描述，让未来的自己更容易接着做。', style: TextStyle(color: task.note == null ? tokens.textTertiary : tokens.textSecondary, fontSize: 13, height: 1.55)),
                    ),
                  ),
                  if (task.subtaskTotal > 0) ...[
                    const SizedBox(height: 23),
                    _InspectorSection(
                      label: '子任务  ${task.subtaskCompleted}/${task.subtaskTotal}',
                      child: Column(
                        children: [
                          _SubtaskRow(label: '整理核心指标数据', completed: true, tokens: tokens),
                          _SubtaskRow(label: '完成增长章节图表', completed: true, tokens: tokens),
                          _SubtaskRow(label: '排练一遍讲述节奏', completed: false, tokens: tokens),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 23),
                  _InspectorSection(
                    label: '标签',
                    child: Wrap(spacing: 7, runSpacing: 7, children: [const SoftPill(label: '工作'), const SoftPill(label: 'Q3 复盘')]),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: tokens.border))),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined, size: 14, color: tokens.success),
                const SizedBox(width: 7),
                Text('已自动保存', style: TextStyle(color: tokens.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('刚刚', style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _listColor(String listName, WorkFollowTheme tokens) {
    return switch (listName) {
      '工作' => tokens.accent,
      '学习' => tokens.warning,
      '个人' => tokens.success,
      _ => tokens.textTertiary,
    };
  }
}

class _InspectorPrimaryAction extends StatelessWidget {
  const _InspectorPrimaryAction({required this.label, required this.icon, required this.completed, required this.onPressed});

  final String label;
  final IconData icon;
  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
      color: completed ? tokens.success : tokens.accent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 7), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))]),
        ),
      ),
    );
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 2, bottom: 9), child: Text(label.toUpperCase(), style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .55))),
      child,
    ]);
  }
}

class _InspectorProperty extends StatelessWidget {
  const _InspectorProperty({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.border.withOpacity(.7)))),
      child: Row(children: [
        Icon(icon, size: 16, color: tokens.textTertiary),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value, style: TextStyle(color: tokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 2),
        Icon(Icons.chevron_right_rounded, size: 15, color: tokens.textTertiary),
      ]),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.label, required this.completed, required this.tokens});

  final String label;
  final bool completed;
  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 17, height: 17, decoration: BoxDecoration(shape: BoxShape.circle, color: completed ? tokens.success : Colors.transparent, border: Border.all(color: completed ? tokens.success : tokens.borderStrong, width: 1.4)), child: completed ? const Icon(Icons.check_rounded, size: 11, color: Colors.white) : null),
        const SizedBox(width: 9),
        Expanded(child: Text(label, style: TextStyle(color: completed ? tokens.textTertiary : tokens.textSecondary, fontSize: 12, decoration: completed ? TextDecoration.lineThrough : null))),
      ]),
    );
  }
}
