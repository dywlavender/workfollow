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
    /// 整个窗口的宽度（含图标栏与文件夹列），用于判断文件夹列能否内联展开。
    /// 直接挂在测试宿主里时为 0，此时不做自动收起。
    var windowWidth: CGFloat = 0
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// 空标题的笔记自动聚焦标题；回车后由组件自己收起编辑态。
    @State private var titleEditing = false
    @State private var dragOrigin: CGFloat?
    @State private var query = ""
    private var favorites: Bool { notes.favoritesOnly }
    private var glassActive: Bool {
        WFGlassSupport.isActive(material,
                                reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency)
    }
    @State private var detailOnly = false
    @State private var purgeID: UUID?
    @AppStorage("notes.ai.paneWidth") private var aiPaneWidth = Double(NoteAIPaneMetrics.defaultWidth)
    @State private var aiDragOrigin: CGFloat?
    @StateObject private var aiExpansion = AIPaneWindowExpansion()
    @State private var aiDraftEdit: NoteAIDraftEditTarget?
    @State private var aiDestination = TaskList.inbox.name
    @State private var aiSectionID: String?
    @StateObject private var editorHandle = DocumentEditorHandle()
    /// 浮窗打开时原编辑栏改成只读预览；独立身份避免与浮窗争同一份编辑状态。
    @State private var previewDocumentID = UUID()
    @ObservedObject private var floatingNotes = FloatingNoteWindowController.shared
    private var trash: Bool { navigation.destination == .notesTrash }
    private var rows: [Note] { notes.rows(trash: trash, query: query, folder: nil, favorites: favorites) }
    private var visibleNote: Note? { rows.first { $0.id == notes.selectedID } ?? rows.first }
    /// 命令面板打开笔记后，等编辑器换好文档再把光标落到命中词。
    private func revealPendingSearchMatch() {
        guard !trash, let note = visibleNote,
              let request = notes.searchRevealRequest,
              request.targetID == note.id else { return }
        scheduleSearchReveal(noteID: note.id, query: request.query, attempts: 15)
    }

    private func scheduleSearchReveal(noteID: UUID, query: String, attempts: Int) {
        DispatchQueue.main.async {
            guard !trash, visibleNote?.id == noteID,
                  notes.searchRevealRequest?.targetID == noteID else { return }
            switch editorHandle.revealSearchMatch(query, documentID: noteID) {
            case .some:
                _ = notes.consumeSearchReveal(for: noteID)
            case .none:
                guard attempts > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scheduleSearchReveal(noteID: noteID, query: query, attempts: attempts - 1)
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = columnLayout(contentWidth: geometry.size.width)
            ZStack(alignment: .topLeading) {
                workspace(layout: layout, note: visibleNote)
                aiDraftEditorOverlay(note: visibleNote)
            }
            .coordinateSpace(name: PlanningCoordinateSpace.name)
        }
        .onChange(of: navigation.destination) { _, _ in
            detailOnly = false; query = ""; aiDraftEdit = nil
            syncAIExpansion()
        }
        .onChange(of: notes.folderFilter) { _, _ in detailOnly = false; query = "" }
        .onChange(of: notes.favoritesOnly) { _, _ in detailOnly = false; query = "" }
        .onChange(of: visibleNote?.id) { oldID, _ in
            aiDraftEdit = nil
            // 换笔记后旧笔记的选区事务已经写不回去了，别让「替换」留在它的 AI 栏里。
            if let oldID { aiConversations.model(for: oldID).clearSelectionTarget() }
            // AI 会话窗只由 RootShellView 的切页钩子隐藏/恢复；换笔记不在这里关，
            // 应用结果时 AISelectionTarget 会校验文档 ID 与 epoch。
            syncAIExpansion()
        }
        .onChange(of: notes.aiPaneVisible) { _, visible in
            if !visible { aiDraftEdit = nil }
            syncAIExpansion()
        }
        .onChange(of: aiExpansion.expandedWidth) { _, width in
            if width == 0 { clearFrozenWindowWidth() }
        }
        .onChange(of: notes.revealRequest) { _, _ in query = ""; detailOnly = true }
        .onChange(of: notes.searchRevealRequest) { _, _ in
            query = ""
            detailOnly = true
            revealPendingSearchMatch()
        }
        .onAppear {
            if notes.revealRequest != nil { query = ""; detailOnly = true }
            if notes.searchRevealRequest != nil { query = ""; detailOnly = true; revealPendingSearchMatch() }
        }
        .onDisappear {
            aiExpansion.collapse()
            clearFrozenWindowWidth()
        }
        .workfollowAlert(
            "永久删除笔记？",
            isPresented: Binding(get: { purgeID != nil }, set: { if !$0 { purgeID = nil } }),
            actions: [
                .cancel(),
                .destructive("删除") { if let id = purgeID { notes.purge(id) }; purgeID = nil }
            ])
    }

    private var aiConversations: NoteAIConversationStore { .shared }

    /// 右扩给 AI 的那一栏正好是 AI 所需宽度，所以列分配直接按实际宽度算：
    /// 放得下时原有列宽不变，放不下才退回“列表让位、正文保底”的规则。
    /// 按扩展前宽度算会让窄窗（原先单栏看列表）扩宽后仍不渲染 AI。
    private func columnLayout(contentWidth: CGFloat) -> NotesColumnLayout {
        NotesColumnLayoutEngine.layout(
            contentWidth: contentWidth,
            storedPaneWidth: tasks.taskListPaneWidth,
            storedAIWidth: CGFloat(aiPaneWidth),
            aiOpen: notes.aiPaneVisible,
            detailOnly: detailOnly,
            noteExists: visibleNote != nil,
            trash: trash)
    }

    private var hostWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "WorkFollowNativeMain" }
    }

    private func setAIOpen(_ open: Bool) {
        guard open != notes.aiPaneVisible else { return }
        if open {
            if let window = hostWindow, visibleNote != nil, !trash {
                // 先冻结扩展前的壳层宽度，窗口变宽的同一帧里导航列不会跳出来。
                environment.notesAIFrozenWindowWidth = window.frame.width
                if !aiExpansion.expand(window, by: CGFloat(aiPaneWidth)) {
                    clearFrozenWindowWidth()
                }
            }
            notes.aiPaneVisible = true
        } else {
            notes.aiPaneVisible = false
            aiDraftEdit = nil
            aiExpansion.collapse()
            clearFrozenWindowWidth()
        }
    }

    private func clearFrozenWindowWidth() {
        // This is global shell state. Leaving an ordinary note must not
        // invalidate every cached page by publishing nil again.
        if environment.notesAIFrozenWindowWidth != nil { environment.notesAIFrozenWindowWidth = nil }
    }

    /// AI 被别处关掉、当前笔记消失或进入垃圾桶时，不再保留右扩的窗口宽度。
    private func syncAIExpansion() {
        guard aiExpansion.isExpanded else { return }
        if !notes.aiPaneVisible || visibleNote == nil || trash {
            aiExpansion.collapse()
        }
    }

    @ViewBuilder
    private func workspace(layout: NotesColumnLayout, note: Note?) -> some View {
        HStack(spacing: 0) {
            if layout.showList {
                list.frame(width: layout.wide ? layout.paneWidth : nil)
                    .frame(maxWidth: layout.wide ? nil : .infinity)
                if layout.wide { listDivider(width: layout.paneWidth, maximum: layout.maximumPaneWidth) }
            }
            if layout.wide || (detailOnly && note != nil) {
                inspector(compact: !layout.wide)
                if layout.aiVisible, let note {
                    aiDivider(width: layout.aiWidth)
                    aiPane(note: note, width: layout.aiWidth)
                        .frame(width: layout.aiWidth)
                }
            }
        }
        .workfollowPageSurface(0.90)
    }

    private func listDivider(width: CGFloat, maximum: CGFloat) -> some View {
        Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
            .overlay {
                Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        if dragOrigin == nil { dragOrigin = width }
                        let origin = dragOrigin ?? width
                        tasks.setTaskListPaneWidth(min(max(origin + value.translation.width,
                            WFMetrics.listMinimum), maximum))
                    }.onEnded { _ in dragOrigin = nil })
            }
    }

    private func aiDivider(width: CGFloat) -> some View {
        Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
            .overlay {
                Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        // 手动改 AI 宽度就不再维持“窗口右扩、原列宽不变”的模式。
                        if aiExpansion.isExpanded { aiExpansion.invalidate() }
                        if aiDragOrigin == nil { aiDragOrigin = width }
                        let origin = aiDragOrigin ?? width
                        let proposed = origin - value.translation.width
                        let clamped = min(max(proposed, NoteAIPaneMetrics.minimumWidth),
                                          NoteAIPaneMetrics.maximumWidth)
                        aiPaneWidth = Double(clamped)
                    }.onEnded { _ in aiDragOrigin = nil })
            }
    }

    @ViewBuilder
    private func aiDraftEditorOverlay(note: Note?) -> some View {
        if let target = aiDraftEdit, let note,
           let exchange = aiConversations.model(for: note.id).exchange(id: target.exchangeID),
           let session = exchange.taskSession,
           let request = exchange.taskRequest {
            PlanningOverlayLayer(anchor: target.anchor,
                                 placement: WFOverlayPlacement(preferredSide: .left, alignment: .center),
                                 size: NoteAIPaneMetrics.draftEditorSize,
                                 onDismiss: { aiDraftEdit = nil }) {
                NoteAITaskDraftEditorHost(session: session, draftID: target.draftID,
                                          request: request, destination: aiDestination,
                                          tasks: tasks, onClose: { aiDraftEdit = nil })
                    .environmentObject(environment)
            }
        }
    }

    private var list: some View {
        NotesFolderTreeListView(notes: notes, navigation: navigation,
                                query: $query, detailOnly: $detailOnly,
                                trash: trash, selectedNoteID: visibleNote?.id)
    }

    @ViewBuilder private func inspector(compact: Bool) -> some View {
        if let note = visibleNote {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if compact { Button { detailOnly = false } label: { Image(systemName: "chevron.left") }.hoverTip(trash ? "返回笔记垃圾桶" : "返回笔记列表") }
                    if trash {
                        Label("已删除的笔记", systemImage: "trash").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(NoteDateLabel.tickStyle(note.updatedAt))
                                .font(WFType.body.weight(.medium))
                                .foregroundStyle(WFColors.accent)
                            Text(notes.folderPath(named: note.folder).joined(separator: " › "))
                                .font(WFType.supporting)
                                .foregroundStyle(WFColors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if trash {
                        Button { notes.restore(note.id); detailOnly = false } label: { Image(systemName: "arrow.uturn.backward") }.hoverTip("恢复笔记")
                        Button(role: .destructive) { purgeID = note.id } label: { Image(systemName: "trash.slash") }.hoverTip("永久删除笔记")
                    } else {
                        noteAIButton
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
                        // 与任务详情/浮窗同一套标题控件：Return 接力给正文第一行，
                        // 不用再拿鼠标点一次正文。
                        AppKitTaskTitleField(
                            text: Binding(get: { notes.notes.first { $0.id == note.id }?.title ?? "" },
                                         set: { value in notes.edit(note.id) { $0.title = value } }),
                            isEditing: $titleEditing,
                            placeholder: "笔记标题",
                            font: .systemFont(ofSize: 18, weight: .semibold),
                            accessibilityLabel: "笔记标题",
                            onSubmit: { editorHandle.focusFirstLine() },
                            onArrowRightAtEnd: { editorHandle.focusFirstLineStart() })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .task(id: note.id) {
                                titleEditing = note.title.isEmpty
                                editorHandle.onLeftEdge = { titleEditing = true }
                            }
                        if note.hasPreservedRichContent {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield")
                                Text("原始富文本已保留；需要纯文本版本时可创建独立副本。")
                                Button("创建副本") { _ = notes.createPlainTextCopy(note.id) }
                            }.font(WFType.caption).foregroundStyle(.secondary)
                        }
                        // Task and note hosts share the same native editing kernel.
                        // The profile supplies note-specific business actions.
                        DocumentEditor(documentID: note.id, document: note.document,
                                       onDocumentChange: { document in notes.edit(note.id) { $0.document = document } },
                                       onEscape: { .endEditing },
                                       onEditingChanged: { _ in },
                                       profile: NoteDocumentProfile.make(host: NoteEditorHostActions.make(
                                           noteID: note.id, tasks: tasks, notes: notes,
                                           runAIAction: { runNoteAIAction($0, noteID: note.id) },
                                           runSelectionAI: { runSelectionAI($0, $1, noteID: note.id) },
                                           openLink: { raw in
                                               guard let url = URL(string: raw),
                                                     let link = NativeResourceLink(url: url) else { return false }
                                               return NativeResourceLinkRouter.open(link, tasks: tasks,
                                                                                    notes: notes, navigation: navigation)
                                           },
                                           checklistReminderNotice: { environment.reminders.checklistReminderNotice })),
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { WorkfollowReadingSurface() }
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

    /// 仿 TaskInspectorShell.saveAsTemplate：同名模板先确认替换，再按 kind = "note" 落盘。
    private func saveAsNoteTemplate(_ note: Note) {
        guard let name = TaskNamePrompt.ask("保存为笔记模板", value: note.title, confirm: "保存"),
              !name.isEmpty else { return }
        if TemplateStore.shared.contains(name: name) {
            guard TaskNamePrompt.confirm("模板“\(name)”已存在",
                                         message: "是否用当前笔记替换这个模板？",
                                         action: "替换") else { return }
        }
        _ = TemplateStore.shared.saveNoteTemplate(name: name, from: note, forceReplace: true)
    }

    private func noteActionsMenu(_ note: Note) -> some View {
        BusinessMenu(title: "笔记操作", prefersAbove: true) {
            Button(note.favorite ? "取消收藏" : "收藏") {
                notes.edit(note.id) { $0.favorite.toggle() }
            }
            Button("复制笔记正文") { copyPlainText(note) }
            Button("保存为笔记模板") { saveAsNoteTemplate(note) }
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

    private var noteAIButton: some View {
        Button {
            setAIOpen(!notes.aiPaneVisible)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                Text("AI 助手")
            }
            .font(WFType.supporting)
            .foregroundStyle(notes.aiPaneVisible ? WFColors.accent : WFColors.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(notes.aiPaneVisible ? WFColors.selection : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notes.aiPaneVisible ? "关闭 AI 助手" : "打开 AI 助手")
        .hoverTip(notes.aiPaneVisible ? "关闭 AI 助手" : "AI 助手")
        .accessibilityIdentifier("note.ai")
        .workflowActionAnchor("note.ai")
    }

    private func aiPane(note: Note, width: CGFloat) -> some View {
        NoteAIPaneView(model: aiConversations.model(for: note.id), tasks: tasks,
                       noteID: note.id,
                       noteTitle: note.title.isEmpty ? "未命名笔记" : note.title,
                       noteContentIsEmpty: note.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       canReplaceBody: !floatingNotes.isOpen(note.id) && !note.hasPreservedRichContent,
                       destination: $aiDestination, sectionID: $aiSectionID,
                       makeContext: { noteAIContext(noteID: note.id) },
                       onPrepareDocument: { editorHandle.prepareForDocumentChange() },
                       onReplaceBody: { replaceNoteBody($0, noteID: note.id) },
                       onEditDraft: { exchangeID, draftID, rect in
                           let anchor = PlanningAnchorRef()
                           anchor.rect = rect
                           aiDraftEdit = NoteAIDraftEditTarget(exchangeID: exchangeID,
                                                               draftID: draftID, anchor: anchor)
                       },
                       onRevealTasks: revealTasks,
                       onOpenNote: openNote,
                       onClose: { setAIOpen(false) })
            .frame(width: width)
    }

    private func noteAIContext(noteID: UUID) -> NoteAIContext {
        guard let note = notes.notes.first(where: { $0.id == noteID && $0.deletedAt == nil }) else {
            return NoteAIContext(noteID: noteID, title: "", content: "",
                                 referenceDate: Date(), existingTitles: [])
        }
        return NoteAIContext(noteID: note.id,
                             title: note.title.isEmpty ? "未命名笔记" : note.title,
                             content: note.document.plainText,
                             referenceDate: note.updatedAt,
                             existingTitles: tasks.allTasks.filter {
                                 $0.deletedAt == nil
                                     && ($0.sourceNoteID == note.id || note.linkedTaskIDs.contains($0.id))
                             }.map(\.title))
    }

    /// 斜杠 AI 命令入口：与 AI 栏按钮同一条 ask 管线，结果同样展示在 AI 栏。
    /// 空笔记的可用性与 AI 栏按钮的 isAllowed 保持一致（extract 允许只有标题）。
    private func runNoteAIAction(_ action: NoteAIAction, noteID: UUID) {
        guard let note = notes.notes.first(where: { $0.id == noteID && $0.deletedAt == nil }) else { return }
        let contentEmpty = note.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let titleEmpty = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch action {
        case .extract: guard !contentEmpty || !titleEmpty else { return }
        case .organize, .polish: guard !contentEmpty else { return }
        }
        let model = aiConversations.model(for: noteID)
        guard !model.isRunning, !model.attachments.isImporting else { return }
        editorHandle.prepareForDocumentChange()
        model.ask(action, context: noteAIContext(noteID: noteID),
                  using: environment.conversationClient().generator(for: model.conversation))
        setAIOpen(true)
    }

    /// 选中文字的「AI 润色 / 翻译 / 总结」：不再开独立浮窗，交给右侧 AI 栏输出。
    /// 生成完成后 AI 栏给出「替换 / 插入」，由 AISelectionTarget 把结果写回原选区，
    /// 走编辑器原生撤销链（⌘Z）。
    private func runSelectionAI(_ target: AISelectionTarget, _ preset: AIConversationPreset,
                                noteID: UUID) -> Bool {
        guard !trash, visibleNote?.id == noteID,
              notes.notes.contains(where: { $0.id == noteID && $0.deletedAt == nil }) else { return false }
        let model = aiConversations.model(for: noteID)
        guard !model.isRunning, !model.attachments.isImporting else { return false }
        // 刻意不调用 prepareForDocumentChange()：这一路不改动文档，而
        // flush/commit 可能推进 revision 或改写 editor.string，让选区快照
        // 在回写校验时失配。快照由编辑器在焦点离开前捕获。
        model.askSelection(preset, target: target,
                           using: environment.conversationClient().generator(for: model.conversation))
        setAIOpen(true)
        return true
    }

    private func replaceNoteBody(_ text: String, noteID: UUID) {
        guard notes.notes.contains(where: { $0.id == noteID && $0.deletedAt == nil }) else { return }
        editorHandle.prepareForDocumentChange()
        let body = DocumentExternalClipboardCodec.fragment(fromMarkdown: text)?.document
            ?? NativeDocument(plainText: text)
        notes.edit(noteID) { $0.document = body }
    }

    private func revealTasks(_ ids: [UUID]) {
        guard let id = ids.first else { return }
        _ = NativeResourceLinkRouter.open(.task(id), tasks: tasks, notes: notes, navigation: navigation)
    }

    private func openNote(_ id: UUID) {
        _ = NativeResourceLinkRouter.open(.note(id), tasks: tasks, notes: notes, navigation: navigation)
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

    /// Flutter tasksLinkedToNote 的原生并集：笔记侧 linkedTaskIDs + 任务侧 sourceNoteID
    /// + 正文 `@` 提及的文档链接。
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
        for link in DocumentMentionScanner.resourceLinks(in: note.document) {
            if case let .task(id) = link, let task = tasks.task(for: id),
               task.deletedAt == nil, seen.insert(task.id).inserted {
                result.append(task)
            }
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
                    .buttonStyle(.plain).font(.caption).foregroundStyle(WFColors.danger).help(error)
            }
            noteActionsMenu(note)
        }
        .padding(.horizontal, 20)
        .frame(height: DocumentEditorPresentationMetrics.footerHeight)
    }
}
