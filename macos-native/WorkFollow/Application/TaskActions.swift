import Foundation

final class TaskActions {
    private let store: WorkspaceStore
    private let clock: () -> Date
    private let calendar: Calendar

    init(store: WorkspaceStore, clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
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
        guard !task.isClosed else { return .failure(.alreadyCompleted) }
        let now = clock()
        var snapshot = store.tasks.map { original -> Task in
            var value = original
            if (value.id == id || value.parentID == id), value.deletedAt == nil,
               !value.isClosed && value.skippedAt == nil {
                value.status = .completed
                value.completedAt = now
                value.updatedAt = now
            }
            return value
        }
        // Only the directly completed recurrence starts a new occurrence.
        // Children carried by parent completion must not spawn separate chains.
        if task.recurrence != .never {
            let base = task.schedule.dueAt ?? calendar.startOfDay(for: now)
            if let next = RecurrenceEngine.next(for: task, now: now, calendar: calendar) {
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
                    value.recurrenceRule = source.recurrenceRule
                    return value
                }
                var occurrence = nextOccurrence(task, parentID: task.parentID)
                occurrence.schedule.dueAt = next
                var rule = task.recurrenceRule ?? RecurrenceRule()
                rule.monthDay = rule.monthDay ?? calendar.component(.day, from: base)
                rule.remainingCount = rule.remainingCount.map { $0 - 1 }
                occurrence.recurrenceRule = rule
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
        guard task.isClosed else { return .failure(.alreadyActive) }
        return edit(id) { task in
            task.status = .active
            task.completedAt = nil
            task.abandonedAt = nil
        }
    }

    @discardableResult
    func abandon(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        guard !task.isClosed else { return .failure(.alreadyCompleted) }
        return edit(id) { $0.abandonedAt = clock() }
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
        edit(id, undoPolicy: .skip) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    func setDocument(_ id: UUID, _ document: NativeDocument) -> TaskActionResult {
        edit(id, undoPolicy: .skip) { $0.document = document }
    }

    func setSourceNote(_ id: UUID, _ noteID: UUID) -> TaskActionResult {
        edit(id) { $0.sourceNoteID = noteID }
    }

    @discardableResult
    func setPriority(_ id: UUID, _ priority: TaskPriority) -> TaskActionResult {
        edit(id) { $0.priority = priority }
    }

    @discardableResult
    func setPinned(_ id: UUID, _ isPinned: Bool) -> TaskActionResult {
        edit(id) { $0.isPinned = isPinned }
    }

    @discardableResult
    func convertToNote(_ id: UUID, noteID: UUID,
                       undoNote: @escaping () -> Void) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        guard !task.isConverted else { return .failure(.alreadyConverted) }
        let now = clock()
        var snapshot = store.tasks
        guard let parentIndex = snapshot.firstIndex(where: { $0.id == id }) else {
            return .failure(.missingTask)
        }
        snapshot[parentIndex].convertedNoteID = noteID
        snapshot[parentIndex].updatedAt = now
        for index in snapshot.indices where snapshot[index].parentID == id && snapshot[index].deletedAt == nil {
            snapshot[index].deletedAt = now
            snapshot[index].updatedAt = now
        }
        store.commit(snapshot, undoCompensation: undoNote)
        return .success(id)
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
        setRecurrence(id, frequency: recurrence, rule: nil)
    }

    @discardableResult
    func setRecurrence(_ id: UUID, frequency: TaskRepeat, rule: RecurrenceRule?) -> TaskActionResult {
        edit(id) { task in
            task.recurrence = frequency
            var normalized = rule
            normalized?.interval = max(1, rule?.interval ?? 1)
            normalized?.remainingCount = rule?.remainingCount.map { max(1, $0) }
            task.recurrenceRule = frequency == .never ? nil : normalized
        }
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
    func saveTiming(_ id: UUID, schedule: TaskSchedule, reminder: Date?, frequency: TaskRepeat,
                    recurrenceRule: RecurrenceRule? = nil) -> TaskActionResult {
        guard let current = store.task(id) else { return .failure(.missingTask) }
        guard current.deletedAt == nil else { return .failure(.deletedTask) }
        store.transaction {
            _ = setSchedule(id, schedule)
            _ = setReminder(id, reminder)
            if current.recurrence != frequency {
                _ = setRecurrence(id, frequency: frequency, rule: recurrenceRule)
            } else if let recurrenceRule, current.recurrenceRule != recurrenceRule {
                _ = setRecurrence(id, frequency: frequency, rule: recurrenceRule)
            }
        }
        return .success(id)
    }

    @discardableResult
    func setSchedule(_ id: UUID, _ schedule: TaskSchedule) -> TaskActionResult {
        edit(id) { $0.schedule = schedule }
    }

    /// Move an overdue group to today while preserving each task's timed/all-day
    /// meaning and keeping the entire group move as one undoable operation.
    func postponeOverdue(_ ids: Set<UUID>, to day: Date) {
        let targetDay = calendar.startOfDay(for: day)
        store.transaction {
            for task in store.tasks where ids.contains(task.id) &&
                task.deletedAt == nil && task.skippedAt == nil && !task.isClosed {
                guard let dueAt = task.schedule.dueAt else { continue }
                let movedDate: Date
                if task.schedule.hasTime {
                    let time = calendar.dateComponents([.hour, .minute], from: dueAt)
                    movedDate = calendar.date(bySettingHour: time.hour ?? 0,
                                              minute: time.minute ?? 0,
                                              second: 0, of: targetDay) ?? targetDay
                } else {
                    movedDate = targetDay
                }
                var schedule = task.schedule
                schedule.dueAt = movedDate
                _ = setSchedule(task.id, schedule)
            }
        }
    }

    private func edit(_ id: UUID, undoPolicy: WorkspaceStore.UndoPolicy = .record, mutation: (inout Task) -> Void) -> TaskActionResult {
        var snapshot = store.tasks
        guard let index = snapshot.firstIndex(where: { $0.id == id }) else {
            return .failure(.missingTask)
        }
        guard snapshot[index].deletedAt == nil else { return .failure(.deletedTask) }
        mutation(&snapshot[index])
        guard snapshot[index] != store.tasks[index] else { return .success(id) }
        snapshot[index].updatedAt = clock()
        store.commit(snapshot, undoPolicy: undoPolicy)
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

    func renameList(_ old: String?, to name: String) {
        var lists = store.lists.filter { $0 != old }
        if !lists.contains(name) { lists.append(name) }
        store.commit(store.tasks.map { task in
            var value = task
            if task.list.name == old { value.list = TaskList(name: name); value.updatedAt = clock() }
            return value
        }, lists: lists)
    }

    func removeList(_ name: String) {
        guard name != TaskList.inbox.name else { return }
        store.commit(store.tasks.map { task in
            var value = task
            if task.list.name == name { value.list = .inbox; value.updatedAt = clock() }
            return value
        }, lists: store.lists.filter { $0 != name })
    }

    func renameTag(_ old: String, to raw: String?) {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        store.commit(store.tasks.map { task in
            var value = task
            guard value.tags.contains(old) else { return value }
            value.tags.removeAll { $0 == old }
            if let name, !name.isEmpty, !value.tags.contains(name) { value.tags.append(name) }
            value.updatedAt = clock()
            return value
        })
    }

    func batch(_ ids: Set<UUID>, operation: TaskBatchOperation) {
        // Parent commands already carry children: never spawn a child recurrence twice.
        let targets = store.tasks.filter { ids.contains($0.id) && $0.deletedAt == nil && $0.skippedAt == nil }
        store.transaction {
            for task in targets {
                switch operation {
                case .complete:
                    if !ids.contains(task.parentID ?? task.id) || task.parentID == nil { _ = complete(task.id) }
                case .delete:
                    if !ids.contains(task.parentID ?? task.id) || task.parentID == nil { _ = delete(task.id) }
                case .move(let list):
                    if task.parentID == nil { _ = moveToList(task.id, TaskList(name: list)) }
                case .schedule(let schedule): _ = setSchedule(task.id, TaskSchedule(dueAt: schedule.dueAt, hasTime: schedule.hasTime, deadlineAt: task.schedule.deadlineAt))
                case .priority(let priority): _ = setPriority(task.id, priority)
                }
            }
        }
    }

    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, frequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil) -> TaskActionResult {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.invalidList) }
        var result: TaskActionResult = .failure(.missingTask)
        store.transaction {
            result = create(title: title, list: TaskList(name: list), schedule: schedule, priority: priority)
            if let id = result.taskID {
                _ = setTags(id, tags)
                _ = setReminder(id, reminder)
                _ = setRecurrence(id, frequency: frequency, rule: recurrenceRule)
            }
        }
        return result
    }

    func duplicate(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id), task.deletedAt == nil else { return .failure(.missingTask) }
        func copy(_ source: Task, parent: UUID?) -> Task {
            var value = Task(id: UUID(), title: source.title, document: source.document,
                             tags: source.tags, recurrence: source.recurrence, list: source.list,
                             priority: source.priority, schedule: source.schedule, parentID: parent,
                             childOrder: source.childOrder, createdAt: clock(), updatedAt: clock())
            value.recurrenceRule = source.recurrenceRule
            value.attachments = source.attachments
            value.reminderAt = source.reminderAt
            return value
        }
        let value = copy(task, parent: task.parentID)
        store.commit(store.tasks + [value] + store.children(of: id).map { copy($0, parent: value.id) })
        return .success(value.id)
    }

    func skip(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id), !task.isClosed, task.deletedAt == nil,
              RecurrenceEngine.next(for: task, now: clock(), calendar: calendar) != nil else { return .failure(.missingTask) }
        let original = store.tasks
        store.transaction {
            _ = complete(id)
            store.commit(store.tasks.map { value in
                guard let previous = original.first(where: { $0.id == value.id }),
                      value.id == id || value.parentID == id else { return value }
                var skipped = previous
                skipped.skippedAt = clock(); skipped.updatedAt = clock()
                return skipped
            })
        }
        return .success(id)
    }

    func reorder(_ id: UUID, before targetID: UUID) {
        guard id != targetID, let source = store.task(id), let target = store.task(targetID),
              source.parentID == target.parentID else { return }
        var values = store.tasks.filter { $0.id != id }
        guard let index = values.firstIndex(where: { $0.id == targetID }) else { return }
        values.insert(source, at: index)
        if source.parentID != nil {
            var order = 0
            for i in values.indices where values[i].parentID == source.parentID {
                values[i].childOrder = order; order += 1
            }
        }
        store.commit(values)
    }
}

enum TaskBatchOperation {
    case complete, delete, move(String), schedule(TaskSchedule), priority(TaskPriority)
}
