import AppKit
import SwiftUI

struct NotesWorkspaceView: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var tasks: TaskWorkspaceModel
    @State private var query = ""
    @State private var folder: String?
    @State private var favorites = false
    @State private var confirmClear = false
    @State private var purgeID: UUID?
    // 笔记页脚的浮动格式工具条（Round B2 迁移：Flutter DocumentEditorFooter + DocumentEditorToolbar）。
    @State private var showFormatToolbar = false
    @StateObject private var editorHandle = DocumentEditorHandle()
    private var trash: Bool { navigation.destination == .notesTrash }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 640 || notes.selected == nil {
                    list.frame(maxWidth: geometry.size.width >= 640 ? 360 : .infinity)
                }
                if geometry.size.width >= 640 || notes.selected != nil {
                    Divider()
                    inspector
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trash ? "笔记垃圾桶" : "笔记").font(WFType.pageTitle)
                Spacer()
                if trash {
                    Button("全部删除") { confirmClear = true }.disabled(!notes.notes.contains { $0.deletedAt != nil })
                } else {
                    Button { notes.create() } label: { Image(systemName: "plus") }.help("新建笔记")
                }
            }
            HStack {
                Button("全部笔记") { navigation.destination = .notes }
                Button("垃圾桶") { navigation.destination = .notesTrash }
            }.buttonStyle(.borderless)
            TextField("搜索笔记", text: $query)
            if !trash {
                HStack {
                    Menu(folder ?? "全部文件夹") {
                        Button("全部文件夹") { folder = nil }
                        ForEach(Array(Set(notes.notes.map(\.folder))).sorted(), id: \.self) { value in
                            Button(value) { folder = value }
                        }
                    }
                    Toggle("收藏", isOn: $favorites).toggleStyle(.checkbox)
                }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    let rows = notes.rows(trash: trash, query: query, folder: folder, favorites: favorites)
                    if rows.isEmpty { Text("暂无笔记").foregroundStyle(.secondary).padding() }
                    ForEach(rows) { note in
                        Button { notes.selectedID = note.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if note.favorite { Image(systemName: "star.fill") }
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title).lineLimit(1)
                                    Spacer()
                                }
                                Text(note.document.plainText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(note.folder) · \((note.deletedAt ?? note.updatedAt).formatted(.dateTime.year().month().day().locale(.appDate)))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(notes.selectedID == note.id ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }.padding(20)
    }

    @ViewBuilder private var inspector: some View {
        if let note = notes.selected {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { notes.selectedID = nil } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    if trash {
                        Button("恢复") { notes.restore(note.id) }
                        Button("永久删除", role: .destructive) { purgeID = note.id }
                    } else {
                        Button { notes.edit(note.id) { $0.favorite.toggle() } } label: {
                            Image(systemName: note.favorite ? "star.fill" : "star")
                        }
                        Button("删除", role: .destructive) { notes.delete(note.id) }
                        noteActionsMenu(note)
                    }
                }.buttonStyle(.borderless)
                if trash {
                    Text(note.title.isEmpty ? "未命名笔记" : note.title).font(WFType.detailTitle)
                    ScrollView { Text(note.document.plainText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    TextField("未命名笔记", text: Binding(get: { notes.selected?.title ?? "" }, set: { value in notes.edit(note.id) { $0.title = value } }))
                        .textFieldStyle(.plain).font(WFType.detailTitle)
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
                                   })]),
                                   handle: editorHandle).id(note.id)
                    linkedTasksSection(note)
                    TextField("文件夹", text: Binding(get: { notes.selected?.folder ?? "" }, set: { value in notes.edit(note.id) { $0.folder = value.isEmpty ? "未归档" : value } }))
                    AttachmentListView(attachments: note.attachments) { attachments in
                        notes.edit(note.id) { $0.attachments = attachments }
                    }
                }
                Spacer(minLength: 0)
                if !trash { footer(note) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("选择一篇笔记").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 笔记操作菜单（Round B2：复制正文 / 创建纯文本副本；移到垃圾桶沿用删除按钮）

    private func noteActionsMenu(_ note: Note) -> some View {
        Menu {
            Button("复制笔记正文") { copyPlainText(note) }
            if note.hasPreservedRichContent {
                Button("创建纯文本副本") { _ = notes.createPlainTextCopy(note.id) }
            }
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
            Button { showFormatToolbar.toggle() } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(showFormatToolbar ? WFColors.accent : WFColors.secondaryText)
            }.buttonStyle(.plain).help("正文格式").accessibilityLabel("正文格式")
        }
        .overlay(alignment: .bottomTrailing) {
            if showFormatToolbar {
                DocumentFormatToolbarView(handle: editorHandle)
                    .padding(.trailing, 2).padding(.bottom, 32)
            }
        }
    }
}
