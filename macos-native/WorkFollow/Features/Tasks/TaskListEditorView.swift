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
        // 按滴答桌面版「编辑清单」的实测规格重排：
        //   标题居中 17pt / 标签 13pt 左列 96pt / 色点 22pt 间距 6
        //   视图卡 65×50 / 行高 45pt
        // 宽度必须容下最长的一行：96 标签 + 12 间距 + 386 色点（14×22+13×6）
        // + 36 内边距 = 530pt。440 会撑破容器把左侧标签裁掉。
        SheetDialog(title: originalName == nil ? "新建清单" : "编辑清单",
                    width: 396,
                    primaryTitle: originalName == nil ? "创建" : "保存",
                    canSubmit: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    cancelIdentifier: "list-editor-cancel", primaryIdentifier: "list-editor-save",
                    cancelDecoration: { AnyView($0.listManagementAnchor(.cancel)) },
                    primaryDecoration: { AnyView($0.listManagementAnchor(.save)) },
                    onCancel: { dismiss() }, onSubmit: save,
                    titleAlignment: .center, buttonsCentered: true) {
            VStack(alignment: .leading, spacing: 0) {
            // 名称：全宽输入框，行内左端是清单图标（点击换图标），滴答口径。
            HStack(spacing: 10) {
                TaskListIconPicker(icon: $draft.icon, color: previewColor, inlineField: true)
                TextField("清单名称", text: $draft.name)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($nameFocused).onSubmit(save)
                    .accessibilityIdentifier("list-editor-name")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(nameFocused ? WFColors.accent : WFColors.border, lineWidth: 1.5))
            .padding(.bottom, 18)

            TickTickRow("清单颜色") {
                // 15 个色点（自动 + 14 调色板）放不进一行，滴答同样横向滚动。
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // 「自动」：清掉显式色，颜色按清单名推导（滴答的斜杠圆）。
                        Button { draft.colorIndex = nil; draft.colorARGB = nil } label: {
                            ListAutoSwatch(selected: draft.colorIndex == nil && draft.colorARGB == nil)
                        }
                        .buttonStyle(.plain).hoverTip("清单颜色 自动")
                            .accessibilityLabel("清单颜色 自动")
                        ForEach(WFListPalette.argb.indices, id: \.self) { index in
                            let selected = (draft.colorIndex ?? WFListPalette.colorIndex(for: draft.name, explicit: nil)) == index && draft.colorARGB == nil
                            Button { draft.colorIndex = index; draft.colorARGB = nil } label: {
                                ZStack {
                                    Circle().strokeBorder(
                                        selected ? WFListPalette.swatch(WFListPalette.argb[index]) : .clear,
                                        lineWidth: 1.5
                                    ).frame(width: 30, height: 30)
                                    Circle().fill(WFListPalette.swatch(WFListPalette.argb[index]))
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .buttonStyle(.plain).hoverTip("清单颜色 \(index + 1)")
                                .accessibilityLabel("清单颜色 \(index + 1)")
                                .accessibilityValue(selected ? "已选择" : "未选择")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }

            TickTickRow("视图类型") {
                HStack(spacing: 12) {
                    ForEach(TaskListViewMode.allCases) { value in
                        Button { mode = value } label: {
                            VStack(spacing: 6) {
                                Image(systemName: symbol(value)).font(.system(size: 15, weight: .regular))
                                Text(value.title).font(.system(size: 11))
                            }
                            .frame(width: 72, height: 52)
                            .foregroundStyle(mode == value ? WFColors.accent : WFColors.secondaryText)
                            .background(mode == value ? WFColors.accent.opacity(0.08) : WFColors.secondarySurface,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(mode == value ? WFColors.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .hoverTip(value.title + "视图")
                        .accessibilityLabel(value.title + "视图")
                        .accessibilityValue(mode == value ? "已选择" : "未选择")
                        .listManagementAnchor(.mode(value))
                    }
                }
            }

            TickTickRow("文件夹") {
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
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WFColors.border, lineWidth: 1))
                }
            }

            if newFolder {
                TickTickRow("") {
                    TextField("文件夹名称", text: Binding(get: { draft.folderName ?? "" }, set: { draft.folderName = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }

            TickTickRow("在智能清单显示") {
                BusinessMenu(title: "在智能清单中显示") {
                    BusinessMenuOption("所有任务", selected: draft.showsInSmartLists) {
                        draft.showsInSmartLists = true
                    }
                    BusinessMenuOption("不显示", selected: !draft.showsInSmartLists) {
                        draft.showsInSmartLists = false
                    }
                } label: {
                    HStack {
                        Text(draft.showsInSmartLists ? "所有任务" : "不显示").lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WFColors.border, lineWidth: 1))
                }
            }

            TickTickRow("任务提醒", trailing: true) {
                Toggle("", isOn: $draft.remindersEnabled)
                    .toggleStyle(.switch).labelsHidden()
                    .help("控制本机通知及同步到提醒事项的到点提醒")
            }

            TickTickRow("设为默认清单", trailing: true) {
                Toggle("", isOn: $draft.isDefault)
                    .toggleStyle(.switch).labelsHidden()
            }
            }

        } status: {
            Text(error ?? "").foregroundStyle(WFColors.danger)
        }
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
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            Text("复制清单").font(WFType.section)
            WFFormSection {
                WFFormRow("清单名称", showsDivider: false) {
                    TextField("清单名称", text: $name).textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("list-copy-name")
                }
            }
            WFFormSection("复制范围") {
                ForEach(TaskListCopyScope.allCases) { option in
                    Button { scope = option } label: {
                        HStack(spacing: 10) {
                            Image(systemName: scope == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(scope == option ? WFColors.accent : WFColors.secondaryText)
                            Text(option.title).foregroundStyle(WFColors.text)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, WFSpace.md)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityValue(scope == option ? "已选择" : "未选择")
                        .listManagementAnchor(.copyScope(option))
                }
            }
            .font(WFType.body)
            if let error { Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger) }
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
        }.padding(24).frame(width: SheetDialogMetrics.compactWidth)
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
            Button("编辑清单…", action: onEdit)
            Button(meta?.isPinned == true ? "取消置顶" : "置顶") {
                _ = workspace.setListPinned(name, meta?.isPinned != true)
            }
            Button(meta?.isDefault == true ? "取消默认清单" : "设为默认清单") {
                _ = workspace.setDefaultList(meta?.isDefault == true ? nil : name)
            }
        }
        Button("复制清单…", action: onCopy)
        if let onActivity { Button("清单动态", action: onActivity) }
        Divider()
        if workspace.isListArchived(name) {
            Button("取消归档") { _ = workspace.setListArchived(name, false) }
        } else {
            Button("归档清单…") {
                if TaskNamePrompt.confirm("归档清单“\(name)”？", message: "归档后不在智能清单中显示，到期不提醒。可以随时取消归档。", action: "归档") {
                    _ = workspace.setListArchived(name, true)
                }
            }.disabled(meta?.isDefault == true)
        }
        Button("删除清单…", role: .destructive) {
            if TaskNamePrompt.confirm("删除清单“\(name)”？", message: "清单中的任务和子任务将移入垃圾桶。可以撤销。", action: "删除") {
                _ = workspace.deleteList(name)
            }
        }.disabled(meta?.isDefault == true)
    }
}

/// 滴答清单颜色行首的「自动」圆：描边圆 + 斜杠，选中时外圈同色环。
/// 选中语义 = 无显式颜色，按清单名推导（与后端口径一致）。
struct ListAutoSwatch: View {
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle().strokeBorder(WFColors.secondaryText, lineWidth: 1.5)
                    .frame(width: 30, height: 30)
            }
            Circle()
                .strokeBorder(WFColors.secondaryText, lineWidth: 1.2)
                .frame(width: 22, height: 22)
            Rectangle()
                .fill(WFColors.secondaryText)
                .frame(width: 1.2, height: 26)
                .rotationEffect(.degrees(45))
                .frame(width: 22, height: 22)
                .clipped()
        }
        .frame(width: 30, height: 30)
    }
}

struct TaskListIconPicker: View {
    @Binding var icon: String?
    let color: Color
    var fallbackSymbol: String? = nil
    /// 嵌入名称输入框的紧凑触发器：无底板，无图标时画滴答的列表线稿。
    var inlineField = false
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
            if inlineField {
                Group {
                    if let icon { Text(icon).font(.system(size: 17)) }
                    else { Image(systemName: "line.3.horizontal").font(.system(size: 14, weight: .medium)) }
                }
                .foregroundStyle(icon == nil ? WFColors.secondaryText : WFColors.text)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            } else {
                Group {
                    if let icon { Text(icon).font(.system(size: 24)) }
                    else if let fallbackSymbol { Image(systemName: fallbackSymbol).font(.system(size: 22)).foregroundStyle(color) }
                    else { Circle().fill(color).frame(width: 18, height: 18) }
                }
                .frame(width: 40, height: 40)
                .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
            }
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
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            Text(originalName == nil ? "新建文件夹" : "编辑文件夹").font(WFType.section)
            WFFormSection {
                WFFormRow("图标") {
                    TaskListIconPicker(icon: $icon, color: WFColors.secondaryText, fallbackSymbol: "folder")
                }
                WFFormRow("名称", showsDivider: false) {
                    TextField("文件夹名称", text: $name).textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .focused($nameFocused).onSubmit(save)
                }
            }
            if let error { Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(originalName == nil ? "创建" : "保存", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: SheetDialogMetrics.compactWidth)
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

/// 清单编辑器的一行：左侧固定宽标签 + 右侧控件（滴答口径）。
///
/// 原来名称/色点/视图各自铺满整宽，没有标签列，三行等高块纵向排开，
/// 用户反馈「密度太小、很空」。加标签列后纵向节奏与滴答一致。
/// 简单换行布局：一行放不下就折到下一行。
///
/// 清单调色板有 14 个色点，用 HStack 会按固有宽度撑开父容器，
/// 在 400pt 弹框里溢出 100pt 以上，把左侧标签列推出可见区。
/// 换成按行装箱后宽度被约束在可用范围内，多出来的自动折行。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 滴答口径的表单行：左列固定 96pt / 13pt 灰标签，右侧控件。
///
/// 之前用 64pt 列宽导致「在智能清单显示」折成两行、把行撑高；
/// 96pt 是「在智能清单显示」七个汉字在 13pt 下单行放完的最小宽度。
private struct TickTickRow<Control: View>: View {
    let title: String
    /// 开关类靠右，下拉/输入类紧贴标签。
    var trailing = false
    @ViewBuilder var control: () -> Control

    init(_ title: String, trailing: Bool = false,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.trailing = trailing
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 124, alignment: .leading)
            if trailing {
                Spacer(minLength: 0)
                control()
            } else {
                control()
                Spacer(minLength: 0)
            }
        }
        .frame(height: 48)
    }
}
