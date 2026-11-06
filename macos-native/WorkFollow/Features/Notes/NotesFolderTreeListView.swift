import AppKit
import SwiftUI

/// 笔记页左栏：文件夹与笔记共用一棵树。
///
/// 设计约束（方案 C）：
/// - 单击文件夹**只展开/折叠**，不改 `selectedID`、不切 destination、不写 `folderFilter`；
///   正文始终由 `selectedID` 决定，与折叠状态无关。
/// - 节点只显示标题，不抽取 `document.previewText`，正文只在编辑栏出现一处。
/// - 「未归档」是固定的根级伪节点，「收藏」是顶部作用域切换，「垃圾桶」是底部入口。
/// - 展开态存在 `NotesWorkspaceModel.expandedFolderIDs`，不复用 `revision` 以免折叠触发写盘。
/// - 所有输入/确认框走 SwiftUI 非阻塞 `.workfollowAlert`。`TaskNamePrompt` 内部是
///   `NSApp.runModal`，在 SwiftUI 手势回调里启动会嵌套事件跟踪，弹窗按钮收不到点击。
struct NotesFolderTreeListView: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @Binding var query: String
    @Binding var detailOnly: Bool
    var trash: Bool
    var selectedNoteID: UUID?
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// 拖放悬停的文件夹节点。笔记与文件夹共用 String 负载，只挂一个
    /// dropDestination，按前缀在闭包里分派，避免同类型落点互相抢事件。
    @State private var dropTargetID: String?
    @State private var showNoteTemplatePicker = false
    @ObservedObject private var floatingNotes = FloatingNoteWindowController.shared

    // MARK: - 统一的非阻塞弹窗

    private struct DialogRequest {
        var title: String
        var message: String? = nil
        /// 非 nil 时带一个文本输入框。
        var placeholder: String? = nil
        var initialText: String = ""
        var confirm: String = "确定"
        var destructive: Bool = false
        var onConfirm: (String) -> Void
    }

    @State private var dialog: DialogRequest?
    @State private var dialogText = ""

    private var dialogPresented: Binding<Bool> {
        Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })
    }

    private var dialogActions: [WorkfollowDialogAction] {
        let label = dialog?.confirm ?? "确定"
        return [.cancel(), dialog?.destructive == true
            ? .destructive(label) { confirmDialog() }
            : .primary(label) { confirmDialog() }]
    }

    private func present(_ request: DialogRequest) {
        dialogText = request.initialText
        dialog = request
    }

    private func confirmDialog() {
        let request = dialog
        let value = dialogText.trimmingCharacters(in: .whitespacesAndNewlines)
        dialog = nil
        request?.onConfirm(value)
    }

    /// 校验失败的提示要延后一拍：框架在按钮 handler 返回后才复位 isPresented，
    /// 同步弹第二个会把新请求一起清掉。
    private func presentNotice(_ title: String) {
        DispatchQueue.main.async {
            present(DialogRequest(title: title, confirm: "好", onConfirm: { _ in }))
        }
    }

    private var favorites: Bool { notes.favoritesOnly }
    private var glassActive: Bool {
        WFGlassSupport.isActive(material,
                                reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency)
    }
    private var rows: [Note] {
        notes.rows(trash: trash, query: query, folder: nil, favorites: favorites)
    }

    /// DFS 序列里，祖先折叠的节点整棵隐藏。
    private var visibleFolderNodes: [NoteFolderNode] {
        var hidden = Set<String>()
        var result: [NoteFolderNode] = []
        for node in notes.folderNodes {
            if let parent = node.parentID, hidden.contains(parent) {
                hidden.insert(node.id)
                continue
            }
            result.append(node)
            if !notes.isFolderExpanded(node.id) { hidden.insert(node.id) }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !trash { searchBar }
            if !trash { scopePicker }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if trash { trashRows } else { treeRows }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .compactScrollbars()
            footer
        }
        .padding(.horizontal, 10).padding(.bottom, 16)
        .accessibilityIdentifier("note.folderTree")
        .workfollowAlert(
            dialog?.title ?? "",
            message: dialog?.message,
            isPresented: dialogPresented,
            textField: dialog?.placeholder.map {
                WorkfollowDialogTextField(placeholder: $0, text: $dialogText)
            },
            actions: dialogActions)
        .sheet(isPresented: $showNoteTemplatePicker) {
            TaskTemplateGalleryView(
                templateStore: TemplateStore.shared,
                apply: { self.applyNoteTemplate($0) },
                title: "笔记模板",
                kind: .note,
                builtIns: BuiltInNoteTemplates.all,
                onDismiss: { showNoteTemplatePicker = false },
                onApplied: { _ in detailOnly = true })
        }
    }

    // MARK: - 头部 / 搜索 / 作用域

    private var header: some View {
        HStack(spacing: 8) {
            if trash {
                Button {
                    environment.navigate(to: .notes)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).hoverTip("返回笔记")
            }
            Text(trash ? "垃圾桶" : "笔记").font(WFType.pageTitle)
            Spacer()
            if trash {
                Button("全部删除") {
                    present(DialogRequest(
                        title: "清空笔记垃圾桶",
                        message: "垃圾桶中的笔记将被永久删除，无法恢复。任务不受影响。",
                        confirm: "全部删除", destructive: true) { _ in notes.emptyTrash() })
                }
                .disabled(!notes.notes.contains { $0.deletedAt != nil })
            } else {
                Button {
                    showNoteTemplatePicker = true
                } label: {
                    Image(systemName: "doc.badge.plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(WFColors.accent)
                .hoverTip("从模板新建")
                .accessibilityLabel("从模板新建")
                Button(action: createNote) {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(WFColors.onAccent)
                .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 6))
                .hoverTip("新建笔记")
            }
        }
        .frame(height: 44)
    }

    private var searchBar: some View {
        HStack(spacing: 4) {
            if backgroundTheme.isThemed || glassActive {
                TextField("搜索笔记", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background {
                        WFGlassSurface(shape: RoundedRectangle(cornerRadius: 6),
                                       fallback: backgroundTheme.inputFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(WFColors.border, lineWidth: 1)
                    }
            } else {
                TextField("搜索笔记", text: $query).textFieldStyle(.roundedBorder)
            }
            WFGlassControlGroup(spacing: 0) {
                BusinessMenu {
                    Button("按标题排序") { notes.sort(.title) }
                    Button("按最近编辑排序") { notes.sort(.recentlyEdited) }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .fixedSize().hoverTip("笔记排序")
            }
        }
        .frame(height: 34)
    }

    private var scopePicker: some View {
        HStack(spacing: 3) {
            scopeButton("全部", selected: !favorites) { notes.favoritesOnly = false }
            scopeButton("收藏", selected: favorites) { notes.favoritesOnly = true }
        }
        .frame(maxWidth: .infinity)
        .padding(2)
        .background(WFColors.quickAddIdleFill, in: RoundedRectangle(cornerRadius: 7))
    }

    private func scopeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5))
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
                // 背景始终存在（未选中时用透明），否则 .plain 按钮的命中区域
                // 只剩文字字形，点空白处没反应。
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? WFColors.content : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(selected ? WFColors.text : WFColors.secondaryText)
        .accessibilityLabel(title)
    }

    // MARK: - 树

    @ViewBuilder private var treeRows: some View {
        let unfiledExpanded = notes.isFolderExpanded(NoteFolderTree.unfiledNodeID)
        folderRow(name: NoteFolderTree.unfiledName, nodeID: NoteFolderTree.unfiledNodeID,
                  depth: 0, expanded: unfiledExpanded, real: false,
                  toggle: { notes.setFolderExpanded(NoteFolderTree.unfiledNodeID, !unfiledExpanded) })
        if unfiledExpanded {
            noteChildren(notes.notes(inFolderNamed: NoteFolderTree.unfiledName,
                                     query: query, favorites: favorites), depth: 1)
        }

        ForEach(visibleFolderNodes) { node in
            let expanded = notes.isFolderExpanded(node.id)
            folderRow(name: node.name, nodeID: node.id,
                      depth: node.depth, expanded: expanded, real: true,
                      toggle: { notes.setFolderExpanded(node.id, !expanded) })
            if expanded {
                noteChildren(notes.notes(inFolderNamed: node.name,
                                         query: query, favorites: favorites),
                             depth: node.depth + 1)
            }
        }

        Divider().padding(.vertical, 10)
        Button {
            environment.navigate(to: .notesTrash)
        } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "trash").frame(width: 15)
                Text("垃圾桶").font(WFType.navigation)
                Spacer()
                Text("\(notes.notes.filter { $0.deletedAt != nil }.count)")
                    .font(WFType.sidebarBadge).foregroundStyle(WFColors.taskMetaText)
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.secondaryText)
        .rowHoverBackground(selected: false)
        .accessibilityLabel("垃圾桶")
    }

    @ViewBuilder
    private func noteChildren(_ items: [Note], depth: Int) -> some View {
        if items.isEmpty, query.isEmpty && !favorites {
            Text("暂无笔记")
                .font(.system(size: 11)).foregroundStyle(WFColors.tertiaryText)
                .padding(.leading, CGFloat(depth) * 16 + 22)
                .frame(height: 24)
        } else {
            ForEach(items) { note in
                noteRow(note, depth: depth)
            }
        }
    }

    @ViewBuilder
    private func folderRow(name: String, nodeID: String, depth: Int,
                           expanded: Bool, real: Bool,
                           toggle: @escaping () -> Void) -> some View {
        let count = notes.notes(inFolderNamed: name, query: query, favorites: favorites).count
        HStack(spacing: 5) {
            // 行主体用真正的 Button，不给整个 HStack 挂 onTapGesture。
            // 之前「+」按钮嵌在手势视图里，点它启动的同步模态会被手势跟踪吞事件。
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .foregroundStyle(WFColors.tertiaryText)
                    Image(systemName: "folder").font(.system(size: 13))
                        .frame(width: 15).foregroundStyle(WFColors.secondaryText)
                    Text(name).font(WFType.navigation).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .firstMouseAction(toggle)
            Spacer(minLength: 4)
            if real {
                Button {
                    presentNewSubfolder(under: nodeID, name: name)
                } label: {
                    Image(systemName: "plus").font(.system(size: 10))
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.tertiaryText)
                .hoverTip("新建子文件夹")
            }
            Text("\(count)").font(WFType.sidebarBadge).foregroundStyle(WFColors.tertiaryText)
        }
        .padding(.leading, CGFloat(depth) * 16 + 6)
        .padding(.trailing, WFSpace.sm)
        .frame(height: NavigationMetrics.rowHeight)
        .contentShape(Rectangle())
        .rowHoverBackground(selected: dropTargetID == nodeID, cornerRadius: 6)
        .overlay {
            if dropTargetID == nodeID {
                RoundedRectangle(cornerRadius: 6).stroke(WFColors.accent, lineWidth: 1.5)
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(expanded ? "已展开" : "已折叠")
        .accessibilityIdentifier(real ? "note.folder.\(nodeID)" : "note.folder.unfiled")
        .dropDestination(for: String.self) { values, _ in
            guard let payload = values.first else { return false }
            if let source = NoteFolderDragPayload.decode(payload) {
                // 「未归档」是伪节点，不能作为父文件夹。
                return real ? notes.moveFolder(id: source, under: nodeID) : false
            }
            return NoteFolderDrop.move(payload: payload, to: name, notes: notes)
        } isTargeted: { inside in
            dropTargetID = inside ? nodeID : nil
        }
        .ifLet(real ? nodeID : nil) { view, id in
            view.modifier(NoteFolderDragSource(id: id))
        }
        .ifLet(real ? name : nil) { view, folderName in
            view.businessContextMenu {
                Button("新建子文件夹…") { presentNewSubfolder(under: nodeID, name: folderName) }
                Button("移到根目录") { _ = notes.moveFolder(id: nodeID, under: nil) }
                Button("重命名文件夹…") {
                    present(DialogRequest(title: "重命名文件夹", placeholder: "文件夹名称",
                                          initialText: folderName, confirm: "保存") { value in
                        guard !value.isEmpty, value != folderName else { return }
                        if !self.notes.renameFolder(folderName, to: value) {
                            self.presentNotice("名称为空或已存在")
                        }
                    })
                }
                Button("删除文件夹…") {
                    present(DialogRequest(
                        title: "删除文件夹“\(folderName)”？",
                        message: "其中的笔记会移到“未归档”，子文件夹会移到根目录。",
                        confirm: "删除", destructive: true) { _ in
                        self.notes.removeFolder(folderName)
                    })
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note, depth: Int) -> some View {
        let openNote = {
            notes.selectedID = note.id
            detailOnly = true
        }
        HStack(spacing: 6) {
            if note.favorite {
                Image(systemName: "star.fill").font(.system(size: 9))
                    .foregroundStyle(.orange).frame(width: 10)
            } else {
                Circle().fill(WFColors.tertiaryText).frame(width: 4, height: 4)
                    .frame(width: 10)
            }
            if floatingNotes.isOpen(note.id) {
                Image(systemName: "rectangle.on.rectangle").font(.caption2)
                    .foregroundStyle(WFColors.accent)
            }
            Text(note.title.isEmpty ? "未命名笔记" : note.title)
                .font(WFType.navigation).lineLimit(1)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 2)
        }
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, WFSpace.sm)
        .frame(height: 28)
        .contentShape(Rectangle())
        .rowHoverBackground(selected: selectedNoteID == note.id, cornerRadius: 6)
        .onTapGesture(perform: openNote)
        .firstMouseAction(openNote)
        .accessibilityLabel(note.title.isEmpty ? "未命名笔记" : note.title)
        .accessibilityIdentifier("note.row.\(note.id.uuidString)")
        .modifier(NoteDragSource(note: note, enabled: true))
        .businessContextMenu(onOpen: { notes.selectedID = note.id }) {
            noteRowMenu(note)
        }
    }

    // MARK: - 垃圾桶

    @ViewBuilder private var trashRows: some View {
        if rows.isEmpty {
            Text("笔记垃圾桶是空的").foregroundStyle(.secondary).padding()
        }
        ForEach(rows) { note in
            HStack(spacing: 6) {
                Text(note.title.isEmpty ? "未命名笔记" : note.title)
                    .font(WFType.navigation).lineLimit(1)
                Spacer()
                Button { notes.restore(note.id) } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).hoverTip("恢复笔记：\(note.title)")
                Button {
                    let id = note.id
                    present(DialogRequest(title: "永久删除笔记？", confirm: "删除",
                                          destructive: true) { _ in self.notes.purge(id) })
                } label: {
                    Image(systemName: "trash.slash").frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).hoverTip("永久删除笔记：\(note.title)")
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: 30)
            .rowHoverBackground(selected: false, cornerRadius: 6)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !trash {
                Image(systemName: "folder").font(.system(size: 10))
                Text(favorites ? "只显示收藏" : "文件夹可折叠 · 正文看编辑栏")
            }
            Spacer()
            Text("\(rows.count) 篇")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(WFColors.tertiaryText)
    }

    // MARK: - 动作

    private func createNote() {
        query = ""
        notes.favoritesOnly = false
        let folder = notes.selected?.folder ?? NoteFolderTree.unfiledName
        notes.create(folder: folder)
        notes.expandAncestors(ofFolderNamed: folder)
        detailOnly = true
    }

    /// 套用笔记模板：正文与标题原样写进新笔记，落在当前选中的文件夹并选中。
    @discardableResult
    private func applyNoteTemplate(_ template: TaskTemplate) -> UUID? {
        query = ""
        notes.favoritesOnly = false
        let folder = notes.selected?.folder ?? NoteFolderTree.unfiledName
        let title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = notes.create(folder: folder, title: title, document: template.document)
        notes.expandAncestors(ofFolderNamed: folder)
        detailOnly = true
        return id
    }

    private func presentNewSubfolder(under parentID: String?, name: String) {
        let title = parentID == nil ? "新建文件夹" : "在「\(name)」下新建子文件夹"
        present(DialogRequest(title: title, placeholder: "文件夹名称", confirm: "创建") { value in
            guard self.notes.addFolder(value, parentID: parentID) != nil else {
                self.presentNotice("名称为空或已存在")
                return
            }
        })
    }

    /// 与原笔记列表右键菜单保持同样的 6 行结构（打开 / 收藏 / 移动到 /
    /// 复制正文 / 转换为任务 / 移到垃圾桶），树化不该悄悄改掉行为契约。
    @ViewBuilder
    private func noteRowMenu(_ note: Note) -> some View {
        Button("打开笔记") { notes.selectedID = note.id; detailOnly = true }
        Divider()
        Button(note.favorite ? "取消收藏" : "收藏") {
            notes.edit(note.id) { $0.favorite.toggle() }
        }
        BusinessMenu("移动到") {
            ForEach([NoteFolderTree.unfiledName] + notes.folders, id: \.self) { name in
                Button(name) { notes.moveNoteToFolder(note.id, named: name) }
            }
            Divider()
            Button("移到新文件夹…") {
                let id = note.id
                present(DialogRequest(title: "新建文件夹", placeholder: "文件夹名称",
                                      confirm: "创建") { value in
                    guard self.notes.addFolder(value, parentID: nil) != nil else {
                        self.presentNotice("名称为空或已存在")
                        return
                    }
                    self.notes.moveNoteToFolder(id, named: value)
                })
            }
        }
        Divider()
        Button("复制笔记正文") { copyPlainText(note) }
        if note.hasPreservedRichContent {
            Button("创建纯文本副本") { _ = notes.createPlainTextCopy(note.id) }
        }
        Button("转换为任务") { _ = notes.convertToTask(note.id) }
        Divider()
        Button("移到垃圾桶", role: .destructive) { notes.delete(note.id) }
    }

    private func copyPlainText(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(notePlainTextBody(note.document), forType: .string)
    }
}

// MARK: - 条件修饰

private extension View {
    /// SwiftUI 里没有可选值的 `if let` 修饰写法，抽一个小工具避免把树行拆成两份。
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?,
                                 @ViewBuilder transform: (Self, T) -> Content) -> some View {
        if let value { transform(self, value) } else { self }
    }
}
