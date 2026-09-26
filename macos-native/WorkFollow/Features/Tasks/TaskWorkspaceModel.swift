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
    @Published private(set) var taskListPaneWidth = WFMetrics.listPreferred
    @Published var activeList: String?
    @Published var activeTag: String?
    @Published var bulkSelection: Set<UUID> = []
    @Published private(set) var bulkAnchorTaskID: UUID?

    private let store: WorkspaceStore
    private let actions: TaskActions
    let clock: () -> Date
    let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         seedDemoData: Bool = true, initialTasks: [Task]? = nil, initialLists: [String] = []) {
        self.clock = clock
        self.calendar = calendar
        let store = WorkspaceStore()
        self.store = store
        self.actions = TaskActions(store: store, clock: clock, calendar: calendar)
        if let initialTasks { store.commit(initialTasks); store.clearUndo() }
        else if seedDemoData { seed() }
        store.commit(store.tasks, lists: initialLists)
        store.clearUndo()
    }

    var listNames: [String] {
        Array(Set(store.lists + allTasks.map { $0.list.name })).filter { $0 != TaskList.inbox.name }.sorted()
    }
    var allListNames: [String] { [TaskList.inbox.name] + listNames }
    var tagNames: [String] { Array(Set(allTasks.flatMap(\.tags))).sorted() }

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
    func applyBulk(_ operation: TaskBatchOperation) {
        actions.batch(bulkSelection, operation: operation)
        clearBulkSelection()
        revision += 1
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
    func duplicate(_ id: UUID) { didMutate(actions.duplicate(id)) }
    func skip(_ id: UUID) { didMutate(actions.skip(id)); select(nil) }
    func reorder(_ id: UUID, before target: UUID) { actions.reorder(id, before: target); revision += 1 }
    func postponeOverdue(_ ids: Set<UUID>) {
        actions.postponeOverdue(ids, to: clock())
        revision += 1
    }

    @discardableResult
    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, repeatFrequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil) -> TaskActionResult {
        let result = actions.createDraft(title: title, list: list, schedule: schedule, priority: priority,
                                         tags: tags, reminder: reminder, frequency: repeatFrequency,
                                         recurrenceRule: recurrenceRule)
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result
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
                    recurrenceRule: RecurrenceRule? = nil) {
        let result = actions.saveTiming(id, schedule: schedule, reminder: reminder,
                                        frequency: frequency, recurrenceRule: recurrenceRule)
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
        return TaskListProjection.groups(in: scope, store: store, now: clock(), calendar: calendar, query: query)
    }

    func count(for scope: TaskListScope) -> Int {
        _ = revision
        return TaskListProjection.count(in: scope, store: store, now: clock(), calendar: calendar)
    }

    func count(for destination: NativeDestination) -> Int {
        if destination == .trash { return deletedTasks.count }
        guard let scope = Self.scope(for: destination) else { return 0 }
        return count(for: scope)
    }

    func nodes(for group: TaskListGroup, scope: TaskListScope, query: TaskListQuery = TaskListQuery(),
               orderedRoots: [Task]? = nil) -> [TaskTreeNode] {
        _ = revision
        let matching = TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar, query: query)
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

    func consumePendingChildTitleEditor() -> UUID? {
        defer { pendingChildTitleEditorID = nil }
        return pendingChildTitleEditorID
    }

    @discardableResult
    func complete(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = actions.complete(id)
        didMutate(result, scope: scope)
        return result
    }

    @discardableResult
    func restore(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = actions.restore(id)
        didMutate(result, scope: scope)
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
        return result
    }

    @discardableResult
    func moveToList(_ id: UUID, _ list: TaskList) -> TaskActionResult {
        let result = actions.moveToList(id, list)
        didMutate(result)
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
        let result = actions.setPinned(id, isPinned)
        didMutate(result)
        return result
    }

    @discardableResult
    func convertToNote(_ id: UUID, noteID: UUID, undoNote: @escaping () -> Void) -> TaskActionResult {
        let result = actions.convertToNote(id, noteID: noteID, undoNote: undoNote)
        didMutate(result)
        if result.taskID != nil { select(nil) }
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
        return setSchedule(id, schedule)
    }

    @discardableResult
    func clearDueDate(_ id: UUID) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var schedule = task.schedule
        schedule.dueAt = nil
        schedule.hasTime = false
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
        let result = actions.saveTiming(id, schedule: schedule, reminder: nil,
                                        frequency: .never, recurrenceRule: nil)
        didMutate(result)
        return result
    }

    @discardableResult
    func moveDueDate(_ id: UUID, to date: Date) -> TaskActionResult {
        guard let current = task(for: id)?.schedule else { return .failure(.missingTask) }
        let moved = TaskDateDraft.movingDay(current.dueAt ?? date, to: date, calendar: calendar)
        return setSchedule(id, TaskDateDraft.applying(date: moved, hasTime: current.hasTime,
                                                     deadline: false, to: current, calendar: calendar))
    }

    @discardableResult
    func setDeadline(_ id: UUID, _ date: Date?) -> TaskActionResult {
        guard var schedule = task(for: id)?.schedule else { return .failure(.missingTask) }
        schedule.deadlineAt = date.map(calendar.startOfDay(for:))
        return setSchedule(id, schedule)
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
