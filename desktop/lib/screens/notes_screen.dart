import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/migration.dart';
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
  String? selectedFolderId;
  bool favoritesOnly = false;
  bool unfiledOnly = false;
  bool newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final notes = _visibleNotes();
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
            _FolderColumn(
              width: folderWidth,
              controller: widget.controller,
              selectedFolderId: selectedFolderId,
              favoritesOnly: favoritesOnly,
              unfiledOnly: unfiledOnly,
              onCreateNote: _createNote,
              onCreateFolder: _createFolder,
              onShowAll: () => setState(() {
                selectedFolderId = null;
                favoritesOnly = false;
                unfiledOnly = false;
              }),
              onShowFavorites: () => setState(() {
                selectedFolderId = null;
                favoritesOnly = true;
                unfiledOnly = false;
              }),
              onShowUnfiled: () => setState(() {
                selectedFolderId = null;
                favoritesOnly = false;
                unfiledOnly = true;
              }),
              onSelectFolder: (folder) => setState(() {
                selectedFolderId = folder.id;
                favoritesOnly = false;
                unfiledOnly = false;
              }),
            ),
            VerticalDivider(width: 1, thickness: 1, color: tokens.border),
            SizedBox(
              width: listWidth,
              child: _NoteListColumn(
                notes: notes,
                selectedId: selected?.id ?? selectedId,
                newestFirst: newestFirst,
                onSort: () => setState(() => newestFirst = !newestFirst),
                onSelect: (id) => setState(() => selectedId = id),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: tokens.border),
            Expanded(
              child: selected == null
                  ? _EmptyNoteEditor(tokens: tokens)
                  : _NoteEditor(
                      note: selected,
                      controller: widget.controller,
                      folders: widget.controller.folders,
                      onDelete: () => _deleteNote(selected.id),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<NoteItem> _visibleNotes() {
    final notes = widget.controller.notes.where((note) {
      if (favoritesOnly) return note.isFavorite;
      if (unfiledOnly) return note.folderId == null;
      if (selectedFolderId == null) return true;
      MigrationFolderRecord? folder;
      for (final item in widget.controller.folders) {
        if (item.id == selectedFolderId) {
          folder = item;
          break;
        }
      }
      return note.folderId == selectedFolderId ||
          (folder != null && note.folder == folder.name);
    }).toList();
    notes.sort((a, b) {
      final aDate = DateTime.tryParse(a.updatedAt ?? a.createdAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b.updatedAt ?? b.createdAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return newestFirst ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });
    return notes;
  }

  Future<void> _createNote() async {
    final id = widget.controller.addNote(folderId: selectedFolderId);
    if (!mounted) return;
    setState(() {
      selectedId = id;
      favoritesOnly = false;
      unfiledOnly = false;
    });
  }

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '例如：旅行灵感'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text),
              child: const Text('创建')),
        ],
      ),
    );
    nameController.dispose();
    if (!mounted || name == null) return;
    final folder = widget.controller.addFolder(name);
    if (folder == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文件夹名称为空，或已经存在。')));
      return;
    }
    setState(() {
      selectedFolderId = folder.id;
      favoritesOnly = false;
      unfiledOnly = false;
    });
  }

  Future<void> _deleteNote(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除笔记？'),
        content: const Text('删除后这条笔记会从本机空间移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.controller.removeNote(id);
    final remaining = _visibleNotes();
    setState(() => selectedId = remaining.isEmpty ? '' : remaining.first.id);
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
      child: Text('还没有笔记，从左上角开始记录。',
          style: TextStyle(color: tokens.textTertiary, fontSize: 13)),
    );
  }
}

class _FolderColumn extends StatelessWidget {
  const _FolderColumn({
    required this.width,
    required this.controller,
    required this.selectedFolderId,
    required this.favoritesOnly,
    required this.unfiledOnly,
    required this.onCreateNote,
    required this.onCreateFolder,
    required this.onShowAll,
    required this.onShowFavorites,
    required this.onShowUnfiled,
    required this.onSelectFolder,
  });

  final double width;
  final WorkspaceController controller;
  final String? selectedFolderId;
  final bool favoritesOnly;
  final bool unfiledOnly;
  final VoidCallback onCreateNote;
  final VoidCallback onCreateFolder;
  final VoidCallback onShowAll;
  final VoidCallback onShowFavorites;
  final VoidCallback onShowUnfiled;
  final ValueChanged<MigrationFolderRecord> onSelectFolder;

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
                  onPressed: onCreateNote),
            ],
          ),
          const SizedBox(height: 22),
          _NoteGroupHeading(label: '视图'),
          const SizedBox(height: 6),
          _FolderItem(
              label: '全部笔记',
              count: controller.notes.length,
              icon: Icons.notes_outlined,
              selected:
                  !favoritesOnly && !unfiledOnly && selectedFolderId == null,
              onTap: onShowAll),
          _FolderItem(
              label: '收藏',
              count: controller.notes.where((note) => note.isFavorite).length,
              icon: Icons.star_border_rounded,
              selected: favoritesOnly,
              onTap: onShowFavorites),
          _FolderItem(
              label: '未归档',
              count: controller.notes
                  .where((note) => note.folderId == null)
                  .length,
              icon: Icons.inbox_outlined,
              selected: unfiledOnly,
              onTap: onShowUnfiled),
          const SizedBox(height: 23),
          Row(
            children: [
              Expanded(child: _NoteGroupHeading(label: '文件夹')),
              AppIconButton(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: '新建文件夹',
                  size: 26,
                  iconSize: 15,
                  onPressed: onCreateFolder),
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
                selected: !favoritesOnly &&
                    !unfiledOnly &&
                    selectedFolderId == folder.id,
                onTap: () => onSelectFolder(folder),
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
  const _NoteListColumn({
    required this.notes,
    required this.selectedId,
    required this.newestFirst,
    required this.onSort,
    required this.onSelect,
  });

  final List<NoteItem> notes;
  final String selectedId;
  final bool newestFirst;
  final VoidCallback onSort;
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
                  child: Text(newestFirst ? '最近编辑' : '最早编辑',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700))),
              AppIconButton(
                  icon: newestFirst ? Icons.south_rounded : Icons.north_rounded,
                  tooltip: '切换排序',
                  size: 28,
                  iconSize: 16,
                  onPressed: onSort),
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

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.note,
    required this.controller,
    required this.folders,
    required this.onDelete,
  });

  final NoteItem note;
  final WorkspaceController controller;
  final List<MigrationFolderRecord> folders;
  final VoidCallback onDelete;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController titleController;
  late final TextEditingController bodyController;
  late final FocusNode titleFocusNode;
  late final FocusNode bodyFocusNode;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note.title);
    bodyController = TextEditingController(text: _bodyFor(widget.note));
    titleFocusNode = FocusNode();
    bodyFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(titleController, widget.note.title, titleFocusNode);
    _sync(bodyController, _bodyFor(widget.note), bodyFocusNode);
  }

  @override
  void dispose() {
    titleFocusNode.dispose();
    bodyFocusNode.dispose();
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final note = widget.note;
    return Container(
      color: tokens.inspector,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 20, 13),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _chooseFolder,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            size: 14, color: tokens.textTertiary),
                        const SizedBox(width: 6),
                        Text(note.folder,
                            style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded,
                            size: 14, color: tokens.textTertiary),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                AppIconButton(
                    icon: note.isFavorite
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    tooltip: note.isFavorite ? '取消收藏' : '收藏笔记',
                    size: 28,
                    iconSize: 16,
                    onPressed: () =>
                        widget.controller.toggleNoteFavorite(note.id)),
                AppIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: '更多操作',
                    size: 28,
                    iconSize: 17,
                    onPressed: _showMore),
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
                    TextField(
                      key: const ValueKey('note-title-editor'),
                      controller: titleController,
                      focusNode: titleFocusNode,
                      onChanged: (value) =>
                          widget.controller.updateNoteTitle(note.id, value),
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.65),
                      decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero),
                    ),
                    const SizedBox(height: 9),
                    Text('最近编辑于 ${note.updatedLabel}',
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 11)),
                    const SizedBox(height: 31),
                    TextField(
                      key: const ValueKey('note-body-editor'),
                      controller: bodyController,
                      focusNode: bodyFocusNode,
                      onChanged: (value) =>
                          widget.controller.updateNoteBody(note.id, value),
                      minLines: 8,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 15,
                          height: 1.8),
                      decoration: InputDecoration(
                        hintText: '写下你的想法、会议记录或下一步行动…',
                        hintStyle: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: 15,
                            height: 1.8),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
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
                          Icon(Icons.storage_outlined,
                              size: 16, color: tokens.accent),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text('这条笔记保存在本机，编辑内容会自动写入本地快照。',
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
                Text(noteUpdatedLabelFor(note.updatedAt),
                    style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _bodyFor(NoteItem note) => note.plainText ?? note.preview;

  void _sync(
      TextEditingController controller, String value, FocusNode focusNode) {
    if (focusNode.hasFocus || controller.text == value) return;
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _chooseFolder() async {
    final tokens = WorkFollowTheme.of(context);
    final folderId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: tokens.overlay,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('移动到文件夹',
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700))),
            ListTile(
                title: const Text('未归档'),
                trailing: widget.note.folderId == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop('__unfiled__')),
            ...widget.folders.map((folder) => ListTile(
                title: Text(folder.name),
                trailing: widget.note.folderId == folder.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(folder.id))),
          ],
        ),
      ),
    );
    if (folderId == '__unfiled__' && widget.note.folderId != null) {
      widget.controller.moveNoteToFolder(widget.note.id, null);
    } else if (folderId != null && folderId != '__unfiled__') {
      widget.controller.moveNoteToFolder(widget.note.id, folderId);
    }
  }

  Future<void> _showMore() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制笔记正文'),
                onTap: () => Navigator.of(sheetContext).pop('copy')),
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除笔记'),
                onTap: () => Navigator.of(sheetContext).pop('delete')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      // Keeping the editor focused is more useful than showing a second menu;
      // the platform clipboard action is handled by the text field itself.
      await ClipboardHelper.copy(_bodyFor(widget.note));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记正文已复制')));
    } else if (action == 'delete') {
      widget.onDelete();
    }
  }
}

class ClipboardHelper {
  static Future<void> copy(String value) async {
    // Imported lazily to keep this file's widget code easy to scan.
    await Clipboard.setData(ClipboardData(text: value));
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
      this.selected = false,
      this.onTap});

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(7)),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? tokens.accent : tokens.textSecondary),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color:
                              selected ? tokens.accent : tokens.textSecondary,
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
        ),
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
                  Row(
                    children: [
                      Expanded(
                          child: Text(note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25))),
                      if (note.isFavorite)
                        Icon(Icons.push_pin, size: 12, color: tokens.accent),
                    ],
                  ),
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
