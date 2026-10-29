import SwiftUI
import AppKit

@MainActor
enum TaskNamePrompt {
    static func ask(_ title: String, value: String = "", confirm: String = "确定") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        let primary = alert.addButton(withTitle: confirm)
        let cancel = alert.addButton(withTitle: "取消")
        NativeDialogActions.configure(alert, primary: primary, cancel: cancel)
        alert.window.initialFirstResponder = field
        guard NativeDialogActions.runModal(alert, cancel: cancel) == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// 二次确认。`action` 是**确认按钮的文案**。
    ///
    /// 写动作名（「删除」「移除」「替换」），不要写「确定」：正文问的是
    /// 「删除『X』？」，按钮再写「确定」，用户得自己把两句话对上才算看懂。
    ///
    /// 之所以不给默认值：默认值会让下一个新增的破坏性调用点悄悄拿到「确定」，
    /// 缺陷重新长出来。没有默认值，漏写就编译不过。
    static func confirm(_ title: String, message: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let primary = alert.addButton(withTitle: action)
        let cancel = alert.addButton(withTitle: "取消")
        NativeDialogActions.configure(alert, primary: primary, cancel: cancel, destructive: true)
        return NativeDialogActions.runModal(alert, cancel: cancel) == .alertFirstButtonReturn
    }
    static func invalidName() {
        let alert = NSAlert(); alert.messageText = "名称为空或已存在"; alert.runModal()
    }
}

/// 侧栏"清单"分组：小号灰字标题 + 右侧新建，行内右侧灰色计数。
/// 行样式对齐 Flutter _TaskListItem：色板圆点 + hover"⋯"清单操作 +
/// 拖放高亮；置顶清单排在分组前。
struct TaskCollectionsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showListEditor = false
    @State private var archivedCopy: String?
    @State private var folderEditor: TaskFolderEditingRequest?
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    var collapsed: Bool = false
    var onToggleSection: () -> Void = {}
    /// Local presentation state is restored from the shared view preferences.
    @State private var collapsedFolders: Set<String> = []
    @State private var archivedExpanded = true
    @State private var targetedFolder: String?
    /// 文件夹下清单的缩进（与文件夹行的箭头列对齐）。
    private static let folderIndent: CGFloat = 16

    var body: some View {
        // 行间不再额外放宽：滴答导航行步长就是行高 38（连续行 y=45/83/121）。
        // 分组间隔由侧栏统一提供的 32pt 间隔行负责。
        let counts = workspace.listOpenCounts
        let pinned = workspace.orderedListNames.filter { workspace.listMeta(for: $0)?.isPinned == true }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(pinned, id: \.self) { name in
                SidebarListRowView(workspace: workspace, name: name, openCount: counts[name, default: 0]) { openList(name) }
            }
            if !pinned.isEmpty { Color.clear.frame(height: 12) }
            SidebarSectionHeader(title: "清单", collapsed: collapsed, toggle: onToggleSection) {
                newListBox.fixedSize()
            }
            if !collapsed {
                ForEach(workspace.listTree) { node in
                    switch node {
                    case .list(let name):
                        if workspace.listMeta(for: name)?.isPinned != true {
                            insertionStrip(before: name, clearsFolder: true)
                            SidebarListRowView(workspace: workspace, name: name, openCount: counts[name, default: 0]) { openList(name) }
                        }
                    case .folder(let folder, let lists):
                        // 文件夹前的空档落在"文件夹第一个成员"位置 → 仍属文件夹内，别误删归属。
                        insertionStrip(before: lists.first, clearsFolder: false)
                        folderRow(folder, count: lists.count)
                        if !collapsedFolders.contains(folder) {
                            ForEach(lists, id: \.self) { name in
                                insertionStrip(before: name, clearsFolder: false)
                                SidebarListRowView(workspace: workspace, name: name, openCount: counts[name, default: 0]) { openList(name) }
                                    .padding(.leading, Self.folderIndent)
                            }
                        }
                    }
                }
                insertionStrip(before: nil, clearsFolder: true)
                if !workspace.archivedListNames.isEmpty {
                    archivedLists
                }
            }
        }.buttonStyle(.plain).font(WFType.navigation)
        .sheet(isPresented: $showListEditor) {
            TaskListEditorView(workspace: workspace, preferences: environment.viewPreferences, onSaved: openList)
        }
        .sheet(isPresented: Binding(get: { archivedCopy != nil }, set: { if !$0 { archivedCopy = nil } })) {
            if let name = archivedCopy {
                TaskListCopyView(workspace: workspace, source: name) { copied in
                    environment.viewPreferences.copyScope(
                        from: TaskViewScopeKey.key(destination: .allTasks, activeList: name, activeTag: nil),
                        to: TaskViewScopeKey.key(destination: .allTasks, activeList: copied, activeTag: nil))
                    openList(copied)
                }
            }
        }
        .sheet(item: $folderEditor) { request in
            TaskFolderEditorView(workspace: workspace, name: request.name) { name in
                if let old = request.name, collapsedFolders.remove(old) != nil { collapsedFolders.insert(name) }
            }
        }
        .onAppear {
            collapsedFolders = environment.viewPreferences.collapsedCollectionFolders
            archivedExpanded = !environment.viewPreferences.archivedListsCollapsed
        }
        .onChange(of: collapsedFolders) { _, value in environment.viewPreferences.setCollapsedCollectionFolders(value) }
        .onChange(of: archivedExpanded) { _, value in environment.viewPreferences.setArchivedListsCollapsed(!value) }
    }

    private var archivedLists: some View {
        VStack(spacing: WFSpace.xs) {
            Button {
                archivedExpanded.toggle()
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Image(systemName: archivedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 12)
                    Image(systemName: "archivebox").font(.system(size: 12))
                    Text("已归档的清单")
                    Spacer(minLength: 0)
                    Text("\(workspace.archivedListNames.count)").font(WFType.supporting)
                }
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: NavigationMetrics.rowHeight)
                .contentShape(Rectangle())
                .rowHoverBackground()
            }
            .accessibilityLabel((archivedExpanded ? "收起" : "展开") + "已归档的清单")
            if archivedExpanded {
                ForEach(workspace.archivedListNames, id: \.self) { name in
                    Button { openList(name) } label: {
                        HStack(spacing: WFSpace.sm) {
                            Circle().fill(WFListPalette.color(for: name, meta: workspace.listMeta(for: name)))
                                .frame(width: 9, height: 9)
                            Text(name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(WFColors.secondaryText)
                        .padding(.horizontal, WFSpace.sm)
                        .frame(height: NavigationMetrics.rowHeight)
                        .contentShape(Rectangle())
                        .rowHoverBackground(selected: workspace.activeList == name)
                    }
                    .padding(.leading, Self.folderIndent)
                    .accessibilityLabel("已归档清单：" + name)
                    .businessContextMenu {
                        TaskListCommands(workspace: workspace, name: name,
                            onEdit: {}, onCopy: { archivedCopy = name })
                    }
                }
            }
        }
    }

    /// 行间拖放带：清单拖到这里 = **排序**（拖到行上才是"建文件夹"，滴答同一手势两种结果）。
    /// 顶层间隙同时支持移出文件夹，文件夹内间隙保留归属。
    private func insertionStrip(before target: String?, clearsFolder: Bool) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { values, _ in
                guard let raw = values.first,
                      case .list(let moved)? = SidebarDragPayload.decode(raw) else { return false }
                return workspace.moveList(moved, before: target, clearsFolder: clearsFolder)
            }
    }

    /// 文件夹行：展开箭头 + 名称 + 成员清单数；右键重命名 / 删除（清单保留，回到顶层）。
    private func folderRow(_ folder: String, count: Int) -> some View {
        let collapsed = collapsedFolders.contains(folder)
        return Button {
            if collapsed { collapsedFolders.remove(folder) } else { collapsedFolders.insert(folder) }
        } label: {
            HStack(spacing: WFSpace.xs) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(width: 12)
                if let icon = workspace.listFolders.first(where: { $0.name == folder })?.icon {
                    Text(icon).font(.system(size: 13))
                } else {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(WFColors.secondaryText)
                }
                Text(folder).font(WFType.navigation).foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
                Text("\(count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .contentShape(Rectangle())
            .rowHoverBackground(selected: targetedFolder == folder)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, case .list(let name)? = SidebarDragPayload.decode(raw) else { return false }
            return workspace.setListFolder(name, folder)
        } isTargeted: { targeted in targetedFolder = targeted ? folder : nil }
        .businessContextMenu {
            Button("编辑文件夹…") { folderEditor = TaskFolderEditingRequest(name: folder) }
            Button("解散文件夹…") {
                guard TaskNamePrompt.confirm("解散文件夹“\(folder)”？",
                                             message: "清单会保留，并移到顶层。",
                                             action: "解散") else { return }
                _ = workspace.dissolveListFolder(folder)
            }
        }
    }

    /// 滴答桌面端是「光标覆盖"清单"区 → 点 +」：一个入口，两种新建（清单 / 文件夹）。
    private var newListBox: some View {
        BusinessMenu {
            Button("新建清单…") { showListEditor = true }
            Button("新建文件夹…") { folderEditor = TaskFolderEditingRequest() }
        } label: {
            Image(systemName: "plus").font(.system(size: 12))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .hoverTip("新建清单 / 文件夹")
    }

    private func openList(_ name: String) {
        workspace.openFilter(nil)
        navigation.destination = .allTasks; workspace.activeList = name; workspace.activeTag = nil
        workspace.select(nil); workspace.clearBulkSelection(); onNavigate()
    }
}

/// 侧栏清单行（Round B1）：色板圆点、hover"⋯"菜单（置顶/重命名/颜色/删除）、
/// 作为拖放目标接收任务行拖拽（drop → moveToList），拖拽悬停时高亮描边。
private struct SidebarListRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showEditor = false
    @State private var showCopy = false
    @ObservedObject var workspace: TaskWorkspaceModel
    let name: String
    let openCount: Int
    let onOpen: () -> Void
    @State private var hovering = false
    @State private var menuPresented = false
    @State private var dragTargeted = false

    private var meta: TaskListMeta? { workspace.listMeta(for: name) }
    private var pinned: Bool { meta?.isPinned ?? false }
    /// 当前所属文件夹（nil = 顶层）。
    private var folder: String? { workspace.folderName(forList: name) }
    /// 收集箱是任务中转站：不可归类、不可删除（滴答规则）。
    private var isInbox: Bool { name == TaskList.inbox.name }

    /// 滴答主手势：把一个清单拖到另一个清单上 → 建文件夹并把两者放进去。
    /// 本行已在某文件夹里就直接跟随（不弹窗）；否则弹一次命名。
    private func combine(_ moved: String, into target: String) -> Bool {
        guard moved != target, !isInbox, moved != TaskList.inbox.name else { return false }
        guard let title = folder ?? TaskNamePrompt.ask("新建文件夹"), !title.isEmpty else { return false }
        return workspace.combineListsIntoFolder(moved, target, folder: title)
    }
    private var selected: Bool { workspace.activeList == name }
    private var dotColor: Color {
        WFListPalette.color(for: name, meta: meta)
    }
    var body: some View {
        HStack(spacing: WFSpace.xs) {
            Button(action: onOpen) {
                // 滴答 AX 实测（2026-10-17）：色点框 14x14 起于行内 7，文字紧贴色点右缘（行内 19）。
                // 这里用 10 的框 + 2 的间距，落到同一文字起点，同时不让 9pt 色点被视觉压扁。
                HStack(spacing: 2) {
                    // 有图标显示 Emoji，否则回落到色点（滴答：图标优先，颜色仍在）。
                    if let icon = meta?.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 12))
                            .frame(width: 10)
                            .accessibilityLabel("清单图标")
                    } else {
                        Circle().fill(dotColor).frame(width: 9, height: 9)
                            .frame(width: 10)
                            .accessibilityLabel("清单颜色")
                    }
                    Text(name).lineLimit(1)
                    Spacer(minLength: WFSpace.xs)
                    if openCount > 0 {
                        Text("\(openCount)").font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // "⋯"常驻占位（对齐 Flutter 的 AnimatedOpacity）：行宽不因 hover 抖动。
            BusinessMenu(isPresented: $menuPresented) { menuItems } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .fixedSize()
            .opacity(hovering || menuPresented ? 1 : 0)
            .allowsHitTesting(hovering || menuPresented)
            .disabled(!hovering && !menuPresented)
            .hoverTip("清单操作")
        }
        // 容器本身已有 8 的横向内边距；清单行的色点比智能清单图标再靠左 12pt，
        // 所以这里不再加 leading，落到行内 8（滴答 7，差 1pt 由色点框宽吸收）。
        .padding(.trailing, WFSpace.sm)
        .frame(height: NavigationMetrics.rowHeight)
        .contentShape(Rectangle())
        .rowHoverBackground(selected: selected || dragTargeted, onHoverChanged: { hovering = $0 })
        .guideTourAnchor("list." + name)
        // 拖拽悬停高亮描边（对齐 Flutter dragActive 的 accent 边框）。
        .overlay(RoundedRectangle(cornerRadius: WFMetrics.corner)
            .strokeBorder(dragTargeted ? WFColors.accent : Color.clear, lineWidth: 1))
        .businessContextMenu { menuItems }
        // 拖拽：任务拖进来 = 移入本清单（HUD 由 workspace 自动上报）；
        // 清单拖进来 = 建文件夹（滴答主手势：拖动一个清单到另一个清单上方）。
        .draggable(SidebarDragPayload.encode(.list(name)))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let payload = SidebarDragPayload.decode(raw) else { return false }
            switch payload {
            case .task(let id):
                return workspace.moveToList(id, TaskList(name: name)).taskID != nil
            case .list(let moved):
                return combine(moved, into: name)
            }
        } isTargeted: { dragTargeted = $0 }
        .sheet(isPresented: $showEditor) {
            TaskListEditorView(workspace: workspace, preferences: environment.viewPreferences, name: name)
        }
        .sheet(isPresented: $showCopy) {
            TaskListCopyView(workspace: workspace, source: name) { copied in
                workspace.openFilter(nil); workspace.activeList = copied; workspace.activeTag = nil
                environment.navigation.destination = .allTasks
                environment.viewPreferences.copyScope(
                    from: TaskViewScopeKey.key(destination: .allTasks, activeList: name, activeTag: nil),
                    to: TaskViewScopeKey.key(destination: .allTasks, activeList: copied, activeTag: nil))
            }
        }
    }

    private var menuItems: some View {
        TaskListCommands(workspace: workspace, name: name, onEdit: { showEditor = true }, onCopy: { showCopy = true })
    }
}

/// 色板 ARGB 值 → SwiftUI 颜色的视图侧映射（色板本身留在 Foundation 层）。
extension WFListPalette {
    static func swatch(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: Double((value >> 24) & 0xFF) / 255)
    }

    static func color(for name: String, meta: TaskListMeta?) -> Color {
        swatch(argb(for: name, meta: meta))
    }

    /// 色块上的勾选颜色：按亮度取黑/白（对齐 Flutter WorkFollowThemeContrast.foregroundOn）。
    static func checkmarkOn(_ value: UInt32) -> Color {
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6 ? .black : .white
    }
}

struct TaskComposer: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let onClose: (Bool) -> Void
    var dismissedTokenIDs: Set<String> = []
    let initialSchedule: QuickAddScheduleDraft?
    let initialProperties: QuickAddPropertiesOverrides
    @State var title: String
    @State var list: String
    /// 日程（日期 / 时间段 / 提醒 / 重复）只有**一个编辑器**：共享的 `TaskDatePopoverV2`。
    /// 面板确定后整体带回，本地形状就是 application 层的 `SchedulePlan`——
    /// 对话框不再自带第三套日期/提醒/重复控件（那套既漏 `dueEndAt` 也漏多级提醒）。
    @State private var plan: SchedulePlan
    /// 面板是否覆盖过解析结果：没覆盖时以标题解析为准（"明天 开会"仍按滴答语义生效）。
    @State private var scheduleEdited = false
    @State private var showSchedulePanel = false
    @State private var priority: TaskPriority
    @State private var tags: String
    /// 页面给的日期语义（打开时的"安排日期"与日期），未被面板覆盖时作为初值。
    private let scheduled: Bool
    private let presetDate: Date
    @State private var priorityEdited: Bool
    @State private var listEdited: Bool
    @State private var tagsEdited: Bool
    @FocusState private var titleFocused: Bool

    init(workspace: TaskWorkspaceModel, onClose: @escaping (Bool) -> Void,
         dismissedTokenIDs: Set<String> = [], title: String, list: String,
         scheduled: Bool, date: Date, initialSchedule: QuickAddScheduleDraft? = nil,
         initialProperties: QuickAddPropertiesOverrides = QuickAddPropertiesOverrides(
            priority: nil, listName: nil, tags: nil)) {
        let parsed = QuickAddParser.parse(title, now: workspace.clock(), calendar: workspace.calendar,
                                          knownLists: Set(workspace.availableListNames),
                                          dismissedTokenIDs: dismissedTokenIDs)
        self.workspace = workspace
        self.onClose = onClose
        self.dismissedTokenIDs = dismissedTokenIDs
        self.initialSchedule = initialSchedule
        self.initialProperties = initialProperties
        self.scheduled = scheduled
        self.presetDate = date
        _title = State(initialValue: title)
        _list = State(initialValue: initialProperties.listName ?? parsed.listName ?? list)
        _priority = State(initialValue: initialProperties.priority ?? parsed.priority)
        _tags = State(initialValue: initialProperties.tags?.joined(separator: ",") ?? "")
        _plan = State(initialValue: Self.plan(parsed: parsed, initial: initialSchedule,
                                             scheduled: scheduled, date: date,
                                             calendar: workspace.calendar))
        _priorityEdited = State(initialValue: initialProperties.priority != nil)
        _listEdited = State(initialValue: initialProperties.listName != nil)
        _tagsEdited = State(initialValue: initialProperties.tags != nil)
    }

    /// 标题解析 + 页面预设 → `SchedulePlan`（创建与面板初值**共用这一处映射**）。
    /// 优先级照旧：调用方给的草稿 > 标题解析 > 页面预设日期。
    private static func plan(parsed: QuickAddParseResult, initial: QuickAddScheduleDraft?,
                             scheduled: Bool, date: Date, calendar: Calendar) -> SchedulePlan {
        let presetDue = scheduled ? (parsed.hasTime ? date : calendar.startOfDay(for: date)) : nil
        return SchedulePlan(
            schedule: TaskSchedule(dueAt: initial?.dueAt ?? parsed.dueAt ?? presetDue,
                                   hasTime: initial?.hasTime ?? (parsed.dueAt != nil ? parsed.hasTime : false),
                                   dueEndAt: initial?.dueEndAt),
            reminder: initial?.reminderAt ?? parsed.reminderAt,
            reminderOffsets: initial?.reminderOffsets ?? parsed.reminderOffsets,
            frequency: initial?.repeatFrequency ?? parsed.recurrence,
            recurrenceRule: initial?.recurrenceRule ?? parsed.recurrenceRule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建任务").font(WFType.detailTitle)
            TextField("准备做什么？", text: $title,
                      prompt: Text("准备做什么？").foregroundStyle(QuickAddBarStyle.placeholderColor))
                .foregroundStyle(WFColors.text)
                .focused($titleFocused)
            BusinessPicker("清单", selection: $list, options:
                workspace.availableListNames.map { BusinessChoice($0, $0, symbol: "tray") })
            .onChange(of: list) { _, _ in listEdited = true }
            scheduleRow
            BusinessPicker("优先级", selection: $priority, options:
                TaskPriority.menuOrder.map { BusinessChoice($0, $0.title, symbol: "flag", color: $0.menuColor) })
            .onChange(of: priority) { _, _ in priorityEdited = true }
            TextField("标签（逗号分隔）", text: $tags)
                .onChange(of: tags) { _, _ in tagsEdited = true }
            HStack {
                Spacer()
                Button("取消") { onClose(false) }.keyboardShortcut(.cancelAction)
                Button("创建") {
                    let parsed = QuickAddParser.parse(title, now: workspace.clock(), calendar: workspace.calendar,
                                                     knownLists: Set(workspace.availableListNames),
                                                     dismissedTokenIDs: dismissedTokenIDs)
                    guard !parsed.title.isEmpty else { return }
                    // 面板没动过时按**当前标题**重新解析（用户可能打开后才在标题里打"明天"）；
                    // 动过就以面板结果为准 —— 与快速添加条"草稿 > 解析"同一口径。
                    let finalPlan = scheduleEdited
                        ? plan
                        : Self.plan(parsed: parsed, initial: initialSchedule,
                                    scheduled: scheduled, date: presetDate,
                                    calendar: workspace.calendar)
                    let parsedTags = tags.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",")
                    let enteredTags = tagsEdited || initialProperties.tags != nil
                        ? parsedTags : parsedTags + parsed.tags
                    let finalTags = (workspace.activeTag.map { [$0] } ?? []) + enteredTags
                    let finalList = listEdited ? list : parsed.listName ?? list
                    let finalPriority = priorityEdited ? priority : parsed.priority
                    // 创建也走唯一入口：日程 / 时间段 / 提醒 / 重复整体落地，不再逐字段拆参。
                    let result = workspace.createDraft(title: parsed.title, list: finalList,
                                                       plan: finalPlan, priority: finalPriority,
                                                       tags: finalTags)
                    if result.taskID != nil { onClose(true) }
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
            // 日程唯一编辑器：与列表行 / 四象限 / 快速组合器同一个面板、同一份 plan。
            .schedulePopover(isPresented: $showSchedulePanel) {
                TaskDatePopoverV2(task: draftTask, workspace: workspace, initialPage: .main,
                                  draftCommit: { plan = $0; scheduleEdited = true }) {
                    showSchedulePanel = false
                }
                .environment(\.calendar, workspace.calendar)
                .environment(\.timeZone, workspace.calendar.timeZone)
            }
            .onAppear { titleFocused = true }
            .environment(\.calendar, workspace.calendar).environment(\.timeZone, workspace.calendar.timeZone)
    }

    // MARK: 日程入口（共享面板）

    private var scheduleRow: some View {
        Button {
            showSchedulePanel = true
        } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "calendar").font(.system(size: 16))
                Text(scheduleLabel).font(WFType.control)
                Spacer(minLength: 0)
            }
            .foregroundStyle(plan.schedule.dueAt == nil ? WFColors.tertiaryText : WFColors.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("设置日期、时间段、提醒与重复")
        .scheduleTrigger()
        .accessibilityLabel("设置日期：\(scheduleLabel)")
    }

    /// 一行摘要：日期（含时间段）+ 提醒 + 重复。文案函数与列表行共用。
    private var scheduleLabel: String {
        var parts: [String] = []
        if let due = plan.schedule.dueAt {
            parts.append(TaskDateLabel.text(due, hasTime: plan.schedule.hasTime,
                                            now: workspace.clock(), calendar: workspace.calendar))
            if let end = plan.schedule.dueEndAt {
                parts.append(TaskDateLabel.text(end, hasTime: plan.schedule.hasTime,
                                                now: workspace.clock(), calendar: workspace.calendar))
            }
        }
        if !plan.reminderOffsets.isEmpty || plan.reminder != nil { parts.append("提醒") }
        if plan.frequency != .never { parts.append(plan.frequency.title) }
        return parts.isEmpty ? "设置日期" : parts.joined(separator: " · ")
    }

    /// 面板要一个任务做初值：现拼一个只用于展示的草稿任务（同 `TaskQuickComposer`），
    /// 确定后只回传 plan，不落库。
    private static let draftTaskID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0DE1")!
    private var draftTask: Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = workspace.clock()
        return Task(id: Self.draftTaskID,
                    title: trimmed.isEmpty ? "准备做什么？" : trimmed,
                    recurrence: plan.frequency,
                    recurrenceRule: plan.recurrenceRule,
                    reminderAt: plan.reminder,
                    reminderOffsets: plan.reminderOffsets.isEmpty ? nil : plan.reminderOffsets,
                    list: TaskList(name: list),
                    priority: priority,
                    schedule: plan.schedule,
                    parentID: nil,
                    childOrder: 0,
                    createdAt: now,
                    updatedAt: now)
    }
}
