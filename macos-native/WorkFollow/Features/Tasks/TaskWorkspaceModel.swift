import Combine
import Foundation

/// Presentation adapter: owns view-only selection/expansion state and routes
/// every mutation through TaskActions and every list shape through projections.
@MainActor
final class TaskWorkspaceModel: ObservableObject {
    static let inspectorLists = [
        TaskList.inbox,
        TaskList(name: "工作"),
        TaskList(name: "学习"),
        TaskList(name: "个人")
    ]

    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var collapsedTaskIDs: Set<UUID> = []
    @Published private(set) var pendingChildTitleEditorID: UUID?
    @Published private(set) var revision = 0
    /// Invalidates date-derived projections and labels without treating time
    /// passing as a task mutation or scheduling a persistence write.
    @Published private(set) var dateRevision = 0
    @Published private(set) var taskListPaneWidth = WFMetrics.listPreferred
    @Published var activeList: String?
    @Published var activeTag: String?
    @Published var activeFilterID: UUID?
    @Published var bulkSelection: Set<UUID> = []
    @Published private(set) var bulkAnchorTaskID: UUID?

    private let store: WorkspaceStore
    private let actions: TaskActions
    /// 反馈出口（A3 HUD 反馈迁移），由 AppEnvironment 注入；为 nil 时动作照常执行、只是不弹 HUD。
    weak var feedbackSink: FeedbackCenter?
    private var filterStore: FilterStore?
    private var filterCancellable: AnyCancellable?
    let clock: () -> Date
    let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         seedDemoData: Bool = true, initialTasks: [Task]? = nil, initialLists: [String] = [],
         initialListMeta: [TaskListMeta]? = nil) {
        self.clock = clock
        self.calendar = calendar
        let store = WorkspaceStore()
        self.store = store
        self.actions = TaskActions(store: store, clock: clock, calendar: calendar)
        if let initialTasks { store.commit(initialTasks); store.clearUndo() }
        else if seedDemoData { seed() }
        store.commit(store.tasks, lists: initialLists, listMetas: initialListMeta)
        store.clearUndo()
    }

    var listNames: [String] {
        Array(Set(store.lists + allTasks.map { $0.list.name })).filter { $0 != TaskList.inbox.name }.sorted()
    }

    func refreshDates() {
        dateRevision += 1
    }

    var allListNames: [String] { [TaskList.inbox.name] + listNames }
    var tagNames: [String] { Array(Set(allTasks.flatMap(\.tags))).sorted() }

    // MARK: 清单元数据（Round B1 加法）

    /// 侧栏清单显示顺序（对齐 Flutter orderedLists）：置顶在前，其余按 meta
    /// sortOrder、再按名字；未注册/无 meta 的清单按字典序排在后面。
    var orderedListNames: [String] {
        _ = revision
        return TaskListOrdering.ordered(listNames, metas: store.listMetas)
    }
    func listMeta(for name: String) -> TaskListMeta? {
        _ = revision
        return store.listMeta(for: name)
    }
    /// 全部清单 meta（持久化接线用：随快照的 taskListMeta 存取）。
    var listMetas: [TaskListMeta] {
        _ = revision
        return store.listMetas
    }
    /// 清单颜色（WFListPalette 下标，nil 清除显式色）。收集箱不可着色。
    @discardableResult
    func setListColor(_ name: String, colorIndex: Int?) -> Bool {
        let changed = actions.setListColor(name, colorIndex)
        if changed { revision += 1 }
        return changed
    }
    /// 置顶/取消置顶清单；侧栏置顶分组排在其余清单之前。
    @discardableResult
    func setListPinned(_ name: String, _ isPinned: Bool) -> Bool {
        let changed = actions.setListPinned(name, isPinned)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func saveList(_ raw: String, replacing old: String? = nil) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != TaskList.inbox.name,
              name == old || !allListNames.contains(name) else { return false }
        actions.renameList(old, to: name)
        if activeList == old { activeList = name }
        revision += 1
        return true
    }
    func removeList(_ name: String) {
        actions.removeList(name)
        if activeList == name { activeList = nil }
        revision += 1
    }
    func renameTag(_ old: String, to value: String?) {
        actions.renameTag(old, to: value)
        if activeTag == old { activeTag = value }
        revision += 1
    }

    /// Called once by AppEnvironment after both stores exist. Resolves
    /// `activeFilterID` through the store, refreshes projections when filter
    /// contents change, and clears the active filter if it is deleted anywhere.
    func attachFilterStore(_ store: FilterStore) {
        filterStore = store
        filterCancellable = store.$filters.sink { [weak self] filters in
            guard let self else { return }
            self.revision += 1
            if let activeFilterID = self.activeFilterID,
               !filters.contains(where: { $0.id == activeFilterID }) {
                self.activeFilterID = nil
            }
        }
    }

    func openFilter(_ id: UUID?) {
        activeFilterID = id
    }

    /// Deletes through the attached store and, mirroring `renameTag`, clears
    /// the active selection when the deleted filter was the active one.
    @discardableResult
    func deleteFilter(_ id: UUID) -> Bool {
        guard let filterStore, filterStore.delete(id) else { return false }
        if activeFilterID == id { activeFilterID = nil }
        return true
    }

    var activeFilter: SavedFilter? {
        guard let activeFilterID else { return nil }
        return filterStore?.filter(withID: activeFilterID)
    }
    func applyBulk(_ operation: TaskBatchOperation) {
        let count = bulkSelection.count
        let tasksBeforeBatch = store.tasks
        actions.batch(bulkSelection, operation: operation)
        clearBulkSelection()
        revision += 1
        reportBulk(operation, count: count, changed: store.tasks != tasksBeforeBatch)
        if selectedTask?.deletedAt != nil { select(nil) }
    }

    func setBulkSelected(_ id: UUID, _ selected: Bool) {
        if selected { bulkSelection.insert(id) } else { bulkSelection.remove(id) }
        bulkAnchorTaskID = id
    }

    func toggleBulkSelection(_ id: UUID) {
        if !bulkSelection.insert(id).inserted { bulkSelection.remove(id) }
        bulkAnchorTaskID = id
    }

    func setBulkSelection(in order: [UUID]) {
        bulkSelection = Set(order)
        bulkAnchorTaskID = order.first
    }

    func extendBulkSelection(to id: UUID, in order: [UUID]) {
        guard let anchor = bulkAnchorTaskID,
              let start = order.firstIndex(of: anchor),
              let end = order.firstIndex(of: id) else {
            bulkSelection.insert(id)
            return
        }
        bulkSelection.formUnion(order[min(start, end)...max(start, end)])
    }

    func clearBulkSelection() {
        bulkSelection.removeAll()
        bulkAnchorTaskID = nil
    }

    /// One session-wide width is shared by task lists and task trash, matching
    /// the Flutter workspace UI state without mixing presentation into task data.
    func setTaskListPaneWidth(_ width: CGFloat) {
        guard width.isFinite, taskListPaneWidth != width else { return }
        taskListPaneWidth = min(max(width, WFMetrics.listMinimum), WFMetrics.listMaximum)
    }

    func selectFromKeyboard(_ id: UUID) {
        clearBulkSelection()
        select(id)
    }
    /// 复制任务（Flutter 的"复制任务"）：连同子任务生成副本，HUD 带一步撤销。
    func duplicate(_ id: UUID) {
        let result = actions.duplicate(id)
        didMutate(result)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .success, message: "已复制\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
    }
    func skip(_ id: UUID) { didMutate(actions.skipOccurrence(id)); select(nil) }
    func reorder(_ id: UUID, before target: UUID) { actions.reorder(id, before: target); revision += 1 }
    /// 已过期组头"顺延"（对齐 Flutter _postponeOverdue）：逐任务保留各自时钟，
    /// 整组动作是单条事务，一次撤销整组生效；HUD 报告顺延数量。
    func postponeOverdue(_ ids: Set<UUID>) {
        let before = store.tasks
        actions.postponeOverdue(ids, to: clock())
        let moved = store.tasks.filter { task in
            guard let previous = before.first(where: { $0.id == task.id }) else { return false }
            return previous.schedule.dueAt != task.schedule.dueAt
        }.count
        revision += 1
        guard moved > 0 else {
            report(FeedbackEvent(kind: .info, message: "没有可顺延的任务"))
            return
        }
        report(FeedbackEvent(kind: .undoable, message: "已顺延 \(moved) 项到今天",
                             actionTitle: "撤销", action: undoStep()))
    }

    @discardableResult
    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, repeatFrequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil,
                     document: NativeDocument = .empty) -> TaskActionResult {
        let result = actions.createDraft(title: title, list: list, schedule: schedule, priority: priority,
                                         tags: tags, reminder: reminder, frequency: repeatFrequency,
                                         recurrenceRule: recurrenceRule, document: document)
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result
    }

    @discardableResult
    func createFromTemplate(_ template: TaskTemplate) -> UUID? {
        let listName = template.listName.flatMap { allListNames.contains($0) ? $0 : nil }
            ?? TaskList.inbox.name
        let result = actions.createFromTemplate(template, list: TaskList(name: listName))
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result.taskID
    }

    var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        return store.task(selectedTaskID)
    }

    var allTasks: [Task] { _ = revision; return store.tasks }
    var canUndo: Bool { _ = revision; return store.canUndo }
    func undo() { actions.undo(); revision += 1; if selectedTask == nil { select(nil) } }
    func setRepeat(_ id: UUID, _ value: TaskRepeat) { didMutate(actions.setRepeat(id, value)) }
    func setRecurrence(_ id: UUID, frequency: TaskRepeat, rule: RecurrenceRule?) {
        didMutate(actions.setRecurrence(id, frequency: frequency, rule: rule))
    }
    func saveTiming(_ id: UUID, schedule: TaskSchedule, reminder: Date?, frequency: TaskRepeat,
                    recurrenceRule: RecurrenceRule? = nil, reminderOffsets: [Int]? = nil) {
        let result = actions.saveTiming(id, schedule: schedule, reminder: reminder,
                                        frequency: frequency, recurrenceRule: recurrenceRule,
                                        reminderOffsets: reminderOffsets)
        didMutate(result)
    }
    var deletedTasks: [Task] {
        allTasks.filter { $0.deletedAt != nil }.sorted {
            if $0.deletedAt == $1.deletedAt { return $0.createdAt > $1.createdAt }
            return $0.deletedAt! > $1.deletedAt!
        }
    }
    func restoreDeleted(_ id: UUID) {
        let result = actions.restoreDeleted(id)
        didMutate(result)
        if result.taskID != nil { select(nil) }
    }
    func permanentlyDelete(_ id: UUID) {
        didMutate(actions.permanentlyDelete(id))
        if selectedTaskID != nil && selectedTask == nil { select(nil) }
    }
    func emptyTrash() { actions.emptyTrash(); select(nil); revision += 1 }

    func task(for id: UUID) -> Task? {
        _ = revision
        return store.task(id)
    }

    static func scope(for destination: NativeDestination) -> TaskListScope? {
        switch destination {
        case .today: return .today
        case .inbox: return .inbox
        case .allTasks: return .allTasks
        case .nextSevenDays: return .nextSevenDays
        case .completed: return .completed
        default: return nil
        }
    }

    func groups(for scope: TaskListScope, query: TaskListQuery = TaskListQuery()) -> [TaskListGroup] {
        _ = revision
        return applyingFilter(
            TaskListProjection.groups(in: scope, store: store, now: clock(), calendar: calendar, query: query))
    }

    /// Count for the visible list; when a saved filter is active the header
    /// count shrinks with the filtered content (like `activeList`/`activeTag`).
    func count(for scope: TaskListScope) -> Int {
        _ = revision
        return filteredMatches(in: scope, query: TaskListQuery())
            .filter { scope == .completed || !$0.isClosed }.count
    }

    /// Sidebar badge count: intentionally ignores the saved filter (and the
    /// list/tag query) so destination badges stay stable while filtering.
    func count(for destination: NativeDestination) -> Int {
        if destination == .trash { return deletedTasks.count }
        guard let scope = Self.scope(for: destination) else { return 0 }
        return TaskListProjection.count(in: scope, store: store, now: clock(), calendar: calendar)
    }

    func nodes(for group: TaskListGroup, scope: TaskListScope, query: TaskListQuery = TaskListQuery(),
               orderedRoots: [Task]? = nil) -> [TaskTreeNode] {
        _ = revision
        let matching = filteredMatches(in: scope, query: query)
        let followsMatchedParent = (scope == .today || scope == .nextSevenDays) &&
            query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let roots = Set(group.tasks.map(\.id))
        return TaskTreeProjection.nodes(roots: orderedRoots ?? group.tasks, store: store,
                                        expanded: query.isFiltering ? roots : roots.subtracting(collapsedTaskIDs),
                                        matchingTaskIDs: followsMatchedParent ? nil : Set(matching.map(\.id)))
    }

    func visibleNodes(for scope: TaskListScope, query: TaskListQuery = TaskListQuery()) -> [TaskTreeNode] {
        groups(for: scope, query: query).flatMap { nodes(for: $0, scope: scope, query: query) }
    }

    // MARK: Saved filter application

    private func filterMatches(_ task: Task) -> Bool {
        guard let filter = activeFilter else { return true }
        return FilterEvaluator.matches(task, filter: filter, now: clock(), calendar: calendar)
    }

    /// Post-filters projection output with the active saved filter, dropping
    /// groups that end up empty so the view falls back to its empty state. A
    /// root that fails the filter stays when one of its children passes, so
    /// the matched child remains reachable — mirroring how the list/tag query
    /// promotes matching children into rows.
    private func applyingFilter(_ groups: [TaskListGroup]) -> [TaskListGroup] {
        guard let filter = activeFilter else { return groups }
        return groups.compactMap { group in
            let tasks = group.tasks.filter { task in
                filterMatches(task) || hasMatchingChild(of: task, filter: filter)
            }
            guard !tasks.isEmpty else { return nil }
            guard tasks.count != group.tasks.count else { return group }
            return TaskListGroup(kind: group.kind, day: group.day, tasks: tasks, label: group.label)
        }
    }

    private func hasMatchingChild(of task: Task, filter: SavedFilter) -> Bool {
        store.children(of: task.id).contains {
            FilterEvaluator.matches($0, filter: filter, now: clock(), calendar: calendar)
        }
    }

    private func filteredMatches(in scope: TaskListScope, query: TaskListQuery) -> [Task] {
        TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar, query: query)
            .filter { filterMatches($0) }
    }

    func select(_ id: UUID?) {
        selectedTaskID = id
        bulkAnchorTaskID = id
    }

    func toggleExpanded(_ id: UUID) {
        if !collapsedTaskIDs.insert(id).inserted {
            collapsedTaskIDs.remove(id)
        }
    }

    func selectAdjacent(_ offset: Int, in scope: TaskListScope) {
        let nodes = visibleNodes(for: scope)
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) }
            ?? (offset < 0 ? nodes.count - 1 : 0)
        selectFromKeyboard(nodes[index].task.id)
    }

    @discardableResult
    func createTask(title: String, in scope: TaskListScope) -> TaskActionResult {
        let schedule = scope == .today
            ? TaskSchedule(dueAt: calendar.startOfDay(for: clock()))
            : TaskSchedule()
        let result = actions.create(title: title, list: .inbox, schedule: schedule)
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .info, message: "已添加到「\(TaskList.inbox.name)」"))
        }
        return result
    }

    @discardableResult
    func createChild(_ parentID: UUID, title: String = "") -> TaskActionResult {
        let result = actions.createChild(parentID, title: title)
        didMutate(result)
        return result
    }

    @discardableResult
    func requestChildTitleEditor(for parentID: UUID) -> UUID? {
        let result = actions.createChild(parentID)
        didMutate(result)
        guard let childID = result.taskID else { return nil }
        select(parentID)
        pendingChildTitleEditorID = childID
        return childID
    }

    @discardableResult
    func assignParent(_ id: UUID, parentID: UUID) -> TaskActionResult {
        let result = actions.setParent(id, parentID: parentID)
        didMutate(result)
        if result.taskID != nil {
            collapsedTaskIDs.remove(parentID)
        }
        return result
    }

    func consumePendingChildTitleEditor() -> UUID? {
        defer { pendingChildTitleEditorID = nil }
        return pendingChildTitleEditorID
    }

    @discardableResult
    func complete(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = actions.complete(id)
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .completion, message: "已完成\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep(), sound: .completion,
                                 coalesceKey: "task-completed",
                                 coalescedMessage: { "已完成 \($0) 个任务" }))
        }
        return result
    }

    @discardableResult
    func restore(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = actions.restore(id)
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .completion, message: "已恢复\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    @discardableResult
    func changeStatus(_ task: Task, in scope: TaskListScope? = nil) -> TaskActionResult {
        task.isClosed ? restore(task.id, in: scope) : complete(task.id, in: scope)
    }

    @discardableResult
    func abandon(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = actions.abandon(id)
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .undoable, message: "已放弃\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    @discardableResult
    func moveToList(_ id: UUID, _ list: TaskList) -> TaskActionResult {
        let listBefore = task(for: id)?.list.name
        let result = actions.moveToList(id, list)
        didMutate(result)
        if result.taskID != nil, listBefore != list.name {
            report(FeedbackEvent(kind: .undoable,
                                 message: "已移动到「\(task(for: id)?.list.name ?? list.name)」",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    func canMoveToList(_ id: UUID) -> Bool {
        guard let task = task(for: id) else { return false }
        return task.parentID == nil && task.deletedAt == nil
    }

    @discardableResult
    func delete(_ id: UUID) -> TaskActionResult {
        let result = actions.delete(id)
        guard result.taskID != nil else { return result }
        if selectedTaskID == id { selectedTaskID = nil }
        didMutate(result)
        report(FeedbackEvent(kind: .undoable, message: "已删除\(quotedTitle(id))",
                             actionTitle: "撤销", action: undoStep()))
        return result
    }

    @discardableResult
    func setSchedule(_ id: UUID, _ schedule: TaskSchedule) -> TaskActionResult {
        let result = actions.setSchedule(id, schedule)
        didMutate(result)
        return result
    }

    @discardableResult
    func setTitle(_ id: UUID, _ title: String) -> TaskActionResult {
        let result = actions.setTitle(id, title)
        didMutate(result)
        return result
    }

    @discardableResult
    func setDocument(_ id: UUID, _ document: NativeDocument) -> TaskActionResult {
        let result = actions.setDocument(id, document)
        didMutate(result)
        return result
    }

    func setSourceNote(_ id: UUID, _ noteID: UUID) { didMutate(actions.setSourceNote(id, noteID)) }

    @discardableResult
    func setPriority(_ id: UUID, _ priority: TaskPriority) -> TaskActionResult {
        let result = actions.setPriority(id, priority)
        didMutate(result)
        return result
    }

    @discardableResult
    func setPinned(_ id: UUID, _ isPinned: Bool) -> TaskActionResult {
        let pinnedBefore = task(for: id)?.isPinned
        let result = actions.setPinned(id, isPinned)
        didMutate(result)
        if result.taskID != nil, pinnedBefore != isPinned {
            report(FeedbackEvent(kind: .success, message: isPinned ? "已置顶" : "已取消置顶"))
        }
        return result
    }

    @discardableResult
    func convertToNote(_ id: UUID, noteID: UUID, undoNote: @escaping () -> Void) -> TaskActionResult {
        let result = actions.convertToNote(id, noteID: noteID, undoNote: undoNote)
        didMutate(result)
        if result.taskID != nil { select(nil) }
        if result.taskID != nil {
            report(FeedbackEvent(kind: .undoable, message: "已转换为笔记",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    func setTags(_ id: UUID, _ tags: [String]) { didMutate(actions.setTags(id, tags)) }
    func setReminder(_ id: UUID, _ date: Date?) { didMutate(actions.setReminder(id, date)) }
    func setAttachments(_ id: UUID, _ values: [NativeAttachment]) { didMutate(actions.setAttachments(id, values)) }

    func dateFromToday(_ offset: Int) -> Date {
        let start = calendar.startOfDay(for: clock())
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    @discardableResult
    func setDueDate(_ id: UUID, _ date: Date?) -> TaskActionResult {
        guard var schedule = task(for: id)?.schedule else { return .failure(.missingTask) }
        schedule.dueAt = date.map(calendar.startOfDay(for:))
        schedule.hasTime = false
        // 没有开始日的区间不成区间：清掉安排日时时间段一并清掉（Flutter 同款）。
        if date == nil { schedule.dueEndAt = nil }
        return setSchedule(id, schedule)
    }

    @discardableResult
    func clearDueDate(_ id: UUID) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var schedule = task.schedule
        schedule.dueAt = nil
        schedule.hasTime = false
        schedule.dueEndAt = nil
        let result = actions.saveTiming(id, schedule: schedule, reminder: task.reminderAt,
                                        frequency: task.recurrence,
                                        recurrenceRule: task.recurrenceRule)
        didMutate(result)
        return result
    }

    @discardableResult
    func clearScheduledProperties(_ id: UUID) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var schedule = task.schedule
        schedule.dueAt = nil
        schedule.hasTime = false
        schedule.dueEndAt = nil
        let result = actions.saveTiming(id, schedule: schedule, reminder: nil,
                                        frequency: .never, recurrenceRule: nil)
        didMutate(result)
        return result
    }

    @discardableResult
    func moveDueDate(_ id: UUID, to date: Date) -> TaskActionResult {
        guard let current = task(for: id)?.schedule else { return .failure(.missingTask) }
        let moved = TaskDateDraft.movingDay(current.dueAt ?? date, to: date, calendar: calendar)
        var next = TaskDateDraft.applying(date: moved, hasTime: current.hasTime,
                                          deadline: false, to: current, calendar: calendar)
        // 对齐 Flutter `updateTaskDue`：改期平移整个时间段，区间长度不变。
        // 只挪开始日会把「9/1 – 9/5」压成「9/3 – 9/5」——日历上一条跨天色带
        // 被拖到别的日子后长度不该变。
        if let start = current.dueAt, let end = current.dueEndAt {
            let shifted = end.addingTimeInterval(moved.timeIntervalSince(start))
            next.dueEndAt = current.hasTime ? shifted : calendar.startOfDay(for: shifted)
        }
        return setSchedule(id, next)
    }

    @discardableResult
    func setDeadline(_ id: UUID, _ date: Date?) -> TaskActionResult {
        guard var schedule = task(for: id)?.schedule else { return .failure(.missingTask) }
        schedule.deadlineAt = date.map(calendar.startOfDay(for:))
        return setSchedule(id, schedule)
    }

    /// 是否有未删除的一级子任务。四象限行尾的「有子任务」标记用它。
    func hasChildren(_ id: UUID) -> Bool {
        allTasks.contains { task in
            task.parentID == id && task.deletedAt == nil && task.skippedAt == nil &&
                !task.isAbandoned && !task.isConverted
        }
    }

    /// 任务被拖进某个象限时的语义（对齐 Flutter `moveTaskToMatrix`）。
    ///
    /// 象限由「重要」（优先级）与「紧急」（安排日在三天内）两个属性推出来，
    /// 所以跨象限就是改这两项：重要性与紧迫性在**改动之前**各算一次，然后按
    /// 象限补齐缺的那一项。`later` 象限里先降优先级再判「重要」会得到另一个
    /// 答案，所以那两个布尔值必须先落定。
    ///
    /// 日期只挪「日」的部分，时刻跟着走（06:30 的任务拖进 Ⅰ 象限仍是今天
    /// 06:30），全天任务仍然是全天。
    @discardableResult
    func moveTaskToMatrix(_ id: UUID, _ quadrant: MatrixQuadrant) -> TaskActionResult {
        guard let current = task(for: id), current.deletedAt == nil,
              current.skippedAt == nil, !current.isAbandoned, !current.isConverted else {
            return .failure(.missingTask)
        }
        let now = clock()
        let important = PlanningProjection.isImportant(current)
        let urgent = PlanningProjection.isUrgent(current, now: now, calendar: calendar)

        func onDay(_ offset: Int) -> TaskSchedule {
            var next = TaskDateDraft.applying(date: TaskDateDraft.movingDay(
                current.schedule.dueAt ?? dateFromToday(offset),
                to: dateFromToday(offset), calendar: calendar),
                hasTime: current.schedule.hasTime, deadline: false,
                to: current.schedule, calendar: calendar)
            // 只挪开始日会截断区间：时间段跟着一起平移，长度不变。
            if let start = current.schedule.dueAt, let end = current.schedule.dueEndAt {
                let shifted = end.addingTimeInterval(
                    (next.dueAt ?? start).timeIntervalSince(start))
                next.dueEndAt = current.schedule.hasTime ? shifted : calendar.startOfDay(for: shifted)
            }
            return next
        }

        var result = TaskActionResult.success(id)
        switch quadrant {
        case .doNow:
            if !important { result = setPriority(id, .high) }
            result = setSchedule(id, onDay(0))
        case .schedule:
            if !important { result = setPriority(id, .high) }
            if urgent { result = setSchedule(id, onDay(7)) }
        case .delegate:
            if !urgent { result = setSchedule(id, onDay(0)) }
            if important { result = setPriority(id, .low) }
        case .later:
            if important { result = setPriority(id, .none) }
            if urgent { result = setSchedule(id, onDay(7)) }
        }
        return result
    }

    // MARK: 反馈上报（A3 加法：动作层只声明发生了什么；显示、时长与仲裁归 FeedbackCenter）

    private func report(_ event: FeedbackEvent) {
        feedbackSink?.show(event)
    }

    /// 单步全局撤销：WorkspaceStore 快照栈回退一次（批量操作是单条事务，一次撤销整批生效）。
    private func undoStep() -> () -> Void {
        { [weak self] in self?.undo() }
    }

    private func quotedTitle(_ id: UUID) -> String {
        guard let title = task(for: id)?.title, !title.isEmpty else { return "任务" }
        return "「\(title)」"
    }

    private func reportBulk(_ operation: TaskBatchOperation, count: Int, changed: Bool) {
        guard changed, count > 0 else { return }
        switch operation {
        case .complete:
            // 批量自带总数，不参与单条合并（再叠一条会重计成 2）。
            report(FeedbackEvent(kind: .completion, message: "已完成 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep(), sound: .completion))
        case .delete:
            report(FeedbackEvent(kind: .undoable, message: "已删除 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep()))
        case .move(let list):
            report(FeedbackEvent(kind: .undoable, message: "已移动 \(count) 个任务到「\(list)」",
                                 actionTitle: "撤销", action: undoStep()))
        case .schedule:
            report(FeedbackEvent(kind: .undoable, message: "已调整 \(count) 个任务的日期",
                                 actionTitle: "撤销", action: undoStep()))
        case .priority:
            report(FeedbackEvent(kind: .success, message: "已更新 \(count) 个任务的优先级"))
        case .reminderOffsets:
            report(FeedbackEvent(kind: .success, message: "已更新 \(count) 个任务的提醒"))
        }
    }

    private func didMutate(_ result: TaskActionResult, scope: TaskListScope? = nil) {
        guard result.taskID != nil else { return }
        revision += 1
        if let scope, let selectedTaskID,
           !TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar)
            .contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = nil
        }
    }

    private func seed() {
        let today = calendar.startOfDay(for: clock())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        guard let parentID = actions.create(
            title: "整理本周用户反馈",
            list: TaskList(name: "工作"),
            schedule: TaskSchedule(dueAt: today),
            priority: .high
        ).taskID else { return }
        if let first = actions.createChild(parentID, title: "归纳高频问题").taskID {
            _ = actions.setSchedule(first, TaskSchedule(dueAt: today))
        }
        if let second = actions.createChild(parentID, title: "整理改进建议").taskID {
            _ = actions.setSchedule(second, TaskSchedule(dueAt: today))
        }
        _ = actions.create(title: "阅读《设计心理学》第四章",
                           list: TaskList(name: "学习"),
                           schedule: TaskSchedule(dueAt: today))
        _ = actions.create(title: "准备季度复盘材料",
                           list: TaskList(name: "工作"),
                           schedule: TaskSchedule(dueAt: today))
        _ = actions.create(title: "记录下次旅行的想法",
                           list: TaskList(name: "个人"),
                           schedule: TaskSchedule(dueAt: tomorrow))
        if let finished = actions.create(title: "确认本周安排",
                                         list: TaskList(name: "工作"),
                                         schedule: TaskSchedule(dueAt: today)).taskID {
            _ = actions.complete(finished)
        }
        _ = actions.create(title: "随手收集一个想法")
        revision = 0
        store.clearUndo()
    }
}
