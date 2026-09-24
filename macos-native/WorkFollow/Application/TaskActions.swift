import Foundation

final class TaskActions {
    private let store: WorkspaceStore
    private let clock: () -> Date

    init(store: WorkspaceStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    @discardableResult
    func create(title: String, list: TaskList = .inbox,
                schedule: TaskSchedule = TaskSchedule(),
                priority: TaskPriority = .none) -> TaskActionResult {
        guard !list.name.isEmpty else { return .failure(.invalidList) }
        let now = clock()
        let task = Task(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        list: list, priority: priority, schedule: schedule,
                        parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        store.commit(store.tasks + [task])
        return .success(task.id)
    }

    @discardableResult
    func createChild(_ parentID: UUID, title: String = "") -> TaskActionResult {
        guard let parent = store.task(parentID) else { return .failure(.missingTask) }
        guard parent.deletedAt == nil else { return .failure(.deletedTask) }
        guard parent.parentID == nil else { return .failure(.childCannotHaveChildren) }
        let now = clock()
        let order = (store.children(of: parentID, includingDeleted: true).map(\.childOrder).max() ?? -1) + 1
        let child = Task(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                         list: parent.list, priority: .none, schedule: TaskSchedule(),
                         parentID: parentID, childOrder: order, createdAt: now, updatedAt: now)
        store.commit(store.tasks + [child])
        return .success(child.id)
    }

    @discardableResult
    func complete(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        guard task.status != .completed else { return .failure(.alreadyCompleted) }
        let now = clock()
        var snapshot = store.tasks.map { original -> Task in
            var value = original
            if (value.id == id || value.parentID == id), value.deletedAt == nil,
               value.status == .active {
                value.status = .completed
                value.completedAt = now
                value.updatedAt = now
            }
            return value
        }
        // Only the directly completed recurrence starts a new occurrence.
        // Children carried by parent completion must not spawn separate chains.
        if task.recurrence != .never {
            let calendar = Calendar.current
            let base = task.schedule.dueAt ?? now
            if let next = calendar.date(byAdding: task.recurrence.component, value: 1, to: base) {
                let days = calendar.dateComponents([.day], from: base, to: next).day ?? 1
                func nextOccurrence(_ source: Task, parentID: UUID?) -> Task {
                    var value = Task(id: UUID(), title: source.title, document: source.document,
                                     tags: source.tags, recurrence: source.recurrence,
                                     list: source.list, priority: source.priority, schedule: source.schedule,
                                     parentID: parentID, childOrder: source.childOrder,
                                     createdAt: now, updatedAt: now)
                    value.schedule.dueAt = source.schedule.dueAt.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
                    value.schedule.deadlineAt = source.schedule.deadlineAt.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
                    value.reminderAt = source.reminderAt.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
                    value.attachments = source.attachments
                    return value
                }
                var occurrence = nextOccurrence(task, parentID: task.parentID)
                occurrence.schedule.dueAt = next
                snapshot.append(occurrence)
                if task.parentID == nil {
                    snapshot += store.children(of: task.id).map { nextOccurrence($0, parentID: occurrence.id) }
                }
            }
        }
        store.commit(snapshot)
        return .success(id)
    }

    /// Reopen a completed task, not a trash restore. Does not reopen descendants.
    @discardableResult
    func restore(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.status == .completed else { return .failure(.alreadyActive) }
        return edit(id) { task in
            task.status = .active
            task.completedAt = nil
        }
    }

    @discardableResult
    func delete(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        let now = clock()
        store.commit(store.tasks.map { original in
            var value = original
            if (value.id == id || value.parentID == id), value.deletedAt == nil {
                value.deletedAt = now
                value.updatedAt = now
            }
            return value
        })
        return .success(id)
    }

    @discardableResult
    func restoreDeleted(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard let stamp = task.deletedAt else { return .failure(.notDeleted) }
        if let parentID = task.parentID, store.task(parentID)?.deletedAt != nil {
            return .failure(.deletedTask)
        }
        let now = clock()
        store.commit(store.tasks.map { original in
            var value = original
            if value.id == id || (value.parentID == id && value.deletedAt == stamp) {
                value.deletedAt = nil
                value.updatedAt = now
            }
            return value
        })
        return .success(id)
    }

    @discardableResult
    func moveToList(_ id: UUID, _ list: TaskList) -> TaskActionResult {
        guard !list.name.isEmpty else { return .failure(.invalidList) }
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        guard task.parentID == nil else { return .failure(.childListMoveNotSupported) }
        let now = clock()
        store.commit(store.tasks.map { original in
            var value = original
            if (value.id == id || value.parentID == id), value.deletedAt == nil {
                value.list = list
                value.updatedAt = now
            }
            return value
        })
        return .success(id)
    }

    @discardableResult
    func setTitle(_ id: UUID, _ title: String) -> TaskActionResult {
        edit(id) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    func setDocument(_ id: UUID, _ document: NativeDocument) -> TaskActionResult {
        edit(id) { $0.document = document }
    }

    @discardableResult
    func setPriority(_ id: UUID, _ priority: TaskPriority) -> TaskActionResult {
        edit(id) { $0.priority = priority }
    }

    @discardableResult
    func setTags(_ id: UUID, _ tags: [String]) -> TaskActionResult {
        var seen = Set<String>()
        let values = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return edit(id) { $0.tags = values }
    }

    @discardableResult
    func setRepeat(_ id: UUID, _ recurrence: TaskRepeat) -> TaskActionResult {
        edit(id) { $0.recurrence = recurrence }
    }

    @discardableResult
    func setReminder(_ id: UUID, _ date: Date?) -> TaskActionResult {
        edit(id) { $0.reminderAt = date }
    }

    @discardableResult
    func setAttachments(_ id: UUID, _ values: [NativeAttachment]) -> TaskActionResult {
        edit(id) { $0.attachments = values }
    }

    func undo() { store.undo() }

    @discardableResult
    func setSchedule(_ id: UUID, _ schedule: TaskSchedule) -> TaskActionResult {
        edit(id) { $0.schedule = schedule }
    }

    private func edit(_ id: UUID, mutation: (inout Task) -> Void) -> TaskActionResult {
        var snapshot = store.tasks
        guard let index = snapshot.firstIndex(where: { $0.id == id }) else {
            return .failure(.missingTask)
        }
        guard snapshot[index].deletedAt == nil else { return .failure(.deletedTask) }
        mutation(&snapshot[index])
        snapshot[index].updatedAt = clock()
        store.commit(snapshot)
        return .success(id)
    }

    @discardableResult
    func permanentlyDelete(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt != nil else { return .failure(.notDeleted) }
        store.commit(store.tasks.filter { $0.id != id && $0.parentID != id })
        store.clearUndo()
        return .success(id)
    }

    func emptyTrash() {
        store.commit(store.tasks.filter { $0.deletedAt == nil })
        store.clearUndo()
    }
}
