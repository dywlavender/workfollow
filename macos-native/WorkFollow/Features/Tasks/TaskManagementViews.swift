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
        alert.addButton(withTitle: confirm); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
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
        alert.addButton(withTitle: action); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    static func invalidName() {
        let alert = NSAlert(); alert.messageText = "名称为空或已存在"; alert.runModal()
    }
}

/// 侧栏"清单"分组：小号灰字标题 + 右侧新建，行内右侧灰色计数。
/// 行样式对齐 Flutter _TaskListItem：色板圆点 + hover"⋯"清单操作 +
/// 拖放高亮；置顶清单排在分组前。
struct TaskCollectionsView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            sectionHeader("清单", trailing: newListBox)
            ForEach(workspace.orderedListNames, id: \.self) { name in
                SidebarListRowView(workspace: workspace, name: name) { openList(name) }
            }
        }.buttonStyle(.plain).font(WFType.navigation)
    }

    /// 滴答式分组标题：小号灰字，"清单"标题右侧带新建按钮。
    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title, trailing: EmptyView())
    }

    private func sectionHeader<Trailing: View>(_ title: String,
                                               trailing: Trailing) -> some View {
        HStack(spacing: WFSpace.xs) {
            Text(title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.xs)
    }

    private var newListBox: some View {
        Button {
            if let value = TaskNamePrompt.ask("新建清单") {
                if workspace.saveList(value) { openList(value) } else { TaskNamePrompt.invalidName() }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 12))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }.help("新建清单")
    }

    private func openList(_ name: String) {
        navigation.destination = .allTasks; workspace.activeList = name; workspace.activeTag = nil
        workspace.select(nil); workspace.clearBulkSelection(); onNavigate()
    }
}

/// 侧栏清单行（Round B1）：色板圆点、hover"⋯"菜单（置顶/重命名/颜色/删除）、
/// 作为拖放目标接收任务行拖拽（drop → moveToList），拖拽悬停时高亮描边。
private struct SidebarListRowView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let name: String
    let onOpen: () -> Void
    @State private var hovering = false
    @State private var dragTargeted = false
    @State private var showColorPicker = false
    @State private var showIconPicker = false

    private var meta: TaskListMeta? { workspace.listMeta(for: name) }
    private var pinned: Bool { meta?.isPinned ?? false }
    private var selected: Bool { workspace.activeList == name }
    private var dotColor: Color {
        WFListPalette.color(for: name, meta: meta)
    }
    private var openCount: Int {
        workspace.allTasks.filter {
            $0.list.name == name && !$0.isClosed && $0.deletedAt == nil && $0.skippedAt == nil
        }.count
    }

    var body: some View {
        HStack(spacing: WFSpace.xs) {
            Button(action: onOpen) {
                HStack(spacing: WFSpace.sm) {
                    // 有图标显示 Emoji，否则回落到色点（滴答：图标优先，颜色仍在）。
                    if let icon = meta?.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 12))
                            .frame(width: 14)
                            .accessibilityLabel("清单图标")
                    } else {
                        Circle().fill(dotColor).frame(width: 9, height: 9)
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
            Menu { menuItems } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .disabled(!hovering)
            .help("清单操作")
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: NavigationMetrics.rowHeight)
        .background(selected || dragTargeted ? WFColors.listSelection : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        // 拖拽悬停高亮描边（对齐 Flutter dragActive 的 accent 边框）。
        .overlay(RoundedRectangle(cornerRadius: WFMetrics.corner)
            .strokeBorder(dragTargeted ? WFColors.accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        // 任务行拖来的负载是任务 id 字符串：drop 即移入本清单（HUD 由 workspace 自动上报）。
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            return workspace.moveToList(id, TaskList(name: name)).taskID != nil
        } isTargeted: { dragTargeted = $0 }
        .background(AnchoredPropertyPanel(isPresented: $showColorPicker,
                                         width: ListColorPickerPopover.panelWidth, placement: .submenu) {
            ListColorPickerPopover(workspace: workspace, name: name) { showColorPicker = false }
        })
        .background(AnchoredPropertyPanel(isPresented: $showIconPicker,
                                         width: ListIconPickerPopover.panelWidth, placement: .submenu) {
            ListIconPickerPopover(workspace: workspace, name: name) { showIconPicker = false }
        })
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(pinned ? "取消置顶" : "置顶清单") {
            _ = workspace.setListPinned(name, !pinned)
        }
        Button("重命名") {
            if let value = TaskNamePrompt.ask("重命名清单", value: name),
               !workspace.saveList(value, replacing: name) {
                TaskNamePrompt.invalidName()
            }
        }
        // 菜单关闭后再弹色板，避免 macOS 菜单吞掉 popover 的呈现时机。
        Button("选择颜色") {
            DispatchQueue.main.async { showColorPicker = true }
        }
        Button("设置图标") {
            DispatchQueue.main.async { showIconPicker = true }
        }
        Divider()
        Button("删除清单…", role: .destructive) {
            if TaskNamePrompt.confirm("删除清单“\(name)”？",
                                      message: "任务（含子任务）将移到收集箱，不删除任务。可撤销。",
                                      action: "删除") {
                workspace.removeList(name)
            }
        }
    }
}

/// 14 色网格弹层（对齐 Flutter ListColorSwatch）：当前生效色打勾，点选即保存。
private struct ListColorPickerPopover: View {
    // Seven 22pt swatches, six 10pt gaps, and the existing content padding.
    static let panelWidth: CGFloat = 7 * 22 + 6 * 10 + 2 * WFSpace.lg
    @ObservedObject var workspace: TaskWorkspaceModel
    let name: String
    let onDismiss: () -> Void
    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 10), count: 7)

    private var effectiveIndex: Int {
        let meta = workspace.listMeta(for: name)
        guard meta?.colorARGB == nil else { return -1 }
        return WFListPalette.colorIndex(for: name, explicit: meta?.colorIndex)
    }

    var body: some View {
        VStack(spacing: WFSpace.sm) {
            Text("选择清单颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WFListPalette.argb.indices, id: \.self) { index in
                    Button {
                        _ = workspace.setListColor(name, colorIndex: index)
                        onDismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(WFListPalette.swatch(WFListPalette.argb[index]))
                                .frame(width: 22, height: 22)
                            if index == effectiveIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WFListPalette.checkmarkOn(WFListPalette.argb[index]))
                            }
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(WFSpace.lg)
        .onExitCommand(perform: onDismiss)
    }
}

/// 清单图标（Emoji）网格弹层：内置常用集合（不引第三方图标库），选完即保存。
/// 「无图标」清除后侧栏回落色点（用色板仍是独立一步，和滴答一样是两件事）。
private struct ListIconPickerPopover: View {
    static let panelWidth: CGFloat = 6 * 26 + 5 * 10 + 2 * WFSpace.lg
    /// 常用清单图标：够覆盖"工作 / 生活 / 学习 / 兴趣"这类清单，不追求全量 Emoji。
    static let choices = ["📋", "🚀", "💼", "📌", "🎯", "📚",
                          "💡", "🧾", "🏠", "🛒", "🏃", "🍀",
                          "❤️", "⭐️", "🎵", "✈️", "🧪", "🎨"]
    @ObservedObject var workspace: TaskWorkspaceModel
    let name: String
    let onDismiss: () -> Void
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 10), count: 6)

    private var current: String? { workspace.listMeta(for: name)?.icon }

    var body: some View {
        VStack(spacing: WFSpace.sm) {
            Text("选择清单图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.choices, id: \.self) { emoji in
                    Button {
                        _ = workspace.setListIcon(name, emoji)
                        onDismiss()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(WFColors.secondarySurface)
                                .frame(width: 26, height: 26)
                            Text(emoji).font(.system(size: 15))
                            if emoji == current {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(WFColors.accent, lineWidth: 1.5)
                                    .frame(width: 26, height: 26)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button {
                _ = workspace.setListIcon(name, nil)
                onDismiss()
            } label: {
                Text(current == nil ? "无图标（当前）" : "无图标")
                    .font(WFType.supporting)
                    .foregroundStyle(current == nil ? WFColors.tertiaryText : WFColors.text)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(current == nil)
        }
        .padding(WFSpace.lg)
        .onExitCommand(perform: onDismiss)
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
        if let importedColor = meta?.colorARGB { return swatch(importedColor) }
        let index = colorIndex(for: name, explicit: meta?.colorIndex)
        return swatch(argb[index])
    }

    /// 色块上的勾选颜色：按亮度取黑/白（对齐 Flutter WorkFollowThemeContrast.foregroundOn）。
    static func checkmarkOn(_ value: UInt32) -> Color {
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6 ? .black : .white
    }
}

/// 侧栏"标签"分组，行样式与智能清单/清单一致（小图标 + 名称，行高 32）。
struct TaskTagsSectionView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            sectionHeader("标签")
            if workspace.tagNames.isEmpty {
                Text("在任务属性中添加标签").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, WFSpace.sm)
            }
            ForEach(workspace.tagNames, id: \.self) { tag in
                tagRow(tag)
            }
        }.buttonStyle(.plain).font(WFType.navigation)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(WFType.supporting)
            .foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, WFSpace.sm)
            .padding(.top, WFSpace.lg)
            .padding(.bottom, WFSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagRow(_ tag: String) -> some View {
        Button {
            navigation.destination = .allTasks; workspace.activeList = nil; workspace.activeTag = tag; onNavigate()
        } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "tag").font(.system(size: 12)).frame(width: 18)
                Text(tag).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .background(workspace.activeTag == tag ? WFColors.listSelection : .clear,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button("重命名标签") {
                if let value = TaskNamePrompt.ask("重命名标签", value: tag), !value.isEmpty { workspace.renameTag(tag, to: value) }
            }
            Button("移除标签…") {
                if TaskNamePrompt.confirm("移除标签“\(tag)”？", message: "从所有任务移除此标签，不删除任务。可撤销。",
                                          action: "移除") { workspace.renameTag(tag, to: nil) }
            }
        }
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
                                          knownLists: Set(workspace.allListNames),
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
            reminderOffsets: initial?.reminderOffsets ?? [],
            frequency: initial?.repeatFrequency ?? parsed.recurrence,
            recurrenceRule: initial?.recurrenceRule ?? parsed.recurrenceRule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建任务").font(WFType.detailTitle)
            TextField("准备做什么？", text: $title).focused($titleFocused)
            Picker("清单", selection: $list) {
                ForEach(workspace.allListNames, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: list) { _, _ in listEdited = true }
            scheduleRow
            Picker("优先级", selection: $priority) {
                Text("无").tag(TaskPriority.none); Text("低").tag(TaskPriority.low)
                Text("中").tag(TaskPriority.medium); Text("高").tag(TaskPriority.high)
            }
            .onChange(of: priority) { _, _ in priorityEdited = true }
            TextField("标签（逗号分隔）", text: $tags)
                .onChange(of: tags) { _, _ in tagsEdited = true }
            HStack {
                Spacer()
                Button("取消") { onClose(false) }.keyboardShortcut(.cancelAction)
                Button("创建") {
                    let parsed = QuickAddParser.parse(title, now: workspace.clock(), calendar: workspace.calendar,
                                                     knownLists: Set(workspace.allListNames),
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
