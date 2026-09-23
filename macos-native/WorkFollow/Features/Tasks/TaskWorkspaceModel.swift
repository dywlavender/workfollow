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
    @Published private(set) var expandedTaskIDs: Set<UUID> = []
    @Published private(set) var revision = 0

    private let store: WorkspaceStore
    private let actions: TaskActions
    private let clock: () -> Date
    private let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         seedDemoData: Bool = true) {
        self.clock = clock
        self.calendar = calendar
        let store = WorkspaceStore()
        self.store = store
        self.actions = TaskActions(store: store, clock: clock)
        if seedDemoData { seed() }
    }

    var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        return store.task(selectedTaskID)
    }

    func task(for id: UUID) -> Task? {
        _ = revision
        return store.task(id)
    }

    static func scope(for destination: NativeDestination) -> TaskListScope? {
        switch destination {
        case .today: return .today
        case .inbox: return .inbox
        case .completed: return .completed
        default: return nil
        }
    }

    func groups(for scope: TaskListScope) -> [TaskListGroup] {
        _ = revision
        return TaskListProjection.groups(in: scope, store: store, now: clock(), calendar: calendar)
    }

    func count(for scope: TaskListScope) -> Int {
        _ = revision
        return TaskListProjection.count(in: scope, store: store, now: clock(), calendar: calendar)
    }

    func count(for destination: NativeDestination) -> Int {
        guard let scope = Self.scope(for: destination) else { return 0 }
        return count(for: scope)
    }

    func nodes(for group: TaskListGroup, scope: TaskListScope) -> [TaskTreeNode] {
        _ = revision
        let matching = TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar)
        return TaskTreeProjection.nodes(roots: group.tasks, store: store,
                                        expanded: expandedTaskIDs,
                                        matchingTaskIDs: Set(matching.map(\.id)))
    }

    func visibleNodes(for scope: TaskListScope) -> [TaskTreeNode] {
        groups(for: scope).flatMap { nodes(for: $0, scope: scope) }
    }

    func select(_ id: UUID?) { selectedTaskID = id }

    func toggleExpanded(_ id: UUID) {
        if !expandedTaskIDs.insert(id).inserted {
            expandedTaskIDs.remove(id)
        }
    }

    func selectAdjacent(_ offset: Int, in scope: TaskListScope) {
        let nodes = visibleNodes(for: scope)
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) }
            ?? (offset < 0 ? nodes.count - 1 : 0)
        selectedTaskID = nodes[index].task.id
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
        task.status == .completed ? restore(task.id, in: scope) : complete(task.id, in: scope)
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

    @discardableResult
    func setPriority(_ id: UUID, _ priority: TaskPriority) -> TaskActionResult {
        let result = actions.setPriority(id, priority)
        didMutate(result)
        return result
    }

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
        expandedTaskIDs.insert(parentID)
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
    }
}
