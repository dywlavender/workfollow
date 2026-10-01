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
    func setParent(_ id: UUID, parentID: UUID) -> TaskActionResult {
        guard let task = store.task(id), let parent = store.task(parentID) else {
            return .failure(.missingTask)
        }
        if let rejection = TaskParentPolicy.rejection(task: task, parent: parent, tasks: store.tasks) {
            return .failure(rejection)
        }
        guard task.parentID != parentID else { return .success(id) }

        let lastSiblingOrder = store.tasks.filter { $0.parentID == parentID }
            .map(\.childOrder).max() ?? -1
        let childOrder = lastSiblingOrder + 1
        var replacement = task
        replacement.parentID = parentID
        replacement.childOrder = childOrder
        replacement.list = parent.list
        replacement.updatedAt = clock()
        store.commit(store.tasks.map { $0.id == id ? replacement : $0 })
        return .success(id)
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
        var resultID = id
        if task.recurrence != .never,
           let occurrence = makeNextOccurrence(of: task, completedAt: now) {
            snapshot.append(occurrence.spawn)
            snapshot += occurrence.children
            resultID = occurrence.spawn.id
        }
        store.commit(snapshot)
        // The returned id points at the spawned occurrence so callers can move
        // the selection onto the next instance of the chain.
        return .success(resultID)
    }

    /// Builds the next occurrence for a completing or skipped recurring task
    /// (Flutter's _spawnNextRecurrence): due, deadline and reminder ride the
    /// recurrence delta, the count boundary is consumed, and the children come
    /// along as a fresh incomplete checklist whose own repeat rules are cleared.
    private func makeNextOccurrence(of task: Task, completedAt: Date) -> (spawn: Task, children: [Task])? {
        let base = task.schedule.dueAt ?? calendar.startOfDay(for: completedAt)
        var rule = task.recurrenceRule ?? RecurrenceRule()
        rule.monthDay = rule.monthDay ?? calendar.component(.day, from: base)
        guard let next = rule.nextOccurrence(after: base, frequency: task.recurrence, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: base, to: next).day ?? 0
        func shifted(_ date: Date?) -> Date? {
            date.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        }
        let now = clock()
        var spawn = Task(id: UUID(), title: task.title, document: task.document,
                         tags: task.tags, recurrence: task.recurrence, list: task.list,
                         priority: task.priority, schedule: task.schedule,
                         parentID: task.parentID, childOrder: task.childOrder,
                         createdAt: now, updatedAt: now)
        spawn.schedule.dueAt = next
        spawn.schedule.dueEndAt = shifted(task.schedule.dueEndAt)
        spawn.schedule.deadlineAt = shifted(task.schedule.deadlineAt)
        spawn.reminderAt = shifted(task.reminderAt)
        spawn.reminderOffsets = task.reminderOffsets
        spawn.attachments = task.attachments
        spawn.recurrenceRule = rule.following
        spawn.sourceNoteID = task.sourceNoteID
        let children = store.children(of: task.id).enumerated().map { order, child -> Task in
            var value = Task(id: UUID(), title: child.title, document: child.document,
                             tags: child.tags, list: child.list, priority: child.priority,
                             schedule: child.schedule, parentID: spawn.id, childOrder: order,
                             createdAt: now, updatedAt: now)
            value.schedule.dueAt = shifted(child.schedule.dueAt)
            value.schedule.dueEndAt = shifted(child.schedule.dueEndAt)
            value.schedule.deadlineAt = shifted(child.schedule.deadlineAt)
            value.reminderAt = shifted(child.reminderAt)
            value.reminderOffsets = child.reminderOffsets
            value.attachments = child.attachments
            value.convertedNoteID = child.convertedNoteID
            value.sourceNoteID = child.sourceNoteID
            // Fresh defaults: status .active, recurrence .never, rule nil —
            // only the parent drives the chain of occurrences.
            return value
        }
        return (spawn, children)
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
            // Normalization drops out-of-range calendar fields and zero counts
            // (never-ending), mirroring Flutter's RecurrenceDraft.normalized.
            task.recurrenceRule = frequency == .never ? nil : rule?.normalized(calendar: calendar)
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
                    recurrenceRule: RecurrenceRule? = nil, reminderOffsets: [Int]? = nil) -> TaskActionResult {
        guard let current = store.task(id) else { return .failure(.missingTask) }
        guard current.deletedAt == nil else { return .failure(.deletedTask) }
        store.transaction {
            _ = setSchedule(id, schedule)
            _ = setReminder(id, reminder)
            // nil leaves the stored offsets untouched; an explicit list (even
            // empty) replaces them.
            if let reminderOffsets { _ = setReminderOffsets(id, reminderOffsets) }
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
                case .reminderOffsets(let offsets): _ = setReminderOffsets(task.id, offsets)
                }
            }
        }
    }

    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, frequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil,
                     document: NativeDocument = .empty) -> TaskActionResult {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.invalidList) }
        var result: TaskActionResult = .failure(.missingTask)
        store.transaction {
            result = create(title: title, list: TaskList(name: list), schedule: schedule, priority: priority)
            if let id = result.taskID {
                _ = setTags(id, tags)
                _ = setReminder(id, reminder)
                _ = setRecurrence(id, frequency: frequency, rule: recurrenceRule)
                // 正文与其它属性同处一个事务：快速添加的 Tab 描述要么整条任务都建好，
                // 要么一点都不留下。空正文跳过，避免写一个空段落。
                if !document.isEmpty { _ = setDocument(id, document) }
            }
        }
        return result
    }

    /// Construct the complete template snapshot before publishing it. One commit,
    /// one undo step, and no intermediate parent lacking its document/children.
    func createFromTemplate(_ template: TaskTemplate, list: TaskList) -> TaskActionResult {
        let title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .failure(.invalidList) }
        let now = clock()
        let parent = Task(id: UUID(), title: title, document: template.document,
                          tags: template.tags, list: list, priority: template.priority ?? .none,
                          schedule: TaskSchedule(dueAt: template.schedule?.date(from: now, calendar: calendar)),
                          parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        let children = template.childTitles.enumerated().map { index, title in
            Task(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                 list: list, priority: .none, schedule: TaskSchedule(),
                 parentID: parent.id, childOrder: index, createdAt: now, updatedAt: now)
        }
        store.commit(store.tasks + [parent] + children)
        return .success(parent.id)
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

    /// Skips the current occurrence of a recurring task (Flutter parity): the
    /// next occurrence is spawned exactly as completion would, and the current
    /// instance stays in storage stamped `skippedAt` — persisted, but excluded
    /// from active projections. Undo restores the pre-skip snapshot, which
    /// removes the spawned occurrence and clears the skip stamp.
    @discardableResult
    func skipOccurrence(_ id: UUID) -> TaskActionResult {
        guard let task = store.task(id), task.deletedAt == nil, task.skippedAt == nil,
              !task.isClosed, task.recurrence != .never else { return .failure(.missingTask) }
        let now = clock()
        guard let occurrence = makeNextOccurrence(of: task, completedAt: now) else { return .failure(.missingTask) }
        var snapshot = store.tasks
        guard let index = snapshot.firstIndex(where: { $0.id == id }) else { return .failure(.missingTask) }
        snapshot[index].skippedAt = now
        snapshot[index].updatedAt = now
        snapshot.append(occurrence.spawn)
        snapshot += occurrence.children
        store.commit(snapshot)
        return .success(occurrence.spawn.id)
    }

    /// Reminder offsets in minutes relative to the schedule anchor: 0 = on
    /// time, negative = early. An empty list clears the offsets so the legacy
    /// absolute `reminderAt` applies again.
    @discardableResult
    func setReminderOffsets(_ id: UUID, _ offsets: [Int]?) -> TaskActionResult {
        edit(id) { $0.reminderOffsets = Self.normalizedOffsets(offsets) }
    }

    /// Deduplicates into ascending (earliest-first) on-time/early values;
    /// positive inputs are read as "early" magnitudes like the picker sends.
    static func normalizedOffsets(_ offsets: [Int]?) -> [Int]? {
        guard let offsets else { return nil }
        let values = Set(offsets.map { $0 > 0 ? -$0 : $0 }).filter { $0 <= 0 }.sorted()
        return values.isEmpty ? nil : values
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

    // MARK: - 清单元数据（Round B1 加法：颜色/置顶只走 store 的 meta 通道，不碰任务数据）

    /// 收集箱是固定的系统清单：不可改名、不可删除、也不可着色/置顶（对齐 Flutter）。
    private func canManageList(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != TaskList.inbox.name
    }

    /// 对一个清单的 meta 做变更并提交；隐式清单（快速添加里 @新清单 产生、尚未注册的）
    /// 首次从侧栏管理时注册进 store.lists，使颜色/置顶与清单本身一起持久化、可删除。
    private func commitListMeta(_ raw: String, mutation: (inout TaskListMeta) -> Void) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canManageList(name) else { return false }
        var metas = store.listMetas
        if let index = metas.firstIndex(where: { $0.name == name }) {
            mutation(&metas[index])
        } else {
            var fresh = TaskListMeta(name: name)
            mutation(&fresh)
            metas.append(fresh)
        }
        if store.lists.contains(name) {
            store.commit(store.tasks, listMetas: metas)
        } else {
            store.commit(store.tasks, lists: store.lists + [name], listMetas: metas)
        }
        return true
    }

    /// 设置清单颜色（WFListPalette 下标；nil 表示清除显式色，回到按名推导的稳定色）。
    @discardableResult
    func setListColor(_ name: String, _ colorIndex: Int?) -> Bool {
        commitListMeta(name) {
            $0.colorIndex = colorIndex.map { min(max($0, 0), WFListPalette.argb.count - 1) }
            $0.colorARGB = nil
        }
    }

    /// 置顶/取消置顶清单；侧栏置顶分组排在其余清单之前。
    @discardableResult
    func setListPinned(_ name: String, _ isPinned: Bool) -> Bool {
        commitListMeta(name) { $0.isPinned = isPinned }
    }
}

enum TaskBatchOperation {
    case complete, delete, move(String), schedule(TaskSchedule), priority(TaskPriority)
    /// Reminder offsets in minutes (0 = on time, negative = early); an empty
    /// list clears the stored offsets.
    case reminderOffsets([Int])
}
