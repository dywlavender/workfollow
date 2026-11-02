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
        // 2026-11 改版（设计稿 design-preview/stageshow-workfollow/list-editor）：
        //   标签列 84 / 行高 40 / 色点 12（档位 16）/ 视图改分段控件
        // 四条主张：
        //   1. 名称行左端是「清单身份块」——全框唯一用清单色铺底的地方，
        //      换色当场看得到落点（原来那里是一根无意义的 line.3.horizontal）。
        //   2. 色板 16 格一行收全（自动 + 14 色 + 取色盘），不再横向滚动、
        //      不再切掉最后一颗。视觉 12pt / 档位 16pt，16×16 = 256pt
        //      正好铺满控制列。
        //   3. 视图类型是「三选一」，用分段控件，不再用三张 72×52 大卡
        //      抢走整屏的视觉重量，也省下约 26pt 高度。
        //   4. 「在智能清单显示」本来就是二值（显示 / 不显示），改成开关，
        //      和另外两个开关并成一组，中间一道细线把「外观」与「行为」分开。
        //
        // 颜色分工（关键）：清单色是**数据**，只染身份块；强调色是**交互**，
        // 光标 / 选中段 / 开关 / 保存统一 WFColors.accent。让按钮跟着清单色走，
        // 黄色清单（#FFB703）下保存按钮会变成 1.75:1 的黄底白字，
        // 浅灰清单（#8A909B）下开关轨道会和「关闭」状态分不出来。
        SheetDialog(title: originalName == nil ? "新建清单" : "编辑清单",
                    width: SheetDialogMetrics.compactWidth,
                    primaryTitle: originalName == nil ? "创建" : "保存",
                    canSubmit: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    cancelIdentifier: "list-editor-cancel", primaryIdentifier: "list-editor-save",
                    cancelDecoration: { AnyView($0.listManagementAnchor(.cancel)) },
                    primaryDecoration: { AnyView($0.listManagementAnchor(.save)) },
                    onCancel: { dismiss() }, onSubmit: save,
                    titleAlignment: .center, buttonsCentered: true) {
            VStack(alignment: .leading, spacing: 0) {
                nameField
                    .padding(.bottom, WFSpace.md)

                TickTickRow("颜色", fillsWidth: true) {
                    ListColorPalette(colorIndex: $draft.colorIndex, colorARGB: $draft.colorARGB,
                                     autoARGB: previewARGB)
                }

                TickTickRow("视图", trailing: true) {
                    modeSegmented
                }

                folderRow

                if newFolder {
                    TickTickRow("") {
                        TextField("文件夹名称",
                                  text: Binding(get: { draft.folderName ?? "" },
                                                set: { draft.folderName = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .font(WFType.dialogBody)
                    }
                }

                rowDivider

                TickTickRow("在智能清单显示", trailing: true) {
                    Toggle("", isOn: $draft.showsInSmartLists)
                        .toggleStyle(.switch).labelsHidden()
                        .help("关闭后本清单的任务不出现在「所有任务」等智能清单里")
                }
                TickTickRow("任务提醒", trailing: true, showsDivider: true) {
                    Toggle("", isOn: $draft.remindersEnabled)
                        .toggleStyle(.switch).labelsHidden()
                        .help("控制本机通知及同步到提醒事项的到点提醒")
                }
                TickTickRow("设为默认清单", trailing: true, showsDivider: true) {
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
        .onDisappear { WFColorPanelPicker.dismiss() }
    }

    /// 名称输入框 + 左端的清单身份块。身份块是 BusinessMenu（换图标），
    /// 底色永远是当前清单色——选色时这里是唯一会变的地方。
    private var nameField: some View {
        HStack(spacing: WFSpace.control) {
            BusinessMenu(width: 264, title: "图标") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 6), spacing: 8) {
                    ForEach(["📁", "💼", "🏠", "📚", "🎯", "🚀", "🛒", "💡", "🍀", "✈️", "🧪", "🎨"],
                            id: \.self) { value in
                        Button { draft.icon = value } label: {
                            Text(value).frame(width: 30, height: 30)
                        }.buttonStyle(.plain).accessibilityLabel(value)
                    }
                }.padding(8)
                Divider()
                Button("无图标") { draft.icon = nil }
            } label: {
                ListIdentityTile(icon: draft.icon, colorARGB: previewARGB)
            }
            .accessibilityLabel("清单图标")

            TextField("清单名称", text: $draft.name)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($nameFocused).onSubmit(save)
                .accessibilityIdentifier("list-editor-name")
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(nameFocused ? WFColors.accent : WFColors.border, lineWidth: 1.5))
        // 聚焦光晕：向外扩 3pt，只在编辑时出现。
        .overlay {
            if nameFocused {
                RoundedRectangle(cornerRadius: 10.5)
                    .strokeBorder(WFColors.accent.opacity(0.22), lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 视图类型：分段控件。图标沿用原来三张卡上的 SF Symbol。
    private var modeSegmented: some View {
        WFSegmentedControl(selection: $mode,
                           options: TaskListViewMode.allCases.map {
                               WFSegmentedControl<TaskListViewMode>.Option($0, $0.title, symbol: symbol($0))
                           },
                           optionDecoration: { value, view in
                               AnyView(view.listManagementAnchor(.mode(value)))
                           })
        .frame(width: 232)
    }

    /// 文件夹：轻量下拉，宽度只包住值，右缘与分段控件、开关落在同一条线。
    private var folderRow: some View {
        TickTickRow("文件夹", trailing: true) {
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
                HStack(spacing: WFSpace.relaxed) {
                    Text(newFolder ? "新建文件夹" : draft.folderName ?? "无")
                        .font(WFType.dialogBody).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(WFColors.borderStrong.opacity(0.6), lineWidth: 1))
            }
        }
    }

    /// 「外观」与「行为」之间的通栏细线。颜色行和视图/文件夹属于「这个清单长什么样、
    /// 归在哪」，三个开关属于「它怎么工作」，分两道。
    private var rowDivider: some View {
        Rectangle().fill(WFColors.borderStrong.opacity(0.7))
            .frame(height: 1)
            .padding(.vertical, WFSpace.sm)
    }

    /// 当前清单的色值。自动档按清单名推导，与列表页、侧栏同一口径。
    private var previewARGB: UInt32 {
        WFListPalette.argb(for: draft.name,
                           meta: TaskListMeta(name: draft.name,
                                              colorIndex: draft.colorIndex,
                                              colorARGB: draft.colorARGB))
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
    /// 开关与分段/下拉类控件靠右，贴同一条右缘。
    var trailing = false
    /// 控件自己撑满控制列（色板用）。与 `trailing` 互斥，它不需要 Spacer。
    var fillsWidth = false
    /// 组内细线：从标签列右缘起笔，右端到内容区右缘。
    var showsDivider = false
    @ViewBuilder var control: () -> Control

    /// 标签列宽。原 124pt 是「在智能清单显示」那行撑出来的；
    /// 收成 84 后八行标签全部单行，同时给右侧控制列腾出 40pt
    /// ——16 个色点正好铺满，右缘也能和开关对齐。
    static var labelWidth: CGFloat { 84 }

    init(_ title: String, trailing: Bool = false, fillsWidth: Bool = false,
         showsDivider: Bool = false,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.trailing = trailing
        self.fillsWidth = fillsWidth
        self.showsDivider = showsDivider
        self.control = control
    }

    var body: some View {
        HStack(spacing: WFSpace.md) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.labelWidth, alignment: .leading)
            if fillsWidth {
                control().frame(maxWidth: .infinity, alignment: .trailing)
            } else if trailing {
                Spacer(minLength: 0)
                control()
            } else {
                control()
                Spacer(minLength: 0)
            }
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(WFColors.borderStrong.opacity(0.7))
                    .frame(height: 1)
                    .padding(.leading, Self.labelWidth + WFSpace.md)
            }
        }
    }
}

/// 名称行左端的「清单身份块」：圆角底铺清单色 + 图标。
///
/// 全框唯一用清单色铺底的地方。原来是 `line.3.horizontal` 一根灰线，
/// 选完颜色看不到落点；现在换色这里当场变，也顺带把「改图标」这件事
/// 收进同一个可点区域。
///
/// 底上的字形色按对比度取：14 色里 11 个配白字不到 3:1，黄色只有 1.75:1。
struct ListIdentityTile: View {
    let icon: String?
    let colorARGB: UInt32
    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(WFListPalette.swatch(colorARGB))
            .frame(width: 28, height: 28)
            .overlay {
                if let icon {
                    Text(icon).font(.system(size: 15))
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WFListPalette.checkmarkOn(colorARGB))
                }
            }
            .contentShape(Rectangle())
    }
}

/// 色板一行 16 格：自动 + 14 色 + 取色盘。
///
/// 旧版是横向 `ScrollView`，15 个选项只露 6 颗、最后一颗被切一半。
/// 现在视觉 12pt、档位 16pt，16×16 + 间隙正好铺满 256pt 的控制列，
/// 一次看全，不再需要滚动。
///
/// 「自动」= 清掉显式色，按清单名推导（与 `WFListPalette.colorIndex(for:)` 同口径）。
/// 取色盘给 14 色之外的出口，写入 `colorARGB`。
struct ListColorPalette: View {
    @Binding var colorIndex: Int?
    @Binding var colorARGB: UInt32?
    /// 「自动」档下按名字推出来的色值，用于选中描边。
    let autoARGB: UInt32

    private static let slot: CGFloat = 16
    private var isAuto: Bool { colorIndex == nil && colorARGB == nil }

    var body: some View {
        HStack(spacing: 0) {
            autoSwatch
            ForEach(WFListPalette.argb.indices, id: \.self) { index in
                // 16 个档位等分控制列：14 颗色点各自吃一份弹性空间，
                // 两端各留半份，视觉上左右对齐到同一个内缩。
                swatch(index).frame(maxWidth: .infinity)
            }
            customSwatch
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.slot)
    }

    private var autoSwatch: some View {
        Button { colorIndex = nil; colorARGB = nil } label: {
            ZStack {
                Circle().strokeBorder(WFColors.secondaryText, lineWidth: 1.4)
                    .frame(width: 12, height: 12)
                Rectangle().fill(WFColors.secondaryText)
                    .frame(width: 1.4, height: 14)
                    .rotationEffect(.degrees(45))
                    .frame(width: 12, height: 12)
                    .clipped()
            }
            .frame(width: Self.slot, height: Self.slot)
            .overlay {
                if isAuto {
                    Circle().strokeBorder(WFListPalette.swatch(autoARGB), lineWidth: 1.4)
                        .frame(width: Self.slot, height: Self.slot)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain).hoverTip("清单颜色 自动")
            .accessibilityLabel("清单颜色 自动")
            .accessibilityValue(isAuto ? "已选择" : "未选择")
    }

    private func swatch(_ index: Int) -> some View {
        let value = WFListPalette.argb[index]
        let selected = colorARGB == nil && colorIndex == index
        return Button { colorIndex = index; colorARGB = nil } label: {
            Circle()
                .fill(WFListPalette.swatch(value))
                .frame(width: 12, height: 12)
                .overlay {
                    if selected {
                        Circle().strokeBorder(WFListPalette.swatch(value), lineWidth: 1.4)
                            .frame(width: Self.slot, height: Self.slot)
                    }
                }
                .frame(width: Self.slot, height: Self.slot)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).hoverTip("清单颜色 \(index + 1)")
            .accessibilityLabel("清单颜色 \(index + 1)")
            .accessibilityValue(selected ? "已选择" : "未选择")
    }

    /// 取色盘：系统 NSColorPanel。选完写进 `colorARGB`，
    /// 与显式色板互斥（后端仍按 `colorARGB` 优先着色）。
    private var customSwatch: some View {
        Button(action: pickCustomColor) {
            Image(systemName: "paintpalette")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: Self.slot, height: Self.slot)
                .background(WFColors.secondarySurface, in: Circle())
                .overlay {
                    if let colorARGB {
                        Circle().strokeBorder(WFListPalette.swatch(colorARGB), lineWidth: 1.4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain).hoverTip("自定义清单颜色")
            .accessibilityLabel("自定义清单颜色")
    }

    private func pickCustomColor() {
        // 打开面板时的初值 = 当前显示的那一色：自定义色优先，
        // 其次显式色板色，最后才是自动推导色。
        let seed = colorARGB ?? colorIndex.map { WFListPalette.argb[$0] } ?? autoARGB
        WFColorPanelPicker.present(seed: seed) { value in
            colorARGB = value
            colorIndex = nil
        }
    }
}
