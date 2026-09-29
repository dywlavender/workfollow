import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var templateStore = TemplateStore.shared
    @State private var draft = ""
    @State private var showNavigation = false
    @State private var showTemplatePicker = false
    @State private var showQuickAddSchedule = false
    @State private var quickAddSchedulePage: TaskDatePopoverV2.Page = .main
    @State private var pendingQuickAddSchedulePage: TaskDatePopoverV2.Page?
    @State private var showQuickAddProperties = false
    @State private var quickAddScheduleOverride: QuickAddScheduleDraft?
    @State private var quickAddPriorityOverride: TaskPriority?
    @State private var quickAddListOverride: String?
    @State private var quickAddTagsOverride: [String]?
    @State private var dismissedQuickAddTokens: Set<String> = []
    @State private var quickAddEscapePrimed = false
    /// Tab 进入的任务描述草稿（对齐滴答「敲击 Tab 添加任务描述」）。只在创建
    /// 单个任务时随任务一起写进正文；批量创建时每一行各自成任务，不带描述。
    @State private var descriptionDraft = ""
    /// `#`/`@` 候选与描述行的界面状态；与全局快速添加面板共用同一套状态机。
    @State private var candidate = QuickAddCandidateState()
    /// 快速添加输入框是否持有焦点。**两个方向共用的唯一真值。**
    ///
    /// 这里曾经是 `@FocusState` + 另一个 `@State fieldFocused` 并存：
    /// `@FocusState` 挂在 `NSViewRepresentable` 上是**死信号**（没有 `.focused()`
    /// 绑定，SwiftUI 不为它维护状态，写不生效、读永远 `false`，已实测），
    /// 只好另开一路让控件自己上报。代价是两个真值：`quickAddExpanded` 靠
    /// `fieldFocused` 撑着（所以「点击展开」能修好），而 `guard quickAddFocused`
    /// （Esc 两级语义）、`guard !quickAddFocused`（列表上下键/回车/空格不抢键）
    /// 这些守卫**全部恒假**，静默失效——症状分散在几个看起来无关的功能上。
    ///
    /// 现在合成一个 `@State`：控件上报（`onFieldFocusChange`）与
    /// `controlTextDidBegin/EndEditing` 都写它，`QuickAddTextField.updateNSView`
    /// 按它做程序化聚焦与交还。读写都可靠，那些守卫才恢复意义。
    @State private var quickAddFocused = false
    @State private var selecting = false
    @State private var groupExpansion = TaskGroupExpansionState()
    @State private var sortMode = TaskListSortMode.manual
    @State private var seenCompletedGroupIDs: Set<String> = []
    @FocusState private var descriptionFocused: Bool
    @FocusState private var listFocused: Bool

    private var scope: TaskListScope? { TaskWorkspaceModel.scope(for: navigation.destination) }
    private var query: TaskListQuery {
        guard scope == .allTasks else { return TaskListQuery() }
        return TaskListQuery(list: workspace.activeList, tag: workspace.activeTag)
    }
    private var groups: [TaskListGroup] { scope.map { workspace.groups(for: $0, query: query) } ?? [] }
    private var canAdd: Bool { scope == .today || scope == .inbox || scope == .allTasks || scope == .nextSevenDays }
    private var visibleTaskIDs: [UUID] {
        guard let scope else { return [] }
        return groups.flatMap { displayedNodes(for: $0, scope: scope) }.map { $0.task.id }
    }
    /// TickTick shows each row's owning list unless the view is already that list.
    private var showsListBadge: Bool { workspace.activeList == nil && scope != .inbox }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            // 候选列表挂在快速添加条的 overlay 上，会画到任务列表上方；提升层级
            // 才能盖住后面那个兄弟视图（SwiftUI 默认后者在上）。
            if canAdd, let scope { quickAddBar(in: scope).zIndex(1) }
            if !workspace.bulkSelection.isEmpty { TaskBulkBar(workspace: workspace) }
            taskListSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onChange(of: draft) { _, _ in
            // 文本一变，「已被忽略」和候选高亮都作废：候选列表要按新的查询重开。
            candidate.textDidChange()
        }
        .onChange(of: showQuickAddSchedule) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
        .onChange(of: showQuickAddProperties) { _, isPresented in
            guard !isPresented else { return }
            if let page = pendingQuickAddSchedulePage {
                pendingQuickAddSchedulePage = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    quickAddSchedulePage = page
                    showQuickAddSchedule = true
                }
            } else {
                quickAddFocused = true
            }
        }
        .onChange(of: groupIDs) { _, _ in collapseNewCompletedGroups() }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(workspace: workspace, templateStore: templateStore,
                               onDismiss: { showTemplatePicker = false })
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in revealSelectedClosedTask() }
        .onAppear {
            if environment.quickAddRequest > 0 { quickAddFocused = true }
            else { listFocused = true }
            revealSelectedClosedTask()
            collapseNewCompletedGroups()
        }
        // Esc **不在这里接**：视图层 `.onExitCommand` 实测收不到这个按键
        // （见下方 handleQuickAddEscape 的说明），接了也是死代码。
        // 输入框自身的 `cancelOperation:` 才是唯一入口。
    }

    // MARK: - Header bar：☰ + 标题 + 排序/更多（TickTick 式精简）

    private var headerBar: some View {
        HStack(spacing: WFSpace.sm) {
            if !navigationVisible {
                Button { showNavigation.toggle() } label: {
                    Image(systemName: "line.3.horizontal")
                        .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help("显示导航")
                    .popover(isPresented: $showNavigation) {
                        NavigationColumnView(workspace: workspace, navigation: navigation,
                                             filterStore: environment.filterStore) {
                            showNavigation = false
                        }
                        .frame(width: WFMetrics.navigationWidth, height: 440)
                    }
            }
            Text(headerTitle)
                .font(WFType.pageTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            sortMenu
            moreMenu
        }
        .padding(.horizontal, WFSpace.xl)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.md)
    }

    private var headerTitle: String {
        workspace.activeList ?? workspace.activeTag.map { "#" + $0 } ?? navigation.destination.title
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TaskListSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if sortMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("排序：\(sortMode.title)")
    }

    /// 模板、撤销、多选等低频操作全部收进"更多"，保持顶栏只剩排序/更多两个小图标。
    private var moreMenu: some View {
        Menu {
            Menu("从模板添加", systemImage: "doc.badge.plus") {
                if templateStore.templates.isEmpty {
                    Button("还没有模板") {}
                        .disabled(true)
                } else {
                    Button("选择模板…") { showTemplatePicker = true }
                }
            }
            Button("撤销", systemImage: "arrow.uturn.backward") { workspace.undo() }
                .disabled(!workspace.canUndo)
            Divider()
            Button(selecting ? "退出多选" : "多选任务") { selecting.toggle(); workspace.clearBulkSelection() }
            Button("全选当前结果") {
                selecting = true
                let ids = groups.flatMap { displayedNodes(for: $0, scope: scope ?? .allTasks) }
                    .map { $0.task.id }
                workspace.setBulkSelection(in: ids)
            }
            Button("展开/收起已完成", systemImage: "checkmark.circle") {
                groupExpansion.toggleClosedGroups(in: groups)
            }
            .disabled(!groups.contains { $0.kind == .completed && !$0.tasks.isEmpty })
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("列表操作")
    }

    // MARK: - 快速添加：浅灰圆角条，聚焦后展开解析预览

    /// 快速添加日期入口的配色：与任务行日期徽标共用 dateBadgeStyle 归类
    /// （过期红、今天强调色、未来/无日期灰）。
    private func quickAddBadgeColor(_ timing: QuickAddScheduleDraft) -> Color {
        guard let dueAt = timing.dueAt else { return WFColors.secondaryText }
        switch TaskListViewDefaults.dateBadgeStyle(dueAt: dueAt, isClosed: false,
                                                   now: workspace.clock(),
                                                   calendar: workspace.calendar) {
        case .overdue: return .red
        case .today: return WFColors.accent
        case .scheduled, .none: return WFColors.secondaryText
        }
    }

    private func quickAddBar(in scope: TaskListScope) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "plus")
                    .foregroundStyle(WFColors.secondaryText)
                QuickAddTextField(
                    text: $draft,
                    placeholder: "添加任务至“\(quickAddTargetName)”",
                    tokens: quickAddResult.tokens,
                    focused: $quickAddFocused,
                    onSubmit: { addTask(in: scope) },
                    onEscape: handleQuickAddEscape,
                    onTab: handleQuickAddTab,
                    onShiftReturn: openQuickAddDescription,
                    onMoveUp: { moveCandidateSelection(by: -1) },
                    onMoveDown: { moveCandidateSelection(by: 1) },
                    onFieldFocusChange: { quickAddFocused = $0 }
                )
                .frame(maxWidth: .infinity)
                if quickAddExpanded {
                    let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
                    Button {
                        quickAddSchedulePage = .main
                        showQuickAddSchedule = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 10))
                            if navigation.destination != .inbox, let dueAt = timing.dueAt {
                                let start = TaskDateLabel.text(
                                    dueAt, hasTime: timing.hasTime,
                                    now: workspace.clock(), calendar: workspace.calendar)
                                let label = timing.dueEndAt.map { end in
                                    let endLabel = TaskDateLabel.text(
                                        end, hasTime: timing.hasTime,
                                        now: workspace.clock(), calendar: workspace.calendar)
                                    return "\(start) – \(endLabel)"
                                } ?? start
                                Text(label)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(quickAddBadgeColor(timing))
                        .frame(height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("安排日期、提醒和重复")
                    .popover(isPresented: $showQuickAddSchedule) {
                        TaskDatePopoverV2(
                            task: quickAddScheduleTask(in: scope),
                            workspace: workspace,
                            initialPage: quickAddSchedulePage,
                            draftCommit: applyQuickAddSchedulePlan
                        ) {
                            showQuickAddSchedule = false
                        }
                        .environment(\.calendar, workspace.calendar)
                        .environment(\.timeZone, workspace.calendar.timeZone)
                    }
                    Button { showQuickAddProperties = true } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(WFColors.secondaryText)
                            // 必须给足命中区域。少了这两行，纯 `Image` 标签的 `.plain`
                            // 按钮命中区会塌缩到**图形的着墨范围**——省略号是横排的三个点，
                            // 实测 AX 报出来的框是 `12x2`：一个两点高的缝。
                            // 用户瞄着看得见的 `⋯` 点下去，绝大多数位置都落在缝外，
                            // 表现就是「点了没反应」（实测 y=134 / y=140 均无效，只有 137–138 有效）。
                            // 旁边那个日期按钮一直是这么写的，所以它有 41x34 的框。
                            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("更多任务属性")
                    .popover(isPresented: $showQuickAddProperties) {
                        QuickAddPropertiesPopover(
                            workspace: workspace,
                            selectedPriority: quickAddPriorityOverride ?? quickAddResult.priority,
                            selectedList: quickAddListOverride ?? quickAddResult.listName ?? workspace.activeList ?? TaskList.inbox.name,
                            selectedTags: quickAddTagsOverride ?? quickAddResult.tags,
                            onPriority: { value in
                                quickAddPriorityOverride = value
                                showQuickAddProperties = false
                            },
                            onList: { quickAddListOverride = $0 },
                            onTags: { quickAddTagsOverride = $0 },
                            onReminder: { openQuickAddSchedulePage(.reminder) },
                            onRepeat: { openQuickAddSchedulePage(.recurrence) }
                        )
                    }
                } else {
                    Text("⌘N")
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.secondaryText)
                }
            }
            // Tab 进来的描述行（对齐滴答「敲击 Tab 添加任务描述」）。紧贴标题下方，
            // 这样 Tab 的落点就是「下一行」；描述是纯文本，不参与智能识别。
            if candidate.descriptionVisible || !descriptionDraft.isEmpty {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 12)
                    TextField("添加描述", text: $descriptionDraft)
                        .textFieldStyle(.plain)
                        .font(WFType.control)
                        .foregroundStyle(WFColors.text)
                        .focused($descriptionFocused)
                        .onSubmit { addTask(in: scope) }
                        .onExitCommand { closeDescriptionRow() }
                }
                .padding(.leading, 24)
            }
            let parsed = quickAddResult
            if !parsed.tokens.isEmpty {
                QuickAddTokenFlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(parsed.tokens) { token in
                        Button {
                            dismissedQuickAddTokens.insert(token.id)
                        } label: {
                            let color = QuickAddTokenColor.swiftUIColor(for: token.kind)
                            HStack(spacing: 3) {
                                Text(token.label)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                            }
                            .font(WFType.control)
                            .foregroundStyle(color)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(color.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("移除识别项：\(token.label)")
                    }
                }
                .padding(.leading, 24)
            }
            if quickAddExpanded, !parsed.tokens.isEmpty {
                let summary = quickAddSummary(for: scope)
                if !summary.isEmpty {
                    Text(summary)
                        .font(WFType.metaMedium)
                        .foregroundStyle(WFColors.secondaryText)
                        .padding(.leading, 24)
                }
            }
        }
        .frame(minHeight: 36, alignment: .center)
        .padding(.horizontal, WFSpace.md)
        .padding(.vertical, 4)
        // 滴答式两态：未选中是更灰一档的浅灰条、无描边；选中后底色提亮到
        // 窗口底色、描边换「今天」同款强调色（WFColors.accent）。
        .background(RoundedRectangle(cornerRadius: WFMetrics.corner)
            .fill(quickAddExpanded ? WFColors.canvas : WFColors.hover))
        .overlay {
            if quickAddExpanded {
                RoundedRectangle(cornerRadius: WFMetrics.corner)
                    .stroke(WFColors.accent, lineWidth: 1)
                    // 纯装饰层：必须放行点击，否则它会压在输入框上方把点击吃掉，
                    // 输入框拿不到第一响应者，展开也就无从触发。
                    .allowsHitTesting(false)
            }
        }
        // `#`/`@` 候选浮在条下方：overlay 不参与布局，任务列表不会被推下去。
        .overlay(alignment: .bottomLeading) {
            if isCandidateListVisible {
                candidateList
                    .offset(y: QuickAddCandidateList.height(forCount: candidateNames.count) + 6)
            }
        }
        .onTapGesture { quickAddFocused = true }
        .padding(.horizontal, WFSpace.xl)
        .padding(.bottom, WFSpace.xs)
    }

    // MARK: - `#` / `@` 候选（对齐滴答「在添加任务时输入 # 可快速选择标签」）

    @ViewBuilder
    private var candidateList: some View {
        if let marker = activeMarkerQuery {
            QuickAddCandidateList(
                names: candidateNames,
                selectedIndex: min(candidate.selection, max(0, candidateNames.count - 1)),
                emptyMessage: marker.kind == .tag ? "没有匹配的标签" : "没有匹配的清单",
                icon: marker.kind == .tag ? "tag" : "list.bullet",
                onHover: { candidate.selection = $0 },
                onCommit: { commitCandidate($0) }
            )
        }
    }

    /// 输入末尾的标记片段，且没被 Esc 忽略过。
    /// 焦点判据就是输入框的聚焦真值：不聚焦时不该弹候选列表（对齐滴答的输入态）。
    private var activeMarkerQuery: QuickAddComposition.MarkerQuery? {
        candidate.marker(in: draft, isFocused: quickAddFocused)
    }

    /// 候选来源：`#` 查已有标签、`@` 查已有清单。
    private func candidateSource(_ kind: QuickAddComposition.MarkerQuery.Kind) -> [String] {
        kind == .tag ? workspace.tagNames : workspace.allListNames
    }

    private var candidateNames: [String] {
        guard let marker = activeMarkerQuery else { return [] }
        return QuickAddComposition.candidates(candidateSource(marker.kind), matching: marker.query)
    }

    private var isCandidateListVisible: Bool {
        candidate.isListVisible(marker: activeMarkerQuery, names: candidateNames)
    }

    /// Tab：候选列表开着就先提交候选，否则把焦点送进描述行。
    private func handleQuickAddTab() {
        if isCandidateListVisible, candidate.selection >= 0, candidate.selection < candidateNames.count {
            commitCandidate(candidateNames[candidate.selection])
            return
        }
        openQuickAddDescription()
    }

    /// Shift+↩︎：按字面意思就是「加描述」，所以不参与候选提交——候选列表让位收起，
    /// 已输入的文字原样留着。两条快捷键的分工与滴答的提示一致
    /// （`敲击 Enter 添加任务；敲击 Tab 添加任务描述`、`Shift+↩︎ 可添加描述`）。
    private func openQuickAddDescription() {
        if isCandidateListVisible { dismissCandidateList() }
        candidate.descriptionVisible = true
        DispatchQueue.main.async { descriptionFocused = true }
    }

    /// 上下键：只有候选列表开着时才消费按键，否则让插入点照常移动。
    private func moveCandidateSelection(by delta: Int) -> Bool {
        guard isCandidateListVisible else { return false }
        return candidate.move(by: delta, count: candidateNames.count)
    }

    private func commitCandidate(_ name: String) {
        draft = QuickAddComposition.replacingTrailingMarker(in: draft, with: name)
        candidate.textDidChange()
        quickAddFocused = true
    }

    /// 一次 Esc 只收掉候选列表这一层，不清空草稿。
    private func dismissCandidateList() {
        candidate.dismiss(draft: draft)
    }

    private func closeDescriptionRow() {
        descriptionFocused = false
        if descriptionDraft.isEmpty { candidate.descriptionVisible = false }
        DispatchQueue.main.async { quickAddFocused = true }
    }

    private var quickAddTargetName: String {
        TaskListViewDefaults.quickAddTargetName(activeList: workspace.activeList,
                                                inboxName: TaskList.inbox.name)
    }

    /// 快速添加条是否展开（露出日期与「更多」两个槽位、识别 chip 行与摘要行）。
    ///
    /// 逐项对齐 Flutter 参照物 `quick_add.dart:640-645` 的
    /// `expanded = focused || customDate || text.isNotEmpty || spans.isNotEmpty
    /// || _propertiesOpen || _scheduleOpen`：
    /// `focused`↔`quickAddFocused`、`customDate`↔`quickAddScheduleOverride`、
    /// `text.isNotEmpty`↔`!draft.isEmpty`、`spans.isNotEmpty`↔`!parsed.tokens.isEmpty`、
    /// `_propertiesOpen`↔`showQuickAddProperties`、`_scheduleOpen`↔`showQuickAddSchedule`。
    /// 多出的 `description*` 三项对应原生独有的描述行。
    private var quickAddExpanded: Bool {
        quickAddFocused
            || descriptionFocused || candidate.descriptionVisible || !descriptionDraft.isEmpty
            || !draft.isEmpty || quickAddScheduleOverride != nil
            || showQuickAddSchedule || showQuickAddProperties
    }

    private func openQuickAddSchedulePage(_ page: TaskDatePopoverV2.Page) {
        pendingQuickAddSchedulePage = page
        showQuickAddProperties = false
    }

    private func quickAddScheduleTask(in scope: TaskListScope) -> Task {
        let parsed = quickAddResult
        let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
        let now = workspace.clock()
        return Task(
            id: Self.quickAddDraftTaskID,
            title: parsed.title.isEmpty ? "新任务" : parsed.title,
            tags: quickAddTagsOverride ?? parsed.tags,
            recurrence: timing.repeatFrequency,
            recurrenceRule: timing.recurrenceRule,
            reminderAt: timing.reminderAt,
            list: TaskList(name: quickAddListOverride ?? parsed.listName
                ?? workspace.activeList ?? TaskList.inbox.name),
            priority: quickAddPriorityOverride ?? parsed.priority,
            schedule: timing.schedule,
            parentID: nil,
            childOrder: 0,
            createdAt: now,
            updatedAt: now
        )
    }

    private static let quickAddDraftTaskID =
        UUID(uuidString: "00000000-0000-0000-0000-00000000ADD2")!

    private func applyQuickAddSchedulePlan(_ plan: TaskDateDraftModel.CommitPlan) {
        quickAddScheduleOverride = QuickAddScheduleDraft(
            dueAt: plan.schedule.dueAt,
            dueEndAt: plan.schedule.dueEndAt,
            hasTime: plan.schedule.hasTime,
            reminderAt: plan.reminder,
            repeatFrequency: plan.frequency,
            recurrenceRule: plan.recurrenceRule
        )
    }

    private func quickAddSummary(for scope: TaskListScope) -> String {
        let parsed = quickAddResult
        let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
        var parts: [String] = []
        if let dueAt = timing.dueAt {
            let start = TaskDateLabel.text(dueAt, hasTime: timing.hasTime,
                                           now: workspace.clock(), calendar: workspace.calendar)
            if let dueEndAt = timing.dueEndAt {
                let end = TaskDateLabel.text(dueEndAt, hasTime: timing.hasTime,
                                             now: workspace.clock(), calendar: workspace.calendar)
                parts.append("\(start) – \(end)")
            } else {
                parts.append(start)
            }
        }
        if timing.reminderAt != nil { parts.append("提醒") }
        switch timing.repeatFrequency {
        case .never: break
        case .daily: parts.append("每天")
        case .weekly: parts.append("每周")
        case .monthly: parts.append("每月")
        default: parts.append("重复")
        }
        let tags = quickAddTagsOverride ?? parsed.tags
        if !tags.isEmpty { parts.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        if let list = quickAddListOverride ?? parsed.listName { parts.append("@\(list)") }
        switch quickAddPriorityOverride ?? parsed.priority {
        case .none: break
        case .low: parts.append("低优先级")
        case .medium: parts.append("中优先级")
        case .high: parts.append("高优先级")
        }
        return parts.isEmpty ? "" : "→ " + parts.joined(separator: " · ")
    }

    /// Esc 的两级语义，逐行对齐 Flutter `quick_add.dart:379-394` 的 `_handleEscape`：
    ///
    /// ```dart
    /// if (focus.hasFocus) {
    ///   if (_escapePrimed) { setState(_resetDraft); _escapePrimed = false; }
    ///   else               { _escapePrimed = true; focus.unfocus(); }
    ///   return;
    /// }
    /// // 焦点不在输入框 → 草稿留着，什么都不做
    /// ```
    ///
    /// 即：**第一下只收起（不动草稿），重新点回输入框之后再按才清空。**
    /// `focus.unfocus()` 对应这里把 `quickAddFocused` 置假——真正的 AppKit 焦点
    /// 释放由 `QuickAddTextField.updateNSView` 的反向分支执行。
    ///
    /// 候选列表与描述行是原生独有的中间层，按「一次 Esc 只收一层」插在两级之前
    /// （Flutter 那边由 picker/popover 自己处理，不进 `_handleEscape`）。
    ///
    /// **唯一的入口是输入框的 `cancelOperation:`**（`QuickAddTextField.Coordinator`）。
    /// 这里曾经在视图层另挂了一层 `.onExitCommand`，审计时怀疑会重复消费、
    /// 一次按键吃掉两级。插桩数过调用次数后定案：**不会**。
    /// 输入框聚焦时字段自己 `return true` 就把按键消费掉了，视图层那一层收不到；
    /// 描述行聚焦时是描述框自己的 `.onExitCommand` 接管；两者都没聚焦时谁都不触发。
    /// 三层实测（`field=1 view=0`）都证实视图层那层不可达，所以删掉了——
    /// 留着只会让「Esc 到底谁在处理」重新变成需要猜的问题。
    private func handleQuickAddEscape() {
        // 候选列表在最上层，先收起它——一次 Esc 只关一层，不顺手清空草稿。
        if isCandidateListVisible {
            dismissCandidateList()
            return
        }
        // 描述行同理：先把焦点还给标题，行本身留着（有内容时不隐藏）。
        if descriptionFocused {
            closeDescriptionRow()
            return
        }
        // A schedule/properties picker gets first refusal, just like Flutter's
        // nested popovers. Escape on the field is deliberately two-stage.
        guard quickAddFocused,
              !showQuickAddSchedule,
              !showQuickAddProperties else { return }
        if quickAddEscapePrimed {
            clearQuickAddDraft()
            quickAddEscapePrimed = false
        } else {
            quickAddEscapePrimed = true
            quickAddFocused = false
        }
    }

    private func clearQuickAddDraft() {
        draft = ""
        dismissedQuickAddTokens.removeAll()
        quickAddScheduleOverride = nil
        quickAddPriorityOverride = nil
        quickAddListOverride = nil
        quickAddTagsOverride = nil
        descriptionDraft = ""
        descriptionFocused = false
        candidate.reset()
    }

    @ViewBuilder
    private func groupHeader(_ group: TaskListGroup) -> some View {
        HStack(spacing: WFSpace.sm) {
            Button { groupExpansion.toggle(group) } label: {
                HStack(spacing: 6) {
                    Image(systemName: groupExpansion.isCollapsed(group) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                    Text(groupTitle(group)).font(WFType.sectionSemibold)
                    Text("\(group.tasks.count)").font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let note = TaskListViewDefaults.groupTrailingNote(for: group.kind) {
                Button(note) {
                    workspace.postponeOverdue(Set(group.tasks.map(\.id)))
                }
                .buttonStyle(.plain)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.accent)
                .help("将已过期任务顺延到今天")
            }
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.top, WFSpace.md)
        .padding(.bottom, WFSpace.xs)
    }

    private func revealSelectedClosedTask() {
        guard let scope, let task = workspace.selectedTask else { return }
        groupExpansion.reveal(task, in: scope, calendar: workspace.calendar)
    }

    /// "已完成"分组默认折叠在列表底部（TickTick 行为）；只在每个分组第一次出现时折叠一次，
    /// 之后尊重用户手动展开/收起。已完成视图本身不折叠。
    private var groupIDs: [String] { groups.map(\.id) }

    private func collapseNewCompletedGroups() {
        guard scope != .completed else { return }
        for group in groups where group.kind == .completed {
            if seenCompletedGroupIDs.insert(group.id).inserted,
               !groupExpansion.isCollapsed(group) {
                groupExpansion.toggle(group)
            }
        }
    }

    private func displayedNodes(for group: TaskListGroup, scope: TaskListScope) -> [TaskTreeNode] {
        workspace.nodes(for: group, scope: scope, query: query,
                        orderedRoots: group.orderedTasks(using: sortMode, calendar: workspace.calendar))
    }

    private func selectFiltered(_ offset: Int) {
        guard let scope else { return }
        let nodes = groups.flatMap { displayedNodes(for: $0, scope: scope) }
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == workspace.selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) } ?? (offset < 0 ? nodes.count - 1 : 0)
        workspace.selectFromKeyboard(nodes[index].task.id)
    }

    private func groupTitle(_ group: TaskListGroup) -> String {
        switch group.kind {
        case .pinned: return "置顶"
        case .overdue: return "已过期"
        // 滴答式组标题带星期上下文："今天, 周六"。
        case .today:
            return "今天, " + workspace.clock().formatted(.dateTime.weekday(.abbreviated).locale(.appDate))
        case .upcoming: return "最近 7 天"
        case .later: return "更远"
        case .undated: return "无日期"
        case .day:
            guard let day = group.day else { return "" }
            return day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).locale(.appDate))
        case .plain: return ""
        case .completed:
            guard let day = group.day else { return group.label ?? "已完成" }
            return day.formatted(.dateTime.month(.abbreviated).day().locale(.appDate))
        }
    }

    private func rowIdentity(group: TaskListGroup, task: Task) -> String {
        let status = task.status == .completed ? "completed" : "active"
        let abandoned = task.isAbandoned ? "abandoned" : "normal"
        return group.id + ":" + task.id.uuidString + ":" + status + ":" + abandoned
    }

    @ViewBuilder
    private func taskListSection() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty {
                    Text(TaskListViewDefaults.emptyStateMessage(destination: navigation.destination))
                        .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                }
                ForEach(groups, id: \.id) { group in
                    if group.kind != .plain { groupHeader(group) }
                    if group.kind == .plain || !groupExpansion.isCollapsed(group) {
                        ForEach(displayedNodes(for: group, scope: scope ?? .today),
                                id: \.task.id) { node in
                            taskRow(group: group, node: node)
                        }
                    }
                }
            }
            .padding(.horizontal, WFSpace.md)
            .padding(.bottom, WFSpace.xl)
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            selectFiltered(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            selectFiltered(1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            if workspace.selectedTaskID == nil { selectFiltered(1) }
            return .handled
        }
        .onKeyPress(.space) {
            guard !quickAddFocused, let task = workspace.selectedTask else { return .ignored }
            _ = workspace.changeStatus(task, in: scope); return .handled
        }
    }

    @ViewBuilder
    private func taskRow(group: TaskListGroup, node: TaskTreeNode) -> some View {
        let row = HStack(spacing: 0) {
            if selecting {
                Toggle("选择", isOn: Binding(get: { workspace.bulkSelection.contains(node.task.id) }, set: { value in
                    workspace.setBulkSelected(node.task.id, value)
                })).labelsHidden()
            }
            TaskRowView(
                task: node.task,
                workspace: workspace,
                depth: node.depth,
                hasChildren: node.hasChildren,
                expanded: node.expanded,
                selected: workspace.selectedTaskID == node.task.id || workspace.bulkSelection.contains(node.task.id),
                showsListBadge: showsListBadge,
                onSelect: { handleSelection(of: node.task.id) },
                onComplete: { _ = workspace.complete(node.task.id, in: scope) },
                onRestore: { _ = workspace.restore(node.task.id, in: scope) },
                onToggleExpanded: { workspace.toggleExpanded(node.task.id) }
            )
        }
        if node.depth == 0 {
            row
                .draggable(node.task.id.uuidString)
                .modifier(TaskReorderDropModifier(workspace: workspace, targetID: node.task.id))
                .id(rowIdentity(group: group, task: node.task))
        } else {
            // 子任务不可拖、也不作为重排落点（对齐 Flutter）。
            row.id(rowIdentity(group: group, task: node.task))
        }
        // 行分隔线：与行悬浮底色同色（WFColors.hover），右端收进一截。
        Rectangle()
            .fill(WFColors.hover)
            .frame(height: 1)
            .padding(.leading, WFSpace.page)
            .padding(.trailing, WFSpace.lg)
    }

    private func handleSelection(of taskID: UUID) {
        listFocused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.control) {
            selecting = true
            workspace.toggleBulkSelection(taskID)
        } else if modifiers.contains(.shift) {
            selecting = true
            workspace.extendBulkSelection(to: taskID, in: visibleTaskIDs)
        } else if selecting {
            workspace.toggleBulkSelection(taskID)
        } else {
            workspace.clearBulkSelection()
            workspace.select(taskID)
        }
    }

    private var quickAddResult: QuickAddParseResult {
        QuickAddParser.parse(draft, now: workspace.clock(), calendar: workspace.calendar,
                             knownLists: Set(workspace.allListNames),
                             dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private var hasDismissedQuickAddScheduleToken: Bool {
        QuickAddParser.hasDismissedScheduleToken(in: draft, now: workspace.clock(),
            calendar: workspace.calendar, knownLists: Set(workspace.allListNames),
            dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private func currentQuickAddSchedule(for scope: TaskListScope) -> QuickAddScheduleDraft {
        // 时间型视图（今天 / 最近 7 天）默认排期到当天，对齐 Flutter
        // 「Time-based views keep the default-today behaviour」；收集箱不注入。
        QuickAddScheduleDraft(parsed: quickAddResult,
                              defaultDueAt: (scope == .today || scope == .nextSevenDays)
                                && !hasDismissedQuickAddScheduleToken
                                ? workspace.dateFromToday(0) : nil)
    }

    private func addTask(in scope: TaskListScope) {
        // 换行批量添加（对齐滴答「换行可添加多个任务」）：粘贴进来的多行文本按行
        // 各自成一个任务，行内仍然走同一套智能识别。
        let lines = QuickAddComposition.batchLines(in: draft)
        guard !lines.isEmpty else { return }
        let batch = lines.count > 1
        let description = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var created = 0

        for line in lines {
            // 单行时沿用整条草稿的解析结果——只有它带着 chip 删除的忽略状态；
            // 批量时每一行独立解析，行与行之间不互相污染。
            let parsed = batch
                ? QuickAddParser.parse(line, now: workspace.clock(),
                                       calendar: workspace.calendar,
                                       knownLists: Set(workspace.allListNames))
                : quickAddResult
            guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let timing = quickAddScheduleOverride
                ?? (batch
                    ? QuickAddScheduleDraft(parsed: parsed,
                                            defaultDueAt: scope == .today || scope == .nextSevenDays
                                                ? workspace.dateFromToday(0) : nil)
                    : currentQuickAddSchedule(for: scope))
            let priority = quickAddPriorityOverride ?? parsed.priority
            let list = quickAddListOverride ?? parsed.listName ?? workspace.activeList ?? TaskList.inbox.name
            let selectedTags = quickAddTagsOverride ?? parsed.tags
            var tags = workspace.activeTag.map { [$0] } ?? []
            tags.append(contentsOf: selectedTags)
            tags = tags.reduce(into: []) { values, tag in if !values.contains(tag) { values.append(tag) } }
            let result = workspace.createDraft(title: parsed.title,
                                               list: list,
                                               schedule: timing.schedule,
                                               priority: priority, tags: tags,
                                               reminder: timing.reminderAt,
                                               repeatFrequency: timing.repeatFrequency,
                                               recurrenceRule: timing.recurrenceRule,
                                               // 批量创建时每一行各自成任务，共享同一段
                                               // 描述没有意义，描述只跟随单条创建。
                                               document: batch ? NativeDocument.empty
                                                               : NativeDocument(plainText: description))
            if result.taskID != nil { created += 1 }
        }

        // Keep the draft available if creation is rejected; Flutter follows
        // the same rule and only resets after TaskCreator reports success.
        guard created > 0 else { return }
        clearQuickAddDraft()
        quickAddEscapePrimed = false
        // 描述行也能提交，提交后焦点必须回到标题，否则下一次输入无处可去。
        quickAddFocused = true
    }
}

// MARK: - 任务行：复选框 + 标题同行，徽标右对齐，子任务灰色预览

struct TaskRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    var showsListBadge: Bool = true
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onToggleExpanded: () -> Void
    @State private var hovering = false
    @State private var showDatePopover = false
    @State private var showTagPicker = false

    /// 父行展开箭头区宽度：14 + WFSpace.sm 间距 = 22，是子行缩进与父复选框对齐的基准；
    /// 子行缩进步进 44 = 22 + 22，让 depth=1 的子复选框落在父标题起点再偏右一点。
    private var chevronZoneWidth: CGFloat { 14 }

    var body: some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            if depth == 0 {
                ZStack(alignment: .leading) {
                    if hasChildren {
                        Button(action: onToggleExpanded) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help(expanded ? "收起子任务" : "展开子任务")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: chevronZoneWidth)
            }
            Button(action: task.isClosed ? onRestore : onComplete) {
                TaskRowCompletionBox(task: task)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isClosed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.isClosed ? "恢复：\(task.title)" : "完成：\(task.title)")

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(WFType.listTitle).lineLimit(1)
                        .foregroundStyle(task.isClosed ? WFColors.secondaryText : WFColors.text)
                    if let preview = rowPreview {
                        Text(preview)
                            .font(WFType.listBody).lineLimit(1)
                            .foregroundStyle(WFColors.secondaryText)
                    }
                }
                // 内容区高度 = 行高 55 − 上下 11 内边距：点击区铺满内容区，
                // 标题顶对齐（勾选框与标题首行同轴，对齐 Flutter 顶对齐行）。
                .frame(maxWidth: .infinity, minHeight: 33, alignment: .topLeading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            // 与 Flutter 行一致：元数据尾栏常驻，悬浮只做行背景高亮，不浮现
            // 任何快捷按钮（日期走尾栏日期徽章，优先级走右键菜单/检查器）。
            TaskRowMetadataTrail(task: task, workspace: workspace,
                                 showsListBadge: showsListBadge,
                                 onOpenDate: { showDatePopover = true })
        }
        .padding(.horizontal, WFSpace.sm)
        // 对齐 Flutter rowVerticalPadding = 11：内容顶对齐，勾选框贴标题首行。
        .padding(.vertical, 11)
        // 子行每层缩进 44：父行 depth=0 不变；展开箭头区只挂在 depth=0 行上不受影响。
        .padding(.leading, CGFloat(depth) * 44)
        // 行高 55：在 Flutter rowMinHeight = 50 的基础上按使用习惯放宽。
        .frame(minHeight: 55)
        .background(selected ? WFColors.selection : hovering ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onHover { hovering = $0 }
        .overlay {
            // 右键菜单走 AppKit NSPopover 显式定位（对齐 Flutter bottomStart：
            // 面板顶部在光标下方、左缘对齐光标），见 TaskContextMenuPresenter。
            SecondaryClickCapture { rowView, point in
                guard let current = workspace.task(for: task.id) else { return }
                TaskContextMenuPresenter.show(in: rowView, at: point,
                                              environment: environment,
                                              workspace: workspace, task: current,
                                              onCustomDate: { showDatePopover = true })
            }
        }
        .popover(isPresented: $showDatePopover) {
            if let current = workspace.task(for: task.id) {
                TaskDatePopoverV2(task: current, workspace: workspace) { showDatePopover = false }
            }
        }
        .popover(isPresented: $showTagPicker) {
            if let current = workspace.task(for: task.id) {
                TaskTagPickerPopover(initialTags: current.tags, workspace: workspace,
                                     onCancel: { showTagPicker = false },
                                     onApply: { tags in
                                         workspace.setTags(task.id, tags)
                                         showTagPicker = false
                                     })
            }
        }
    }

    private var children: [Task] {
        workspace.allTasks.filter {
            $0.parentID == task.id && $0.deletedAt == nil && $0.skippedAt == nil &&
                !$0.isAbandoned && !$0.isConverted
        }.sorted { $0.childOrder < $1.childOrder }
    }

    /// 折叠时在标题下方显示灰色的"- [ ] 子任务"预览；展开后由子任务行呈现，不再重复。
    private var subtaskPreview: String? {
        guard hasChildren, !expanded else { return nil }
        return TaskListViewDefaults.subtaskPreview(titles: children.map(\.title))
    }

    /// 标题下的灰色预览行：折叠且有子任务用子任务预览，否则正文有内容时用单行正文。
    private var rowPreview: String? {
        subtaskPreview ?? TaskListViewDefaults.bodyPreview(of: task.document.plainText)
    }

}

private enum TaskRowPriority {
    static func title(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    static func color(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: WFColors.secondaryText
        case .low: WFColors.accent
        case .medium: .orange
        case .high: .red
        }
    }
}

/// 勾选框对齐 Flutter：18×18 槽位（即点击区），描边盒按 completionBoxSize
/// 14.58 绘制（圆角 4.5 × 缩放 0.81 ≈ 3.6），贴槽位左缘；完成/放弃图标居中。
/// 描边按优先级着色（高红/中橙/低=强调色），完成后强调色填充。
private struct TaskRowCompletionBox: View {
    let task: Task

    var body: some View {
        if task.isAbandoned {
            Image(systemName: "circle.slash")
                .font(.system(size: 15))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 18, height: 18)
        } else if task.isClosed {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 14.5))
                .foregroundStyle(WFColors.accent)
                .frame(width: 18, height: 18)
        } else {
            RoundedRectangle(cornerRadius: 3.6)
                .stroke(TaskRowPriority.color(task.priority), lineWidth: 1.5)
                .frame(width: 14.58, height: 14.58)
                .frame(width: 18, height: 18, alignment: .leading)
        }
    }
}

/// 手动排序的拖放目标（Round B1，对齐 Flutter moveTaskBefore）：拖行悬停时在
/// 目标行上缘显示插入条，drop → workspace.reorder(id, before:)。只挂在根任务
/// 行上（见 taskRow），子任务不可拖也不作为落点。
private struct TaskReorderDropModifier: ViewModifier {
    @ObservedObject var workspace: TaskWorkspaceModel
    let targetID: UUID
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { values, _ in
                guard let id = values.first.flatMap(UUID.init(uuidString:)),
                      id != targetID else { return false }
                workspace.reorder(id, before: targetID)
                return true
            } isTargeted: { targeted = $0 }
            .overlay(alignment: .top) {
                if targeted {
                    Capsule()
                        .fill(WFColors.accent)
                        .frame(height: 2)
                        .padding(.horizontal, WFSpace.sm)
                        .transition(.opacity)
                }
            }
    }
}

/// 行尾右对齐的元数据：清单、优先级旗标、截止、描述/提醒等小图标与日期徽标
/// 全部常驻（与迁移版一致），悬浮时快捷操作在尾栏右侧追加，不替换任何元素。
/// 日期徽标颜色：今天=强调色、过期=红色、其余=灰色。
private struct TaskRowMetadataTrail: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var showsListBadge: Bool
    let onOpenDate: () -> Void

    private var deadlineOverdue: Bool {
        guard let deadline = task.schedule.deadlineAt, !task.isClosed else { return false }
        return workspace.calendar.startOfDay(for: deadline) <= workspace.calendar.startOfDay(for: workspace.clock())
    }

    private var dateStyle: TaskListViewDefaults.DateBadgeStyle {
        TaskListViewDefaults.dateBadgeStyle(dueAt: task.schedule.dueAt, isClosed: task.isClosed,
                                            now: workspace.clock(), calendar: workspace.calendar)
    }

    private var muted: Color { task.isClosed ? WFColors.tertiaryText : WFColors.secondaryText }

    var body: some View {
        HStack(spacing: WFSpace.xs) {
            if task.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(task.isClosed ? muted : WFColors.accent)
                    .accessibilityLabel("已置顶")
            }
            if task.isAbandoned { Text("已放弃").foregroundStyle(muted) }
            if showsListBadge, task.list.name != TaskList.inbox.name {
                // 清单名最先被压缩：低优先级 + 40pt 上限，把宽度让给日期。
                Text(task.list.name).lineLimit(1)
                    .frame(maxWidth: 40).foregroundStyle(muted).layoutPriority(-1)
            }
            if task.priority != .none {
                Image(systemName: "flag.fill")
                    .foregroundStyle(task.isClosed ? muted : TaskRowPriority.color(task.priority))
                    .accessibilityLabel(TaskRowPriority.title(task.priority))
            }
            ForEach(Array(secondaryMetadata.prefix(WFMetrics.secondaryMetadataLimit))) { item in
                if let value = item.value {
                    Text(value).foregroundStyle(muted).accessibilityLabel(item.accessibilityLabel)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol).foregroundStyle(muted)
                        .accessibilityLabel(item.accessibilityLabel)
                }
            }
            if let deadline = task.schedule.deadlineAt {
                Text(TaskDateLabel.text(deadline, hasTime: false,
                                        now: workspace.clock(), calendar: workspace.calendar) + "截止")
                    .foregroundStyle(task.isClosed ? muted : deadlineOverdue ? .red : muted)
                    .layoutPriority(0)
            }
            if task.schedule.dueAt != nil {
                // 日期是行内最重要的元信息：固定尺寸不被压缩。
                dateBadge.fixedSize().layoutPriority(2)
            }
        }
        .font(WFType.supporting)
        .lineLimit(1)
        .frame(maxWidth: 200, alignment: .trailing)
    }

    private var dateBadge: some View {
        Button { onOpenDate() } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar").font(.system(size: 10))
                Text(TaskDateLabel.text(task.schedule.dueAt ?? Date(), hasTime: task.schedule.hasTime,
                                        now: workspace.clock(), calendar: workspace.calendar))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(task.isClosed ? WFColors.tertiaryText : badgeColor)
        .help("修改安排日期")
        .accessibilityLabel("安排日期：\(task.title.isEmpty ? "无标题" : task.title)")
    }

    private var badgeColor: Color {
        switch dateStyle {
        case .overdue: .red
        case .today: WFColors.accent
        case .scheduled: WFColors.secondaryText
        case .none: WFColors.secondaryText
        }
    }

    private var secondaryMetadata: [TaskRowSecondaryMetadata] {
        var items: [TaskRowSecondaryMetadata] = []
        if task.recurrence != .never {
            items.append(.init(id: "repeat", symbol: "repeat", accessibilityLabel: "重复任务"))
        }
        if task.reminderAt != nil {
            items.append(.init(id: "reminder", symbol: "bell", accessibilityLabel: "有提醒"))
        }
        if !task.tags.isEmpty {
            items.append(.init(id: "tags", symbol: "tag", accessibilityLabel: "有标签"))
        }
        if !task.document.isEmpty {
            items.append(.init(id: "description", symbol: "text.alignleft", accessibilityLabel: "有描述"))
        }
        if !task.attachments.isEmpty {
            items.append(.init(id: "attachments", symbol: "paperclip", accessibilityLabel: "有附件"))
        }
        return items
    }
}

private struct TaskRowSecondaryMetadata: Identifiable {
    let id: String
    var symbol: String? = nil
    var value: String? = nil
    let accessibilityLabel: String
}

// MARK: - 纯展示规则（Foundation 逻辑，供 WorkFollowTests/TaskListViewDefaults.swift 覆盖）

/// 对齐滴答清单的纯展示规则：快速添加占位、空状态文案、日期徽标归类、
/// 子任务预览与分组尾注。只依赖 Foundation 与投影类型，保持可单测。
enum TaskListViewDefaults {
    /// 日期徽标归类：过期红、今天强调色、未来灰、无日期/已关闭不给色。
    enum DateBadgeStyle: Equatable {
        case overdue, today, scheduled, none
    }

    /// Flutter uses the creation list in the placeholder, not the current view
    /// or tag filter. With no explicit list selection, capture targets Inbox.
    static func quickAddTargetName(activeList: String?, inboxName: String) -> String {
        activeList ?? inboxName
    }

    /// 列表为空时的文案，对齐滴答各视图的空状态。
    static func emptyStateMessage(destination: NativeDestination) -> String {
        switch destination {
        case .trash: return "垃圾桶是空的"
        case .today: return "今天的事情都做完了"
        case .inbox: return "没想好把任务安排在哪？可以先放这里"
        default: return "这里还没有任务"
        }
    }

    static func dateBadgeStyle(dueAt: Date?, isClosed: Bool, now: Date, calendar: Calendar) -> DateBadgeStyle {
        guard let dueAt, !isClosed else { return .none }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dueAt)
        if day < today { return .overdue }
        if day == today { return .today }
        return .scheduled
    }

    /// TickTick 式子任务预览：`- [ ] 甲 - [ ] 乙`，取前 limit 条；无标题兜底"无标题"。
    static func subtaskPreview(titles: [String], limit: Int = 3) -> String? {
        let names = titles.map { $0.isEmpty ? "无标题" : $0 }.prefix(max(limit, 1))
        guard !names.isEmpty else { return nil }
        return names.map { "- [ ] " + $0 }.joined(separator: " ")
    }

    /// 行内正文预览：取纯文本第一个非空行；正文为空返回 nil（不占预览行）。
    static func bodyPreview(of plainText: String) -> String? {
        for line in plainText.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// 分组标题右侧的小字尾注；只有"已过期"组显示"顺延"。
    static func groupTrailingNote(for kind: TaskGroupKind) -> String? {
        kind == .overdue ? "顺延" : nil
    }
}
