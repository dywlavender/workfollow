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
          color: tokens.canvas,
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c.notesFavoritesOnly ? '收藏笔记' : '笔记',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.4,
                            color: tokens.textPrimary)),
                    const SizedBox(height: 4),
                    Text('${notes.length} 条笔记',
                        style: TextStyle(
                            fontSize: 12, color: tokens.textTertiary)),
                  ])),
              _NewNoteButton(onCreate: create),
            ]),
            const SizedBox(height: 14),
            TextField(
                controller: search,
                onChanged: (value) => setState(() => query = value),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    hintText: '搜索笔记',
                    prefixIcon: const AppIcon(WorkFollowIcons.search,
                        size: WorkFollowMetrics.navigationIcon),
                    isDense: true,
                    filled: true,
                    fillColor: tokens.content,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.control),
                        borderSide: BorderSide.none))),
            const SizedBox(height: 10),
            Row(children: [
              const Spacer(),
              TextButton(
                  onPressed: () => setState(() => newestFirst = !newestFirst),
                  child: Text(newestFirst ? '最近编辑' : '按标题',
                      style: const TextStyle(fontSize: 12))),
            ]),
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
      return Row(children: [
        SizedBox(width: 286, child: list),
        VerticalDivider(width: 1, color: tokens.border),
        Expanded(child: page)
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
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: tokens.content,
                    borderRadius: BorderRadius.circular(WorkFollowRadii.card),
                    border: Border.all(
                        color: widget.selected
                            ? tokens.accent.withValues(alpha: .5)
                            : hovering
                                ? tokens.borderStrong
                                : tokens.border),
                    boxShadow: widget.selected
                        ? [
                            BoxShadow(
                                color: tokens.shadow,
                                blurRadius: 10,
                                offset: const Offset(0, 2))
                          ]
                        : null),
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary))),
                      ]),
                      const SizedBox(height: 6),
                      Text(note.preview.isEmpty ? '还没有内容' : note.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: tokens.textSecondary)),
                      const SizedBox(height: 9),
                      Row(children: [
                        Text(noteUpdatedLabelFor(note.updatedAt),
                            style: TextStyle(
                                fontSize: 11, color: tokens.textTertiary)),
                        const Spacer(),
                        Flexible(
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                    color: tokens.accent.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(
                                        WorkFollowRadii.pill)),
                                child: Text(note.folder,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
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
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
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
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 26, 36, 44),
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
                              fontSize: 28,
                              height: 1.3,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
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
                                fontSize: 11, color: tokens.textTertiary)),
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textSecondary)),
                          const SizedBox(width: 6),
                          Text('${linked.length}',
                              style: TextStyle(
                                  fontSize: 11, color: tokens.textTertiary)),
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
                              fontSize: 13,
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
