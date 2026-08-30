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
    final selected = notes.isEmpty
        ? null
        : notes.firstWhere((note) => note.id == selectedId,
            orElse: () => notes.first);

    return LayoutBuilder(
      builder: (context, constraints) {
        final folderWidth = constraints.maxWidth >= 980 ? 218.0 : 190.0;
        final listWidth = constraints.maxWidth >= 980 ? 300.0 : 260.0;
        return Row(
          children: [
            _FolderColumn(width: folderWidth, controller: widget.controller),
            VerticalDivider(width: 1, thickness: 1, color: tokens.border),
            SizedBox(
              width: listWidth,
              child: _NoteListColumn(
                notes: notes,
                selectedId: selectedId,
                onSelect: (id) => setState(() => selectedId = id),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: tokens.border),
            Expanded(
              child: selected == null
                  ? _EmptyNoteEditor(tokens: tokens)
                  : _NoteEditor(note: selected),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyNoteEditor extends StatelessWidget {
  const _EmptyNoteEditor({required this.tokens});

  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.inspector,
      alignment: Alignment.center,
      child: Text(
        '还没有笔记，从左上角开始记录。',
        style: TextStyle(color: tokens.textTertiary, fontSize: 13),
      ),
    );
  }
}

class _FolderColumn extends StatelessWidget {
  const _FolderColumn({required this.width, required this.controller});

  final double width;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      width: width,
      color: tokens.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('笔记',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.35))),
              AppIconButton(
                  icon: Icons.add,
                  tooltip: '新建笔记',
                  size: 28,
                  iconSize: 17,
                  onPressed: () {}),
            ],
          ),
          const SizedBox(height: 22),
          _NoteGroupHeading(label: '视图'),
          const SizedBox(height: 6),
          _FolderItem(
              label: '全部笔记',
              count: controller.notes.length,
              icon: Icons.notes_outlined,
              selected: true),
          _FolderItem(
              label: '收藏',
              count: controller.notes.where((note) => note.isFavorite).length,
              icon: Icons.star_border_rounded),
          _FolderItem(
              label: '未归档',
              count: controller.notes
                  .where((note) => note.folderId == null)
                  .length,
              icon: Icons.inbox_outlined),
          const SizedBox(height: 23),
          Row(
            children: [
              Expanded(child: _NoteGroupHeading(label: '文件夹')),
              AppIconButton(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: '新建文件夹',
                  size: 26,
                  iconSize: 15,
                  onPressed: () {}),
            ],
          ),
          const SizedBox(height: 6),
          ...controller.folders.map((folder) => _FolderItem(
                label: folder.name,
                count: controller.notes
                    .where((note) =>
                        note.folderId == folder.id ||
                        note.folder == folder.name)
                    .length,
                icon: Icons.folder_outlined,
              )),
          const Spacer(),
          Text('本地笔记空间',
              style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }
}

class _NoteListColumn extends StatelessWidget {
  const _NoteListColumn(
      {required this.notes, required this.selectedId, required this.onSelect});

  final List<NoteItem> notes;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      color: tokens.content,
      padding: const EdgeInsets.fromLTRB(13, 20, 10, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('最近编辑',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700))),
              AppIconButton(
                  icon: Icons.sort_rounded,
                  tooltip: '排序',
                  size: 28,
                  iconSize: 16,
                  onPressed: () {}),
            ],
          ),
          const SizedBox(height: 4),
          Text('${notes.length} 条笔记',
              style: TextStyle(color: tokens.textTertiary, fontSize: 10.5)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return _NoteItem(
                    note: note,
                    selected: note.id == selectedId,
                    onTap: () => onSelect(note.id));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteEditor extends StatelessWidget {
  const _NoteEditor({required this.note});

  final NoteItem note;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      color: tokens.inspector,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 20, 13),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 14, color: tokens.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(note.folder,
                        style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600))),
                AppIconButton(
                    icon: Icons.push_pin_outlined,
                    tooltip: '收藏笔记',
                    size: 28,
                    iconSize: 16,
                    onPressed: () {}),
                AppIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: '更多操作',
                    size: 28,
                    iconSize: 17,
                    onPressed: () {}),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(31, 28, 58, 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.title,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.65)),
                    const SizedBox(height: 9),
                    Text('最近编辑于 ${note.updatedLabel}',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 11)),
                    const SizedBox(height: 31),
                    Text(note.preview,
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 15,
                            height: 1.8)),
                    const SizedBox(height: 26),
                    Container(height: 1, color: tokens.border),
                    const SizedBox(height: 24),
                    Text('把想法写下来，任务就有了可以回来的地方。',
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            height: 1.8)),
                    const SizedBox(height: 27),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: tokens.accentFaint,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: tokens.accent.withOpacity(.12))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.link_rounded,
                              size: 16, color: tokens.accent),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text('关联任务 · 准备季度产品评审演示文稿',
                                  style: TextStyle(
                                      color: tokens.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(25, 10, 20, 12),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.border))),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    size: 14, color: tokens.success),
                const SizedBox(width: 7),
                Text('已自动保存',
                    style: TextStyle(
                        color: tokens.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('刚刚',
                    style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteGroupHeading extends StatelessWidget {
  const _NoteGroupHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(label,
          style: TextStyle(
              color: tokens.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .45)),
    );
  }
}

class _FolderItem extends StatelessWidget {
  const _FolderItem(
      {required this.label,
      required this.count,
      required this.icon,
      this.selected = false});

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
      decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(7)),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: selected ? tokens.accent : tokens.textSecondary),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected ? tokens.accent : tokens.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500))),
          if (count > 0)
            Text('$count',
                style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NoteItem extends StatelessWidget {
  const _NoteItem(
      {required this.note, required this.selected, required this.onTap});

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
        padding: const EdgeInsets.fromLTRB(10, 11, 9, 11),
        decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: tokens.accent.withOpacity(.17))
                : null),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                    color: Color(note.accent.value), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.25)),
                  const SizedBox(height: 5),
                  Text(note.preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 10.5,
                          height: 1.35)),
                  const SizedBox(height: 6),
                  Text(note.updatedLabel,
                      style:
                          TextStyle(color: tokens.textTertiary, fontSize: 9.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
