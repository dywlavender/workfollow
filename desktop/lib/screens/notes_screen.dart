import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/migration.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/save_status_footer.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  // Folder/favorites/unfiled filters live in the controller so shortcuts
  // (Cmd-N "new note in the current folder") share the same state.
  bool newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final controller = widget.controller;
    final notes = _visibleNotes();
    // The selected note lives in the controller so search results (openNote)
    // and this screen always agree on which note the editor is showing.
    final controllerSelectedId = controller.selectedNoteId;
    final selected = notes.isEmpty
        ? null
        : (controllerSelectedId != null &&
                notes.any((note) => note.id == controllerSelectedId)
            ? notes.firstWhere((note) => note.id == controllerSelectedId)
            : notes.first);

    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = constraints.maxWidth >= 980 ? 300.0 : 260.0;
        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: _NoteListColumn(
                notes: notes,
                selectedId: selected?.id,
                newestFirst: newestFirst,
                onSort: () => setState(() => newestFirst = !newestFirst),
                onSelect: (id) => controller.selectNote(id),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: tokens.border),
            Expanded(
              child: selected == null
                  ? _EmptyNoteEditor(tokens: tokens)
                  : _NoteEditor(
                      note: selected,
                      controller: controller,
                      folders: controller.folders,
                      onDelete: () => _deleteNote(selected.id),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<NoteItem> _visibleNotes() {
    final controller = widget.controller;
    final selectedFolderId = controller.notesFolderFilter;
    final notes = controller.activeNotes.where((note) {
      if (controller.notesFavoritesOnly) return note.isFavorite;
      if (controller.notesUnfiledOnly) return note.folderId == null;
      if (selectedFolderId == null) return true;
      MigrationFolderRecord? folder;
      for (final item in controller.folders) {
        if (item.id == selectedFolderId) {
          folder = item;
          break;
        }
      }
      return note.folderId == selectedFolderId ||
          (folder != null && note.folder == folder.name);
    }).toList();
    notes.sort((a, b) {
      final aDate = localDateTimeFromStorage(a.updatedAt ?? a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = localDateTimeFromStorage(b.updatedAt ?? b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return newestFirst ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });
    return notes;
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

class _NoteListColumn extends StatelessWidget {
  const _NoteListColumn({
    required this.notes,
    required this.selectedId,
    required this.newestFirst,
    required this.onSort,
    required this.onSelect,
  });

  final List<NoteItem> notes;
  final String? selectedId;
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
  bool _hasBodySelection = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note.title);
    bodyController = TextEditingController(text: _bodyFor(widget.note));
    titleFocusNode = FocusNode();
    bodyFocusNode = FocusNode();
    bodyController.addListener(_updateSelectionState);
  }

  void _updateSelectionState() {
    final hasSelection = _selectedBodyText().isNotEmpty;
    if (hasSelection != _hasBodySelection && mounted) {
      setState(() => _hasBodySelection = hasSelection);
    }
  }

  String _selectedBodyText() {
    final selection = bodyController.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return bodyController.text.substring(selection.start, selection.end).trim();
  }

  void _generateTaskFromSelection() {
    final text = _selectedBodyText();
    if (text.isEmpty) return;
    // 行动项取选区首行；原文保持不动，任务带回源笔记链接。
    widget.controller
        .addTaskFromNote(widget.note.id, text.split('\n').first.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已创建任务，可从下方关联任务列表进入')));
    }
  }

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(titleController, widget.note.title, titleFocusNode);
    _sync(bodyController, _bodyFor(widget.note), bodyFocusNode);
  }

  @override
  void dispose() {
    bodyController.removeListener(_updateSelectionState);
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
                    if (note.hasPreservedRichContent) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: tokens.accentFaint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: tokens.accent.withOpacity(.16)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 15, color: tokens.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '这条笔记含链接或列表等富文本。追加新行会保留原结构；如需自由改写，请先转换为纯文本副本。',
                                style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 11,
                                    height: 1.4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _convertRichToPlainText,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('转换'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton.icon(
                          key: const ValueKey('generate-task-from-selection'),
                          onPressed: _hasBodySelection
                              ? _generateTaskFromSelection
                              : null,
                          icon: Icon(Icons.playlist_add_check_rounded,
                              size: 15,
                              color: _hasBodySelection
                                  ? tokens.accent
                                  : tokens.textTertiary),
                          label: Text('从选中生成任务',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _hasBodySelection
                                      ? tokens.accent
                                      : tokens.textTertiary)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (!_hasBodySelection)
                          Text('先选中一段行动项',
                              style: TextStyle(
                                  color: tokens.textTertiary, fontSize: 10.5)),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    _LinkedTasksSection(
                        controller: widget.controller, noteId: note.id),
                  ],
                ),
              ),
            ),
          ),
          SaveStatusFooter(
            controller: widget.controller,
            trailing: noteUpdatedLabelFor(note.updatedAt),
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
            if (widget.note.hasPreservedRichContent)
              ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: const Text('转换为纯文本副本'),
                  onTap: () => Navigator.of(sheetContext).pop('convert')),
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
    } else if (action == 'convert') {
      await _convertRichToPlainText();
    } else if (action == 'delete') {
      widget.onDelete();
    }
  }

  Future<void> _convertRichToPlainText() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('转换为纯文本副本？'),
        content: const Text('转换会移除链接、列表和其他富文本格式，但当前显示的正文会保留。原导入文件仍可从 Web 端重新导出。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('转换')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.controller.convertNoteToPlainText(widget.note.id);
  }
}

class ClipboardHelper {
  static Future<void> copy(String value) async {
    // Imported lazily to keep this file's widget code easy to scan.
    await Clipboard.setData(ClipboardData(text: value));
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

/// The "执行后回到记录" half of the loop: tasks generated from this note,
/// with live completion status.
class _LinkedTasksSection extends StatelessWidget {
  const _LinkedTasksSection({required this.controller, required this.noteId});

  final WorkspaceController controller;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks = controller.tasksLinkedToNote(noteId);
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: tokens.border),
        const SizedBox(height: 18),
        Text(
            '关联任务 · ${tasks.where((task) => task.completed).length}/${tasks.length} 完成',
            style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => controller.openTask(task.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => controller.toggleTask(task.id),
                        child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: task.completed
                                    ? tokens.success
                                    : Colors.transparent,
                                border: Border.all(
                                    color: task.completed
                                        ? tokens.success
                                        : tokens.borderStrong,
                                    width: 1.4)),
                            child: task.completed
                                ? const Icon(Icons.check_rounded,
                                    size: 11, color: Colors.white)
                                : null),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: task.completed
                                  ? tokens.textTertiary
                                  : tokens.textPrimary,
                              fontSize: 12.5,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(task.timeLabel ?? '未安排',
                          style: TextStyle(
                              color: tokens.textTertiary, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
