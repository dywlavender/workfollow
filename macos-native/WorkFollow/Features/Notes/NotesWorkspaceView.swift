import AppKit
import SwiftUI

private enum NotesWorkspaceMetrics {
    static let contentInset: CGFloat = 28
    static let contentMaxWidth: CGFloat = 820
    /// TextKit 容器自带 5pt fragment padding，工具条内容原点扣掉后与标题/正文一致。
    static var toolbarLeadingPadding: CGFloat {
        contentInset - DocumentEditorPresentationMetrics.textContainerFragmentPadding
    }
}

struct NotesWorkspaceView: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var tasks: TaskWorkspaceModel
    var navigationVisible = true
    @EnvironmentObject private var environment: AppEnvironment
    @FocusState private var focusedTitle: UUID?
    @State private var showNavigation = false
    @State private var dragOrigin: CGFloat?
    @State private var query = ""
    private var folder: String? { notes.folderFilter }
    private var favorites: Bool { notes.favoritesOnly }
    @State private var detailOnly = false
    @State private var confirmClear = false
    @State private var purgeID: UUID?
    @State private var aiTaskRequest: AITaskRequest?
    @State private var aiRewriteRequest: NoteRewriteRequest?
    @StateObject private var editorHandle = DocumentEditorHandle()
    /// 浮窗打开时原编辑栏改成只读预览；独立身份避免与浮窗争同一份编辑状态。
    @State private var previewDocumentID = UUID()
    @ObservedObject private var floatingNotes = FloatingNoteWindowController.shared
    private var trash: Bool { navigation.destination == .notesTrash }
    private var rows: [Note] { notes.rows(trash: trash, query: query, folder: folder, favorites: favorites) }
    private var visibleNote: Note? { rows.first { $0.id == notes.selectedID } ?? rows.first }
    private func createNote() {
        query = ""
        notes.favoritesOnly = false
        notes.create(folder: folder)
        detailOnly = true
    }

    var body: some View {
        GeometryReader { geometry in
            // 双栏门槛与任务页/任务垃圾桶**共用同一个值**（原来非垃圾桶分支硬编码 760）。
            // 两个页面是 RootShellView 同一个 HStack 的兄弟节点，读到的是同一个内容区宽度，
            // 所以门槛可以直接比。各写各的时候，内容区宽度落在 [621,760) 这一段里
            // （窗口 674–812pt 或 871–1009pt），任务页已经是双栏、笔记页却 `wide = false`
            // → 列表铺满整页、检查器不渲染，切页时详情栏整个消失。
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            let maximum = max(WFMetrics.listMinimum, min(WFMetrics.listMaximum,
                geometry.size.width - WFMetrics.inspectorMinimum - WFMetrics.divider))
            // 与任务列表列共用同一宽度（原来这里按窗口宽度硬编码 330 / 300）。
            // 两个页面各写各的，用户在中栏之间切换就会看到忽宽忽窄；共用一个值之后，
            // 在哪一边拖分隔条，另一边也跟着变——这才是「宽度一致」。
            let paneWidth = min(max(tasks.taskListPaneWidth, WFMetrics.listMinimum), maximum)
            HStack(spacing: 0) {
                if wide || !detailOnly || visibleNote == nil {
                    list.frame(width: wide ? paneWidth : nil)
                        .frame(maxWidth: wide ? nil : .infinity)
                }
                if wide || (detailOnly && visibleNote != nil) {
                    if wide {
                        // 任务页与笔记页（含笔记垃圾桶）用同一条可拖分隔条。
                        // 原来非垃圾桶分支只放了个静态 `Divider()`，于是「共用一个宽度」
                        // 却只有任务页能改它——在笔记页够不着，等于半个功能。
                        Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
                            .overlay {
                                Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                                    .onHover { inside in
                                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                    }
                                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                        if dragOrigin == nil { dragOrigin = paneWidth }
                                        tasks.setTaskListPaneWidth(min(max((dragOrigin ?? paneWidth) + value.translation.width,
                                            WFMetrics.listMinimum), maximum))
                                    }.onEnded { _ in dragOrigin = nil })
                            }
                    }
                    inspector(compact: !wide)
                }
            }
        }
        .onChange(of: navigation.destination) { _, _ in detailOnly = false; query = "" }
        .onChange(of: notes.folderFilter) { _, _ in detailOnly = false; query = "" }
        .onChange(of: notes.favoritesOnly) { _, _ in detailOnly = false; query = "" }
        .onChange(of: notes.revealRequest) { _, _ in query = ""; detailOnly = true }
        .onAppear { if notes.revealRequest != nil { query = ""; detailOnly = true } }
        .sheet(item: $aiTaskRequest) { AITaskComposerView(request: $0) }
        .sheet(item: $aiRewriteRequest) { NoteRewriteComposerView(request: $0) }
        .alert("清空笔记垃圾桶", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("全部删除", role: .destructive) { notes.emptyTrash() }
        } message: { Text("垃圾桶中的笔记将被永久删除，无法恢复。任务不受影响。") }
        .alert("永久删除笔记？", isPresented: Binding(get: { purgeID != nil }, set: { if !$0 { purgeID = nil } })) {
            Button("取消", role: .cancel) { purgeID = nil }
            Button("删除", role: .destructive) { if let id = purgeID { notes.purge(id) }; purgeID = nil }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !navigationVisible || !environment.sidebarVisible {
                    Button { showNavigation.toggle() } label: { Image(systemName: "sidebar.left") }
                        .buttonStyle(.plain).hoverTip("笔记导航")
                        .background(AnchoredPropertyPanel(isPresented: $showNavigation,
                                                          width: WFMetrics.navigationWidth) {
                            NavigationColumnView(workspace: tasks, navigation: navigation,
                                filterStore: environment.filterStore, onNavigate: { showNavigation = false })
                                .frame(width: WFMetrics.navigationWidth, height: 480)
                        })
                }
                Text(trash ? "垃圾桶" : favorites ? "收藏笔记" : "笔记").font(WFType.pageTitle)
                Spacer()
                if trash {
                    Button("全部删除") { confirmClear = true }.disabled(!notes.notes.contains { $0.deletedAt != nil })
                } else {
                    Button(action: createNote) { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 6)).hoverTip("新建笔记")
                }
            }
            .frame(height: 44)
            if !trash { HStack(spacing: 4) {
                TextField("搜索笔记", text: $query).textFieldStyle(.roundedBorder)
                if !trash {
                    BusinessMenu {
                        Button("按标题排序") { notes.sort(.title) }
                        Button("按最近编辑排序") { notes.sort(.recentlyEdited) }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .fixedSize().hoverTip("笔记排序")
                }
            }.frame(height: 34) }
            ScrollView {
                // 行距 0：与任务列表同口径，也与滴答一致（它的相邻行顶边 = 上一行底边）。
                // 原来是 `spacing: 4`，再叠一条独立的 `Divider()`，于是带分割线的行
                // pitch 变成 61+4+1+4 = 70、选中行（不画线）变成 65——同一栏两种行距。
                LazyVStack(spacing: 0) {
                    if rows.isEmpty { Text(query.isEmpty ? (trash ? "笔记垃圾桶是空的" : "从一条新笔记开始") : "没有找到相关笔记").foregroundStyle(.secondary).padding() }
                    ForEach(rows) { note in
                        HStack(spacing: 4) {
                        Button { notes.selectedID = note.id; detailOnly = true } label: {
                            HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if note.favorite { Image(systemName: "star.fill") }
                                    if floatingNotes.isOpen(note.id) {
                                        Image(systemName: "rectangle.on.rectangle")
                                            .font(.caption2)
                                            .foregroundStyle(WFColors.accent)
                                            .hoverTip("正在浮窗中编辑")
                                    }
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title).lineLimit(1).strikethrough(trash)
                                    Spacer()
                                }
                                Text(note.document.isEmpty ? "还没有内容" : note.document.previewText.replacingOccurrences(of: "\n", with: " "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    // 标题用正文字号、预览用 caption，小字号的字形左侧留白更少，
                                    // 视觉上会比标题靠左。补一点内缩，和任务列表的「标题 / 正文」对齐。
                                    .padding(.leading, 4)
                                    // 与任务列表的正文同口径：占满左侧列，右侧留给元数据，
                                    // 超出按可用宽度截断，而不是按文字固有宽度。
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            // 内容列优先吃宽度：预览要尽量铺到日期前，而不是被右列按上限挤窄。
                            .layoutPriority(1)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(note.folder)
                                Text((note.deletedAt ?? note.updatedAt).formatted(.dateTime.month().day().locale(.appDate)) + (trash ? "删除" : ""))
                            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                // 右列按内容固定宽度，避免被左侧的 layoutPriority 压没。
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 56, maxWidth: 96, alignment: .trailing)
                            // 行几何与任务列表共用同一套常量（原来这里写死 10 / 61）：
                            // 上下内边距 11、最小行高 50，内容超出时按内容长高。
                            }.padding(.horizontal, 12).padding(.vertical, WFMetrics.rowVerticalPadding)
                                .frame(minHeight: WFMetrics.rowHeight)
                                // 行本身要撑满列表宽度，否则内部的 maxWidth: .infinity 拿不到额外空间。
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if trash {
                            Button { notes.restore(note.id) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28).contentShape(Rectangle()) }
                                .buttonStyle(.plain).hoverTip("恢复笔记：\(note.title)")
                            Button { purgeID = note.id } label: { Image(systemName: "trash.slash").frame(width: 28, height: 28).contentShape(Rectangle()) }
                                .buttonStyle(.plain).hoverTip("永久删除笔记：\(note.title)")
                        }
                        }
                        // 行分割线：与任务列表同一条（`ListRowDivider`），画在行内底边
                        // 所以不占行距。原来这里用系统 `Divider()`，比任务列表那条重一档，
                        // 而且选中行不画——两栏切来切去看到的是两种线。
                        //
                        // 但「选中行不画」这条保留：选中行有自己的圆角底色，`.overlay`
                        // 画在 `.background` 之上，线会横穿底边（任务列表那边就是因此
                        // 露出「下半截不是同一个蓝」）。
                        .overlay(alignment: .bottom) {
                            if visibleNote?.id != note.id {
                                ListRowDivider(leading: ListRowMetrics.notesDividerLeading,
                                               trailing: ListRowMetrics.notesDividerLeading)
                            }
                        }
                        .rowHoverBackground(selected: visibleNote?.id == note.id, cornerRadius: 8)
                        // 右键先选中目标行（Finder / 滴答口径），再弹常用操作；
                        // 垃圾桶行不可拖，只有恢复/永久删除。
                        .modifier(NoteDragSource(note: note, enabled: !trash))
                        .businessContextMenu(onOpen: { notes.selectedID = note.id }) {
                            noteRowMenu(note)
                        }
                    }
                }
            }
        }.padding(.horizontal, 10).padding(.bottom, 16)
    }

    @ViewBuilder private func inspector(compact: Bool) -> some View {
        if let note = visibleNote {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if compact { Button { detailOnly = false } label: { Image(systemName: "chevron.left") }.hoverTip(trash ? "返回笔记垃圾桶" : "返回笔记列表") }
                    if trash {
                        Label("已删除的笔记", systemImage: "trash").foregroundStyle(.secondary)
                    } else {
                        // 滴答口径：笔记顶栏是相对日期行（蓝色"今天，10月24日"），
                        // 文件夹/收藏/操作全部下沉到底部操作栏。
                        Text(NoteDateLabel.tickStyle(note.updatedAt))
                            .font(WFType.body.weight(.medium))
                            .foregroundStyle(WFColors.accent)
                    }
                    Spacer()
                    if trash {
                        Button { notes.restore(note.id); detailOnly = false } label: { Image(systemName: "arrow.uturn.backward") }.hoverTip("恢复笔记")
                        Button(role: .destructive) { purgeID = note.id } label: { Image(systemName: "trash.slash") }.hoverTip("永久删除笔记")
                    } else {
                        noteAIMenu(note)
                        FloatingEditorButton { openFloatingNote(note) }
                    }
                }.buttonStyle(.borderless).padding(.horizontal, 20).frame(height: 44)
                Divider()
                if !trash && !floatingNotes.isOpen(note.id) {
                    DocumentFormattingToolbarRow(
                        handle: editorHandle,
                        leadingPadding: NotesWorkspaceMetrics.toolbarLeadingPadding,
                        trailingPadding: NotesWorkspaceMetrics.contentInset,
                        contentMaxWidth: NotesWorkspaceMetrics.contentMaxWidth)
                    Divider()
                }
                GeometryReader { viewport in
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                if trash {
                    Text(note.title.isEmpty ? "未命名笔记" : note.title).font(WFType.detailTitle).strikethrough().frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(note.folder) · \((note.deletedAt ?? note.updatedAt).formatted(.dateTime.year().month().day().hour().minute().locale(.appDate)))删除")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    let body = note.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(body.isEmpty ? "还没有正文。" : body).font(WFType.body)
                        .foregroundStyle(body.isEmpty ? WFColors.tertiaryText : WFColors.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if floatingNotes.isOpen(note.id) {
                        floatingNoteBanner(note)
                        Text(note.title.isEmpty ? "未命名笔记" : note.title)
                            .font(WFType.detailTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // 编辑权在浮窗，这里只保留同一套富文本排版供阅读/复制；
                        // 标题、列表、引用、代码块不再退化成 plainText。
                        DocumentEditor(documentID: previewDocumentID, document: note.document,
                                       onDocumentChange: { _ in },
                                       onEscape: { .keepInspector },
                                       onEditingChanged: { _ in },
                                       profile: NoteDocumentProfile.make(host: NoteEditorHostActions.make(
                                           noteID: note.id, tasks: tasks, notes: notes)),
                                       contentSized: true,
                                       readOnly: true)
                            .overlay(alignment: .topLeading) {
                                if DocumentEditorPlaceholder.isVisible(for: note.document) {
                                    DocumentEditorPlaceholder(title: "还没有正文。")
                                }
                            }
                            .padding(.leading, -DocumentEditorPresentationMetrics.textContainerFragmentPadding)
                    } else {
                        TextField("笔记标题", text: Binding(get: { notes.notes.first { $0.id == note.id }?.title ?? "" }, set: { value in notes.edit(note.id) { $0.title = value } }), axis: .vertical)
                            .textFieldStyle(.plain).font(WFType.detailTitle)
                            .lineLimit(1...3).focused($focusedTitle, equals: note.id)
                            .task(id: note.id) { if note.title.isEmpty { focusedTitle = note.id } }
                        if note.hasPreservedRichContent {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield")
                                Text("原始富文本已保留；需要纯文本版本时可创建独立副本。")
                                Button("创建副本") { _ = notes.createPlainTextCopy(note.id) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        // Task and note hosts share the same native editing kernel.
                        // The profile supplies note-specific business actions.
                        DocumentEditor(documentID: note.id, document: note.document,
                                       onDocumentChange: { document in notes.edit(note.id) { $0.document = document } },
                                       onEscape: { .endEditing },
                                       onEditingChanged: { _ in },
                                       profile: NoteDocumentProfile.make(host: NoteEditorHostActions.make(
                                           noteID: note.id, tasks: tasks, notes: notes)),
                                       contentSized: true, handle: editorHandle)
                            .overlay(alignment: .topLeading) {
                                if DocumentEditorPlaceholder.isVisible(for: note.document, handle: editorHandle) {
                                    DocumentEditorPlaceholder(title: "写下你的想法、会议记录或下一步行动…")
                                }
                            }
                            // 正文墨迹比宿主内缩 5pt；宿主左移同样的量，标题与正文左缘齐平。
                            .padding(.leading, -DocumentEditorPresentationMetrics.textContainerFragmentPadding)
                    }
                    linkedTasksSection(note)
                    if !note.attachments.isEmpty { AttachmentListView(attachments: note.attachments) { attachments in
                        notes.edit(note.id) { $0.attachments = attachments }
                    } }
                }
                }.padding(.horizontal, NotesWorkspaceMetrics.contentInset).padding(.top, 14).padding(.bottom, 44)
                    .frame(maxWidth: NotesWorkspaceMetrics.contentMaxWidth)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    .background {
                        if !trash && !floatingNotes.isOpen(note.id) {
                            EditorWhitespaceHitTarget(handle: editorHandle, documentID: note.id)
                        }
                    }
                    .compactScrollbars()
                }
                }
                if !trash { Divider(); footer(note) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(trash ? "没有可预览的笔记" : "选择一篇笔记").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func floatingNoteBanner(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(WFColors.accent)
            Text("正在浮窗中编辑")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            Spacer()
            Button("定位浮窗") { floatingNotes.bringToFront(noteID: note.id) }
                .buttonStyle(.plain)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.accent)
        }
        .padding(10)
        .background(WFColors.selection, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 笔记操作菜单（Round B2：复制正文 / 创建纯文本副本；移到垃圾桶沿用删除按钮）

    private func openFloatingNote(_ note: Note) {
        editorHandle.prepareForDocumentChange()
        floatingNotes.open(noteID: note.id)
    }

    // MARK: - 笔记列表右键菜单

    @ViewBuilder private func noteRowMenu(_ note: Note) -> some View {
        if trash {
            Button("恢复笔记") { notes.restore(note.id) }
            Divider()
            Button("永久删除…", role: .destructive) { purgeID = note.id }
        } else {
            Button("打开笔记") { notes.selectedID = note.id; detailOnly = true }
            Divider()
            Button(note.favorite ? "取消收藏" : "收藏") {
                notes.edit(note.id) { $0.favorite.toggle() }
            }
            BusinessMenu("移动到") { noteFolderMenu(note) }
            Divider()
            Button("复制笔记正文") { copyPlainText(note) }
            if note.hasPreservedRichContent {
                Button("创建纯文本副本") { _ = notes.createPlainTextCopy(note.id) }
            }
            Button("转换为任务") { _ = notes.convertToTask(note.id) }
            Divider()
            Button("移到垃圾桶", role: .destructive) { notes.delete(note.id) }
        }
    }

    /// 页脚文件夹菜单与右键「移动到」共用同一份归属列表。
    @ViewBuilder private func noteFolderMenu(_ note: Note) -> some View {
        ForEach(["未归档"] + notes.folders, id: \.self) { value in
            Button(value) { notes.moveNoteToFolder(note.id, named: value) }
        }
        Divider()
        Button("移到新文件夹…") { moveToNewFolder(note) }
    }

    private func moveToNewFolder(_ note: Note) {
        guard let value = TaskNamePrompt.ask("文件夹名称"), !value.isEmpty else { return }
        guard notes.addFolder(value) else { TaskNamePrompt.invalidName(); return }
        notes.moveNoteToFolder(note.id, named: value)
    }

    private func noteActionsMenu(_ note: Note) -> some View {
        BusinessMenu(title: "笔记操作", prefersAbove: true) {
            Button(note.favorite ? "取消收藏" : "收藏") {
                notes.edit(note.id) { $0.favorite.toggle() }
            }
            Button("复制笔记正文") { copyPlainText(note) }
            if note.hasPreservedRichContent {
                Button("创建纯文本副本") { _ = notes.createPlainTextCopy(note.id) }
            }
            Divider()
            Button("转换为任务") { _ = notes.convertToTask(note.id) }
            Divider()
            Button("移到垃圾桶", role: .destructive) { notes.delete(note.id) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
                .accessibilityLabel("更多笔记操作")
        }.fixedSize()
        .hoverTip("更多操作")
    }

    private func noteAIMenu(_ note: Note) -> some View {
        BusinessMenu(title: "笔记 AI") {
            Button("整理要点…") { rewrite(note, action: .organize) }.disabled(note.document.isEmpty)
                .workflowActionAnchor("note.ai.organize")
            Button("润色笔记…") { rewrite(note, action: .polish) }.disabled(note.document.isEmpty)
                .workflowActionAnchor("note.ai.polish")
            Button("提取待办…") {
                editorHandle.prepareForDocumentChange()
                do {
                    let current = notes.notes.first { $0.id == note.id } ?? note
                    aiTaskRequest = try environment.aiTaskRequest(for: current)
                } catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
            }.disabled(note.document.isEmpty && note.title.isEmpty)
                .workflowActionAnchor("note.ai.tasks")
        } label: { Label("AI", systemImage: "sparkles").accessibilityLabel("笔记 AI") }
        .accessibilityIdentifier("note.ai")
        .workflowActionAnchor("note.ai")
    }

    private func rewrite(_ note: Note, action: NoteRewriteRequest.Action) {
        editorHandle.prepareForDocumentChange()
        do {
            let current = notes.notes.first { $0.id == note.id } ?? note
            let body = try current.document.materialized().plainText
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            aiRewriteRequest = NoteRewriteRequest(noteID: current.id,
                title: current.title.isEmpty ? "未命名笔记" : current.title, content: body, action: action)
        } catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
    }

    private func copyPlainText(_ note: Note) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(note.document.plainText, forType: .string)
    }

    // MARK: - 关联任务区（Round B2：linkedTaskIDs + sourceNoteID 指向本笔记的任务）

    @ViewBuilder private func linkedTasksSection(_ note: Note) -> some View {
        let linked = linkedTasks(for: note)
        if !linked.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("关联任务").font(.callout).foregroundStyle(.secondary)
                    Text("\(linked.count)").font(.caption).foregroundStyle(WFColors.tertiaryText)
                    Spacer()
                }
                ForEach(linked) { task in
                    linkedTaskRow(task)
                }
            }
        }
    }

    /// Flutter tasksLinkedToNote 的原生并集：笔记侧 linkedTaskIDs + 任务侧 sourceNoteID。
    private func linkedTasks(for note: Note) -> [Task] {
        var seen = Set<UUID>()
        var result: [Task] = []
        for id in note.linkedTaskIDs {
            if let task = tasks.task(for: id), task.deletedAt == nil, seen.insert(task.id).inserted {
                result.append(task)
            }
        }
        let bySource = notes.taskProvider?().filter { $0.sourceNoteID == note.id && $0.deletedAt == nil }
            ?? tasks.allTasks.filter { $0.sourceNoteID == note.id && $0.deletedAt == nil }
        for task in bySource where seen.insert(task.id).inserted {
            result.append(task)
        }
        return result
    }

    private func linkedTaskRow(_ task: Task) -> some View {
        HStack(spacing: 10) {
            Button {
                if task.isClosed { tasks.restore(task.id) } else { tasks.complete(task.id) }
            } label: {
                Image(systemName: task.isClosed ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isClosed ? WFColors.accent : WFColors.secondaryText)
            }.buttonStyle(.plain).hoverTip(task.isClosed ? "恢复任务" : "完成任务")
            Button { openLinkedTask(task.id) } label: {
                HStack {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .lineLimit(1)
                        .foregroundStyle(task.isClosed ? WFColors.tertiaryText : WFColors.text)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WFColors.tertiaryText)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(10)
        .background(WFColors.selection, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
    }

    /// 打开任务 = 闭包回调（主线接 taskWorkspace.select）；未接线时退回本地路由。
    private func openLinkedTask(_ id: UUID) {
        if let openTask = notes.openTask {
            openTask(id)
        } else {
            navigation.destination = .inbox
            tasks.select(id)
        }
    }

    // MARK: - 页脚：字数统计 + 浮动格式工具条开关

    /// The folder belongs to the note host; formatting uses shared controls.
    private func footer(_ note: Note) -> some View {
        HStack(spacing: 10) {
            BusinessMenu(prefersAbove: true) {
                noteFolderMenu(note)
            } label: { Label(note.folder, systemImage: "folder") }
            .lineLimit(1).fixedSize()
            Spacer()
            if let error = environment.storageError {
                Button("保存失败 · 重试") { environment.flush { _ in } }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.red).help(error)
            }
            noteActionsMenu(note)
        }
        .padding(.horizontal, 20)
        .frame(height: DocumentEditorPresentationMetrics.footerHeight)
    }
}
