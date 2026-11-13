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

    @State private var dropTarget: NoteFolderPlacement?
    /// 鼠标悬停的文件夹行：悬停时计数换成「新建子文件夹」小方钮。
    @State private var hoveredFolderID: String?
    @State private var showNoteTemplatePicker = false
    /// 「从模板新建」的目标文件夹：nil = 头部入口（落在当前选中文件夹）。
    @State private var templateTargetFolder: String?
    /// 右键「编辑文件夹」的目标节点：非 nil 时弹出图标 + 名称颜色编辑弹窗。
    @State private var editingFolder: NoteFolderNode?
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
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            if trash { trashRows } else { treeRows }
                        }
                        if !trash { rootDropArea }
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                }
                .compactScrollbars()
            }
            // 垃圾桶固定在侧栏底部：不随树滚动，常驻可达（此前挂在树尾，
            // 列表一长就够不着）；树尾那段已并入这里。
            if !trash { trashEntry }
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
                apply: { self.applyNoteTemplate($0, folder: templateTargetFolder) },
                title: "笔记模板",
                kind: .note,
                builtIns: BuiltInNoteTemplates.all,
                onDismiss: { showNoteTemplatePicker = false; templateTargetFolder = nil },
                onApplied: { _ in detailOnly = true })
        }
        .sheet(item: $editingFolder) { node in
            NoteFolderEditSheet(
                folderName: node.name,
                initialIcon: node.icon,
                initialColorHex: node.nameColorHex,
                onSave: { icon, colorHex in
                    notes.setFolderIcon(icon, for: node.id)
                    notes.setFolderNameColor(colorHex, for: node.id)
                    editingFolder = nil
                },
                onCancel: { editingFolder = nil })
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
                    presentNewSubfolder(under: nil, name: "")
                } label: {
                    Image(systemName: "folder.badge.plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(WFColors.accent)
                .hoverTip("新建文件夹")
                .accessibilityLabel("新建文件夹")
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
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WFColors.tertiaryText)
                TextField("搜索笔记", text: $query)
                    .textFieldStyle(.plain)
                    .font(WFType.body)
                    .padding(.leading, -1)
                    .frame(height: 28)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                if backgroundTheme.isThemed || glassActive {
                    WFGlassSurface(shape: RoundedRectangle(cornerRadius: 6),
                                   fallback: backgroundTheme.inputFill)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(backgroundTheme.inputFill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(WFColors.border, lineWidth: 1)
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
                // 选中段白底 + 描边（分段控件标准画法），未选中保持素底。
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 5).stroke(WFColors.border)
                    }
                }
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
                      depth: node.depth, expanded: expanded, real: true, icon: node.icon,
                      nameColorHex: node.nameColorHex,
                      toggle: { notes.setFolderExpanded(node.id, !expanded) })
            if expanded {
                noteChildren(notes.notes(inFolderNamed: node.name,
                                         query: query, favorites: favorites),
                             depth: node.depth + 1)
            }
        }
    }

    private var rootDropArea: some View {
        let target = NoteDirectoryDropDelegate(notes: notes, rowID: nil, folderName: nil, indicator: $dropTarget)
        return Color.clear
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if dropTarget == .root { insertionLine(depth: 0) }
            }
            .onDrop(of: target.types, delegate: target)
    }

    private func insertionLine(depth: Int) -> some View {
        Capsule().fill(WFColors.accent).frame(height: 2)
            .padding(.leading, CGFloat(depth) * 16 + 6)
            .padding(.trailing, WFSpace.sm)
            .allowsHitTesting(false)
    }

    /// 垃圾桶入口：固定在侧栏底部（分隔线 + 单行），与树滚动区分离。
    private var trashEntry: some View {
        VStack(spacing: 0) {
            Divider().padding(.bottom, 6)
            Button {
                environment.navigate(to: .notesTrash)
            } label: {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "trash").font(.system(size: 12)).frame(width: 15)
                    Text("垃圾桶").font(WFType.navigation)
                    Spacer()
                    countBadge(notes.notes.filter { $0.deletedAt != nil }.count)
                }
                .padding(.horizontal, WFSpace.sm)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.secondaryText)
            .rowHoverBackground(selected: false, cornerRadius: 6)
            .accessibilityLabel("垃圾桶")
        }
    }

    /// 圆角胶囊计数：文件夹与垃圾桶统一口径（此前是裸的灰色小数字）。
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(WFType.sidebarBadge)
            .monospacedDigit()
            .foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, 7)
            .frame(minWidth: 20, minHeight: 16)
            .background(WFColors.quickAddIdleFill, in: Capsule())
    }

    @ViewBuilder
    private func noteChildren(_ items: [Note], depth: Int) -> some View {
        // 空文件夹不再渲染「暂无笔记」占位（用户要求），直接留白。
        ForEach(items) { note in
            noteRow(note, depth: depth)
        }
    }

    @ViewBuilder
    private func folderRow(name: String, nodeID: String, depth: Int,
                           expanded: Bool, real: Bool, icon: String? = nil,
                           nameColorHex: String? = nil,
                           toggle: @escaping () -> Void) -> some View {
        let count = notes.notes(inFolderNamed: name, query: query, favorites: favorites).count
        let hovered = hoveredFolderID == nodeID
        let symbol = NoteDirectoryIcon.resolve(icon)?.rawValue ?? (real ? "folder" : "tray")
        let target = NoteDirectoryDropDelegate(notes: notes, rowID: nodeID, folderName: name, indicator: $dropTarget)
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
                    NoteDirectoryGlyph(icon: NoteDirectoryIcon.resolve(icon),
                                       symbol: real ? "folder" : "tray", size: 16)
                    Text(name).font(WFType.navigation).lineLimit(1)
                        .ifLet(nameColorHex.flatMap { NSColor(documentHex: $0) }) { text, color in
                            text.foregroundStyle(Color(nsColor: color))
                        }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .firstMouseAction(toggle)
            Spacer(minLength: 4)
            // 悬停时计数换成「新建子文件夹」小方钮；「未归档」没有子文件夹
            // 概念，恒显计数胶囊。
            if real, hovered {
                Button {
                    presentNewSubfolder(under: nodeID, name: name)
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 4.5))
                        .overlay(RoundedRectangle(cornerRadius: 4.5).stroke(WFColors.border))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.secondaryText)
                .hoverTip("新建子文件夹")
            } else {
                countBadge(count)
            }
        }
        .padding(.leading, CGFloat(depth) * 16 + 6)
        .padding(.trailing, WFSpace.sm)
        .frame(height: NoteDirectoryDropDelegate.rowHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredFolderID = nodeID }
            else if hoveredFolderID == nodeID { hoveredFolderID = nil }
        }
        .rowHoverBackground(selected: dropTarget == .inside(nodeID), cornerRadius: 6)
        .overlay {
            if dropTarget == .inside(nodeID) {
                RoundedRectangle(cornerRadius: 6).stroke(WFColors.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if dropTarget == .before(nodeID) { insertionLine(depth: depth) }
        }
        .overlay(alignment: .bottom) {
            if dropTarget == .after(nodeID) { insertionLine(depth: depth) }
        }
        .accessibilityLabel(name)
        .accessibilityValue(expanded ? "已展开" : "已折叠")
        .accessibilityIdentifier(real ? "note.folder.\(nodeID)" : "note.folder.unfiled")
        .onDrop(of: target.types, delegate: target)
        .ifLet(real ? nodeID : nil) { view, id in
            view.modifier(NoteFolderDragSource(id: id, name: name,
                                               icon: NoteDirectoryIcon.resolve(icon),
                                               symbol: symbol))
        }
        .businessContextMenu {
            if real {
                Button("新建文件") { createNote(in: name) }
                Button("从模板新建…") {
                    templateTargetFolder = name
                    showNoteTemplatePicker = true
                }
                Divider()
                Button("新建子文件夹…") { presentNewSubfolder(under: nodeID, name: name) }
                if depth > 0 {
                    Button("移到根目录") { notes.moveFolder(id: nodeID, under: nil) }
                }
                NoteDirectoryIconMenu(icon: icon) { notes.setFolderIcon($0, for: nodeID) }
                Button("编辑文件夹…") {
                    editingFolder = notes.folderNodes.first { $0.id == nodeID }
                }
                Button("重命名文件夹…") {
                    present(DialogRequest(title: "重命名文件夹", placeholder: "文件夹名称",
                                          initialText: name, confirm: "保存") { value in
                        guard !value.isEmpty, value != name else { return }
                        if !self.notes.renameFolder(name, to: value) {
                            self.presentNotice("名称为空或已存在")
                        }
                    })
                }
                Button("删除文件夹…") {
                    present(DialogRequest(
                        title: "删除文件夹“\(name)”？",
                        message: "其中的笔记会移到“未归档”，子文件夹会移到根目录。",
                        confirm: "删除", destructive: true) { _ in
                        self.notes.removeFolder(name)
                    })
                }
            } else {
                // 「未归档」伪节点：右键补一个顶层文件夹入口（此前树里无处新建顶层文件夹）。
                Button("新建文件夹…") { presentNewSubfolder(under: nil, name: name) }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note, depth: Int) -> some View {
        let selected = selectedNoteID == note.id
        let openNote = {
            notes.selectedID = note.id
            detailOnly = true
        }
        HStack(spacing: 5) {
            NoteDirectoryGlyph(icon: NoteDirectoryIcon.resolve(note.icon),
                               symbol: "doc.text", size: 15)
                .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
            if floatingNotes.isOpen(note.id) {
                Image(systemName: "rectangle.on.rectangle").font(.caption2)
                    .foregroundStyle(WFColors.accent)
            }
            Text(note.title.isEmpty ? "未命名笔记" : note.title)
                .font(WFType.navigation).lineLimit(1)
                .foregroundStyle(WFColors.text)
            if note.favorite {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange)
            }
            Spacer(minLength: 2)
        }
        // 预留展开箭头的空间，让同层文件夹与笔记的图标对齐。
        .padding(.leading, CGFloat(depth) * 16 + 23)
        .padding(.trailing, WFSpace.sm)
        .frame(height: 28)
        .contentShape(Rectangle())
        .rowHoverBackground(selected: selected, cornerRadius: 6)
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

    // MARK: - 动作

    private func createNote() {
        createNote(in: notes.selected?.folder ?? NoteFolderTree.unfiledName)
    }

    /// 在指定文件夹里新建笔记并选中（头部「+」与文件夹右键菜单共用）。
    private func createNote(in folder: String) {
        query = ""
        notes.favoritesOnly = false
        notes.create(folder: folder)
        notes.expandAncestors(ofFolderNamed: folder)
        detailOnly = true
    }

    /// 套用笔记模板：正文与标题原样写进新笔记，落在当前选中的文件夹并选中。
    @discardableResult
    private func applyNoteTemplate(_ template: TaskTemplate, folder: String? = nil) -> UUID? {
        query = ""
        notes.favoritesOnly = false
        let folder = folder ?? notes.selected?.folder ?? NoteFolderTree.unfiledName
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
        NoteDirectoryIconMenu(icon: note.icon) { notes.setNoteIcon($0, for: note.id) }
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
