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
        .onChange(of: navigation.destination) { _, _ in notes.selectedID = nil }
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
                                Text("\(note.folder) · \((note.deletedAt ?? note.updatedAt).formatted(date: .abbreviated, time: .omitted))")
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
                    }
                }.buttonStyle(.borderless)
                if trash {
                    Text(note.title.isEmpty ? "未命名笔记" : note.title).font(WFType.detailTitle)
                    ScrollView { Text(note.document.plainText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    TextField("未命名笔记", text: Binding(get: { notes.selected?.title ?? "" }, set: { value in notes.edit(note.id) { $0.title = value } }))
                        .textFieldStyle(.plain).font(WFType.detailTitle)
                    DocumentEditor(taskID: note.id, document: note.document,
                                   onDocumentChange: { document in notes.edit(note.id) { $0.document = document } },
                                   onEscape: { .endEditing }, onEditingChanged: { _ in },
                                   selectionActionTitle: "用所选文字创建任务",
                                   onSelectionAction: { text in
                                       if let id = tasks.createTask(title: text, in: .inbox).taskID {
                                           notes.edit(note.id) { $0.linkedTaskIDs.append(id) }
                                       }
                                   }).id(note.id)
                    if !note.linkedTaskIDs.isEmpty {
                        DisclosureGroup("关联任务 \(note.linkedTaskIDs.count)") {
                            ForEach(note.linkedTaskIDs, id: \.self) { id in
                                if let task = tasks.task(for: id), task.deletedAt == nil {
                                    Button(task.title) { navigation.destination = .inbox; tasks.select(id) }
                                }
                            }
                        }
                    }
                    TextField("文件夹", text: Binding(get: { notes.selected?.folder ?? "" }, set: { value in notes.edit(note.id) { $0.folder = value.isEmpty ? "未归档" : value } }))
                    AttachmentListView(attachments: note.attachments) { attachments in
                        notes.edit(note.id) { $0.attachments = attachments }
                    }
                }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("选择一篇笔记").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
