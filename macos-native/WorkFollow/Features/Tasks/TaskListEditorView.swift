import SwiftUI

enum ListManagementAnchor: Hashable {
    case mode(TaskListViewMode), more, save, cancel, copyScope(TaskListCopyScope)
}
struct ListManagementFrames: PreferenceKey {
    static var defaultValue: [ListManagementAnchor: CGRect] = [:]
    static func reduce(value: inout [ListManagementAnchor: CGRect], nextValue: () -> [ListManagementAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    @ViewBuilder func listManagementAnchor(_ anchor: ListManagementAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { proxy in
            Color.clear.preference(key: ListManagementFrames.self,
                value: [anchor: proxy.frame(in: .named("list-management"))])
        }.allowsHitTesting(false))
        #else
        self
        #endif
    }
}

struct TaskListEditorView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var preferences: TaskViewPreferenceStore
    let originalName: String?
    var onSaved: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskListEditingDraft
    @State private var mode: TaskListViewMode
    @State private var more = false
    @State private var newFolder = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    init(workspace: TaskWorkspaceModel, preferences: TaskViewPreferenceStore,
         name: String? = nil, onSaved: @escaping (String) -> Void = { _ in }) {
        self.workspace = workspace; self.preferences = preferences
        originalName = name; self.onSaved = onSaved
        _draft = State(initialValue: TaskListEditingDraft(meta: name.map { workspace.listMeta(for: $0) ?? TaskListMeta(name: $0) }))
        let key = TaskViewScopeKey.key(destination: .allTasks, activeList: name, activeTag: nil)
        _mode = State(initialValue: name == nil ? .list : preferences.viewMode(for: key, availableModes: TaskListViewMode.allCases))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(originalName == nil ? "新建清单" : "编辑清单").font(WFType.section)
            HStack(spacing: 12) {
                TaskListIconPicker(icon: $draft.icon, color: previewColor)
                TextField("清单名称", text: $draft.name)
                    .textFieldStyle(.plain).font(.system(size: 18))
                    .focused($nameFocused).onSubmit(save)
                    .accessibilityIdentifier("list-editor-name")
            }
            HStack(spacing: 8) {
                ForEach(WFListPalette.argb.indices, id: \.self) { index in
                    Button { draft.colorIndex = index; draft.colorARGB = nil } label: {
                        Circle().fill(WFListPalette.swatch(WFListPalette.argb[index]))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if (draft.colorIndex ?? WFListPalette.colorIndex(for: draft.name, explicit: nil)) == index && draft.colorARGB == nil {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(WFListPalette.checkmarkOn(WFListPalette.argb[index]))
                                }
                            }
                    }
                    .buttonStyle(.plain).hoverTip("清单颜色 \(index + 1)")
                        .accessibilityLabel("清单颜色 \(index + 1)")
                }
            }
            HStack(spacing: 12) {
                ForEach(TaskListViewMode.allCases) { value in
                    Button { mode = value } label: {
                        VStack(spacing: 10) {
                            Image(systemName: symbol(value)).font(.system(size: 25, weight: .light))
                            Text(value.title).font(WFType.body)
                        }
                        .frame(maxWidth: .infinity).frame(height: 84)
                        .foregroundStyle(mode == value ? WFColors.accent : WFColors.secondaryText)
                        .background(mode == value ? WFColors.accent.opacity(0.07) : WFColors.secondarySurface,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(mode == value ? WFColors.accent : .clear))
                    }
                    .buttonStyle(.plain).accessibilityLabel(value.title + "视图")
                    .accessibilityValue(mode == value ? "已选择" : "未选择")
                    .listManagementAnchor(.mode(value))
                }
            }
            DisclosureGroup("更多设置", isExpanded: $more) {
                VStack(spacing: 0) {
                    WFFormRow("文件夹") {
                        BusinessMenu(title: "所属文件夹") {
                            BusinessMenuOption("无", selected: draft.folderName == nil && !newFolder) {
                                draft.folderName = nil; newFolder = false
                            }
                            ForEach(workspace.listFolderNames, id: \.self) { folder in
                                BusinessMenuOption(folder, selected: draft.folderName == folder && !newFolder) {
                                    draft.folderName = folder; newFolder = false
                                }
                            }
                            Divider()
                            Button("新建文件夹…") { draft.folderName = ""; newFolder = true }
                        } label: {
                            HStack {
                                Text(newFolder ? "新建文件夹" : draft.folderName ?? "无").lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 10))
                            }
                        }
                    }
                    if newFolder {
                        TextField("文件夹名称", text: Binding(get: { draft.folderName ?? "" }, set: { draft.folderName = $0 }))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, WFSpace.md).padding(.vertical, 8)
                    }
                    WFFormToggleRow("在智能清单中显示", isOn: $draft.showsInSmartLists)
                        .help("在今天、明天、最近 7 天中显示")
                    WFFormToggleRow("任务提醒", isOn: $draft.remindersEnabled)
                        .help("控制本机通知及同步到提醒事项的到点提醒")
                    WFFormToggleRow("设为默认清单", isOn: $draft.isDefault, showsDivider: false)
                }.padding(.top, 8)
            }.font(WFType.body).listManagementAnchor(.more)
            if let error { Text(error).font(WFType.supporting).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    .listManagementAnchor(.cancel)
                Button(originalName == nil ? "创建" : "保存", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listManagementAnchor(.save)
            }
        }
        .padding(24).frame(width: 464)
        .workfollowPopupSurface()
        .coordinateSpace(name: "list-management")
        .onAppear { nameFocused = true }
        .onChange(of: draft.name) { _, _ in error = nil }
    }

    private var previewColor: Color {
        WFListPalette.color(for: draft.name, meta: TaskListMeta(name: draft.name, colorIndex: draft.colorIndex, colorARGB: draft.colorARGB))
    }
    private func symbol(_ mode: TaskListViewMode) -> String {
        switch mode { case .list: "list.bullet"; case .kanban: "rectangle.split.3x1"; case .timeline: "chart.bar.xaxis" }
    }
    private func save() {
        if let message = TaskListEditingDraft.nameError(draft.name, existing: workspace.allListNames, replacing: originalName) {
            error = message; return
        }
        if newFolder && (draft.folderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "请输入文件夹名称"; return
        }
        guard workspace.saveListDetails(draft, replacing: originalName) else { error = "无法保存清单，请重试"; return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.setViewMode(mode, for: TaskViewScopeKey.key(destination: .allTasks, activeList: name, activeTag: nil))
        onSaved(name); dismiss()
    }
}

struct TaskListCopyView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let source: String
    var onCopied: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var scope = TaskListCopyScope.allPreservingStatus
    @State private var error: String?

    init(workspace: TaskWorkspaceModel, source: String, onCopied: @escaping (String) -> Void = { _ in }) {
        self.workspace = workspace; self.source = source; self.onCopied = onCopied
        var name = source + " 副本", n = 2
        while workspace.allListNames.contains(name) { name = source + " 副本 \(n)"; n += 1 }
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("复制清单").font(WFType.section)
            TextField("清单名称", text: $name).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("list-copy-name")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(TaskListCopyScope.allCases) { option in
                    Button { scope = option } label: {
                        HStack(spacing: 10) {
                            Image(systemName: scope == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(scope == option ? WFColors.accent : WFColors.secondaryText)
                            Text(option.title).foregroundStyle(WFColors.text)
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityValue(scope == option ? "已选择" : "未选择")
                        .listManagementAnchor(.copyScope(option))
                }
            }.font(WFType.body)
            if let error { Text(error).font(WFType.supporting).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    .listManagementAnchor(.cancel)
                Button("复制") {
                    if let message = TaskListEditingDraft.nameError(name, existing: workspace.allListNames) { error = message; return }
                    guard workspace.copyList(source, to: name, scope: scope) else { error = "无法复制清单"; return }
                    onCopied(name.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .listManagementAnchor(.save)
            }
        }.padding(24).frame(width: 420)
            .workfollowPopupSurface()
            .coordinateSpace(name: "list-management")
    }
}

/// Sidebar and title menus use the same commands and eligibility rules.
struct TaskListCommands: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let name: String
    let onEdit: () -> Void
    let onCopy: () -> Void
    var onActivity: (() -> Void)?

    private var meta: TaskListMeta? { workspace.listMeta(for: name) }
    var body: some View {
        if !workspace.isListArchived(name) {
            Button("编辑清单…", systemImage: "pencil", action: onEdit)
            Button(meta?.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") {
                _ = workspace.setListPinned(name, meta?.isPinned != true)
            }
            Button(meta?.isDefault == true ? "取消默认清单" : "设为默认清单", systemImage: "tray") {
                _ = workspace.setDefaultList(meta?.isDefault == true ? nil : name)
            }
        }
        Button("复制清单…", systemImage: "doc.on.doc", action: onCopy)
        if let onActivity { Button("清单动态", systemImage: "clock.arrow.circlepath", action: onActivity) }
        Divider()
        if workspace.isListArchived(name) {
            Button("取消归档", systemImage: "archivebox") { _ = workspace.setListArchived(name, false) }
        } else {
            Button("归档清单…", systemImage: "archivebox") {
                if TaskNamePrompt.confirm("归档清单“\(name)”？", message: "归档后不在智能清单中显示，到期不提醒。可以随时取消归档。", action: "归档") {
                    _ = workspace.setListArchived(name, true)
                }
            }.disabled(meta?.isDefault == true)
        }
        Button("删除清单…", systemImage: "trash", role: .destructive) {
            if TaskNamePrompt.confirm("删除清单“\(name)”？", message: "清单中的任务和子任务将移入垃圾桶。可以撤销。", action: "删除") {
                _ = workspace.deleteList(name)
            }
        }.disabled(meta?.isDefault == true)
    }
}

struct TaskListIconPicker: View {
    @Binding var icon: String?
    let color: Color
    var fallbackSymbol: String? = nil
    var body: some View {
        BusinessMenu(width: 264, title: "图标") {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 6), spacing: 8) {
                ForEach(["📁", "💼", "🏠", "📚", "🎯", "🚀", "🛒", "💡", "🍀", "✈️", "🧪", "🎨"], id: \.self) { value in
                    Button { icon = value } label: { Text(value).frame(width: 30, height: 30) }
                        .buttonStyle(.plain).accessibilityLabel(value)
                }
            }.padding(8)
            Divider()
            Button("无图标") { icon = nil }
        } label: {
            Group {
                if let icon { Text(icon).font(.system(size: 24)) }
                else if let fallbackSymbol { Image(systemName: fallbackSymbol).font(.system(size: 22)).foregroundStyle(color) }
                else { Circle().fill(color).frame(width: 18, height: 18) }
            }
            .frame(width: 40, height: 40)
            .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
        }.accessibilityLabel(fallbackSymbol == nil ? "清单图标" : "文件夹图标")
    }
}

struct TaskFolderEditingRequest: Identifiable {
    let id = UUID()
    var name: String? = nil
}

struct TaskFolderEditorView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let originalName: String?
    var onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String?
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    init(workspace: TaskWorkspaceModel, name: String?, onSaved: @escaping (String) -> Void = { _ in }) {
        self.workspace = workspace; originalName = name; self.onSaved = onSaved
        _name = State(initialValue: name ?? "")
        _icon = State(initialValue: workspace.listFolders.first { $0.name == name }?.icon)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(originalName == nil ? "新建文件夹" : "编辑文件夹").font(WFType.section)
            HStack(spacing: 12) {
                TaskListIconPicker(icon: $icon, color: WFColors.secondaryText, fallbackSymbol: "folder")
                TextField("文件夹名称", text: $name).textFieldStyle(.plain).font(.system(size: 18))
                    .focused($nameFocused).onSubmit(save)
            }
            if let error { Text(error).font(WFType.supporting).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(originalName == nil ? "创建" : "保存", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 420)
            .workfollowPopupSurface()
            .onAppear { nameFocused = true }
    }
    private func save() {
        guard workspace.saveListFolderDetails(name, replacing: originalName, icon: icon) else {
            error = "文件夹名称为空或已存在"; return
        }
        onSaved(name.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
    }
}
