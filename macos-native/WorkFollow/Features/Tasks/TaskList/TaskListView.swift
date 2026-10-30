import SwiftUI
import UniformTypeIdentifiers

private struct TaskOutlineRowState: Equatable {
    let task: Task
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    let recentlyCreated: Bool
    let showsListBadge: Bool
    let hidesDetails: Bool
    let hiddenFields: [TaskRowDetailField]
    let allowsReordering: Bool
    let progress: String?
    let day: Date
    let dateRevision: Int
}

private struct TaskOutlineRowLayout: Equatable {
    let hasPreview: Bool
    /// 有标签时行底下多一行胶囊，行高随之变高。
    let hasTags: Bool
    let completed: Bool
    let depth: Int
}

private struct TaskOutlineHeaderState: Equatable {
    let revision: Int
    let title: String
    let count: Int
    let collapsed: Bool
    /// 悬停中的分组 id（系统分组没有 sectionID，也要能悬停出按钮）。
    let hoveredGroupID: String?
    let menuOpen: Bool
    let moveTarget: String?
}

private struct TaskOutlineCountdownState: Equatable {
    let section: CountdownSmartListSection
    let collapsed: Bool
}

private struct TaskTimelineCreation: Identifiable {
    let id = UUID()
    let schedule: TaskSchedule
}

struct TaskListView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var templateStore = TemplateStore.shared
    @State private var draft = ""
    @State private var restoredCaptureDraft = false
    @State private var scheduleSourceText = ""
    private var captureStorageKey: String { "listQuickAddDraft.v1." + navigation.destination.rawValue }
    private var capturePersistenceValue: GlobalQuickAddDraft.Snapshot {
        .init(text: draft, description: descriptionDraft, dismissedTokens: dismissedQuickAddTokens,
            schedule: quickAddScheduleOverride, priority: quickAddPriorityOverride,
            list: quickAddListOverride, tags: quickAddTagsOverride, attachments: quickAddAttachments)
    }
    private func saveCaptureDraft() {
        guard restoredCaptureDraft else { return }
        GlobalQuickAddDraft(storageKey: captureStorageKey).replace(with: capturePersistenceValue)
    }
    private func restoreCaptureDraft() {
        guard !restoredCaptureDraft else { return }
        let saved = GlobalQuickAddDraft(storageKey: captureStorageKey)
        draft = saved.text; descriptionDraft = saved.description
        scheduleSourceText = saved.text
        quickAddScheduleOverride = saved.schedule; quickAddPriorityOverride = saved.priority
        quickAddListOverride = saved.list; quickAddTagsOverride = saved.tags
        dismissedQuickAddTokens = saved.dismissedTokens; quickAddAttachments = saved.attachments
        restoredCaptureDraft = true
    }
    @State private var showNavigation = false
    @State private var showTemplatePicker = false
    /// 清单动态弹层（事件模型与任务动态共用 `TaskActivityStore`）。
    @State private var showListActivity = false
    @State private var showDisplaySettings = false
    @State private var showListEditor = false
    @State private var showListCopy = false
    @State private var timelineCreation: TaskTimelineCreation?
    @State private var showQuickAddSchedule = false
    @State private var quickAddSchedulePage: TaskDatePopoverV2.Page = .main
    /// 光标落在哪个分组标题上（滴答的 `+` / `⋯` 是 hover 才出现的，未悬停时标题行
    /// 只有箭头 + 标题 + 计数——这是对着本机滴答实测出来的）。
    /// 悬停中的分组 id（用 `TaskListGroup.id`，系统分组也有，不再只限自定义小节）。
    @State private var hoveredGroupID: String?
    @State private var activeSectionMenuID: String?
    /// 正在为哪个分组挑目标清单（非 nil 时弹出自绘卡片 MoveTargetPickerCard）。
    @State private var moveTargetSectionID: String?
    @State private var pendingTemplatePicker = false
    @State private var showQuickAddProperties = false
    @State private var quickAddScheduleOverride: QuickAddScheduleDraft?
    @State private var quickAddPriorityOverride: TaskPriority?
    @State private var quickAddListOverride: String?
    @State private var quickAddTagsOverride: [String]?
    /// 属性菜单里选好的附件（创建成功后挂到新任务，对齐滴答属性菜单的「附件」）。
    @State private var quickAddAttachments: [NativeAttachment] = []
    /// 输入框显示模式（滴答「输入框设置」的简洁 / 详细）。
    @AppStorage(QuickAddDisplayMode.defaultsKey) private var quickAddDisplayModeRaw = QuickAddDisplayMode.compact.rawValue
    @State private var dismissedQuickAddTokens: Set<String> = []
    @State private var quickAddEscapePrimed = false
    /// Tab 进入的任务描述草稿（对齐滴答「敲击 Tab 添加任务描述」）。只在创建
    /// 单个任务时随任务一起写进正文；批量创建时每一行各自成任务，不带描述。
    @State private var descriptionDraft = ""
    /// `#`/`@` 候选与描述行的界面状态；与全局快速添加面板共用同一套状态机。
    @State private var candidate = QuickAddCandidateState()
    @State private var inputSelection: NSRange?
    @State private var requestedInputSelection: NSRange?
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
    @State private var groupExpansion = TaskGroupExpansionState()
    /// 折叠态是否已经从偏好里恢复过（只在首次出现时读一次，避免每次 body 都覆盖用户操作）。
    @State private var groupExpansionRestored = false
    @State private var seenCompletedGroupIDs: Set<String> = []
    /// 已完成组的"已展开条数"（按 group.id）。缺省 = 第一页。
    /// 对齐滴答 `countToShowOfCompleted` + `didClickLoadMore`。
    @State private var completedPageCounts: [String: Int] = [:]
    /// 正在"加载"的已完成组（滴答 `TTListLoadMoreCell.startLoading` 的转圈态）。
    @State private var loadingCompletedGroupIDs: Set<String> = []
    /// 「倒数纪念日」小节的折叠状态。它与任务组的折叠是两套：任务组按 `id` 记，
    /// 这里只有一个固定小节，用布尔就够。
    @State private var countdownSectionCollapsed = false
    @FocusState private var descriptionFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var editingRowTitle = false
    @StateObject private var dropFeedback = TaskDropFeedback()

    private var scope: TaskListScope? { TaskWorkspaceModel.scope(for: navigation.destination) }
    private var query: TaskListQuery {
        guard scope == .allTasks else { return TaskListQuery() }
        return TaskListQuery(list: workspace.activeList, tag: workspace.activeTag)
    }
    /// 视图偏好的唯一真值源是 TaskViewPreferenceStore（持久化）；视图只读不存，
    /// 避免历史上 @FocusState/@State 双真值导致守卫静默失效的那类问题。
    private var preferenceKey: String {
        TaskViewScopeKey.key(destination: navigation.destination,
                             activeList: workspace.activeList, activeTag: workspace.activeTag,
                             activeFilterID: workspace.activeFilter?.id)
    }
    private var sortMode: TaskListSortMode { environment.viewPreferences.sortMode(for: preferenceKey) }
    /// 分组只对"所有任务"（含清单/标签过滤）生效；时间型视图的日期分组是视图本体。
    private var grouping: TaskListGrouping {
        guard scope == .allTasks else { return .byDate }
        let allTasksRoot = workspace.activeList == nil && workspace.activeTag == nil
        return environment.viewPreferences.grouping(for: preferenceKey, allTasksRoot: allTasksRoot)
    }
    private var availableGroupings: [TaskListGrouping] {
        TaskListGrouping.availableOptions(destination: navigation.destination,
                                          activeList: workspace.activeList,
                                          activeTag: workspace.activeTag)
    }
    private var groups: [TaskListGroup] {
        scope.map { workspace.groups(for: $0, query: query, grouping: grouping,
                                     hidesCompleted: environment.viewPreferences
                                        .hidesCompleted(for: preferenceKey), viewMode: viewMode) } ?? []
    }
    private var canAdd: Bool {
        if let list = workspace.activeList, scope == .allTasks, workspace.isListArchived(list) { return false }
        return scope == .today || scope == .tomorrow || scope == .inbox
            || scope == .allTasks || scope == .nextSevenDays
    }
    private var nativeTextEditing: Bool {
        editingRowTitle || NSApp.keyWindow?.firstResponder is NSTextView
    }
    /// TickTick shows each row's owning list unless the view is already that list.
    private var showsListBadge: Bool { workspace.activeList == nil && scope != .inbox }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if scope == .allTasks, let list = workspace.activeList, workspace.isListArchived(list) {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "archivebox")
                    Text("清单已归档，任务不在智能清单中显示，到期不提醒。")
                        .font(WFType.supporting)
                    Spacer(minLength: 0)
                    Button("恢复清单") { _ = workspace.setListArchived(list, false) }
                        .buttonStyle(.plain).foregroundStyle(WFColors.accent)
                }
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.xl).padding(.vertical, WFSpace.sm)
                .background(WFColors.secondarySurface)
            }
            // 候选列表挂在快速添加条的 overlay 上，会画到任务列表上方；提升层级
            // 才能盖住后面那个兄弟视图（SwiftUI 默认后者在上）。
            // 多选时快速添加条让位给批量动作条（滴答 `isMultipleModeForOneSelected`：
            // 多选是一个显式模式，输入区换成批量动作）。两者不同时出现——
            // 批量态下用户的意图是"处理已选的"，不是"再建一条"。
            if !workspace.bulkSelection.isEmpty {
                TaskBulkActionBar(workspace: workspace, onOpenPanel: openBatchPanel)
                    .zIndex(2)
            } else if canAdd, let scope, viewMode != .kanban || environment.viewPreferences.kanbanOptions(for: preferenceKey).showsInput {
                quickAddBar(in: scope)
                    .zIndex(1)
                    // 占位文案实测过"清单已经是学习、却仍写着收集箱"：内容按 activeList
                    // 过滤是对的（看板只有一列即证），所以问题是这条 bar 没有随目标变化
                    // 重建。`.id` 绑到**落点名字**上，目标一变就换一个身份重建
                    // （这是刻意为之的钝器：根因是这条子树的失效边界，不是取值逻辑）。
                    .id(quickAddTargetName)
            }
            if viewMode == .kanban {
                // 看板：列 = 投影分组（清单内有自定义分组时即分组本身）。
                TaskKanbanView(groups: groups, workspace: workspace, onSelect: { id in
                    workspace.select(id)
                }, sortMode: sortMode, sortDescending: sortDescending,
                               showsListBadge: showsListBadge,
                               hidesCompleted: environment.viewPreferences.hidesCompleted(for: preferenceKey),
                               hidesDetails: environment.viewPreferences.hidesDetails(for: preferenceKey),
                               hiddenFields: environment.viewPreferences.hiddenDetailFields(for: preferenceKey),
                               scope: scope ?? .allTasks, allowsCreation: canAdd,
                               display: environment.viewPreferences.kanbanOptions(for: preferenceKey))
            } else if viewMode == .timeline {
                TaskTimelineView(tasks: timelineTasks, workspace: workspace, allowsCreation: canAdd,
                    onCreate: { timelineCreation = TaskTimelineCreation(schedule: $0) },
                    onSelect: { workspace.select($0) })
            } else {
                taskListSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .workfollowPageSurface(0.90)
        .onReceive(NotificationCenter.default.publisher(for: .workspaceOrganizationRenamed)) { notification in
            quickAddTagsOverride = QuickAddPropertiesOverrides.renamedTags(quickAddTagsOverride, notification: notification)
        }
        .onAppear {
            restoreCaptureDraft()
            restoreGroupExpansion()
        }
        .onChange(of: preferenceKey) { _, _ in restoreGroupExpansion() }
        .onChange(of: capturePersistenceValue) { _, _ in saveCaptureDraft() }
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onChange(of: draft) { _, _ in
            // 文本一变，「已被忽略」和候选高亮都作废：候选列表要按新的查询重开。
            candidate.textDidChange()
            if QuickAddScheduleDraft.scheduleTextChanged(from: scheduleSourceText, to: draft,
                now: workspace.clock(), calendar: workspace.calendar,
                knownLists: Set(workspace.availableListNames), dismissedTokenIDs: dismissedQuickAddTokens) {
                quickAddScheduleOverride = nil
            }
            scheduleSourceText = draft
        }
        .onChange(of: quickAddFocused) { _, focused in
            if focused { listFocused = false }
        }
        .onChange(of: descriptionFocused) { _, focused in
            if focused { listFocused = false }
        }
        .onChange(of: showQuickAddSchedule) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
        .onChange(of: showQuickAddProperties) { _, isPresented in
            guard !isPresented else { return }
            if pendingTemplatePicker {
                pendingTemplatePicker = false
                DispatchQueue.main.async { showTemplatePicker = true }
            } else {
                quickAddFocused = true
            }
        }
        .onChange(of: groupIDs) { _, _ in collapseNewCompletedGroups() }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(workspace: workspace, templateStore: templateStore,
                               onDismiss: { showTemplatePicker = false },
                               onApplied: { _ in
                                   clearQuickAddDraft()
                                   showQuickAddProperties = false
                                   quickAddFocused = false
                                   listFocused = true
                               })
        }
        .sheet(isPresented: $showListActivity) {
            if let list = workspace.activeList {
                ListActivitySheet(listName: list, workspace: workspace,
                                  activity: environment.taskActivityStore) {
                    showListActivity = false
                }
            }
        }
        .sheet(isPresented: $showDisplaySettings) {
            if viewMode == .kanban { TaskKanbanSettingsView(preferences: environment.viewPreferences, key: preferenceKey) }
            else { TaskDisplaySettingsView() }
        }
        .sheet(isPresented: $showListEditor) {
            if let list = workspace.activeList {
                TaskListEditorView(workspace: workspace, preferences: environment.viewPreferences, name: list)
            }
        }
        .sheet(isPresented: $showListCopy) {
            if let list = workspace.activeList {
                TaskListCopyView(workspace: workspace, source: list) { copied in
                    environment.viewPreferences.copyScope(from: preferenceKey,
                        to: TaskViewScopeKey.key(destination: .allTasks, activeList: copied, activeTag: nil))
                    workspace.activeList = copied
                }
            }
        }
        .sheet(item: $timelineCreation) { creation in
            TaskComposer(workspace: workspace, onClose: { _ in timelineCreation = nil },
                title: "", list: workspace.activeList ?? TaskList.inbox.name,
                scheduled: true, date: creation.schedule.dueAt ?? workspace.clock(),
                initialSchedule: QuickAddScheduleDraft(dueAt: creation.schedule.dueAt,
                    dueEndAt: creation.schedule.dueEndAt, hasTime: creation.schedule.hasTime))
        }
        .onChange(of: showTemplatePicker) { _, presented in
            if presented { quickAddFocused = false; descriptionFocused = false }
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in revealSelectedClosedTask() }
        .onChange(of: navigation.destination) { _, _ in dropFeedback.clear() }
        .onDisappear { dropFeedback.clear() }
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
        HStack(spacing: 0) {
            Button {
                if navigationVisible { environment.sidebarVisible.toggle() }
                else { showNavigation.toggle() }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: TaskListMetrics.headerActionSize,
                           height: TaskListMetrics.headerActionSize)
                    .contentShape(Rectangle())
                    .popupMenuRowBackground()
            }
            .buttonStyle(.plain)
            .hoverTip(navigationVisible
                  ? (environment.sidebarVisible ? "隐藏导航" : "显示导航")
                  : "显示导航")
            .background(AnchoredPropertyPanel(isPresented: $showNavigation,
                                              width: WFMetrics.navigationWidth) {
                NavigationColumnView(workspace: workspace, navigation: navigation,
                                     filterStore: environment.filterStore) {
                    showNavigation = false
                }
                .frame(width: WFMetrics.navigationWidth, height: 440)
            })
            // 滴答页头没有目的地图标，标题 20pt Medium 紧贴汉堡。
            Text(headerTitle)
                .font(WFType.taskListPageTitle)
                .lineLimit(1)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .businessContextMenu { listTitleMenu }
            Spacer(minLength: 0)
            viewMenu
            moreMenu
        }
        .padding(.horizontal, TaskListMetrics.rowHorizontalPadding)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.md)
    }

    /// 空态的下一步动作（滴答 `TTTaskListEmptyHolderView.actionButton`）。
    ///
    /// 文案与落点按视图给：空列表最怕的是"看着一句话，不知道下一步点哪"。
    private var emptyStateAction: (title: String, perform: () -> Void)? {
        switch navigation.destination {
        case .today:
            return ("看看未来 7 天", { navigation.destination = .nextSevenDays })
        case .inbox:
            return ("新建第一个任务", {
                quickAddFocused = true
                listFocused = false
            })
        case .nextSevenDays, .tomorrow:
            return ("回到今天", { navigation.destination = .today })
        default:
            return nil
        }
    }

    private var headerTitle: String {
        workspace.activeFilter?.name ?? workspace.activeList
            ?? workspace.activeTag.map { "#" + $0 } ?? navigation.destination.title
    }

    /// 「⋯」按滴答只留显示类操作，清单动态/添加分组改从标题右键进入，入口不丢。
    @ViewBuilder
    private var listTitleMenu: some View {
        if let list = workspace.activeList, list != TaskList.inbox.name {
            TaskListCommands(workspace: workspace, name: list,
                onEdit: { showListEditor = true }, onCopy: { showListCopy = true },
                onActivity: { showListActivity = true })
        } else {
            Button("清单动态", systemImage: "clock.arrow.circlepath") {
                DispatchQueue.main.async { showListActivity = true }
            }.disabled(workspace.activeList == nil)
        }
        if canAdd, let list = workspace.activeList, list != TaskList.inbox.name {
            Button("添加分组", systemImage: "plus") {
                guard let title = TaskNamePrompt.ask("添加分组") else { return }
                if !workspace.addListSection(list, title: title) { TaskNamePrompt.invalidName() }
            }
        }
    }

    /// 分组、排序与方向共用业务菜单行，选中状态由显式选项渲染。
    private var viewMenu: some View {
        BusinessMenu(title: "分组与排序") {
            if !availableGroupings.isEmpty {
                BusinessMenuSection(title: "分组")
                BusinessMenuChoices(selection: groupingBinding, options: availableGroupings.map { BusinessChoice($0, $0.title) })
                Divider()
            }
            BusinessMenuSection(title: "排序")
            BusinessMenuChoices(selection: sortModeBinding, options: TaskListSortMode.menuOrder.map { BusinessChoice($0, $0.title) })
            if sortMode != .manual {
                BusinessMenuSection(title: "方向")
                BusinessMenuChoices(selection: sortDescendingBinding, options:
                    [BusinessChoice(false, "升序"), BusinessChoice(true, "降序")])
                Button("恢复默认排序", systemImage: "arrow.counterclockwise") { resetSort() }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: TaskListMetrics.headerActionSize,
                       height: TaskListMetrics.headerActionSize)
                .contentShape(Rectangle())
                .popupMenuRowBackground()
        }
        .fixedSize()
        .hoverTip("分组与排序")
        .id(preferenceKey)
    }


    private var viewMode: TaskListViewMode {
        environment.viewPreferences.viewMode(for: preferenceKey, availableModes: availableViewModes)
    }

    private var availableViewModes: [TaskListViewMode] {
        TaskListViewMode.availableOptions(destination: navigation.destination,
            activeList: workspace.activeList, activeTag: workspace.activeTag,
            activeFilterID: workspace.activeFilter?.id)
    }

    private var timelineTasks: [Task] {
        TaskTimelineProjection.tasks(in: scope ?? .allTasks, source: workspace.allTasks,
            now: workspace.clock(), calendar: workspace.calendar, query: query,
            archivedLists: Set(workspace.archivedListNames), filter: workspace.activeFilter,
            hidesCompleted: environment.viewPreferences.hidesCompleted(for: preferenceKey),
            sortMode: sortMode, descending: sortDescending)
    }

    private var viewModeBinding: Binding<TaskListViewMode> {
        Binding(get: { viewMode },
                set: { environment.viewPreferences.setViewMode($0, for: preferenceKey) })
    }

    /// 显示设置（按视图记忆；缺省全显示）。
    private var hidesCompletedBinding: Binding<Bool> {
        Binding(get: { environment.viewPreferences.hidesCompleted(for: preferenceKey) },
                set: { environment.viewPreferences.setHidesCompleted($0, for: preferenceKey) })
    }

    private var hidesDetailsBinding: Binding<Bool> {
        Binding(get: { environment.viewPreferences.hidesDetails(for: preferenceKey) },
                set: { environment.viewPreferences.setHidesDetails($0, for: preferenceKey) })
    }

    private var sortModeBinding: Binding<TaskListSortMode> {
        Binding(get: { environment.viewPreferences.sortMode(for: preferenceKey) },
                set: { environment.viewPreferences.setSortMode($0, for: preferenceKey) })
    }

    private var sortDescending: Bool {
        environment.viewPreferences.sortDescending(for: preferenceKey)
    }

    private var sortDescendingBinding: Binding<Bool> {
        Binding(get: { sortDescending },
                set: { environment.viewPreferences.setSortDescending($0, for: preferenceKey) })
    }

    private func resetSort() {
        environment.viewPreferences.resetSort(for: preferenceKey)
    }

    private var groupingBinding: Binding<TaskListGrouping> {
        Binding(get: { grouping },
                set: { environment.viewPreferences.setGrouping($0, for: preferenceKey) })
    }

    /// 模板、撤销等低频操作收进"更多"，保持顶栏只剩排序/更多两个小图标。
    private var moreMenu: some View {
        // 滴答清单页「⋯」：视图三图标 + 隐藏已完成 + 隐藏/显示详细 + 显示设置。
        // 打印按用户要求不提供；撤销在菜单栏、模板在快速添加属性里已有入口。
        BusinessMenu(width: PopupMetrics.menuWidthNarrow, title: "列表操作") {
            ForEach(TaskListMoreMenuPolicy.entries, id: \.self) { entry in
                switch entry {
                case .viewModes:
                    TaskListMenuViewModes(selection: viewModeBinding, options: availableViewModes)
                case .separator:
                    Divider()
                case .hidesCompleted:
                    Toggle("隐藏已完成", systemImage: "checkmark.circle", isOn: hidesCompletedBinding)
                case .detailsVisibility:
                    Button(TaskListMoreMenuPolicy.detailsTitle(
                        hidesDetails: hidesDetailsBinding.wrappedValue),
                           systemImage: "list.bullet.indent") {
                        hidesDetailsBinding.wrappedValue.toggle()
                    }
                case .displaySettings:
                    Button("显示设置", systemImage: "slider.horizontal.3") {
                        showDisplaySettings = true
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: TaskListMetrics.headerActionSize,
                       height: TaskListMetrics.headerActionSize)
                .contentShape(Rectangle())
                .popupMenuRowBackground()
        }
        .fixedSize()
        .hoverTip("列表操作")
        .id(preferenceKey)
    }

    // MARK: - 快速添加：浅灰圆角条，聚焦后展开解析预览

    /// 快速添加日期入口的配色：与任务行日期徽标共用 dateBadgeStyle 归类
    /// （过期红、今天强调色、未来/无日期灰）。
    private func quickAddBadgeColor(_ timing: QuickAddScheduleDraft) -> Color {
        guard let dueAt = timing.dueAt else { return WFColors.secondaryText }
        switch TaskListViewDefaults.dateBadgeStyle(dueAt: dueAt, dueEndAt: timing.dueEndAt,
                                                   hasTime: timing.hasTime, isClosed: false,
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
                // 待办框视觉走唯一真源 QuickAddBarStyle（滴答对齐：小而浅的加号）。
                Image(systemName: "plus")
                    .font(.system(size: QuickAddBarStyle.iconSize))
                    .foregroundStyle(QuickAddBarStyle.iconColor)
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
                    onFieldFocusChange: { quickAddFocused = $0 },
                    onSelectionChange: { if inputSelection != $0 { inputSelection = $0 } },
                    requestedSelection: $requestedInputSelection
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
                    .popupMenuRowBackground()
                    .hoverTip("安排日期、提醒和重复")
                    .quickAddRenderAnchor(.schedule)
                    .schedulePopover(isPresented: $showQuickAddSchedule) {
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
                        Image(systemName: "chevron.down")
                            .foregroundStyle(WFColors.secondaryText)
                            // Keep the whole control hit-testable, not just the glyph.
                            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popupMenuRowBackground()
                    .hoverTip("更多任务属性")
                    .background(AnchoredPropertyPanel(isPresented: $showQuickAddProperties, width: PopupMetrics.quickAddPropertiesWidth) {
                        QuickAddPropertiesPopover(
                            workspace: workspace,
                            selectedPriority: quickAddPriorityOverride ?? quickAddResult.priority,
                            selectedList: quickAddListOverride ?? quickAddResult.listName ?? workspace.activeList ?? TaskList.inbox.name,
                            selectedTags: quickAddTagsOverride ?? quickAddResult.tags,
                            attachments: quickAddAttachments,
                            displayMode: quickAddDisplayMode,
                            onPriority: { value in
                                quickAddPriorityOverride = value
                                showQuickAddProperties = false
                            },
                            onList: { quickAddListOverride = $0 },
                            onTags: { quickAddTagsOverride = $0 },
                            onTemplate: {
                                pendingTemplatePicker = true
                                showQuickAddProperties = false
                            },
                            onAttachments: { quickAddAttachments = $0 },
                            onDisplayMode: { quickAddDisplayModeRaw = $0.rawValue },
                            onDismiss: { showQuickAddProperties = false }
                        )
                    })
                }
            }
            .frame(height: TaskListMetrics.quickAddHeight)
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
                        QuickAddTokenChip(
                            token: token,
                            // 日程类 chip 点开面板对应页改值；标签/清单/优先级仍走属性面板。
                            onEdit: TaskDatePopoverV2.Page(editing: token).map { page in
                                {
                                    quickAddSchedulePage = page
                                    showQuickAddSchedule = true
                                }
                            },
                            onRemove: { dismissedQuickAddTokens.insert(token.id) },
                            font: WFType.control,
                            horizontalPadding: 6,
                            verticalPadding: 3,
                            backgroundOpacity: 0.09)
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
        .padding(.horizontal, WFSpace.md)
        // 滴答式两态：未选中是带蓝调的极浅灰条（QuickAddBarStyle.idleFill）、
        // 无描边；选中后底色提亮到窗口底色、描边换「今天」同款强调色。
        .background(RoundedRectangle(cornerRadius: TaskListMetrics.quickAddRadius)
            .fill(quickAddExpanded ? WFColors.canvas : QuickAddBarStyle.idleFill))
        .overlay {
            if quickAddExpanded {
                RoundedRectangle(cornerRadius: TaskListMetrics.quickAddRadius)
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
            let tags = tagCandidateCatalog
            QuickAddCandidateList(
                names: candidateNames,
                selectedIndex: min(candidate.selection, max(0, candidateNames.count - 1)),
                emptyMessage: marker.kind == .tag ? "没有匹配的标签" : "没有匹配的清单",
                icon: marker.kind == .tag ? "tag" : "list.bullet",
                onHover: { candidate.selection = $0 },
                onCommit: { commitCandidate($0) },
                colors: marker.kind == .tag ? tags.colors : [:],
                depths: marker.kind == .tag ? tags.depths : [:]
            )
        }
    }

    /// 输入末尾的标记片段，且没被 Esc 忽略过。
    /// 焦点判据就是输入框的聚焦真值：不聚焦时不该弹候选列表（对齐滴答的输入态）。
    private var activeMarkerQuery: QuickAddComposition.MarkerQuery? {
        candidate.marker(in: draft, isFocused: quickAddFocused, selection: inputSelection)
    }

    /// 候选来源：`#` 查已有标签、`@` 查已有清单。
    private var tagCandidateCatalog: QuickAddTagCatalog { QuickAddTagCatalog(tags: workspace.taskTags) }

    private func candidateSource(_ kind: QuickAddComposition.MarkerQuery.Kind) -> [String] {
        kind == .tag ? tagCandidateCatalog.names : workspace.availableListNames
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
        let result = QuickAddComposition.replacingMarker(in: draft, selection: inputSelection, with: name)
        draft = result.text
        inputSelection = result.selection
        requestedInputSelection = result.selection
        candidate.textDidChange()
        quickAddFocused = true
    }

    /// 一次 Esc 只收掉候选列表这一层，不清空草稿。
    private func dismissCandidateList() {
        candidate.dismiss(draft: draft, selection: inputSelection)
    }

    private func closeDescriptionRow() {
        descriptionFocused = false
        if descriptionDraft.isEmpty { candidate.descriptionVisible = false }
        DispatchQueue.main.async { quickAddFocused = true }
    }

    /// 快速添加的**落点**（与 `addTask` 的判定同源：override → 文本解析 → 当前清单 → 收集箱）。
    ///
    /// 实测出现过"清单页占位写收集箱、实际却落到学习"的不一致：占位此前只读
    /// `activeList ?? 收集箱`，忽略了另外两条更靠前的来源。这里让**文案与落点同源**，
    /// 从结构上消掉二者跑偏的可能（落点判定本身没有动）。
    private var quickAddTargetName: String {
        quickAddListOverride ?? quickAddResult.listName
            ?? TaskListViewDefaults.quickAddTargetName(activeList: workspace.activeList,
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
        // 「输入框设置：详细」时始终露出日期与属性图标（滴答「详细」模式）。
        quickAddDisplayMode == .detailed
            || quickAddFocused
            || descriptionFocused || candidate.descriptionVisible || !descriptionDraft.isEmpty
            || !draft.isEmpty || quickAddScheduleOverride != nil
            || showQuickAddSchedule || showQuickAddProperties
    }

    private var quickAddDisplayMode: QuickAddDisplayMode {
        QuickAddDisplayMode(rawValue: quickAddDisplayModeRaw) ?? .compact
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
            reminderOffsets: timing.reminderOffsetsOrNil,
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
        // 常量构造：宿主不再逐字段手抄，加字段时不会漏（见 `QuickAddScheduleDraft.init(_:)`）。
        let scheduleDraft = QuickAddScheduleDraft(plan)
        // 面板改完把等价文字写回输入框：chip 是按文字解析出来的，不改文字
        // 就会出现「chip 写 3 分钟、实际建 30 分钟」。
        // 没有可落的日程片段（用户只打了标题）时保持文字不动，由 override 承担。
        if let rewritten = QuickAddScheduleTextSync.rewrite(
            draft, to: scheduleDraft, now: workspace.clock(), calendar: workspace.calendar,
            knownLists: Set(workspace.availableListNames),
            dismissedTokenIDs: dismissedQuickAddTokens) {
            draft = rewritten
            // 文字已经承载了新值，override 不必再叠加（避免两套值各说各话）。
            scheduleSourceText = rewritten
            quickAddScheduleOverride = nil
        } else {
            quickAddScheduleOverride = scheduleDraft
        }
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
        // 提醒可能来自旧式单点（`reminderAt`）或面板的多级偏移（`reminderOffsets`），
        // 两者都算"已设提醒"，摘要都要提示。
        if timing.reminderAt != nil || !timing.reminderOffsets.isEmpty { parts.append("提醒") }
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
            listFocused = true
        }
    }

    private func clearQuickAddDraft() {
        draft = ""
        dismissedQuickAddTokens.removeAll()
        quickAddScheduleOverride = nil
        quickAddPriorityOverride = nil
        quickAddListOverride = nil
        quickAddTagsOverride = nil
        quickAddAttachments.removeAll()
        descriptionDraft = ""
        descriptionFocused = false
        candidate.reset()
        saveCaptureDraft()
    }

    @ViewBuilder
    private func groupHeader(_ group: TaskListGroup) -> some View {
        if group.sectionID != nil {
            // 分组标题本身就是交互点（滴答词表里同时有 `分组标题` 与 `删除分组`）：
            // 就地重命名/删除，不用绕到顶栏菜单。其它分组（按日期/优先级…）没有归属可改，
            // 不给菜单，避免"看着能改其实不能"。
            headerContent(group).businessContextMenu { sectionMenu(group) }
        } else {
            headerContent(group)
        }
    }

    @ViewBuilder
    private func sectionMenu(_ group: TaskListGroup) -> some View {
        if let sectionID = group.sectionID {
            Button("重命名", systemImage: "pencil") {
                guard let title = TaskNamePrompt.ask("重命名分组", value: group.label ?? ""),
                      title != group.label else { return }
                if !workspace.renameListSection(sectionID, title: title) {
                    TaskNamePrompt.invalidName()
                }
            }
            // 滴答分组标题菜单的其余三项：上/下方添加分组 + 移动到另一个清单。
            Button("在上方添加分组", systemImage: "arrow.up.square") { addSection(above: sectionID) }
            Button("在下方添加分组", systemImage: "arrow.down.square") { addSection(below: sectionID) }
            // 这一项不再开系统子菜单：滴答那版带搜索框 + 当前清单打勾，系统菜单做不到，
            // 改成弹出自绘卡片（MoveTargetPickerCard，过滤/高亮逻辑在 MoveTargetPicker）。
            Button("移动到", systemImage: "folder") { moveTargetSectionID = sectionID }
            Button("删除", systemImage: "trash") {
                guard TaskNamePrompt.confirm("删除分组“\(group.label ?? "")”？",
                                             message: "其中的任务会保留，并回到未分组。",
                                             action: "删除") else { return }
                _ = workspace.removeListSection(sectionID)
            }
        }
    }

    /// 从持久化偏好恢复折叠态（滴答 `expandedTasksInSmartList` 的落盘口径）。
    ///
    /// 每个视图键恢复一次：`preferenceKey` 变了（切清单/标签/过滤器）要重新读。
    /// **不覆盖**已完成组的"首次出现自动折叠"——那是 `collapseNewCompletedGroups()`
    /// 的事；这里只把存档里的折叠集合装回去，若该组没有存档记录则保持默认展开。
    private func restoreGroupExpansion() {
        let stored = environment.viewPreferences.collapsedGroups(for: preferenceKey)
        groupExpansion = TaskGroupExpansionState(collapsedIDs: stored)
        groupExpansionRestored = environment.viewPreferences.hasCollapsedGroupsRecord(for: preferenceKey)
    }

    /// 这一组的动作位（`+` / `…` / 「顺延」）。
    private func headerActions(for group: TaskListGroup) -> TaskGroupHeaderActions {
        TaskGroupHeaderActions.resolve(kind: group.kind, sectionID: group.sectionID,
                                       taskCount: group.tasks.count,
                                       isUnsectionedBucket: group.isUnsectionedBucket)
    }

    /// 当前分组是否在悬停（用 `group.id`，系统分组也有）。
    private func isHovered(_ group: TaskListGroup) -> Bool { hoveredGroupID == group.id }

    /// 分组头是否按自定义小节样式渲染（34pt、无上方留白、有 +/…）。
    private func isSectionGroup(_ group: TaskListGroup) -> Bool {
        group.sectionID != nil || group.isUnsectionedBucket
    }

    /// 分组头的「+」。
    ///
    /// 滴答只有自定义小节有 `+`。点它走既有的「在此分组新建任务」对话框
    /// → `createTaskInSection`，因为"归到哪个小节"是创建参数，快速添加条
    /// 目前不接受小节。未分组桶没有 sectionID，直接把焦点交给快速添加条，
    /// 落点就是当前清单（未分组）。
    private func beginCapture(in group: TaskListGroup) {
        let actions = headerActions(for: group)
        if case .section(let sectionID) = actions.prefill {
            guard let list = workspace.activeList,
                  let title = TaskNamePrompt.ask("在此分组新建任务"),
                  !title.isEmpty else { return }
            if !workspace.createTaskInSection(sectionID, list: list, title: title) {
                TaskNamePrompt.invalidName()
            }
            return
        }
        quickAddFocused = true
        listFocused = false
    }

    /// 在分组上/下方插入新分组（滴答分组标题菜单的两项）。
    /// "在下方" = 插到**下一个分组之前**；没有下一个就追加到末尾。
    private func addSection(above id: String?) {
        guard let list = workspace.activeList,
              let title = TaskNamePrompt.ask("添加分组") else { return }
        if !workspace.insertListSection(list, title: title, above: id) { TaskNamePrompt.invalidName() }
    }

    private func addSection(below id: String) {
        guard let list = workspace.activeList else { return }
        let ordered = workspace.listSections(forList: list)
        let next = ordered.firstIndex { $0.id == id }.flatMap { $0 + 1 < ordered.count ? ordered[$0 + 1].id : nil }
        addSection(above: next)
    }

    private func headerContent(_ group: TaskListGroup) -> some View {
        let headerActions = headerActions(for: group)
        let isGroupHovered = isHovered(group)
        let headerHeight = TaskListMetrics.groupHeaderHeight(isSection: isSectionGroup(group))
        return HStack(spacing: 6) {
            Button {
                groupExpansion.toggle(group)
                // 滴答 `taskCollapseStateChanged:`：折叠态落盘，重启后保持。
                environment.viewPreferences.setCollapsedGroups(groupExpansion.collapsedIDs,
                                                               for: preferenceKey)
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: groupExpansion.isCollapsed(group) ? "chevron.right" : "chevron.down")
                        .font(.system(size: TaskListMetrics.groupChevronSize, weight: .semibold))
                        .foregroundStyle(WFColors.taskMetaText)
                        .frame(width: TaskListMetrics.groupChevronSize, height: headerHeight)
                    // 滴答日期分组标题 14pt Demi、计数 12pt Regular（运行时实测）。
                    Text(groupTitle(group))
                        .font(WFType.sectionSemibold)
                        .padding(.leading, 4)
                    Text("\(group.tasks.count)")
                        .font(WFType.groupCount)
                        .padding(.leading, 5)
                        .foregroundStyle(group.kind == .completed ? WFColors.taskCompletedCount : WFColors.taskMetaText)
                }
                .frame(height: headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            // + / … 只属于自定义小节；滴答日期分组头在 AX 树里没有任何按钮。
            if headerActions.showsAdd, isGroupHovered {
                Button { beginCapture(in: group) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: TaskListMetrics.groupActionHit, height: TaskListMetrics.groupActionHit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverTip("在此分组新建任务")
                .accessibilityLabel("在「\(groupTitle(group))」新建任务")
            }
            if headerActions.showsMenu, let sectionID = group.sectionID,
               isGroupHovered || activeSectionMenuID == sectionID {
                BusinessMenu(isPresented: Binding(get: { activeSectionMenuID == sectionID },
                    set: { visible in
                        if visible { activeSectionMenuID = sectionID }
                        else if activeSectionMenuID == sectionID { activeSectionMenuID = nil }
                    })) { sectionMenu(group) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: TaskListMetrics.groupActionHit, height: TaskListMetrics.groupActionHit)
                        .contentShape(Rectangle())
                }
                .fixedSize()
                .hoverTip("分组操作")
            }
            // 滴答唯一常驻的分组头文字动作：已过期 →「顺延」（26×20）。
            if headerActions.showsPostpone {
                Button("顺延") {
                    workspace.postponeOverdue(Set(group.tasks.map(\.id)))
                }
                .buttonStyle(.plain)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.accent)
                .frame(minWidth: 26, minHeight: 20)
                .help("将已过期任务顺延到今天")
                .accessibilityLabel("顺延：" + groupTitle(group))
            }
        }
        .padding(.horizontal, TaskListMetrics.rowHorizontalPadding)
        .frame(height: headerHeight)
        // nil sections must remain closed; the shared panel builds content on demand.
        .background(AnchoredPropertyPanel(isPresented: Binding(get: { moveTargetSectionID != nil && moveTargetSectionID == group.sectionID },
                                      set: { if !$0 { moveTargetSectionID = nil } }),
                                         width: PopupMetrics.moveTargetWidth, focusPolicy: .panel) {
            Group {
                if let sectionID = group.sectionID {
                    MoveTargetPickerCard(
                        sectionTitle: group.label ?? "",
                        targets: workspace.activeListNames.filter { $0 != workspace.activeList }.map {
                            MoveTarget(name: $0, isCurrent: false)
                        },
                        onPick: { list in
                            _ = workspace.moveListSection(sectionID, to: list)
                            moveTargetSectionID = nil
                        },
                        onCancel: { moveTargetSectionID = nil })
                }
            }
        })
        .onHover { inside in
            // 系统分组没有 sectionID，但按钮同样要有——用 group.id 做悬停身份。
            let groupID = group.id
            if inside { hoveredGroupID = groupID }
            else if hoveredGroupID == groupID { hoveredGroupID = nil }
        }
        // 把任务拖到**分组标题**上 = 改归属（滴答主手势）。
        // 列表行拖的是任务 UUID 字符串；侧栏清单拖拽带 `wf-list:` 前缀，UUID 解析失败即忽略。
        .dropDestination(for: String.self) { values, _ in
            guard let taskID = TaskSectionDropTarget.taskID(for: values.first),
                  let intent = TaskSectionDropTarget.intent(
                      for: values.first,
                      target: .of(sectionID: group.sectionID,
                                  isUnsectionedBucket: group.isUnsectionedBucket)) else { return false }
            switch intent {
            case .assign(let sectionID):
                return workspace.setTaskSection(taskID, sectionID: sectionID).taskID != nil
            case .clear:
                return workspace.setTaskSection(taskID, sectionID: nil).taskID != nil
            }
        } isTargeted: { _ in }
    }

    private func revealSelectedClosedTask() {
        guard let scope, let task = workspace.selectedTask else { return }
        groupExpansion.reveal(task, in: scope, calendar: workspace.calendar)
    }

    /// "已完成"分组默认折叠在列表底部（TickTick 行为）；只在每个分组第一次出现时折叠一次，
    /// 之后尊重用户手动展开/收起。已完成视图本身不折叠。
    private var groupIDs: [String] { groups.map(\.id) }

    private func collapseNewCompletedGroups() {
        guard scope?.isClosedScope != true else { return }
        // 用户在这个视图上明确表过态（有过折叠记录）就完全尊重存档：
        // 否则"手动展开已完成组 → 下次进来又被自动折叠"会反复出现。
        if groupExpansionRestored { return }
        var changed = false
        for group in groups where group.kind == .completed {
            if seenCompletedGroupIDs.insert(group.id).inserted,
               !groupExpansion.isCollapsed(group) {
                groupExpansion.toggle(group)
                changed = true
            }
        }
        if changed {
            environment.viewPreferences.setCollapsedGroups(groupExpansion.collapsedIDs,
                                                           for: preferenceKey)
        }
    }

    /// 已完成组的可见条数上限（其它组不看这个）。
    private func visibleCompletedLimit(for group: TaskListGroup) -> Int {
        guard group.kind == .completed else { return .max }
        return max(TaskListMetrics.completedPageSize,
                   completedPageCounts[group.id] ?? TaskListMetrics.completedPageSize)
    }

    /// 这一组还有多少条没显示（0 = 不需要「显示更多」行）。
    private func hiddenCompletedCount(for group: TaskListGroup, scope: TaskListScope) -> Int {
        guard group.kind == .completed else { return 0 }
        let total = displayedNodes(for: group, scope: scope).count
        return max(0, total - visibleCompletedLimit(for: group))
    }

    /// 「显示更多」：先转圈一小拍再追加，对齐滴答 `startLoading` / `endLoading` 的观感。
    /// 直接同步追加的话列表会"跳"一下，用户以为点漏了。
    private func loadMoreCompleted(in group: TaskListGroup) {
        guard !loadingCompletedGroupIDs.contains(group.id) else { return }
        loadingCompletedGroupIDs.insert(group.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let current = visibleCompletedLimit(for: group)
            completedPageCounts[group.id] = current + TaskListMetrics.completedPageSize
            loadingCompletedGroupIDs.remove(group.id)
        }
    }

    private func displayedNodes(for group: TaskListGroup, scope: TaskListScope) -> [TaskTreeNode] {
        workspace.nodes(for: group, scope: scope, query: query,
                        orderedRoots: group.orderedTasks(using: sortMode,
                                                         descending: sortDescending,
                                                         calendar: workspace.calendar))
    }

    private func selectFiltered(_ offset: Int) {
        guard let scope else { return }
        let nodes = groups.flatMap { displayedNodes(for: $0, scope: scope) }
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == workspace.selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) } ?? (offset < 0 ? nodes.count - 1 : 0)
        workspace.selectFromKeyboard(nodes[index].task.id)
    }

    /// 当前视图的可见行顺序（含子任务）——Shift 范围选择与键盘移动共用这一份顺序。
    private func visibleRowOrder() -> [UUID] {
        groups.flatMap { displayedNodes(for: $0, scope: scope ?? .today) }.map(\.task.id)
    }

    private func groupTitle(_ group: TaskListGroup) -> String {
        // 文案单一来源：`TaskGroupDisplay.title`（看板列头共用同一份）。
        TaskGroupDisplay.title(group, now: workspace.clock())
    }

    private func rowIdentity(group: TaskListGroup, task: Task) -> String {
        let status = task.status == .completed ? "completed" : "active"
        let abandoned = task.isAbandoned ? "abandoned" : "normal"
        return group.id + ":" + task.id.uuidString + ":" + status + ":" + abandoned
    }

    private var taskOutlineRows: [NativeTaskOutline.Row] {
        var rows: [NativeTaskOutline.Row] = []
        let currentGroups = groups
        // 空态**不在这里占行**。原来它是 outline 的第一行，于是跟着列表顶部走：
        // 实测整块墨迹 y 162..297pt、中心 229.5pt，而列表可视区（y 130..892）中心
        // 是 511pt——高了 281pt，不是"没调好"而是"排错位置"。现在由
        // `TaskOutlineHost` 以覆盖层画在列表区正中，见那里的注释。
        for group in currentGroups {
            if group.kind != .plain || group.label != nil {
                let section = isSectionGroup(group)
                let topGap = TaskListMetrics.headerTopGap(isSection: section)
                let headerHeight = TaskListMetrics.groupHeaderHeight(isSection: section)
                let header = TaskOutlineHeaderState(revision: workspace.revision, title: groupTitle(group),
                    count: group.tasks.count, collapsed: groupExpansion.isCollapsed(group),
                    hoveredGroupID: hoveredGroupID,
                    menuOpen: activeSectionMenuID != nil && activeSectionMenuID == group.sectionID,
                    moveTarget: moveTargetSectionID)
                rows.append(.init(id: "header:" + group.id, state: header, layout: "header",
                                  height: topGap + headerHeight) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: topGap)
                            .accessibilityHidden(true)
                        groupHeader(group)
                    }.environmentObject(environment)
                })
            }
            if (group.kind == .plain && group.label == nil) || !groupExpansion.isCollapsed(group) {
                // 已完成组分页（滴答 `countToShowOfCompleted`）：先给一页，
                // 其余由行尾的「显示更多」按页追加。
                let allNodes = displayedNodes(for: group, scope: scope ?? .today)
                let limit = visibleCompletedLimit(for: group)
                let nodes = allNodes.count > limit ? Array(allNodes.prefix(limit)) : allNodes
                for node in nodes {
                    let preview = TaskListViewDefaults.bodyPreview(of: node.task.document)
                    let state = TaskOutlineRowState(task: node.task, depth: node.depth,
                        hasChildren: node.hasChildren, expanded: node.expanded,
                        selected: workspace.selectedTaskID == node.task.id || workspace.bulkSelection.contains(node.task.id),
                        recentlyCreated: workspace.recentlyCreatedTaskIDs.contains(node.task.id),
                        showsListBadge: showsListBadge,
                        hidesDetails: environment.viewPreferences.hidesDetails(for: preferenceKey),
                        hiddenFields: environment.viewPreferences.hiddenDetailFields(for: preferenceKey),
                        allowsReordering: sortMode == .manual && !node.task.isClosed && !workspace.isListArchived(node.task.list.name),
                        progress: workspace.checklistProgress(for: node.task)
                            ?? workspace.subtaskProgress(for: node.task.id),
                        day: workspace.calendar.startOfDay(for: workspace.clock()), dateRevision: workspace.dateRevision)
                    let hasTags = !state.hidesDetails && !state.hiddenFields.contains(.tags)
                        && !node.task.tags.isEmpty
                    let layout = TaskOutlineRowLayout(hasPreview: preview != nil, hasTags: hasTags,
                        completed: node.task.status == .completed, depth: node.depth)
                    rows.append(.init(id: rowIdentity(group: group, task: node.task), state: state,
                                      layout: layout,
                                      height: TaskListMetrics.taskRowHeight(hasPreview: preview != nil,
                                                                            hasTags: hasTags)) {
                        taskRow(group: group, node: node).environmentObject(environment)
                    })
                }
                if allNodes.count > nodes.count {
                    let remaining = allNodes.count - nodes.count
                    let loading = loadingCompletedGroupIDs.contains(group.id)
                    rows.append(.init(id: "loadMore:" + group.id,
                                      state: "loadMore:\(remaining):\(loading)",
                                      layout: "loadMore",
                                      height: TaskListMetrics.loadMoreRowHeight) {
                        Button { loadMoreCompleted(in: group) } label: {
                            HStack(spacing: 6) {
                                if loading {
                                    ProgressView().controlSize(.small)
                                }
                                Text(loading ? "正在加载…" : "显示更多（还有 \(remaining) 条）")
                                    .font(WFType.supporting)
                                    .foregroundStyle(WFColors.accent)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: TaskListMetrics.loadMoreRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(loading)
                        .accessibilityLabel("显示更多已完成任务，还有 \(remaining) 条")
                    })
                }
            }
        }
        rows.append(.init(id: "bottom-inset", state: "inset", layout: "inset",
                          height: WFSpace.xl) {
            Color.clear.frame(height: WFSpace.xl).accessibilityHidden(true)
        })
        return rows
    }

    /// 「更多」：把焦点交给右侧完整面板。批量面板是按 `bulkSelection` 投影的，
    /// 这里只需保证列表区不再抢焦点。
    private func openBatchPanel() {
        listFocused = false
        quickAddFocused = false
    }

    private func taskListSection() -> some View {
        TaskOutlineHost(store: environment.countdownStore,
                        clock: workspace.clock, calendar: workspace.calendar,
                        destination: navigation.destination,
                        includesCountdown: scope == .today,
                        tasksAreEmpty: groups.isEmpty,
                        collapsed: countdownSectionCollapsed,
                        onToggle: { countdownSectionCollapsed.toggle() },
                        onSelect: { _ in navigation.destination = .countdown },
                        emptyActionTitle: emptyStateAction?.title,
                        emptyAction: emptyStateAction?.perform,
                        rows: taskOutlineRows, scopeKey: preferenceKey, onKey: handleOutlineKey)
        .focusable(!editingRowTitle)
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { handleOutlineKey(.up) ? .handled : .ignored }
        .onKeyPress(.downArrow) { handleOutlineKey(.down) ? .handled : .ignored }
        .onKeyPress(.return) { handleOutlineKey(.enter) ? .handled : .ignored }
        .onKeyPress(.space) { handleOutlineKey(.space) ? .handled : .ignored }
        .onKeyPress(.escape) { handleOutlineKey(.escape) ? .handled : .ignored }
    }

    private func handleOutlineKey(_ key: TaskOutlineKey) -> Bool {
        guard !nativeTextEditing else { return false }
        switch key {
        case .up, .down:
            guard !quickAddFocused, scope != nil else { return false }
            selectFiltered(key == .up ? -1 : 1)
        case .enter:
            guard !quickAddFocused, scope != nil, workspace.bulkSelection.isEmpty else { return false }
            if workspace.selectedTaskID == nil { selectFiltered(1) }
        case .space:
            guard !quickAddFocused, workspace.bulkSelection.isEmpty,
                  let task = workspace.selectedTask else { return false }
            _ = workspace.changeStatus(task, in: scope)
        case .escape:
            if !workspace.bulkSelection.isEmpty { workspace.clearBulkSelection() }
            else if workspace.selectedTaskID != nil { workspace.select(nil) }
            else { return false }
        }
        return true
    }

    @ViewBuilder
    private func taskRow(group: TaskListGroup, node: TaskTreeNode) -> some View {
        let isSelected = workspace.selectedTaskID == node.task.id
            || workspace.bulkSelection.contains(node.task.id)
        let row = TaskRowView(
                task: node.task,
                workspace: workspace,
                depth: node.depth,
                hasChildren: node.hasChildren,
                expanded: node.expanded,
                selected: isSelected,
                recentlyCreated: workspace.recentlyCreatedTaskIDs.contains(node.task.id),
                showsListBadge: showsListBadge,
                hidesDetails: environment.viewPreferences.hidesDetails(for: preferenceKey),
                hiddenFields: environment.viewPreferences.hiddenDetailFields(for: preferenceKey),
                allowsReordering: sortMode == .manual && !node.task.isClosed && !workspace.isListArchived(node.task.list.name),
                onTitleEditingRequested: {
                    editingRowTitle = true
                    quickAddFocused = false
                    descriptionFocused = false
                    listFocused = false
                },
                onTitleEditingBegan: { editingRowTitle = true },
                onTitleEditingEnded: { editingRowTitle = false },
                // 进入标题编辑的同时打开详情；再次点击仍保留当前任务。
                onSelect: {
                    workspace.clearBulkSelection()
                    workspace.select(node.task.id)
                },
                onBulkToggle: { id in
                    listFocused = true
                    workspace.toggleBulkSelection(id, carryingSelection: true)
                },
                onRangeSelect: { id in
                    listFocused = true
                    if workspace.bulkSelection.isEmpty {
                        // S0 上的 Shift 等价普通点击：没有锚点就没有范围可言。
                        workspace.select(id)
                    } else {
                        workspace.extendBulkSelection(to: id, in: visibleRowOrder())
                    }
                },
                onComplete: { _ = workspace.complete(node.task.id, in: scope) },
                onRestore: { _ = workspace.restore(node.task.id, in: scope) },
                onToggleExpanded: { workspace.toggleExpanded(node.task.id) }
            )
            // 行分割线：画在行内底边，不给行距加高度（原来它是 LazyVStack 的
            // 兄弟视图，每行多出 1pt，pitch 实测 51 而不是 50）。
            // 滴答实测：所有行都从标题起点起画，右端收进 16pt（选中行不画）。
            //
            // **选中行不画**：选中行有自己的圆角底色和一圈焦点环，而 `.overlay`
            // 画在 `.background` 之上，这条线会横穿底边——实测底边只剩左右两个
            // 圆角是蓝的、中间被 #F4F4F4 盖住，看着就像「下面一半不是同一个蓝」。
            // 滴答在选中行上也不画它自己那条线（实测选中行上下都没有分割线）。
            .overlay(alignment: .bottom) {
                if !isSelected {
                    ListRowDivider(
                        leading: TaskListMetrics.dividerLeading(completed: node.task.status == .completed,
                                                                depth: node.depth),
                        trailing: WFSpace.lg)
                }
            }
        if sortMode == .manual && !node.task.isClosed && !workspace.isListArchived(node.task.list.name) {
            row
                .modifier(TaskReorderDropModifier(workspace: workspace, targetID: node.task.id,
                                                  depth: node.depth, feedback: dropFeedback))
                .id(rowIdentity(group: group, task: node.task))
        } else {
            row.id(rowIdentity(group: group, task: node.task))
        }
    }

    private var quickAddResult: QuickAddParseResult {
        QuickAddParser.parse(draft, now: workspace.clock(), calendar: workspace.calendar,
                             knownLists: Set(workspace.availableListNames),
                             dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private var hasDismissedQuickAddScheduleToken: Bool {
        QuickAddParser.hasDismissedScheduleToken(in: draft, now: workspace.clock(),
            calendar: workspace.calendar, knownLists: Set(workspace.availableListNames),
            dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private func currentQuickAddSchedule(for scope: TaskListScope) -> QuickAddScheduleDraft {
        // 时间型视图默认排期到"那一天"（今天 / 最近 7 天 = 当天，明天 = 次日），
        // 对齐 Flutter「Time-based views keep the default-today behaviour」；收集箱不注入。
        QuickAddScheduleDraft(parsed: quickAddResult,
                              defaultDueAt: hasDismissedQuickAddScheduleToken
                                ? nil : quickAddDefaultDue(for: scope))
    }

    /// 时间型视图的快速添加默认排期：今天 / 最近 7 天 = 当天，明天 = 次日，其余不注入。
    private func quickAddDefaultDue(for scope: TaskListScope) -> Date? {
        switch scope {
        case .today, .nextSevenDays: return workspace.dateFromToday(0)
        case .tomorrow: return workspace.dateFromToday(1)
        default: return nil
        }
    }

    private func addTask(in scope: TaskListScope) {
        let capture = QuickCaptureSession(text: draft, description: descriptionDraft,
            dismissedTokenIDs: dismissedQuickAddTokens, scheduleOverride: quickAddScheduleOverride,
            priorityOverride: quickAddPriorityOverride, listOverride: quickAddListOverride,
            tagsOverride: quickAddTagsOverride)
        let createdIDs = workspace.submitCapture(capture, defaultDueAt: quickAddDefaultDue(for: scope), selectCreatedTask: false)

        // Keep the draft available if creation is rejected; Flutter follows
        // the same rule and only resets after TaskCreator reports success.
        guard let firstID = createdIDs.first else { return }
        // 属性菜单里选的附件在创建成功后挂到新任务（批量时其余行不带附件）。
        if !quickAddAttachments.isEmpty, let task = workspace.task(for: firstID) {
            workspace.setAttachments(firstID, task.attachments + quickAddAttachments)
        }
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
    // The owning list supplies row changes; actions still use the shared model.
    let workspace: TaskWorkspaceModel
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    var recentlyCreated: Bool = false
    var showsListBadge: Bool = true
    /// 隐藏详细 / 详细行里被关掉的字段（滴答「显示设置」）。
    var hidesDetails: Bool = false
    var hiddenFields: [TaskRowDetailField] = []
    var allowsReordering: Bool = false
    var onTitleEditingRequested: (() -> Void)? = nil
    var onTitleEditingBegan: (() -> Void)? = nil
    var onTitleEditingEnded: (() -> Void)? = nil
    let onSelect: () -> Void
    /// Cmd+点击（进入/切换批量选中）。nil 时（渲染契约等宿主）退回普通选中。
    var onBulkToggle: ((UUID) -> Void)? = nil
    /// Shift+点击（从锚点延伸范围）。nil 时退回普通选中。
    var onRangeSelect: ((UUID) -> Void)? = nil
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onToggleExpanded: () -> Void
    @State private var pointer = TaskRowPointerState()
    @StateObject private var titleHandle = TaskRowTitleHandle()
    @State private var showDatePopover = false
    @State private var contextDateAnchor: CGRect?
    /// 完成瞬间的划线扫过：0 → 1 划入，之后淡出（不是常驻划线——
    /// Flutter / 滴答的完成态都只置灰，这里只补「划一下」的手势反馈）。
    @State private var strikeSweep: CGFloat = 0
    @State private var strikeOpacity: Double = 0
    private var readOnly: Bool { workspace.isListArchived(task.list.name) }

    private var showsTagRow: Bool {
        !hidesDetails && !hiddenFields.contains(.tags) && !task.tags.isEmpty
    }

    var body: some View {
        let rowHeight = TaskListMetrics.taskRowHeight(hasPreview: rowPreview != nil,
                                                      hasTags: showsTagRow)
        return HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .leading) {
                    if depth == 0 && hasChildren {
                        Button(action: onToggleExpanded) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .hoverTip(expanded ? "收起子任务" : "展开子任务")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: TaskListMetrics.leadingGutter, height: TaskListMetrics.checkboxSize)
                .taskTreeRenderAnchor(task.id, .disclosure)
                Button(action: task.isClosed ? onRestore : onComplete) {
                    TaskRowCompletionBox(task: task)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverTip(task.isClosed ? "恢复任务" : "完成任务")
                .disabled(readOnly)
                .accessibilityLabel(task.isClosed ? "恢复：\(task.title)" : "完成：\(task.title)")
                .frame(width: TaskListMetrics.checkboxSize, height: TaskListMetrics.checkboxSize)
                .taskTreeRenderAnchor(task.id, .checkbox)
            }
            .padding(.trailing, TaskListMetrics.checkboxTitleGap)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: WFSpace.sm) {
                    if readOnly {
                        Text(task.title).foregroundStyle(WFColors.text)
                            .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                            .frame(height: 18)
                    } else {
                    TaskRowTitleField(title: task.title,
                                      color: task.status == .completed ? WFColors.taskCompletedTitle : task.isClosed ? WFColors.secondaryText : WFColors.text,
                                      handle: titleHandle,
                                      onEditingRequested: {
                                          onTitleEditingRequested?()
                                          onSelect()
                                      },
                                      onEditingBegan: { onTitleEditingBegan?() },
                                      onEditingEnded: { onTitleEditingEnded?() },
                                      onCommit: { _ = workspace.setTitle(task.id, $0) })
                        .frame(minWidth: 96, maxWidth: .infinity)
                        .frame(height: 18)
                        .taskTreeRenderAnchor(task.id, .title)
                    }
                    TaskRowMetadataTrail(task: task, workspace: workspace,
                                         showsListBadge: showsListBadge,
                                         hidesDetails: hidesDetails,
                                         hiddenFields: hiddenFields,
                                         onOpenDate: { contextDateAnchor = nil; showDatePopover = true })
                        .allowsHitTesting(!readOnly)
                }
                if let preview = rowPreview {
                    Text(preview)
                        .font(task.status == .completed ? WFType.completedTaskPreview : WFType.taskPreview)
                        .lineLimit(1)
                        .foregroundStyle(task.status == .completed ? WFColors.taskCompletedPreview : WFColors.taskPreviewText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)
                        .taskTreeRenderAnchor(task.id, .preview)
                }
                if showsTagRow {
                    tagRow.padding(.top, TaskListMetrics.tagRowSpacing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: WFMetrics.rowContentMinHeight, alignment: .topLeading)
            .overlay(alignment: .leading) {
                // 完成反馈的划线：横穿标题中线扫过一遍，随后淡出。
                GeometryReader { geo in
                    Rectangle()
                        .fill(WFColors.taskCompletedTitle)
                        .frame(width: geo.size.width * strikeSweep, height: 1.25)
                        .position(x: geo.size.width * strikeSweep / 2, y: 9)
                }
                .opacity(strikeOpacity)
                .allowsHitTesting(false)
            }
        }
        // 对齐滴答：标题/勾选框都从行顶 +10 起，基础行 40。
        .padding(.vertical, TaskListMetrics.rowVerticalPadding)
        .padding(.leading, CGFloat(depth) * TaskListMetrics.hierarchyIndent
            + TaskListMetrics.rowContentLeading)
        .padding(.trailing, TaskListMetrics.rowTrailingPadding)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .topLeading)
        // 选中底色用中性灰（`listSelection`，滴答实测 #F2F2F2），不用强调色。
        // 行底色铺满 Cell 宿主；宿主左右的 18 / 1pt 内边距决定与列表边界的距离。
        .rowHoverBackground(selected: selected || recentlyCreated,
                            horizontalInset: 0,
                            onHoverChanged: { pointer.update($0) })
        // 整行可点（含左右内缩留白）：标题旁的留白、行内空隙、元数据区点下去也能选中；
        // 行内按钮（勾选框/日期）优先级更高。
        .contentShape(Rectangle())
        .gesture(selectionGesture)
        .modifier(TaskRowActivationPolicy())
        // 完成反馈（对齐滴答）：提示音 + 划线扫过。恢复不播——滴答恢复是静默的。
        .onChange(of: task.status == .completed) { _, completed in
            guard completed, !task.isAbandoned else { return }
            TaskCompletionFeedback.play()
            strikeSweep = 0
            strikeOpacity = 1
            withAnimation(.easeOut(duration: 0.26)) { strikeSweep = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeIn(duration: 0.25)) { strikeOpacity = 0 }
            }
        }
        .taskTreeRenderAnchor(task.id, .row)
        // 滴答的拖拽柄在行背景左侧的留白里（14×14，行左 +1），悬停才出现。
        .overlay(alignment: .leading) {
            if allowsReordering {
                TaskRowReorderHandle(taskID: task.id, title: task.title, selected: selected,
                                     pointer: pointer)
                    .padding(.leading, 1 + CGFloat(depth) * TaskListMetrics.hierarchyIndent)
                    .offset(x: -(TaskListMetrics.outlineLeadingInset - WFSpace.xs))
            }
        }
        .overlay {
            // Context-origin scheduling is anchored to this click, including
            // tasks without a date badge. It must not borrow the whole row.
            SecondaryClickCapture { rowView, point in
                guard !readOnly else { return }
                guard let current = workspace.task(for: task.id) else { return }
                TaskContextMenuPresenter.show(in: rowView, at: point,
                                              environment: environment,
                                              workspace: workspace, task: current,
                                              onCustomDate: {
                                                  contextDateAnchor = CGRect(origin: point, size: CGSize(width: 1, height: 1))
                                                  showDatePopover = true
                                              })
            }
        }
        .schedulePopover(isPresented: $showDatePopover, explicitAnchor: contextDateAnchor) {
            if let current = workspace.task(for: task.id) {
                TaskDatePopoverV2(task: current, workspace: workspace) { showDatePopover = false }
            }
        }
    }

    /// Each recognizer owns the modifiers of its own click. Do not infer them
    /// from NSApp.currentEvent after SwiftUI has completed the gesture.
    private var selectionGesture: some Gesture {
        TapGesture().modifiers(.command).onEnded {
            if let onBulkToggle { onBulkToggle(task.id) } else { onSelect() }
        }
        .exclusively(before: TapGesture().modifiers(.shift).onEnded {
            if let onRangeSelect { onRangeSelect(task.id) } else { onSelect() }
        })
        .exclusively(before: TapGesture().onEnded { if readOnly { onSelect() } else { titleHandle.beginEditing() } })
    }

    /// Folding hides children; only this task's own body supplies its preview.
    /// 标签行：标题下方一排只读胶囊（滴答把任务的标签直接画在列表行里）。
    /// 只读——编辑仍在详情 / 右键菜单里，行内不做第二个标签编辑入口。
    private var tagRow: some View {
        let visible = Array(task.tags.prefix(TaskListMetrics.maxVisibleTags))
        let overflow = task.tags.count - visible.count
        return HStack(spacing: 2) {
            ForEach(visible, id: \.self) { name in
                tagChip(name)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("标签：" + task.tags.joined(separator: "、"))
    }

    private func tagChip(_ name: String) -> some View {
        let color = workspace.tag(named: name)?.colorARGB.map(WFListPalette.swatch)
        return Text(name)
            .font(.system(size: 11))
            .foregroundStyle(color ?? WFColors.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: TaskListMetrics.tagChipHeight)
            .background(color?.opacity(0.1) ?? WFColors.hover, in: Capsule())
    }

    private var rowPreview: String? {
        TaskListViewDefaults.bodyPreview(of: task.document)
    }

}

struct TaskRowActivationPolicy: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.allowsWindowActivationEvents()
        } else {
            content
        }
    }
}

/// 优先级配色（列表行的旗子与看板卡片共用同一份）。
enum TaskRowPriority {
    /// 文案统一取领域类型的 `title`，不再在这里维护第二份表。
    static func title(_ priority: TaskPriority) -> String { priority.title }

    /// 颜色只有一处真源：`TaskPriority.menuColor`（设计系统）。
    static func color(_ priority: TaskPriority) -> Color { priority.menuColor }
}

/// 勾选框对齐滴答实机：19×19 命中格，17×17 描边盒，圆角约 4.3，描边 1.5。
/// 描边按优先级着色；完成后中性灰填充，白勾，不再使用强调色。
struct TaskRowCompletionBox: View {
    let task: Task
    /// 勾选瞬间对勾从 0.4 弹到 1（spring）；初始 true，已完成的行首次渲染就是全尺寸。
    @State private var checkPop = true

    var body: some View {
        content
            .onChange(of: task.isClosed) { _, closed in
                guard closed, !task.isAbandoned else { return }
                checkPop = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkPop = true }
            }
    }

    @ViewBuilder
    private var content: some View {
        if task.isAbandoned {
            Image(systemName: "circle.slash")
                .font(.system(size: 15))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: TaskListMetrics.checkboxSize, height: TaskListMetrics.checkboxSize)
        } else if task.isClosed {
            RoundedRectangle(cornerRadius: 4.3)
                .fill(WFColors.taskCompletedCheckbox)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(checkPop ? 1 : 0.4)
                }
                .frame(width: 17, height: 17)
                .frame(width: TaskListMetrics.checkboxSize, height: TaskListMetrics.checkboxSize,
                       alignment: .leading)
        } else {
            RoundedRectangle(cornerRadius: 4.3)
                .stroke(TaskRowPriority.color(task.priority), lineWidth: 1.5)
                .frame(width: 17, height: 17)
                .frame(width: TaskListMetrics.checkboxSize, height: TaskListMetrics.checkboxSize,
                       alignment: .leading)
        }
    }
}

/// Edge drops reorder; root centers accept children; the left gutter promotes
/// a child to a root. The feedback distinguishes ordering from hierarchy changes.
private struct TaskReorderDropModifier: ViewModifier {
    let workspace: TaskWorkspaceModel
    let targetID: UUID
    let depth: Int
    @ObservedObject var feedback: TaskDropFeedback
    @State private var rowHeight: CGFloat = WFMetrics.rowHeight

    private var placement: TaskDropPlacement? {
        feedback.target?.rowID == targetID ? feedback.target?.placement : nil
    }

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.onAppear { rowHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in rowHeight = height }
            })
            .onDrop(of: [UTType.utf8PlainText], delegate: TaskReorderDropDelegate(
                workspace: workspace, targetID: targetID, depth: depth,
                rowHeight: rowHeight, feedback: feedback))
            .onDisappear { feedback.exit(rowID: targetID) }
            .overlay {
                Group {
                switch placement {
                case .childOf:
                    RoundedRectangle(cornerRadius: WFMetrics.corner)
                        .stroke(WFColors.accent.opacity(0.45), lineWidth: 1)
                        .overlay(alignment: .bottomTrailing) {
                            Text("作为子任务").font(.system(size: 10)).foregroundStyle(WFColors.secondaryText).padding(3)
                        }
                case .before, .rootBefore:
                    VStack { TaskDropMarker(); Spacer(minLength: 0) }
                case .after, .rootAfter:
                    VStack { Spacer(minLength: 0); TaskDropMarker() }
                case nil:
                    EmptyView()
                }
                }
                .allowsHitTesting(false)
            }
    }
}

/// 行尾右对齐的元数据：清单、优先级旗标、截止、描述/提醒等小图标与日期徽标
/// 全部常驻（与迁移版一致），悬浮时快捷操作在尾栏右侧追加，不替换任何元素。
/// 日期徽标颜色：今天=强调色、过期=红色、其余=灰色。
private struct TaskRowMetadataTrail: View {
    let task: Task
    let workspace: TaskWorkspaceModel
    var showsListBadge: Bool
    /// 「隐藏详细」整行隐藏；`hiddenFields` 在此基础上逐字段关闭。
    var hidesDetails: Bool = false
    var hiddenFields: [TaskRowDetailField] = []
    let onOpenDate: () -> Void
    @AppStorage(TaskDateDisplayMode.defaultsKey) private var dateDisplayRaw =
        TaskDateDisplayMode.taskTime.rawValue

    private var dateDisplay: TaskDateDisplayMode {
        TaskDateDisplayMode(rawValue: dateDisplayRaw) ?? .taskTime
    }

    private var deadlineOverdue: Bool {
        guard let deadline = task.schedule.deadlineAt, !task.isClosed else { return false }
        return workspace.calendar.startOfDay(for: deadline) <= workspace.calendar.startOfDay(for: workspace.clock())
    }

    private var dateStyle: TaskListViewDefaults.DateBadgeStyle {
        TaskListViewDefaults.dateBadgeStyle(dueAt: task.schedule.dueAt,
                                            dueEndAt: task.schedule.dueEndAt,
                                            hasTime: task.schedule.hasTime,
                                            isClosed: task.isClosed,
                                            now: workspace.clock(), calendar: workspace.calendar)
    }

    private var muted: Color {
        task.status == .completed ? WFColors.taskCompletedMetadata : task.isClosed ? WFColors.tertiaryText : WFColors.taskMetaText
    }

    var body: some View {
        if hidesDetails {
            EmptyView()
        } else {
            trail
        }
    }

    @ViewBuilder
    private var trail: some View {
        HStack(spacing: 3) {
            if task.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(task.isClosed ? muted : WFColors.accent)
                    .accessibilityLabel("已置顶")
            }
            if task.isAbandoned { Text("已放弃").foregroundStyle(muted) }
            if showsListBadge, !hiddenFields.contains(.list), task.list.name != TaskList.inbox.name {
                // 清单名最先被压缩：低优先级 + 40pt 上限，把宽度让给日期。
                Text(task.list.name).lineLimit(1)
                    .frame(maxWidth: 40).foregroundStyle(muted).layoutPriority(-1)
            }
            // 滴答行内不画优先级旗：优先级由勾选框描边和详情/右键菜单表达。
            if !hiddenFields.contains(.indicators) {
                ForEach(Array(secondaryMetadata.prefix(WFMetrics.secondaryMetadataLimit))) { item in
                    if let value = item.value {
                        Text(value).foregroundStyle(muted)
                            .hoverTip(item.accessibilityLabel)
                            .accessibilityLabel(item.accessibilityLabel)
                    } else if let symbol = item.symbol {
                        Image(systemName: symbol)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(muted)
                            .hoverTip(item.accessibilityLabel)
                            .accessibilityLabel(item.accessibilityLabel)
                    }
                }
            }
            if !hiddenFields.contains(.date), let deadline = task.schedule.deadlineAt {
                Text(TaskDateLabel.text(deadline, hasTime: false,
                                        now: workspace.clock(), calendar: workspace.calendar) + "截止")
                    .foregroundStyle(task.isClosed ? muted : deadlineOverdue ? .red : muted)
                    .layoutPriority(0)
            }
            if !hiddenFields.contains(.date), task.schedule.dueAt != nil {
                // 日期是行内最重要的元信息：固定尺寸不被压缩。
                dateBadge.fixedSize().layoutPriority(2)
            }
        }
        // 滴答行内元信息 10pt；日期仅显示文字，保留原有点击高度。
        .font(WFType.taskMeta)
        .lineLimit(1)
        .frame(maxWidth: 140, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var dateBadge: some View {
        Button { onOpenDate() } label: {
            Text(TaskListViewDefaults.scheduleLabel(
                dueAt: task.schedule.dueAt ?? Date(),
                dueEndAt: task.schedule.dueEndAt,
                hasTime: task.schedule.hasTime,
                now: workspace.clock(),
                calendar: workspace.calendar,
                dateDisplay: dateDisplay))
                .lineLimit(1)
                .frame(minHeight: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(task.isClosed ? muted : badgeColor)
        .help("修改安排日期")
        .accessibilityLabel("安排日期：\(task.title.isEmpty ? "无标题" : task.title)")
        .taskTreeRenderAnchor(task.id, .date)
        .scheduleTrigger()
    }

    private var badgeColor: Color {
        TaskListViewDefaults.rowDateColor(for: dateStyle)
    }

    private var secondaryMetadata: [TaskSecondaryMetadata] {
        TaskSecondaryMetadata.items(for: task, subtaskProgress: workspace.subtaskProgress(for: task.id),
                                    checklistProgress: workspace.checklistProgress(for: task))
            .filter { $0.id != "tags" }
    }
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

    static func headerSymbol(destination: NativeDestination, activeList: String?, activeTag: String?) -> String {
        if activeList != nil { return "list.bullet" }
        if activeTag != nil { return "tag" }
        if destination == .nextSevenDays { return "line.3.horizontal" }
        return destination.symbol
    }

    static func scheduleLabel(dueAt: Date, dueEndAt: Date? = nil, hasTime: Bool, now: Date,
                              calendar: Calendar,
                              dateDisplay: TaskDateDisplayMode = .taskTime) -> String {
        if dateDisplay == .countdown {
            // 时间段以结束为准：区间还在进行时不该出现「逾期」。
            return TaskDateLabel.text(dueEndAt ?? dueAt, hasTime: hasTime, now: now,
                                      calendar: calendar, display: .countdown)
        }
        guard hasTime else {
            return TaskDateLabel.text(dueAt, hasTime: false, now: now, calendar: calendar)
        }
        let time = calendar.dateComponents([.hour, .minute], from: dueAt)
        return String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }

    /// 子任务进度与 Flutter activeTasks 对齐：已完成子任务计入总数，已删除、跳过、
    /// 放弃或已转换成笔记的子任务不计入。
    static func subtaskProgress(parentID: UUID, tasks: [Task]) -> String? {
        let children = tasks.filter {
            $0.parentID == parentID && $0.deletedAt == nil && $0.skippedAt == nil &&
                !$0.isAbandoned && !$0.isConverted
        }
        guard !children.isEmpty else { return nil }
        let completed = children.filter { $0.status == .completed }.count
        return "\(completed)/\(children.count)"
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

    /// 时间段以结束日判定：进行中的区间仍是蓝/强调色，结束后才变红。
    static func dateBadgeStyle(dueAt: Date?, dueEndAt: Date? = nil, hasTime: Bool = false,
                               isClosed: Bool, now: Date, calendar: Calendar) -> DateBadgeStyle {
        guard let dueAt, !isClosed else { return .none }
        let end = dueEndAt ?? dueAt
        if ScheduleOverdue.isOverdue(date: end, hasTime: hasTime,
                                     now: now, calendar: calendar) { return .overdue }
        if calendar.startOfDay(for: end) == calendar.startOfDay(for: now) { return .today }
        return .scheduled
    }

    static func rowDateColor(for style: DateBadgeStyle) -> Color {
        switch style {
        case .overdue: .red
        case .today: WFColors.accent
        case .scheduled: WFColors.taskMetaText
        case .none: WFColors.taskCompletedMetadata
        }
    }

    /// 行内正文预览：取纯文本第一个非空行；正文为空返回 nil（不占预览行）。
    static func bodyPreview(of plainText: String) -> String? {
        for line in plainText.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Stop at the first nonempty block/line instead of joining the whole document.
    static func bodyPreview(of document: NativeDocument) -> String? {
        if !document.isLoaded { return document.firstLinePreview }
        for block in document.blocks {
            if let preview = bodyPreview(of: block.plainText) { return preview }
        }
        return nil
    }

    static func hasReminder(reminderAt: Date?, reminderOffsets: [Int]?) -> Bool {
        reminderAt != nil || !(reminderOffsets ?? []).isEmpty
    }
}

/// 「倒数纪念日」小节的宿主。**只为一件事存在——订阅 `CountdownStore`。**
///
/// 为什么不直接在 `TaskListView` 里读 `environment.countdownStore.events`：
/// `AppEnvironment` 只把自己 `@Published` 的变化发给 SwiftUI，**嵌套的 store 变了
/// 它不知道**，`@EnvironmentObject` 也拿不到嵌套对象的订阅。所以让一个声明了
/// `@ObservedObject` 的小视图去订阅——它自己建立订阅，**不需要额外的环境注入**，
/// 也就不必去动注入链（那条链上还有别的会话在改）。
///
/// 空态也归它管：任务组为空**且**本节为空时才渲染插画。两件事放一起是因为它们
/// 读的是同一个 `section`——分成两处就得算两遍，还可能算出不一致的结果
/// （出现「倒数纪念日 1」下面紧跟着「今天没有任务」）。
/// 清单「⋯」的条目表是 UI 契约：顺序与集合都显式声明，测试直接钉住。
enum TaskListMoreMenuEntry: Hashable {
    case viewModes
    case separator
    case hidesCompleted
    case detailsVisibility
    case displaySettings
}

enum TaskListMoreMenuPolicy {
    static let entries: [TaskListMoreMenuEntry] = [
        .viewModes, .separator, .hidesCompleted, .detailsVisibility, .displaySettings
    ]

    static func detailsTitle(hidesDetails: Bool) -> String {
        hidesDetails ? "显示详细" : "隐藏详细"
    }

    static func viewModeHelp(_ mode: TaskListViewMode) -> String {
        mode.title + "视图"
    }
}

/// 滴答列表「⋯」顶部的视图切换：三枚图标横排，选中蓝、悬停浅灰，名字只走 tooltip。
struct TaskListMenuViewModes: View {
    @Binding var selection: TaskListViewMode
    let options: [TaskListViewMode]
    /// 测试用：返回三枚图标的坐标。
    var onFrames: (([TaskListViewMode: CGRect]) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("视图").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, 10)
            HStack(spacing: 22) {
                ForEach(options) { mode in
                    TaskListMenuViewModeIcon(mode: mode, selected: selection == mode) {
                        selection = mode
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: TaskListMenuModeFrames.self,
                            value: [mode: geometry.frame(in: .named("task-list-menu-modes"))])
                    })
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
        .coordinateSpace(name: "task-list-menu-modes")
        .onPreferenceChange(TaskListMenuModeFrames.self) { onFrames?($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视图")
    }
}

struct TaskListMenuModeFrames: PreferenceKey {
    static var defaultValue: [TaskListViewMode: CGRect] = [:]
    static func reduce(value: inout [TaskListViewMode: CGRect],
                       nextValue: () -> [TaskListViewMode: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TaskListMenuViewModeIcon: View {
    let mode: TaskListViewMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TaskListMenuViewModeGlyph(mode: mode,
                                      color: selected ? WFColors.accent : WFColors.text)
                .frame(width: 32, height: 32)
                .background(hovering ? WFColors.hover : .clear,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(TaskListMoreMenuPolicy.viewModeHelp(mode))
        .accessibilityLabel(TaskListMoreMenuPolicy.viewModeHelp(mode))
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

/// 滴答三枚视图图标是自绘的填充条；SF Symbols 的描边图标观感差别明显。
private struct TaskListMenuViewModeGlyph: View {
    let mode: TaskListViewMode
    let color: Color

    var body: some View {
        Canvas { context, _ in
            switch mode {
            case .list:
                for row in 0..<3 {
                    let y = 3.5 + CGFloat(row) * 5.5
                    context.fill(Path(ellipseIn: CGRect(x: 1, y: y + 0.5, width: 2, height: 2)),
                                 with: .color(color))
                    context.fill(Path(roundedRect: CGRect(x: 6, y: y, width: 12, height: 2.5),
                                      cornerRadius: 1.25), with: .color(color))
                }
            case .kanban:
                for column in 0..<3 {
                    let x = 2 + CGFloat(column) * 6
                    context.fill(Path(roundedRect: CGRect(x: x, y: 2, width: 3.5, height: 14),
                                      cornerRadius: 1.75), with: .color(color))
                }
            case .timeline:
                let bars: [(x: CGFloat, y: CGFloat)] = [(5, 2.5), (1, 7.5), (5, 12.5)]
                for bar in bars {
                    context.fill(Path(roundedRect: CGRect(x: bar.x, y: bar.y, width: 11, height: 2.5),
                                      cornerRadius: 1.25), with: .color(color))
                }
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct TaskOutlineHost: View {
    @ObservedObject var store: CountdownStore
    let clock: () -> Date
    let calendar: Calendar
    let destination: NativeDestination
    let includesCountdown: Bool
    let tasksAreEmpty: Bool
    let collapsed: Bool
    let onToggle: () -> Void
    let onSelect: (UUID) -> Void
    /// 空态的下一步动作（滴答 `actionButtonHandler`）：文案 + 点击。
    var emptyActionTitle: String? = nil
    var emptyAction: (() -> Void)? = nil
    let rows: [NativeTaskOutline.Row]
    let scopeKey: String
    let onKey: (TaskOutlineKey) -> Bool

    var body: some View {
        let section = includesCountdown
            ? CountdownSmartListProjection.section(events: store.events, now: clock(), calendar: calendar)
            : .empty
        let showsCountdown = includesCountdown && !section.isEmpty
        var prefix: [NativeTaskOutline.Row] = []
        if showsCountdown {
            let state = TaskOutlineCountdownState(section: section, collapsed: collapsed)
            let height = TaskListMetrics.groupTopGap + TaskListMetrics.sectionHeaderHeight
                + (collapsed ? 0 : CGFloat(section.entries.count) * TaskListMetrics.countdownRowHeight)
            prefix.append(.init(id: "countdown-section", state: state, layout: state, height: height) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: TaskListMetrics.groupTopGap)
                        .accessibilityHidden(true)
                    CountdownSmartListSectionView(section: section, collapsed: collapsed,
                                                  onToggle: onToggle, onSelect: onSelect)
                }
            })
        }
        // 空态走 `.overlay` 而不是 outline 的一行：outline 每行的高度由
        // `Row.height` 显式给出，行内拿不到"剩余高度"，想靠
        // `.frame(maxHeight: .infinity)` 居中会得到一个和内容一样高的框——
        // 这也是它原先只能贴顶的原因。覆盖层的尺寸跟着主视图（滚动视图＝列表可视区），
        // 默认 `.center` 对齐，于是插画+文案天然落在列表区正中。
        // 今天页多一个前提：倒数纪念日小节非空时优先显示小节，不显示空态
        // （原来这两支是 if/else if，合成 `!showsCountdown` 后语义不变）。
        return NativeTaskOutline(rows: prefix + rows, scopeKey: scopeKey, onKey: onKey)
            .overlay {
                if tasksAreEmpty && !showsCountdown {
                    TaskEmptyStateView(style: .list,
                                       message: TaskListViewDefaults.emptyStateMessage(destination: destination),
                                       actionTitle: emptyActionTitle, action: emptyAction)
                }
            }
    }
}
