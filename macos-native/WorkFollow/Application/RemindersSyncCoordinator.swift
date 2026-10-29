import Combine
import EventKit
import Foundation

struct RemindersSyncConflict: Identifiable, Equatable {
    var id: String
    var title: String
    var task: ReminderTaskFields
    var reminder: ReminderTaskFields
}

enum AppleTaskSyncStatus: Equatable {
    case off, connecting, needsAccess, syncing, needsAttention(Int), ready

    var title: String {
        switch self {
        case .off: return "任务同步未开启"
        case .connecting: return "正在连接 Apple 提醒事项…"
        case .needsAccess: return "任务同步需要授权"
        case .syncing: return "正在同步任务…"
        case .needsAttention(let count): return "有 \(count) 项同步问题待处理"
        case .ready: return "已写入 Apple 提醒事项"
        }
    }
    var issueCount: Int {
        switch self {
        case .needsAttention(let count): return count
        case .needsAccess: return 1
        default: return 0
        }
    }
}

@MainActor
final class RemindersSyncCoordinator: ObservableObject, ModuleStoreFlushable {
    let store: RemindersIntegrationStore
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var accounts: [SystemReminderAccount] = []
    @Published private(set) var lists: [SystemReminderList] = []
    @Published private(set) var syncing = false
    @Published private(set) var connecting = false
    @Published private(set) var message: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var conflicts: [RemindersSyncConflict] = []
    private let client: SystemRemindersClient
    private let calendar: Calendar
    private let clock: () -> Date
    private var tasks: [Task] = []
    private var activeLists: [String] = []
    private var mutedLists: Set<String> = []
    private var generation = 0
    private var work: _Concurrency.Task<Void, Never>?
    private var choices: [String: Bool] = [:]
    private var subscription: AnyCancellable?
    var onNeedsSync: (() -> Void)?
    var onSyncFinished: (() -> Void)?
    var applyExternal: ((CalendarTaskReference, ReminderTaskFields, ReminderTaskFields) async -> Bool)?

    var presentationStatus: AppleTaskSyncStatus {
        if connecting { return .connecting }
        if !store.snapshot.enabled { return message == nil ? .off : .needsAttention(1) }
        if authorization != .fullAccess { return .needsAccess }
        let issues = conflicts.count + (message == nil ? 0 : 1)
        if issues > 0 { return .needsAttention(issues) }
        if syncing || lastSyncAt == nil { return .syncing }
        return .ready
    }

    init(directory: URL = JSONFileStore<RemindersIntegrationSnapshot>.moduleDirectory,
         client: SystemRemindersClient? = nil, clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.calendar = calendar; self.clock = clock
        self.client = client ?? SystemRemindersService(calendar: calendar)
        store = RemindersIntegrationStore(directory: directory)
        authorization = self.client.authorization
        self.client.onChange = { [weak self] in self?.onNeedsSync?() }
        store.onSettingsChange = { [weak self] in self?.onNeedsSync?() }
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func refreshAccess() {
        authorization = client.authorization
        lists = client.lists(); accounts = client.accounts()
    }
    func connect() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            let granted: Bool
            if client.authorization == .fullAccess { granted = true }
            else { granted = try await client.requestAccess() }
            refreshAccess()
            guard granted else {
                message = "请在系统设置 → 隐私与安全性 → 提醒事项中允许 WorkFollow 访问。"
                return
            }
            let target = try connectionTarget()
            store.configure {
                $0.targetListID = target.id; $0.enabled = true
                $0.autoSyncLists = [RemindersIntegrationSnapshot.allTasksScope]
                $0.taskOverrides.removeAll()
                $0.bidirectional = true; $0.useSystemAlerts = true
            }
            message = nil
        } catch { message = error.localizedDescription }
    }
    private func connectionTarget() throws -> SystemReminderList {
        guard let account = accounts.first(where: { $0.title.localizedCaseInsensitiveContains("iCloud") }) else {
            throw CalendarIntegrationError.message("未找到 iCloud 提醒事项。请在系统设置 → Apple 账户 → iCloud 中开启“提醒事项”，然后重新连接。")
        }
        if let existing = lists.first(where: {
            $0.accountID == account.id && $0.writable && $0.title.localizedCaseInsensitiveCompare("WorkFollow") == .orderedSame
        }) { return existing }
        let created = try client.createList(title: "WorkFollow", accountID: account.id)
        refreshAccess()
        return created
    }
    func requestSync(tasks: [Task], activeLists: [String], mutedLists: Set<String> = []) {
        self.tasks = tasks; self.activeLists = activeLists; self.mutedLists = mutedLists; generation += 1
        guard work == nil else { return }
        work = _Concurrency.Task {
            syncing = true
            while true {
                let revision = generation
                await synchronize(revision: revision)
                if generation == revision { break }
            }
            syncing = false; work = nil; onSyncFinished?()
        }
    }
    func waitForSync() async { await work?.value }

    private func exports(_ config: RemindersIntegrationSnapshot) -> [ReminderTaskExport] {
        let eligible = tasks.filter { activeLists.contains($0.list.name) && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned && !$0.isConverted }
        let bound = Set(config.bindings.map(\.id))
        var values: [String: ReminderTaskExport] = [:]
        func append(_ task: Task, _ reference: CalendarTaskReference) {
            guard config.includes(task), task.status != .completed || bound.contains(reference.id) else { return }
            var value = ReminderTaskMapping.export(task, reference: reference, calendar: calendar)
            value.suppressesAlerts = mutedLists.contains(task.list.name)
            if value.suppressesAlerts { value.fields.alarms = [] }
            values[reference.id] = value
        }
        for task in eligible { append(task, ReminderTaskMapping.reference(task, calendar: calendar)) }
        let range = DateInterval(start: clock(), end: calendar.date(byAdding: .day, value: 30, to: clock())!)
        for occurrence in TaskOccurrenceProjection.occurrences(tasks: eligible, in: range, calendar: calendar) where occurrence.isVirtual {
            append(occurrence.task, .init(taskID: occurrence.sourceTaskID, occurrence: occurrence.key))
        }
        // Keep old projected occurrences addressable after their date passes.
        // They can still be completed on the phone and must not disappear overdue.
        for binding in config.bindings where values[binding.id] == nil {
            if let occurrence = CalendarTaskReference.resolve(binding.reference, tasks: eligible, calendar: calendar) {
                append(occurrence.task, binding.reference)
            }
        }
        return values.values.sorted { $0.reference.id < $1.reference.id }
    }

    private func synchronize(revision: Int) async {
        refreshAccess()
        guard store.snapshot.enabled, authorization == .fullAccess else { return }
        let config = store.snapshot
        guard let target = config.targetListID, lists.contains(where: { $0.id == target && $0.writable }) else {
            message = "未能连接 iCloud 的 WorkFollow 清单，请重试连接。"
            return
        }
        do {
            let listIDs = Array(Set([target] + config.bindings.map(\.listID)))
            let managed = try await client.reminders(listIDs: listIDs)
            guard revision == generation else { return }
            let values = exports(config)
            var bindings = config.bindings
            var pendingConflicts: [RemindersSyncConflict] = []
            var errors: [String] = []
            for value in values {
                guard revision == generation else { return }
                do {
                    let index = bindings.firstIndex { $0.id == value.reference.id }
                    let old = index.map { bindings[$0] }
                    if old?.detached == true { continue }
                    let existing = old.flatMap { previous in managed.first { $0.id == previous.reminderID } }
                        ?? managed.first { $0.sourceURL == value.reference.url }
                    if old != nil, existing == nil {
                        bindings[index!].detached = true
                        continue
                    }
                    var result = value.fields
                    if let old, let existing, existing.fields != old.lastSynced {
                        let choice = choices.removeValue(forKey: old.id)
                        var base = old.lastSynced, remote = existing.fields
                        if value.suppressesAlerts { base.alarms = []; remote.alarms = [] }
                        let merged = ReminderTaskMapping.merge(base: base, task: value.fields, reminder: remote)
                        if choice == false { result = value.fields }
                        else if choice == true || (config.bidirectional && merged != nil) {
                            result = choice == true ? remote : merged!
                            if result != value.fields {
                                guard await applyExternal?(value.reference, result, value.fields) == true else {
                                    throw CalendarIntegrationError.message("任务已变化，提醒事项修改将在下次同步时重试。")
                                }
                                guard revision == generation else { return }
                            }
                        } else {
                            pendingConflicts.append(.init(id: old.id, title: value.fields.title, task: value.fields, reminder: existing.fields))
                            continue
                        }
                    }
                    let saved: SystemReminderItem
                    if let existing, existing.fields == result, existing.listID == target { saved = existing }
                    else {
                        saved = try client.save(result, listID: target, sourceURL: value.reference.url,
                            notes: value.notes, existingID: existing?.id)
                    }
                    let binding = ReminderTaskBinding(reference: value.reference, reminderID: saved.id,
                        listID: saved.listID, lastSynced: saved.fields)
                    if let index { bindings[index] = binding } else { bindings.append(binding) }
                } catch { errors.append(error.localizedDescription) }
            }
            let desired = Set(values.map { $0.reference.id })
            for old in bindings where !desired.contains(old.id) && !old.detached {
                do {
                    try client.remove(id: old.reminderID)
                    bindings.removeAll { $0.id == old.id }
                } catch { errors.append(error.localizedDescription) }
            }
            store.setBindings(bindings)
            conflicts = pendingConflicts; message = errors.first
            if errors.isEmpty { lastSyncAt = clock() }
        } catch { message = error.localizedDescription }
    }

    func handlesAlerts(for task: Task) -> Bool {
        guard store.snapshot.enabled, store.snapshot.useSystemAlerts, authorization == .fullAccess,
              store.snapshot.includes(task) else { return false }
        let reference = ReminderTaskMapping.reference(task, calendar: calendar)
        let expected = ReminderTaskMapping.fields(task, calendar: calendar)
        return store.snapshot.bindings.contains {
            $0.id == reference.id && !$0.detached && $0.listID == store.snapshot.targetListID && $0.lastSynced == expected
        }
    }
    func status(for task: Task) -> String {
        guard store.snapshot.includes(task) else { return "未同步" }
        if !store.snapshot.enabled { return "同步已暂停" }
        if authorization != .fullAccess { return "需要提醒事项授权" }
        if store.snapshot.targetListID == nil { return "请选择目标提醒事项清单" }
        let related = store.snapshot.bindings.filter { RemindersIntegrationStore.matches($0, task) }
        if related.contains(where: \.detached) { return "提醒事项已移除，可重新关联" }
        if conflicts.contains(where: { item in related.contains { $0.id == item.id } }) { return "双方修改待处理" }
        if message != nil { return "同步待重试，请查看设置" }
        let expected = ReminderTaskMapping.fields(task, calendar: calendar)
        return related.contains(where: { $0.lastSynced == expected })
            ? "已写入提醒事项" : "等待写入提醒事项"
    }
    func reconnect(_ task: Task) { store.setTask(task, enabled: true) }
    func unlinkKeepingCopy(_ task: Task) {
        var bindings = store.snapshot.bindings
        for index in bindings.indices where RemindersIntegrationStore.matches(bindings[index], task) { bindings[index].detached = true }
        store.setBindings(bindings); store.setTask(task, enabled: false)
    }
    func resolve(_ conflict: RemindersSyncConflict, useReminder: Bool) {
        choices[conflict.id] = useReminder; onNeedsSync?()
    }
    func flush(_ completion: @escaping (Error?) -> Void) { store.flush(completion) }
}
