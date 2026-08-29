import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String selectedId = 'note-01';

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final notes = widget.controller.notes;
    final selected = notes.firstWhere((note) => note.id == selectedId, orElse: () => notes.first);

    return Container(
      color: tokens.content,
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: Container(
              color: tokens.inspector,
              padding: const EdgeInsets.fromLTRB(17, 22, 13, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '笔记',
                          style: TextStyle(color: tokens.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.45),
                        ),
                      ),
                      AppIconButton(icon: Icons.add, tooltip: '新建笔记', size: 28, iconSize: 17, onPressed: () {}),
                    ],
                  ),
                  const SizedBox(height: 21),
                  Text('文件夹', style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5)),
                  const SizedBox(height: 8),
                  const _FolderItem(label: '全部笔记', count: 3, icon: Icons.notes_outlined, selected: true),
                  const _FolderItem(label: '工作笔记', count: 1, icon: Icons.work_outline_rounded),
                  const _FolderItem(label: '灵感', count: 1, icon: Icons.lightbulb_outline_rounded),
                  const _FolderItem(label: '学习', count: 1, icon: Icons.menu_book_outlined),
                  const SizedBox(height: 28),
                  Text('最近编辑', style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _NoteItem(note: note, selected: note.id == selectedId, onTap: () => setState(() => selectedId = note.id));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: tokens.border),
          Expanded(
            child: Container(
              color: tokens.content,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(31, 20, 22, 13),
                    child: Row(
                      children: [
                        Expanded(child: Text(selected.folder, style: TextStyle(color: tokens.textTertiary, fontSize: 11, fontWeight: FontWeight.w600))),
                        AppIconButton(icon: Icons.more_horiz_rounded, tooltip: '更多操作', onPressed: () {}),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(31, 21, 58, 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(selected.title, style: TextStyle(color: tokens.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.65)),
                            const SizedBox(height: 9),
                            Text('最近编辑于 ${selected.updatedLabel}', style: TextStyle(color: tokens.textTertiary, fontSize: 11)),
                            const SizedBox(height: 31),
                            Text(selected.preview, style: TextStyle(color: tokens.textSecondary, fontSize: 15, height: 1.8)),
                            const SizedBox(height: 26),
                            Container(height: 1, color: tokens.border),
                            const SizedBox(height: 24),
                            Text('把想法写下来，任务就有了可以回来的地方。', style: TextStyle(color: tokens.textSecondary, fontSize: 14, height: 1.8)),
                            const SizedBox(height: 27),
                            Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(color: tokens.accentFaint, borderRadius: BorderRadius.circular(10), border: Border.all(color: tokens.accent.withOpacity(.12))),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.link_rounded, size: 16, color: tokens.accent),
                                  const SizedBox(width: 9),
                                  Expanded(child: Text('关联任务 · 准备季度产品评审演示文稿', style: TextStyle(color: tokens.accent, fontSize: 12, fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderItem extends StatelessWidget {
  const _FolderItem({required this.label, required this.count, required this.icon, this.selected = false});

  final String label;
  final int count;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(color: selected ? tokens.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: selected ? tokens.accent : tokens.textSecondary),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: TextStyle(color: selected ? tokens.accent : tokens.textSecondary, fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
          Text('$count', style: TextStyle(color: tokens.textTertiary, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NoteItem extends StatelessWidget {
  const _NoteItem({required this.note, required this.selected, required this.onTap});

  final NoteItem note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(9, 9, 8, 9),
        decoration: BoxDecoration(color: selected ? tokens.content : Colors.transparent, borderRadius: BorderRadius.circular(8), border: selected ? Border.all(color: tokens.border) : null),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 7, height: 7, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: Color(note.accent.value), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(note.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textTertiary, fontSize: 10.5, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
