import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/note_document_editor.dart';
import '../widgets/save_status_footer.dart';

/// Notes workspace: a canvas-coloured list of note cards on the left and a
/// focused writing page on the right (single column on narrow windows).
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  // Web notes use a 300pt note index on the wide desktop and 270pt in the
  // compact desktop media query. NotesScreen receives the width remaining
  // after the native merged rail, hence the local breakpoint below.
  static const double _wideNotesBreakpoint = 1100;
  static const double _notesListWidth = 300;
  static const double _compactNotesListWidth = 270;
  static const double _notesHeaderHeight = 66;
  static const double _notesSearchHeight = 38;
  static const double _editorContentMaxWidth = 960;

  String query = '';
  bool newestFirst = true;
  bool detailOnly = false;
  late int openVersion;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    openVersion = widget.controller.noteOpenVersion;
    detailOnly = widget.controller.selectedNoteId != null && openVersion > 0;
  }

  @override
  void didUpdateWidget(covariant NotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (openVersion != widget.controller.noteOpenVersion) {
      openVersion = widget.controller.noteOpenVersion;
      detailOnly = true;
      query = '';
      search.clear();
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<NoteItem> visible() {
    final c = widget.controller;
    final notes = c.activeNotes.where((note) {
      if (c.notesFavoritesOnly && !note.isFavorite) return false;
      if (c.notesUnfiledOnly && note.folderId != null) return false;
      if (c.notesFolderFilter != null && note.folderId != c.notesFolderFilter)
        return false;
      return query.isEmpty ||
          '${note.title}\n${note.plainText ?? note.preview}'
              .toLowerCase()
              .contains(query.toLowerCase());
    }).toList();
    notes.sort((a, b) => newestFirst
        ? (b.updatedAt ?? '').compareTo(a.updatedAt ?? '')
        : a.title.compareTo(b.title));
    return notes;
  }

  void create() {
    setState(() {
      query = '';
      search.clear();
      detailOnly = true;
    });
    widget.controller.addNoteInCurrentFolder();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, tokens = WorkFollowTheme.of(context);
    final notes = visible();
    final selected =
        notes.where((note) => note.id == c.selectedNoteId).firstOrNull ??
            notes.firstOrNull;
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final list = Container(
          color: tokens.content,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _notesHeaderHeight),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c.notesFavoritesOnly ? '收藏笔记' : '笔记',
                          style: TextStyle(
                              fontSize: WorkFollowTypography.webBody,
                              fontWeight: FontWeight.w600,
                              color: tokens.textPrimary)),
                      const SizedBox(height: 2),
                      Text('${notes.length} 条笔记',
                          style: TextStyle(
                              fontSize: WorkFollowTypography.webCaption,
                              color: tokens.textTertiary)),
                    ])),
                _NewNoteButton(onCreate: create),
              ]),
            ),
            SizedBox(
              height: _notesSearchHeight,
              child: TextField(
                  controller: search,
                  onChanged: (value) => setState(() => query = value),
                  style:
                      const TextStyle(fontSize: WorkFollowTypography.webBody),
                  decoration: InputDecoration(
                      hintText: '搜索笔记',
                      prefixIcon: const AppIcon(WorkFollowIcons.search,
                          size: WorkFollowMetrics.toolbarIcon),
                      isDense: true,
                      filled: true,
                      fillColor: tokens.canvas,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(WorkFollowRadii.md),
                          borderSide: BorderSide.none))),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Row(children: [
                const Spacer(),
                TextButton(
                    onPressed: () => setState(() => newestFirst = !newestFirst),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(newestFirst ? '最近编辑' : '按标题',
                        style: const TextStyle(
                            fontSize: WorkFollowTypography.webCaption))),
              ]),
            ),
            Expanded(
                child: notes.isEmpty
                    ? Center(
                        child: Text(query.isEmpty ? '从一条新笔记开始' : '没有找到相关笔记',
                            style: TextStyle(
                                fontSize: 13, color: tokens.textTertiary)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index],
                              isSelected = selected?.id == notes[index].id;
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _NoteCard(
                                note: note,
                                selected: isSelected,
                                onTap: () {
                                  c.selectNote(note.id);
                                  if (narrow) setState(() => detailOnly = true);
                                },
                              ));
                        })),
          ]));
      final page = selected == null
          ? _EmptyNote(onCreate: create)
          : _NotePage(
              key: ValueKey(selected.id),
              note: selected,
              controller: c,
              onBack: narrow ? () => setState(() => detailOnly = false) : null);
      if (narrow)
        return Stack(fit: StackFit.expand, children: [
          Offstage(offstage: detailOnly && selected != null, child: list),
          if (detailOnly && selected != null) page,
        ]);
      final listWidth = constraints.maxWidth >= _wideNotesBreakpoint
          ? _notesListWidth
          : _compactNotesListWidth;
      return Row(children: [
        SizedBox(
            key: const ValueKey('web-note-list-pane'),
            width: listWidth,
            child: list),
        VerticalDivider(width: 1, color: tokens.border),
        Expanded(
            child: KeyedSubtree(
                key: const ValueKey('web-note-editor-pane'), child: page))
      ]);
    });
  }
}

/// Round accent button that starts a new note.
class _NewNoteButton extends StatelessWidget {
  const _NewNoteButton({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Tooltip(
        message: '新建笔记',
        child: Material(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            child: InkWell(
                borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                onTap: onCreate,
                child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: AppIcon(WorkFollowIcons.add,
                        size: WorkFollowMetrics.toolbarIcon,
                        color: Colors.white)))));
  }
}

/// One note card in the list: title, two-line preview and a meta footer.
class _NoteCard extends StatefulWidget {
  const _NoteCard(
      {required this.note, required this.selected, required this.onTap});

  final NoteItem note;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context), note = widget.note;
    return MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
                duration: WorkFollowMotion.instant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                    // Web note rows are flat. Use a quiet selected surface
                    // instead of a card border and shadow so the editor stays
                    // the visual focus.
                    color: widget.selected
                        ? tokens.accentSoft
                        : hovering
                            ? tokens.canvas
                            : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(WorkFollowRadii.control),
                    border: Border(
                        bottom: BorderSide(
                            color: tokens.border.withValues(alpha: .72)))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (note.isFavorite) ...[
                          AppIcon(WorkFollowIcons.favorite,
                              size: WorkFollowMetrics.metadataIcon,
                              color: tokens.warning),
                          const SizedBox(width: 5)
                        ],
                        Expanded(
                            child: Text(note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: WorkFollowTypography.webLabel,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary))),
                      ]),
                      const SizedBox(height: 4),
                      Text(note.preview.isEmpty ? '还没有内容' : note.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowTypography.webMicro,
                              height: WorkFollowTypography.webLineHeightNormal,
                              color: tokens.textSecondary)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Text(noteUpdatedLabelFor(note.updatedAt),
                            style: TextStyle(
                                fontSize: WorkFollowTypography.webMicro,
                                color: tokens.textTertiary)),
                        const Spacer(),
                        Flexible(
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                    color: tokens.accent.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.pill)),
                                child: Text(note.folder,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: WorkFollowTypography.webMicro,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textSecondary)))),
                      ]),
                    ]))));
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        color: tokens.content,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .09),
                  shape: BoxShape.circle),
              child: AppIcon(WorkFollowIcons.editNote,
                  size: WorkFollowMetrics.railIcon + 8, color: tokens.accent)),
          const SizedBox(height: 18),
          Text('给想法一个安静的地方',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary)),
          const SizedBox(height: 8),
          Text('写下笔记，把下一步变成任务。',
              style: TextStyle(fontSize: 12.5, color: tokens.textTertiary)),
          const SizedBox(height: 22),
          FilledButton.icon(
              onPressed: onCreate,
              icon: const AppIcon(WorkFollowIcons.add,
                  size: WorkFollowMetrics.toolbarIcon),
              label: const Text('新建笔记')),
        ]));
  }
}

class _NotePage extends StatefulWidget {
  const _NotePage(
      {super.key, required this.note, required this.controller, this.onBack});
  final NoteItem note;
  final WorkspaceController controller;
  final VoidCallback? onBack;
  @override
  State<_NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<_NotePage> {
  late final title = TextEditingController(
      text: widget.note.title == '未命名笔记' ? '' : widget.note.title);
  final titleFocus = FocusNode();
  @override
  void dispose() {
    title.dispose();
    titleFocus.dispose();
    super.dispose();
  }

  Future<void> move(BuildContext anchor) async {
    final choice = await showDesktopMenu<String>(anchor,
        selected: widget.note.folderId ?? '',
        entries: [
          const DesktopMenuEntry('', '未归档', icon: WorkFollowIcons.folder),
          for (final folder in widget.controller.folders)
            DesktopMenuEntry(folder.id, folder.name,
                icon: WorkFollowIcons.folder),
        ]);
    if (choice != null)
      widget.controller
          .moveNoteToFolder(widget.note.id, choice.isEmpty ? null : choice);
  }

  Future<void> more(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(anchor, entries: [
      const DesktopMenuEntry('copy', '复制笔记正文', icon: WorkFollowIcons.copy),
      if (widget.note.hasPreservedRichContent)
        const DesktopMenuEntry('plain', '创建纯文本副本', icon: WorkFollowIcons.text),
      const DesktopMenuEntry('delete', '移到废纸篓',
          icon: WorkFollowIcons.delete, destructive: true),
    ]);
    if (action == 'copy')
      await Clipboard.setData(
          ClipboardData(text: widget.note.plainText ?? widget.note.preview));
    if (action == 'plain')
      widget.controller.convertNoteToPlainText(widget.note.id);
    if (action == 'delete') widget.controller.removeNote(widget.note.id);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context), note = widget.note;
    final linked = widget.controller.tasksLinkedToNote(note.id);
    return Container(
        color: tokens.content,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(children: [
                if (widget.onBack != null)
                  IconButton(
                      tooltip: '返回笔记列表',
                      onPressed: widget.onBack,
                      icon: const AppIcon(WorkFollowIcons.back,
                          size: WorkFollowMetrics.headerIcon)),
                PropertyButton(
                    icon: WorkFollowIcons.folder,
                    label: note.folder,
                    onPressed: move),
                const Spacer(),
                IconButton(
                    tooltip: note.isFavorite ? '取消收藏' : '收藏笔记',
                    onPressed: () =>
                        widget.controller.toggleNoteFavorite(note.id),
                    icon: AppIcon(
                        note.isFavorite
                            ? WorkFollowIcons.favorite
                            : WorkFollowIcons.favoriteOutline,
                        color: note.isFavorite
                            ? tokens.warning
                            : tokens.textTertiary,
                        size: WorkFollowMetrics.navigationIcon)),
                Builder(
                    builder: (anchor) => IconButton(
                        key: const ValueKey('note-more-actions'),
                        tooltip: '笔记操作',
                        onPressed: () => more(anchor),
                        icon: AppIcon(WorkFollowIcons.more,
                            size: WorkFollowMetrics.headerIcon,
                            color: tokens.textTertiary))),
              ])),
          Expanded(
              child: SingleChildScrollView(
                  child: Center(
                      child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: _NotesScreenState._editorContentMaxWidth),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 44),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                          key: const ValueKey('note-title-editor'),
                          controller: title,
                          focusNode: titleFocus,
                          autofocus: note.title == '未命名笔记',
                          minLines: 1,
                          maxLines: 3,
                          style: TextStyle(
                              fontSize: WorkFollowTypography.webEditorTitleSize,
                              height: WorkFollowTypography.webLineHeightSnug,
                              fontWeight: FontWeight.w600,
                              letterSpacing:
                                  WorkFollowTypography.webTrackingTight,
                              color: tokens.textPrimary),
                          decoration: const InputDecoration(
                              hintText: '笔记标题',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero),
                          onChanged: (value) => widget.controller
                              .updateNoteTitle(note.id, value)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Text('最近编辑于 ${noteUpdatedLabelFor(note.updatedAt)}',
                            style: TextStyle(
                                fontSize: WorkFollowTypography.caption,
                                color: tokens.textTertiary)),
                        const Spacer(),
                        SoftPill(
                            label:
                                '${(note.plainText ?? note.preview).replaceAll(RegExp(r'\s'), '').runes.length} 字'),
                      ]),
                      const SizedBox(height: 16),
                      NoteDocumentEditor(
                          key: ValueKey('document-${note.id}'),
                          note: note,
                          controller: widget.controller),
                      if (linked.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        Row(children: [
                          Text('关联任务',
                              style: TextStyle(
                                  fontSize: WorkFollowTypography.field,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textSecondary)),
                          const SizedBox(width: 6),
                          Text('${linked.length}',
                              style: TextStyle(
                                  fontSize: WorkFollowTypography.caption,
                                  color: tokens.textTertiary)),
                        ]),
                        const SizedBox(height: 8),
                        for (final task in linked)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _LinkedTaskRow(
                                  task: task,
                                  onToggle: () => task.completed
                                      ? widget.controller.taskActions
                                          .restore(task.id)
                                      : widget.controller.taskActions
                                          .complete(task.id),
                                  onOpen: () =>
                                      widget.controller.openTask(task.id))),
                      ],
                    ])),
          )))),
          SaveStatusFooter(controller: widget.controller),
        ]));
  }
}

/// One linked task under the note body: checkbox + open-on-tap title.
class _LinkedTaskRow extends StatelessWidget {
  const _LinkedTaskRow(
      {required this.task, required this.onToggle, required this.onOpen});

  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        decoration: BoxDecoration(
            color: tokens.accent.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
            border: Border.all(color: tokens.border)),
        child: Row(children: [
          SizedBox(
              width: 26,
              height: 30,
              child: Checkbox(
                  value: task.completed,
                  shape: const CircleBorder(),
                  side: BorderSide(color: tokens.borderStrong, width: 1.4),
                  onChanged: (_) => onToggle())),
          const SizedBox(width: 8),
          Expanded(
              child: InkWell(
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  onTap: onOpen,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowTypography.field,
                              fontWeight: FontWeight.w500,
                              color: task.completed
                                  ? tokens.textTertiary
                                  : tokens.textPrimary,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null))))),
          AppIcon(WorkFollowIcons.next,
              size: WorkFollowMetrics.navigationIcon,
              color: tokens.textTertiary),
        ]));
  }
}
