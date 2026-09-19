import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/editor/presentation/document_editor_footer.dart';
import '../features/editor/presentation/document_editor_shell.dart';
import '../features/editor/presentation/document_formatting_toggle.dart';
import '../features/editor/presentation/document_save_status.dart';
import '../features/editor/presentation/document_title_editor.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme_parity.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/note_document_editor.dart';
import '../widgets/task_completion_box.dart';

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
  static const double _notesListWidth = NotesMetrics.listWidth;
  static const double _compactNotesListWidth = NotesMetrics.compactListWidth;
  static const double _notesHeaderHeight = NotesMetrics.headerHeight;
  static const double _notesSearchHeight = NotesMetrics.searchHeight;
  static const double _editorContentMaxWidth =
      NotesMetrics.editorContentMaxWidth;

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
          padding: const EdgeInsets.fromLTRB(
              WorkFollowSpacing.cardInset,
              WorkFollowSpacing.zero,
              WorkFollowSpacing.cardInset,
              WorkFollowSpacing.sectionGap),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // One header line: what this pane is and the one action that
            // creates. The count that used to follow the title is gone — the
            // navigation column beside it already counts 全部笔记, 收藏, 未归档
            // and every folder, so the index only repeated the number in a
            // second place that the user has to reconcile.
            SizedBox(
              height: _notesHeaderHeight,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(c.notesFavoritesOnly ? '收藏笔记' : '笔记',
                    style: TextStyle(
                        fontSize: WorkFollowMacTypography.listTitle,
                        fontWeight: WorkFollowMacWeight.semibold,
                        color: tokens.textPrimary)),
                const Spacer(),
                _NewNoteButton(onCreate: create),
              ]),
            ),
            SizedBox(
              height: _notesSearchHeight,
              child: Row(children: [
                Expanded(
                    child: _NoteSearchField(
                        controller: search,
                        onChanged: (value) => setState(() => query = value))),
                const SizedBox(width: WorkFollowSpacing.space1),
                _NoteSortButton(
                    newestFirst: newestFirst,
                    onPressed: () =>
                        setState(() => newestFirst = !newestFirst)),
              ]),
            ),
            const SizedBox(height: WorkFollowSpacing.space2),
            Expanded(
                child: notes.isEmpty
                    ? Center(
                        child: Text(query.isEmpty ? '从一条新笔记开始' : '没有找到相关笔记',
                            style: TextStyle(
                                fontSize: WorkFollowMacTypography.supporting,
                                color: tokens.textTertiary)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                            top: WorkFollowSpacing.microGap,
                            bottom: WorkFollowSpacing.space2),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index],
                              isSelected = selected?.id == notes[index].id;
                          final next = index + 1 < notes.length
                              ? notes[index + 1]
                              : null;
                          return _NoteRow(
                            note: note,
                            selected: isSelected,
                            // The open row paints a rounded fill and is its own
                            // separation; every other row is divided from the
                            // next one, never from the fill.
                            divider: !isSelected &&
                                next != null &&
                                selected?.id != next.id,
                            onTap: () {
                              c.selectNote(note.id);
                              if (narrow) setState(() => detailOnly = true);
                            },
                          );
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
        VerticalDivider(
            width: WorkFollowMetrics.dividerThickness, color: tokens.border),
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
                child: SizedBox(
                    width: NotesMetrics.newNoteButtonSize,
                    height: NotesMetrics.newNoteButtonSize,
                    child: AppIcon(WorkFollowIcons.add,
                        size: WorkFollowMetrics.toolbarIcon,
                        color: WorkFollowThemeContrast.foregroundOn(
                            tokens.accent))))));
  }
}

/// The note index's search field.
///
/// A resting border made this read as a web input dropped into a native list.
/// It is a quiet inset field instead: a canvas fill at rest, and on focus the
/// fill turns to the content colour and a 1pt primary edge appears, so the
/// control announces itself only while it is being typed in.
class _NoteSearchField extends StatefulWidget {
  const _NoteSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteSearchField> createState() => _NoteSearchFieldState();
}

class _NoteSearchFieldState extends State<_NoteSearchField> {
  final focus = FocusNode();
  bool focused = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (mounted) setState(() => focused = focus.hasFocus);
    });
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        height: NotesMetrics.searchHeight,
        decoration: BoxDecoration(
            color: focused ? tokens.content : tokens.canvas,
            borderRadius: BorderRadius.circular(WorkFollowRadii.md),
            border: Border.all(
                color: focused ? tokens.accent : Colors.transparent,
                width: WorkFollowMetrics.dividerThickness)),
        child: Row(children: [
          const SizedBox(width: WorkFollowSpacing.compactInset),
          AppIcon(WorkFollowIcons.search,
              size: WorkFollowMetrics.metadataIcon,
              color: focused ? tokens.textSecondary : tokens.textTertiary),
          const SizedBox(width: WorkFollowSpacing.inlineGap),
          Expanded(
              child: TextField(
                  controller: widget.controller,
                  focusNode: focus,
                  onChanged: widget.onChanged,
                  style: const TextStyle(
                      fontSize: WorkFollowMacTypography.control),
                  decoration: InputDecoration(
                      hintText: '搜索笔记',
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          color: tokens.textTertiary)))),
          const SizedBox(width: WorkFollowSpacing.compactInset),
        ]));
  }
}

/// The index order toggle. It sits on the search line rather than under it: the
/// label ("最近编辑" / "按标题") was a full row of the pane for one bit of state.
class _NoteSortButton extends StatelessWidget {
  const _NoteSortButton({required this.newestFirst, required this.onPressed});

  final bool newestFirst;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Tooltip(
        message: newestFirst ? '按最近编辑' : '按标题',
        child: IconButton(
            key: const ValueKey('notes-sort-toggle'),
            onPressed: onPressed,
            icon: AppIcon(WorkFollowIcons.sort,
                size: WorkFollowMetrics.toolbarIcon,
                color: tokens.textTertiary)));
  }
}

/// One row of the note index: title and preview on the left, the folder and
/// the timestamp in a trailing metadata column.
///
/// It is a row, not a card. The previous version drew a rounded container with
/// a bottom border, which gave the open note a filled block that the other rows
/// did not have — two visual languages in one list. Selection is now a soft
/// primary fill at the same 8pt radius, and every other row is separated by a
/// hairline inset to the text column.
///
/// The metadata moved to the trailing edge to match the task rows: the date
/// used to sit at the leading edge of a full-width line, so the row read
/// left-to-right as two unrelated facts with a gap between them.
class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.note,
    required this.selected,
    required this.divider,
    required this.onTap,
  });

  final NoteItem note;
  final bool selected;
  final bool divider;
  final VoidCallback onTap;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context), note = widget.note;
    // See _IconRailButtonState in sidebar.dart: the surface fill never eases.
    return MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
            onTap: widget.onTap,
            child: Column(children: [
              Container(
                  key: ValueKey('note-row-${note.id}'),
                  constraints: const BoxConstraints(
                      minHeight: NotesMetrics.rowMinHeight),
                  padding: const EdgeInsets.symmetric(
                      horizontal: NotesMetrics.rowHorizontalPadding,
                      vertical: NotesMetrics.rowVerticalPadding),
                  decoration: BoxDecoration(
                      color: NotesColors.rowFill(tokens,
                          selected: widget.selected, hovering: hovering),
                      borderRadius:
                          BorderRadius.circular(NotesMetrics.rowRadius)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                if (note.isFavorite) ...[
                                  AppIcon(WorkFollowIcons.favorite,
                                      size: WorkFollowMetrics.metadataIcon,
                                      color: tokens.warning),
                                  const SizedBox(
                                      width: WorkFollowSpacing.denseGap)
                                ],
                                Expanded(
                                    child: Text(note.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: WorkFollowMacTypography
                                                .listTitle,
                                            fontWeight:
                                                WorkFollowMacWeight.semibold,
                                            color: tokens.textPrimary))),
                              ]),
                              const SizedBox(height: WorkFollowSpacing.space1),
                              // One line, same reason the task rows keep one:
                              // the note index is a list to scan, and a
                              // preview that wraps turns each card into a
                              // different height.
                              Text(
                                  note.preview.isEmpty ? '还没有内容' : note.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize:
                                          WorkFollowMacTypography.listBody,
                                      height: WorkFollowMacTypography.lineList,
                                      color: tokens.textSecondary)),
                            ])),
                        const SizedBox(width: NotesMetrics.rowMetaGap),
                        // Folder above, timestamp below: the same order the task
                        // rows use for list name and date.
                        ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxWidth: NotesMetrics.rowMetaMaxWidth),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(note.folder,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize:
                                              WorkFollowMacTypography.listMeta,
                                          color: tokens.textTertiary)),
                                  const SizedBox(
                                      height: WorkFollowSpacing.space1),
                                  Text(noteUpdatedLabelFor(note.updatedAt),
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize:
                                              WorkFollowMacTypography.listMeta,
                                          color: tokens.textTertiary)),
                                ])),
                      ])),
              if (widget.divider)
                Container(
                    height: WorkFollowMetrics.dividerThickness,
                    margin: const EdgeInsets.symmetric(
                        horizontal: NotesMetrics.rowDividerInset),
                    color: tokens.border),
            ])));
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
              width: NotesMetrics.emptyStateIconSize,
              height: NotesMetrics.emptyStateIconSize,
              decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .09),
                  shape: BoxShape.circle),
              child: AppIcon(WorkFollowIcons.editNote,
                  size: WorkFollowMetrics.railIcon + 8, color: tokens.accent)),
          const SizedBox(height: WorkFollowSpacing.sectionGap),
          Text('给想法一个安静的地方',
              style: TextStyle(
                  fontSize: WorkFollowMacTypography.detailTitle,
                  fontWeight: WorkFollowMacWeight.semibold,
                  color: tokens.textPrimary)),
          const SizedBox(height: WorkFollowSpacing.space2),
          Text('写下笔记，把下一步变成任务。',
              style: TextStyle(
                  fontSize: WorkFollowMacTypography.supporting,
                  color: tokens.textTertiary)),
          const SizedBox(height: WorkFollowSpacing.headingGap),
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

  /// Handle on the note's document editor.
  ///
  /// The formatting trigger is page chrome — it rides the bottom status row
  /// instead of trailing the prose, where a short note left it stranded in the
  /// middle of the page. The page therefore has to reach into the editor to
  /// open the toolbar, and to read back whether it is currently up.
  final documentKey = GlobalKey<DocumentEditorState>();
  bool formatToolbarVisible = false;

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
    final wordCount = (note.plainText ?? note.preview)
        .replaceAll(RegExp(r'\s'), '')
        .runes
        .length;
    return DocumentEditorShell(
      backgroundColor: tokens.content,
      header: SizedBox(
          height: NotesMetrics.editorHeaderHeight,
          child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: NotesMetrics.editorHeaderHorizontalPadding),
              child: Row(children: [
                if (widget.onBack != null)
                  IconButton(
                      tooltip: '返回笔记列表',
                      onPressed: widget.onBack,
                      icon: const AppIcon(WorkFollowIcons.back,
                          size: WorkFollowMetrics.headerIcon)),
                _NoteFolderLink(folder: note.folder, onPressed: move),
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
              ]))),
      body: Expanded(
          child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                  child: GestureDetector(
                      // The blank area under the prose belongs to the page,
                      // not to the document. Tapping it puts the caret back
                      // in the document — which is exactly why the document
                      // no longer has to grow to fill the pane, and why the
                      // sections below it follow the text instead of being
                      // pushed into the middle of the page.
                      behavior: HitTestBehavior.translucent,
                      onTap: () => documentKey.currentState?.focusEnd(),
                      child: Center(
                          child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: _NotesScreenState._editorContentMaxWidth,
                            minHeight: viewport.maxHeight),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                WorkFollowSpacing.space7,
                                WorkFollowSpacing.relaxedGap,
                                WorkFollowSpacing.space7,
                                WorkFollowSpacing.editorBottomPadding),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DocumentTitleEditor(
                                    fieldKey:
                                        const ValueKey('note-title-editor'),
                                    controller: title,
                                    focusNode: titleFocus,
                                    autofocus: note.title == '未命名笔记',
                                    maxLines: 3,
                                    fontSize: WorkFollowMacTypography.noteTitle,
                                    placeholder: '笔记标题',
                                    onChanged: (value) => widget.controller
                                        .updateNoteTitle(note.id, value),
                                  ),
                                  const SizedBox(
                                      height: WorkFollowSpacing.space3),
                                  // The page's timestamp carries the clock. "最近编辑于" is
                                  // a sentence explaining what a timestamp is; the position
                                  // under the title already says it.
                                  Text(noteUpdatedStampFor(note.updatedAt),
                                      style: TextStyle(
                                          fontSize:
                                              WorkFollowMacTypography.listMeta,
                                          color: tokens.textTertiary)),
                                  const SizedBox(
                                      height: WorkFollowSpacing.space5),
                                  Container(
                                      height:
                                          WorkFollowMetrics.dividerThickness,
                                      color: tokens.border),
                                  const SizedBox(
                                      height: WorkFollowSpacing.space5),
                                  NoteDocumentEditor(
                                      key: ValueKey('document-${note.id}'),
                                      editorKey: documentKey,
                                      onToolbarChanged: (visible) {
                                        if (mounted) {
                                          setState(() =>
                                              formatToolbarVisible = visible);
                                        }
                                      },
                                      note: note,
                                      controller: widget.controller),
                                  if (linked.isNotEmpty) ...[
                                    const SizedBox(
                                        height:
                                            WorkFollowSpacing.emptyStateGap),
                                    Row(children: [
                                      Text('关联任务',
                                          style: TextStyle(
                                              fontSize: WorkFollowMacTypography
                                                  .control,
                                              fontWeight:
                                                  WorkFollowMacWeight.semibold,
                                              color: tokens.textSecondary)),
                                      const SizedBox(
                                          width: WorkFollowSpacing.inlineGap),
                                      Text('${linked.length}',
                                          style: TextStyle(
                                              fontSize: WorkFollowMacTypography
                                                  .listMeta,
                                              color: tokens.textTertiary)),
                                    ]),
                                    const SizedBox(
                                        height: WorkFollowSpacing.space2),
                                    for (final task in linked)
                                      Padding(
                                          padding: const EdgeInsets.only(
                                              bottom:
                                                  WorkFollowSpacing.inlineGap),
                                          child: _LinkedTaskRow(
                                              key: ValueKey(
                                                  'note-linked-task-${task.id}'),
                                              task: task,
                                              onToggle: () => task.completed
                                                  ? widget
                                                      .controller.taskActions
                                                      .restore(task.id)
                                                  : widget
                                                      .controller.taskActions
                                                      .complete(task.id),
                                              onOpen: () => widget.controller
                                                  .openTask(task.id))),
                                  ],
                                ])),
                      )))))),
      footer: DocumentEditorFooter(
        leading: Text('$wordCount 字',
            style: TextStyle(
                color: tokens.textTertiary,
                fontSize: WorkFollowMacTypography.caption)),
        status: DocumentSaveStatus(controller: widget.controller),
        actions: [
          DocumentFormattingToggle(
            active: formatToolbarVisible,
            onPressed: (anchor) =>
                unawaited(documentKey.currentState?.toggleToolbar(anchor)),
          ),
        ],
      ),
    );
  }
}

/// The note page's folder entry.
///
/// A filled chip in the header made the folder read as a status badge on the
/// document — the loudest control on a page whose subject is the writing. It is
/// an affordance, not a value: a quiet mark, the name, and a chevron that says
/// a menu is behind it.
class _NoteFolderLink extends StatefulWidget {
  const _NoteFolderLink({required this.folder, required this.onPressed});

  final String folder;
  final void Function(BuildContext anchor) onPressed;

  @override
  State<_NoteFolderLink> createState() => _NoteFolderLinkState();
}

class _NoteFolderLinkState extends State<_NoteFolderLink> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final foreground = hovering ? tokens.textPrimary : tokens.textSecondary;
    return Builder(
        builder: (anchor) => MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hovering = true),
            onExit: (_) => setState(() => hovering = false),
            child: GestureDetector(
                onTap: () => widget.onPressed(anchor),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: WorkFollowSpacing.space2,
                        vertical: WorkFollowSpacing.space1),
                    decoration: BoxDecoration(
                        color:
                            hovering ? tokens.listRowHover : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.sm)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(WorkFollowIcons.folder,
                          size: WorkFollowMetrics.metadataIcon,
                          color: foreground),
                      const SizedBox(width: WorkFollowSpacing.denseGap),
                      Text(widget.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.listMeta,
                              fontWeight: WorkFollowMacWeight.regular,
                              color: foreground)),
                      const SizedBox(width: WorkFollowSpacing.microGap),
                      AppIcon(WorkFollowIcons.chevronNext,
                          size: WorkFollowMetrics.metadataIcon,
                          color: foreground),
                    ])))));
  }
}

/// One linked task under the note body: checkbox + open-on-tap title.
class _LinkedTaskRow extends StatelessWidget {
  const _LinkedTaskRow(
      {super.key,
      required this.task,
      required this.onToggle,
      required this.onOpen});

  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        padding: const EdgeInsets.fromLTRB(
            WorkFollowSpacing.cardInset,
            WorkFollowSpacing.denseGap,
            WorkFollowSpacing.cardInset,
            WorkFollowSpacing.denseGap),
        decoration: BoxDecoration(
            color: tokens.accent.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
            border: Border.all(color: tokens.border)),
        child: Row(children: [
          SizedBox(
              width: NotesMetrics.linkedTaskCheckboxWidth,
              height: NotesMetrics.linkedTaskCheckboxHeight,
              child: Checkbox(
                  value: task.completed,
                  // A rounded square, not a circle: the shape a task row's own
                  // control has, so a task reads as the same kind of thing on
                  // a note as it does in the list, on the board and in the
                  // calendar. Only the size is the note's.
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          taskCompletionBoxRadius(
                              WorkFollowMetrics.platformCheckboxSize))),
                  side: BorderSide(color: tokens.borderStrong, width: 1.4),
                  onChanged: (_) => onToggle())),
          const SizedBox(width: WorkFollowSpacing.space2),
          Expanded(
              child: InkWell(
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  onTap: onOpen,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: WorkFollowSpacing.denseGap),
                      child: Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.control,
                              fontWeight: WorkFollowMacWeight.medium,
                              // Grey, not struck through: a finished linked
                              // task reads the way it does in the list, on the
                              // board and in the calendar.
                              color: task.completed
                                  ? tokens.textTertiary
                                  : tokens.textPrimary))))),
          AppIcon(WorkFollowIcons.next,
              size: WorkFollowMetrics.navigationIcon,
              color: tokens.textTertiary),
        ]));
  }
}
