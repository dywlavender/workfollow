import Foundation

enum TaskDropPlacement: Equatable {
    case before(UUID), after(UUID), childOf(UUID), rootBefore(UUID), rootAfter(UUID)

    var targetID: UUID {
        switch self {
        case let .before(id), let .after(id), let .childOf(id), let .rootBefore(id), let .rootAfter(id): id
        }
    }
}

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
        // 平移规则只有一处实现（`ScheduleSemantics.shifted`）：due / dueEnd / deadline /
        // reminder 用同一条，避免新实例的截止与提醒落到不同天。
        func shifted(_ date: Date?) -> Date? {
            ScheduleSemantics.shifted(date, byDays: days, calendar: calendar)
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
        // 艾宾浩斯：interval 承载"已完成次数",spawn 带着递增后的值,引擎据此
        // 取记忆曲线的下一段间隔（RecurrenceRule.nextOccurrence .ebbinghaus）。
        if task.recurrence == .ebbinghaus {
            var ebbingRule = spawn.recurrenceRule ?? RecurrenceRule()
            ebbingRule.interval = max(1, ebbingRule.interval) + 1
            spawn.recurrenceRule = ebbingRule
        }
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

    @discardableResult
    func commitEditorReference(_ id: UUID, document: NativeDocument, sourceNoteID: UUID?) -> TaskActionResult {
        guard let task = store.task(id) else { return .failure(.missingTask) }
        guard task.deletedAt == nil else { return .failure(.deletedTask) }
        guard task.document != document || task.sourceNoteID != sourceNoteID else { return .success(id) }
        store.commitEditorReference(id, document: document, sourceNoteID: sourceNoteID, updatedAt: clock())
        return .success(id)
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

    /// 日程写入的**唯一入口**：所有宿主（面板直写 / 批量 / 将来的创建通道）都构造同一个
    /// `SchedulePlan`，plan → 字段的映射只在这里发生一次。
    ///
    /// `.tasks` 表示同一份 plan 应用到每个任务：字段全带（含 `dueEndAt` / offsets / rule），
    /// 整批算一步撤销；个别任务缺失/已删除则跳过，其余照常写入。
    @discardableResult
    func saveSchedule(_ plan: SchedulePlan, to target: ScheduleTarget) -> TaskActionResult {
        switch target {
        case .task(let id):
            return applySchedule(plan, to: id)
        case .tasks(let ids):
            guard let first = ids.first else { return .failure(.missingTask) }
            var firstFailure: TaskActionResult?
            store.transaction {
                for id in ids {
                    let result = applySchedule(plan, to: id)
                    if case .failure = result, firstFailure == nil { firstFailure = result }
                }
            }
            return firstFailure ?? .success(first)
        }
    }

    /// plan → 一条任务的字段映射，只此一份。语义与 `saveTiming` 完全一致
    /// （offsets 为空数组 = 清除多级提醒，旧式 `reminderAt` 重新生效）。
    private func applySchedule(_ plan: SchedulePlan, to id: UUID) -> TaskActionResult {
        guard let current = store.task(id) else { return .failure(.missingTask) }
        guard current.deletedAt == nil else { return .failure(.deletedTask) }
        return saveTiming(id, schedule: plan.schedule, reminder: plan.reminder,
                          frequency: plan.frequency, recurrenceRule: plan.recurrenceRule,
                          reminderOffsets: plan.reminderOffsets)
    }

    /// 创建通道的 plan 版：宿主产出 `SchedulePlan`，不再逐字段拆参。
    /// （新建对话框此前自己拼 `TaskSchedule`，既没有时间段也传不了多级提醒。）
    func createDraft(title: String, list: String, plan: SchedulePlan, priority: TaskPriority,
                     tags: [String], document: NativeDocument = .empty) -> TaskActionResult {
        createDraft(title: title, list: list, schedule: plan.schedule, priority: priority,
                    tags: tags, reminder: plan.reminder,
                    reminderOffsets: plan.reminderOffsets,
                    frequency: plan.frequency, recurrenceRule: plan.recurrenceRule,
                    document: document)
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

    /// 批量合并（滴答对齐,用户实机验证:所选任务全部变成子任务,父任务是
    /// 新建的）。新父任务落在第一条所选任务的清单里,标题"合并任务";
    /// 已关闭/已转换的任务被 setParent 策略自然跳过。单事务,一步撤销。
    func mergeTasks(_ ids: Set<UUID>) -> TaskActionResult {
        let ordered = store.tasks.filter { ids.contains($0.id) && $0.deletedAt == nil && $0.skippedAt == nil }
        guard ordered.count >= 2 else { return .failure(.missingTask) }
        var parentResult: TaskActionResult = .failure(.missingTask)
        store.transaction {
            parentResult = create(title: "合并任务", list: ordered[0].list,
                                  schedule: TaskSchedule(), priority: .none)
            guard let parentID = parentResult.taskID else { return }
            for task in ordered {
                _ = setParent(task.id, parentID: parentID)
            }
        }
        return parentResult
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
                case .pin(let isPinned):
                    _ = setPinned(task.id, isPinned)
                case .duplicate:
                    if !ids.contains(task.parentID ?? task.id) || task.parentID == nil { _ = duplicate(task.id) }
                case .abandon:
                    if !task.isClosed { _ = abandon(task.id) }
                case .tags(let picked):
                    // 追加去重:保留任务已有标签,只并入选中的新标签。
                    var merged = task.tags
                    for tag in picked where !merged.contains(tag) { merged.append(tag) }
                    if merged != task.tags { _ = setTags(task.id, merged) }
                case .linkParent(let parentID):
                    if task.id != parentID { _ = setParent(task.id, parentID: parentID) }
                case .move(let list):
                    if task.parentID == nil { _ = moveToList(task.id, TaskList(name: list)) }
                case .schedule(let schedule):
                    // 面板可能是「时间段」模式提交的，`dueEndAt` 必须一起落地；
                    // `deadlineAt` 不走批量通道，保留任务原值。
                    _ = setSchedule(task.id, TaskSchedule(dueAt: schedule.dueAt, hasTime: schedule.hasTime,
                                                          dueEndAt: schedule.dueEndAt,
                                                          deadlineAt: task.schedule.deadlineAt))
                case .priority(let priority): _ = setPriority(task.id, priority)
                case .reminderOffsets(let offsets): _ = setReminderOffsets(task.id, offsets)
                }
            }
        }
    }

    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, reminderOffsets: [Int]? = nil,
                     frequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil,
                     document: NativeDocument = .empty) -> TaskActionResult {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.invalidList) }
        var result: TaskActionResult = .failure(.missingTask)
        store.transaction {
            result = create(title: title, list: TaskList(name: list), schedule: schedule, priority: priority)
            if let id = result.taskID {
                _ = setTags(id, tags)
                _ = setReminder(id, reminder)
                // 多级提醒（面板里勾的「准时 / 提前…」）与旧式单点 `reminderAt` 是两个字段：
                // 创建路径必须一起写，否则面板里设的提醒只活在草稿里。
                _ = setReminderOffsets(id, reminderOffsets)
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
        guard !task.isConverted else { return .failure(.alreadyConverted) }
        if let parentID = task.parentID {
            guard let parent = store.task(parentID) else { return .failure(.missingTask) }
            guard parent.deletedAt == nil else { return .failure(.deletedTask) }
            guard !parent.isConverted else { return .failure(.alreadyConverted) }
        }

        let now = clock()
        func copy(_ source: Task, parent: UUID?, childOrder: Int) -> Task {
            Task(id: UUID(), title: source.title, document: source.document,
                 tags: source.tags, recurrence: source.recurrence,
                 recurrenceRule: source.recurrenceRule, reminderAt: source.reminderAt,
                 reminderOffsets: source.reminderOffsets, attachments: source.attachments,
                 list: source.list, priority: source.priority, schedule: source.schedule,
                 status: .active, parentID: parent, childOrder: childOrder,
                 createdAt: now, updatedAt: now, completedAt: nil, deletedAt: nil,
                 isPinned: false, abandonedAt: nil, skippedAt: nil,
                 convertedNoteID: nil, sourceNoteID: source.sourceNoteID)
        }

        let childOrder: Int
        if let parentID = task.parentID {
            childOrder = (store.tasks.filter { $0.parentID == parentID }
                .map(\.childOrder).max() ?? -1) + 1
        } else {
            childOrder = task.childOrder
        }
        let value = copy(task, parent: task.parentID, childOrder: childOrder)
        let copiedChildren = task.parentID == nil
            ? store.children(of: id).filter { !$0.isConverted }
                .map { copy($0, parent: value.id, childOrder: $0.childOrder) }
            : []
        store.commit(store.tasks + [value] + copiedChildren)
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

    /// Reparenting and order changes form one operation, including one undo step.
    @discardableResult
    func move(_ id: UUID, to placement: TaskDropPlacement) -> TaskActionResult {
        guard let source = store.task(id), let target = store.task(placement.targetID) else {
            return .failure(.missingTask)
        }
        guard source.id != target.id else { return .failure(.cannotParentToSelf) }
        guard source.deletedAt == nil, target.deletedAt == nil else { return .failure(.deletedTask) }
        let parentID: UUID?
        switch placement {
        case .childOf: parentID = target.id
        case .rootBefore, .rootAfter: parentID = nil
        case .before, .after: parentID = target.parentID
        }
        if let parentID, let parent = store.task(parentID) {
            if let rejection = TaskParentPolicy.rejection(task: source, parent: parent, tasks: store.tasks) {
                return .failure(rejection)
            }
        }
        var moved = source
        moved.parentID = parentID
        if let parentID, let parent = store.task(parentID) { moved.list = parent.list }
        moved.updatedAt = clock()
        var values = store.tasks.filter { $0.id != id }
        guard let targetIndex = values.firstIndex(where: { $0.id == target.id }) else {
            return .failure(.missingTask)
        }
        let insertion: Int
        switch placement {
        case .childOf:
            insertion = (values.lastIndex { $0.parentID == parentID } ?? targetIndex) + 1
        case .before, .rootBefore:
            insertion = targetIndex
        case .after, .rootAfter:
            insertion = targetIndex + 1
        }
        values.insert(moved, at: insertion)
        // Child order, not array position alone, drives the tree projection.
        for parent in Set([source.parentID, parentID].compactMap { $0 }) {
            var order = 0
            for i in values.indices where values[i].parentID == parent {
                values[i].childOrder = order
                order += 1
            }
        }
        if parentID == nil, let i = values.firstIndex(where: { $0.id == id }) { values[i].childOrder = 0 }
        store.commit(values)
        return .success(id)
    }

    // MARK: - 清单元数据（Round B1 加法：颜色/置顶只走 store 的 meta 通道，不碰任务数据）

    /// 收集箱是固定的系统清单：不可改名、不可删除、也不可着色/置顶（对齐 Flutter）。
    private func canManageList(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != TaskList.inbox.name
    }

    /// 对一个清单的 meta 做变更并提交；隐式清单（快速添加里 @新清单 产生、尚未注册的）
    /// 首次从侧栏管理时注册进 store.lists，使颜色/置顶与清单本身一起持久化、可删除。
    private func commitListMeta(_ raw: String, ensureFolder: String? = nil,
                                mutation: (inout TaskListMeta) -> Void) -> Bool {
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
        // 目标文件夹不存在就顺手建出来：与 meta 同一次提交 = 一步撤销。
        var folders: [TaskListFolder]? = nil
        if let ensureFolder, store.listFolder(named: ensureFolder) == nil {
            folders = store.listFolders + [TaskListFolder(
                name: ensureFolder,
                sortOrder: nextListFolderOrder(metas: metas, folders: store.listFolders))]
        }
        if store.lists.contains(name) {
            store.commit(store.tasks, listMetas: metas, listFolders: folders)
        } else {
            store.commit(store.tasks, lists: store.lists + [name], listMetas: metas, listFolders: folders)
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

    /// 设置清单图标（Emoji）。nil / 空串 = 清除图标，侧栏回落到色点。
    @discardableResult
    func setListIcon(_ name: String, _ icon: String?) -> Bool {
        let trimmed = icon?.trimmingCharacters(in: .whitespacesAndNewlines)
        return commitListMeta(name) {
            $0.icon = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
    }

    /// 新建文件夹（滴答「清单编辑页 → 更多设置 → 文件夹 → 添加文件夹」路径）：
    /// **允许空文件夹**，随后再往里放清单。空名或重名 → false。
    @discardableResult
    func saveListFolder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, store.listFolder(named: trimmed) == nil else { return false }
        let folder = TaskListFolder(name: trimmed,
                                    sortOrder: nextListFolderOrder(metas: store.listMetas,
                                                                   folders: store.listFolders))
        var folders = store.listFolders
        folders.append(folder)
        store.commit(store.tasks, listFolders: folders)
        return true
    }

    /// 新文件夹排在**现有清单与文件夹之后**，避免与清单的 sortOrder 撞车（撞车就只能按名字比大小）。
    private func nextListFolderOrder(metas: [TaskListMeta], folders: [TaskListFolder]) -> Int {
        max(metas.map(\.sortOrder).max() ?? -1, folders.map(\.sortOrder).max() ?? -1) + 1
    }

    /// 把两个清单放进同一个文件夹（滴答拖拽路径：把一个清单拖到另一个上方）。
    /// 文件夹不存在则建；**一次提交 = 一步撤销**（拖拽是一个用户动作，不该产生两步历史）。
    @discardableResult
    func combineListsIntoFolder(_ first: String, _ second: String, folder: String) -> Bool {
        let target = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, first != second,
              canManageList(first), canManageList(second) else { return false }
        var metas = store.listMetas
        var folders = store.listFolders
        var changed = false
        for name in [first, second] {
            guard let index = metas.firstIndex(where: { $0.name == name }) else { continue }
            if metas[index].folderName != target {
                metas[index].folderName = target
                changed = true
            }
        }
        if !folders.contains(where: { $0.name == target }) {
            folders.append(TaskListFolder(name: target,
                                          sortOrder: nextListFolderOrder(metas: metas, folders: folders)))
            changed = true
        }
        guard changed else { return false }
        store.commit(store.tasks, listMetas: metas, listFolders: folders)
        return true
    }

    /// 把清单放进文件夹（nil / 空串 = 移出文件夹回到顶层）。收集箱不可归类。
    /// 目标文件夹不存在时顺手建出来（「移动到文件夹 → 新建文件夹…」这条路径）。
    @discardableResult
    func setListFolder(_ name: String, _ folder: String?) -> Bool {
        let trimmed = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return commitListMeta(name, ensureFolder: target) { $0.folderName = target }
    }

    /// 重命名文件夹：**文件夹记录与归属它的清单一起改**（一次提交、一步撤销）。
    @discardableResult
    func renameListFolder(from old: String, to new: String) -> Bool {
        let target = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target != old else { return false }
        var metas = store.listMetas
        var folders = store.listFolders
        var changed = false
        for index in metas.indices where metas[index].folderName == old {
            metas[index].folderName = target
            changed = true
        }
        if let index = folders.firstIndex(where: { $0.name == old }) {
            folders[index].name = target
            changed = true
        }
        guard changed else { return false }
        store.commit(store.tasks, listMetas: metas, listFolders: folders)
        return true
    }

    /// 解散文件夹：清单**保留**并回到顶层（官方 MCP 语义 dissolve + ungroup，与笔记侧同口径）。
    @discardableResult
    func dissolveListFolder(_ folder: String) -> Bool {
        var metas = store.listMetas
        var changed = false
        for index in metas.indices where metas[index].folderName == folder {
            metas[index].folderName = nil
            changed = true
        }
        let folders = store.listFolders.filter { $0.name != folder }
        if folders != store.listFolders { changed = true }
        guard changed else { return false }
        store.commit(store.tasks, listMetas: metas, listFolders: folders)
        return true
    }


    /// 分组内排序（清单级设置；nil = 恢复默认，跟随视图排序）。
    @discardableResult
    func setListSectionSort(_ list: String, _ sort: TaskSectionSort?) -> Bool {
        guard store.listMeta(for: list)?.sectionTaskSort != sort else { return false }
        return commitListMeta(list) { $0.sectionTaskSort = sort }
    }

    /// 侧栏拖拽排序：把清单移到 `target` 之前（nil = 移到末尾）。
    /// 顺序本体是 `store.lists`（meta.sortOrder 由 store 归一化为下标），
    /// 一次提交 = 一步撤销；颜色/置顶随名字继承。
    ///
    /// `clearsFolder = true` 时**同时移出文件夹**（落点在顶层空档）。滴答的
    /// "清单 ↔ 文件夹"归属只有拖拽一条路径（其前端无 moveProject/移出 之类文案，
    /// 见提交记录），所以"拖到顶层 = 移出"是对它行为的推断实现——顺序与归属
    /// 在同一次提交里落定，撤销一次全复原。
    @discardableResult
    func moveList(_ name: String, before target: String?, clearsFolder: Bool = false) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name_ = trimmed
        guard store.lists.contains(name_), canManageList(name_), target != name_ else { return false }
        var lists = store.lists.filter { $0 != name_ }
        if let target {
            guard let index = lists.firstIndex(of: target) else { return false }
            lists.insert(name_, at: index)
        } else {
            lists.append(name_)
        }
        var metas = store.listMetas
        var metaChanged = false
        if clearsFolder, let index = metas.firstIndex(where: { $0.name == name_ }),
           metas[index].folderName != nil {
            metas[index].folderName = nil
            metaChanged = true
        }
        guard lists != store.lists || metaChanged else { return false }
        store.commit(store.tasks, lists: lists, listMetas: metaChanged ? metas : nil)
        return true
    }

    // MARK: 清单内自定义分组（滴答第三级）

    /// 添加分组（排在清单末尾）。空名 / 同清单重名 → false。
    @discardableResult
    func addListSection(_ list: String, title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canManageList(list) else { return false }
        guard !store.listSections.contains(where: { $0.listName == list && $0.title == trimmed }) else {
            return false
        }
        let order = (store.listSections.filter { $0.listName == list }.map(\.sortOrder).max() ?? -1) + 1
        var sections = store.listSections
        sections.append(TaskListSection(listName: list, title: trimmed, sortOrder: order))
        store.commit(store.tasks, listSections: sections)
        return true
    }

    /// 重命名分组：**id 不变**，任务归属不受影响。
    /// 在某个分组里新建任务（滴答分组标题的 `+`）。
    /// 建任务与归入分组放在**一个事务**里：对用户是一个动作，就该是一步撤销。
    @discardableResult
    func createTaskInSection(_ sectionID: String, list: String, title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canManageList(list),
              store.listSection(sectionID) != nil else { return false }
        var created = false
        store.transaction {
            let result = createDraft(title: trimmed, list: list, schedule: TaskSchedule(),
                                     priority: .none, tags: [], reminder: nil,
                                     frequency: TaskRepeat.never)
            if let id = result.taskID {
                _ = setTaskSection(id, sectionID: sectionID)
                created = true
            }
        }
        return created
    }

    /// 在某个分组的**上方**插入新分组（`above == nil` 即追加到末尾）。
    /// 滴答分组标题菜单：「在上方添加分组 / 在下方添加分组」。
    @discardableResult
    func insertListSection(_ list: String, title: String, above id: String?) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canManageList(list) else { return false }
        guard !store.listSections.contains(where: { $0.listName == list && $0.title == trimmed }) else {
            return false
        }
        var ordered = store.listSections.filter { $0.listName == list }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
        let index = id.flatMap { target in ordered.firstIndex { $0.id == target } } ?? ordered.count
        ordered.insert(TaskListSection(listName: list, title: trimmed), at: index)
        var merged = store.listSections.filter { $0.listName != list }
        for (offset, section) in ordered.enumerated() {
            var copy = section
            copy.sortOrder = offset
            merged.append(copy)
        }
        store.commit(store.tasks, listSections: merged)
        return true
    }

    /// 把分组**连同其中的任务**移动到另一个清单（滴答分组标题菜单：「移动到 ▸ 清单」）。
    /// 分组是任务的归属，只搬分组会把任务落在没有分组的清单里，所以两者一起搬、一次撤销。
    @discardableResult
    func moveListSection(_ id: String, to list: String) -> Bool {
        let target = list.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, canManageList(target),
              let section = store.listSection(id), section.listName != target else { return false }
        var sections = store.listSections
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return false }
        sections[index].listName = target
        sections[index].sortOrder = (sections.filter { $0.listName == target && $0.id != id }
            .map(\.sortOrder).max() ?? -1) + 1
        var tasks = store.tasks
        for taskIndex in tasks.indices where tasks[taskIndex].sectionID == id {
            tasks[taskIndex].list = TaskList(name: target)
        }
        store.commit(tasks, listSections: sections)
        return true
    }

    @discardableResult
    func renameListSection(_ id: String, title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var sections = store.listSections
        guard let index = sections.firstIndex(where: { $0.id == id }),
              sections[index].title != trimmed else { return false }
        // 同清单重名拒绝：添加时会查重，重命名漏了就能造出两个同名分组。
        guard !sections.contains(where: { $0.id != id
                                          && $0.listName == sections[index].listName
                                          && $0.title == trimmed }) else { return false }
        sections[index].title = trimmed
        store.commit(store.tasks, listSections: sections)
        return true
    }

    /// 删除分组：任务**保留**并回到"未分组"（与文件夹同口径；官方未写明）。
    @discardableResult
    func removeListSection(_ id: String) -> Bool {
        let sections = store.listSections.filter { $0.id != id }
        guard sections.count != store.listSections.count else { return false }
        var tasks = store.tasks
        for index in tasks.indices where tasks[index].sectionID == id {
            tasks[index].sectionID = nil
        }
        store.commit(tasks, listSections: sections)
        return true
    }

    /// 任务改归属（nil = 移出分组）。一次提交 = 一步撤销。
    @discardableResult
    func setTaskSection(_ id: UUID, sectionID: String?) -> TaskActionResult {
        guard let index = store.tasks.firstIndex(where: { $0.id == id }) else { return .failure(.missingTask) }
        guard store.tasks[index].deletedAt == nil else { return .failure(.deletedTask) }
        guard store.tasks[index].sectionID != sectionID else { return .success(id) }
        var tasks = store.tasks
        tasks[index].sectionID = sectionID
        store.commit(tasks)
        return .success(id)
    }
}

enum TaskBatchOperation {
    case complete, delete, move(String), schedule(TaskSchedule), priority(TaskPriority)
    /// 置顶/取消置顶（阶段4）。子任务无置顶语义,跟随单任务右键菜单的口径:全部应用。
    case pin(Bool)
    /// 复制（阶段4）：父任务选中时子任务随父复制,批内子任务不再单独复制（避免双份）。
    case duplicate
    /// 放弃（阶段4）：已完成任务跳过（与单任务右键的禁用口径一致）。
    case abandon
    /// 批量添加标签（补齐轮）：picked 逐个并入所选任务的现有标签（去重），
    /// 空数组无意义，面板侧不提供。
    case tags([String])
    /// 批量关联主任务（补齐轮）：所选任务挂到同一父下，逐个走 TaskParentPolicy
    /// 校验（自环/已关闭/已是子任务等失败即跳过），父不得在批内由 UI 保证。
    case linkParent(UUID)
    /// Reminder offsets in minutes (0 = on time, negative = early); an empty
    /// list clears the stored offsets.
    case reminderOffsets([Int])
}
