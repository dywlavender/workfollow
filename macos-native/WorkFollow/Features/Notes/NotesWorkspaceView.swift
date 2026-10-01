import AppKit
import SwiftUI

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
    // 笔记页脚的浮动格式工具条（Round B2 迁移：Flutter DocumentEditorFooter + DocumentEditorToolbar）。
    @State private var showFormatToolbar = false
    @StateObject private var editorHandle = DocumentEditorHandle()
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
            let wide = geometry.size.width >= (trash ? WFMetrics.splitMinimum : 760)
            let maximum = max(WFMetrics.listMinimum, min(WFMetrics.listMaximum,
                geometry.size.width - WFMetrics.inspectorMinimum - WFMetrics.divider))
            let paneWidth = trash ? min(max(tasks.taskListPaneWidth, WFMetrics.listMinimum), maximum)
                : (geometry.size.width >= 1100 ? 330.0 : 300.0)
            HStack(spacing: 0) {
                if wide || !detailOnly || visibleNote == nil {
                    list.frame(width: wide ? paneWidth : nil)
                        .frame(maxWidth: wide ? nil : .infinity)
                }
                if wide || (detailOnly && visibleNote != nil) {
                    if wide {
                        if trash {
                            Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
                                .overlay {
                                    Color.clear.frame(width: 8).contentShape(Rectangle())
                                        .onHover { inside in
                                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                        }
                                        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                            if dragOrigin == nil { dragOrigin = paneWidth }
                                            tasks.setTaskListPaneWidth(min(max((dragOrigin ?? paneWidth) + value.translation.width,
                                                WFMetrics.listMinimum), maximum))
                                        }.onEnded { _ in dragOrigin = nil })
                                }
                        } else { Divider() }
                    }
                    inspector(compact: !wide)
                }
            }
        }
        .onChange(of: visibleNote?.id) { _, _ in showFormatToolbar = false }
        .onChange(of: navigation.destination) { _, _ in detailOnly = false; query = ""; showFormatToolbar = false }
        .onChange(of: notes.folderFilter) { _, _ in detailOnly = false; query = "" }
        .onChange(of: notes.favoritesOnly) { _, _ in detailOnly = false; query = "" }
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
                        .buttonStyle(.plain).help("笔记导航")
                        .popover(isPresented: $showNavigation) {
                            NavigationColumnView(workspace: tasks, navigation: navigation,
                                filterStore: environment.filterStore, onNavigate: { showNavigation = false })
                                .frame(width: WFMetrics.navigationWidth, height: 480)
                        }
                }
                Text(trash ? "垃圾桶" : favorites ? "收藏笔记" : "笔记").font(WFType.pageTitle)
                Spacer()
                if trash {
                    Button("全部删除") { confirmClear = true }.disabled(!notes.notes.contains { $0.deletedAt != nil })
                } else {
                    Button(action: createNote) { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 6)).help("新建笔记")
                }
            }
            .frame(height: 44)
            if !trash { HStack(spacing: 4) {
                TextField("搜索笔记", text: $query).textFieldStyle(.roundedBorder)
                if !trash {
                    Menu {
                        Button("按标题排序") { notes.sort(.title) }
                        Button("按最近编辑排序") { notes.sort(.recentlyEdited) }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("笔记排序")
                }
            }.frame(height: 34) }
            ScrollView {
                LazyVStack(spacing: 4) {
                    if rows.isEmpty { Text(query.isEmpty ? (trash ? "笔记垃圾桶是空的" : "从一条新笔记开始") : "没有找到相关笔记").foregroundStyle(.secondary).padding() }
                    ForEach(rows) { note in
                        HStack(spacing: 4) {
                        Button { notes.selectedID = note.id; detailOnly = true } label: {
                            HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if note.favorite { Image(systemName: "star.fill") }
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title).lineLimit(1).strikethrough(trash)
                                    Spacer()
                                }
                                Text(note.document.isEmpty ? "还没有内容" : note.document.plainText.replacingOccurrences(of: "\n", with: " "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(note.folder)
                                Text((note.deletedAt ?? note.updatedAt).formatted(.dateTime.month().day().locale(.appDate)) + (trash ? "删除" : ""))
                            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 96, alignment: .trailing)
                            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 61)
                                .background(visibleNote?.id == note.id ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if trash {
                            Button { notes.restore(note.id) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28).contentShape(Rectangle()) }
                                .buttonStyle(.plain).help("恢复笔记：\(note.title)")
                            Button { purgeID = note.id } label: { Image(systemName: "trash.slash").frame(width: 28, height: 28).contentShape(Rectangle()) }
                                .buttonStyle(.plain).help("永久删除笔记：\(note.title)")
                        }
                        }
                        if visibleNote?.id != note.id { Divider().padding(.horizontal, 12) }
                    }
                }
            }
        }.padding(.horizontal, 10).padding(.bottom, 16)
    }

    @ViewBuilder private func inspector(compact: Bool) -> some View {
        if let note = visibleNote {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if compact { Button { detailOnly = false } label: { Image(systemName: "chevron.left") }.help(trash ? "返回笔记垃圾桶" : "返回笔记列表") }
                    if trash {
                        Label("已删除的笔记", systemImage: "trash").foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(["未归档"] + notes.folders, id: \.self) { value in
                            Button(value) { notes.moveNoteToFolder(note.id, named: value) }
                        }
                        Divider()
                        Button("移到新文件夹…") {
                            if let value = TaskNamePrompt.ask("文件夹名称"), !value.isEmpty {
                                guard notes.addFolder(value) else { TaskNamePrompt.invalidName(); return }
                                notes.moveNoteToFolder(note.id, named: value)
                            }
                        }
                    } label: { Label(note.folder, systemImage: "folder") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).lineLimit(1)
                    }
                    Spacer()
                    if trash {
                        Button { notes.restore(note.id); detailOnly = false } label: { Image(systemName: "arrow.uturn.backward") }.help("恢复笔记")
                        Button(role: .destructive) { purgeID = note.id } label: { Image(systemName: "trash.slash") }.help("永久删除笔记")
                    } else {
                        Button { notes.edit(note.id) { $0.favorite.toggle() } } label: {
                            Image(systemName: note.favorite ? "star.fill" : "star")
                        }
                        noteActionsMenu(note)
                    }
                }.buttonStyle(.borderless).padding(.horizontal, 20).frame(height: 44)
                Divider()
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
                    TextField("笔记标题", text: Binding(get: { notes.notes.first { $0.id == note.id }?.title ?? "" }, set: { value in notes.edit(note.id) { $0.title = value } }), axis: .vertical)
                        .textFieldStyle(.plain).font(WFType.detailTitle)
                        .lineLimit(1...3).focused($focusedTitle, equals: note.id)
                        .task(id: note.id) { if note.title.isEmpty { focusedTitle = note.id } }
                    Text(note.updatedAt.formatted(.dateTime.year().month().day().hour().minute().locale(.appDate)))
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    if note.hasPreservedRichContent {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                            Text("原始富文本已保留；需要纯文本版本时可创建独立副本。")
                            Button("创建副本") { _ = notes.createPlainTextCopy(note.id) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    DocumentEditor(documentID: note.id, document: note.document,
                                   onDocumentChange: { document in notes.edit(note.id) { $0.document = document } },
                                   onEscape: {
                                       if showFormatToolbar {
                                           showFormatToolbar = false
                                           return .dismissPopover
                                       }
                                       return .endEditing
                                   },
                                   onEditingChanged: { _ in },
                                   profile: NoteDocumentProfile.make(host: .make(noteID: note.id, tasks: tasks, notes: notes)),
                                   contentSized: true, handle: editorHandle).id(note.id)
                        .overlay(alignment: .topLeading) {
                            if note.document.isEmpty {
                                Text("写下你的想法、会议记录或下一步行动…")
                                    .foregroundStyle(WFColors.tertiaryText).padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    linkedTasksSection(note)
                    if !note.attachments.isEmpty { AttachmentListView(attachments: note.attachments) { attachments in
                        notes.edit(note.id) { $0.attachments = attachments }
                    } }
                }
                }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 44)
                    .frame(maxWidth: 820).frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    .background {
                        if !trash {
                            Color.clear.contentShape(Rectangle()).onTapGesture { editorHandle.focusEnd() }
                        }
                    }
                }
                }
                if !trash { Divider(); footer(note).padding(.horizontal, 20).frame(height: 44) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(trash ? "没有可预览的笔记" : "选择一篇笔记").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 笔记操作菜单（Round B2：复制正文 / 创建纯文本副本；移到垃圾桶沿用删除按钮）

    private func noteActionsMenu(_ note: Note) -> some View {
        Menu {
            Button("复制笔记正文") { copyPlainText(note) }
            if note.hasPreservedRichContent {
                Button("创建纯文本副本") { _ = notes.createPlainTextCopy(note.id) }
            }
            Divider()
            Button("移到垃圾桶", role: .destructive) { notes.delete(note.id) }
        } label: {
            Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("笔记操作").accessibilityLabel("笔记操作")
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
            }.buttonStyle(.plain).help(task.isClosed ? "恢复任务" : "完成任务")
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

    private func footer(_ note: Note) -> some View {
        HStack {
            Text("\(noteWordCount(note.document.plainText)) 字")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let error = environment.storageError {
                Button("保存失败 · 重试") { environment.flush { _ in } }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.red).help(error)
            }
            Button { showFormatToolbar.toggle(); if showFormatToolbar { editorHandle.focusEditor() } } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(showFormatToolbar ? WFColors.accent : WFColors.secondaryText)
            }.buttonStyle(.plain).help("正文格式").accessibilityLabel("正文格式")
        }
        .overlay(alignment: .bottom) {
            if showFormatToolbar {
                DocumentFormatToolbarView(handle: editorHandle)
                    .padding(.trailing, 2).padding(.bottom, 32)
            }
        }
    }
}
