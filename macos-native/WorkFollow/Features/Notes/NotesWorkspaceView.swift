import AppKit
import SwiftUI

struct NotesWorkspaceView: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var tasks: TaskWorkspaceModel
    @State private var query = ""
    private var folder: String? { notes.folderFilter }
    private var favorites: Bool { notes.favoritesOnly }
    @State private var newestFirst = true
    @State private var detailOnly = false
    @State private var confirmClear = false
    @State private var purgeID: UUID?
    // 笔记页脚的浮动格式工具条（Round B2 迁移：Flutter DocumentEditorFooter + DocumentEditorToolbar）。
    @State private var showFormatToolbar = false
    @StateObject private var editorHandle = DocumentEditorHandle()
    private var trash: Bool { navigation.destination == .notesTrash }
    private var rows: [Note] { notes.rows(trash: trash, query: query, folder: folder, favorites: favorites, newestFirst: newestFirst) }
    private var visibleNote: Note? { rows.first { $0.id == notes.selectedID } ?? rows.first }
    private func createNote() {
        query = ""
        notes.favoritesOnly = false
        notes.create(folder: folder)
        detailOnly = true
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 760 || !detailOnly || visibleNote == nil {
                    list.frame(maxWidth: geometry.size.width >= 760 ? (geometry.size.width >= 1100 ? 330 : 300) : .infinity)
                }
                if geometry.size.width >= 760 || (detailOnly && visibleNote != nil) {
                    if geometry.size.width >= 760 { Divider() }
                    inspector(compact: geometry.size.width < 760)
                }
            }
        }
        .onChange(of: notes.selectedID) { _, _ in showFormatToolbar = false }
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
            HStack(spacing: 4) {
                TextField("搜索笔记", text: $query).textFieldStyle(.roundedBorder)
                if !trash {
                    Menu {
                        Button(newestFirst ? "按标题排序" : "按最近编辑排序") { newestFirst.toggle() }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("笔记排序")
                }
            }.frame(height: 34)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if rows.isEmpty { Text(query.isEmpty ? (trash ? "笔记垃圾桶是空的" : "从一条新笔记开始") : "没有找到相关笔记").foregroundStyle(.secondary).padding() }
                    ForEach(rows) { note in
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
                                Text((note.deletedAt ?? note.updatedAt).formatted(.dateTime.month().day().locale(.appDate)))
                            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 96, alignment: .trailing)
                            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 61)
                                .background(visibleNote?.id == note.id ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
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
                            Button(value) { notes.edit(note.id) { $0.folder = value } }
                        }
                        Divider()
                        Button("移到新文件夹…") {
                            if let value = TaskNamePrompt.ask("文件夹名称"), !value.isEmpty {
                                guard notes.addFolder(value) else { TaskNamePrompt.invalidName(); return }
                                notes.edit(note.id) { $0.folder = value }
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
                    Text(note.updatedAt.formatted(.dateTime.year().month().day().hour().minute().locale(.appDate)))
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    if note.hasPreservedRichContent {
                        // 富文本保护降级实现：原文 JSON 保留在 originalContentJson，编辑照常进行，
                        // 显式“创建纯文本副本”才得到可自由编辑的副本（Flutter 草稿保护的可用替代）。
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                            Text("此笔记来自导入，编辑将创建纯文本副本")
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
                                   profile: DocumentProfile(selectionActions: [DocumentSelectionAction(id: "note.createTask", title: "用所选文字创建任务", perform: { text in
                                       let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                       guard !trimmed.isEmpty,
                                             let id = tasks.createTask(title: trimmed, in: .inbox).taskID else { return }
                                       notes.edit(note.id) { $0.linkedTaskIDs.append(id) }
                                   })], noteSlash: true),
                                   contentSized: true, handle: editorHandle).id(note.id)
                    linkedTasksSection(note)
                    if !note.attachments.isEmpty { AttachmentListView(attachments: note.attachments) { attachments in
                        notes.edit(note.id) { $0.attachments = attachments }
                    } }
                }
                }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 44)
                    .frame(maxWidth: 820).frame(maxWidth: .infinity)
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
