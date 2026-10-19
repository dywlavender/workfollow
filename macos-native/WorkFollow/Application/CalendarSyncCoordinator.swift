import Foundation
import EventKit
import Combine

struct CalendarSyncConflict: Identifiable, Equatable {
    var id: String
    var title: String
    var task: CalendarEventFields
    var event: CalendarEventFields
}

@MainActor
final class CalendarSyncCoordinator: ObservableObject, ModuleStoreFlushable {
    let store: CalendarIntegrationStore
    @Published private(set) var calendars: [SystemCalendarInfo] = []
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var message: String?
    @Published private(set) var connectionTestResult: String?
    @Published private(set) var syncing = false
    @Published private(set) var conflicts: [CalendarSyncConflict] = []
    @Published private(set) var externalEvents: [SystemCalendarEvent] = []
    private let client: SystemCalendarClient
    private let clock: () -> Date
    private let calendar: Calendar
    private var tasks: [Task] = []
    private var activeListNames: [String] = []
    private var work: _Concurrency.Task<Void, Never>?
    private var generation = 0
    private var displayRange: DateInterval?
    private var choices: [String: Bool] = [:]
    var onNeedsSync: (() -> Void)?
    var applyExternal: ((CalendarTaskReference, CalendarEventFields, CalendarEventFields, Bool) async -> Bool)?
    private var subscription: AnyCancellable?

    init(directory: URL = JSONFileStore<CalendarIntegrationSnapshot>.moduleDirectory,
         client: SystemCalendarClient? = nil, clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        store = CalendarIntegrationStore(directory: directory)
        self.client = client ?? SystemCalendarService(); self.clock = clock; self.calendar = calendar
        authorization = self.client.authorization
        self.client.onChange = { [weak self] in self?.refreshAccess(); self?.onNeedsSync?() }
        store.onSettingsChange = { [weak self] in self?.onNeedsSync?() }
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func refreshAccess() {
        authorization = client.authorization
        calendars = client.calendars()
        if authorization != .fullAccess { externalEvents = [] }
    }
    func connect() async {
        do {
            let granted = try await client.requestAccess()
            refreshAccess()
            message = granted ? nil : "请在系统设置的日历权限中允许完整访问。"
            if granted { store.configure { $0.enabled = true } }
        } catch { message = error.localizedDescription }
    }
    func createDedicatedCalendar(title: String = "WorkFollow") {
        do {
            let value = try client.createCalendar(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
            refreshAccess()
            store.configure { $0.targetCalendarID = value.id; $0.enabled = true }
        } catch { message = error.localizedDescription }
    }
    func testConnection() {
        guard let target = store.snapshot.targetCalendarID else { message = "请先选择目标日历。"; return }
        var temporaryID: String?
        do {
            let start = clock().addingTimeInterval(300)
            var fields = CalendarEventFields(title: "WorkFollow 连接测试", start: start, end: start.addingTimeInterval(60), allDay: false)
            let url = URL(string: "workfollow://calendar-test")!
            let created = try client.save(fields, calendarID: target, sourceURL: url,
                notes: "临时连接测试，完成后自动移除。", timeZone: calendar.timeZone, existingID: nil)
            temporaryID = created.id
            guard client.event(id: created.id) != nil else { throw CalendarIntegrationError.message("日程写入后无法读取。") }
            fields.title = "WorkFollow 连接测试已通过"
            let changed = try client.save(fields, calendarID: target, sourceURL: url,
                notes: "临时连接测试，完成后自动移除。", timeZone: calendar.timeZone, existingID: created.id)
            try client.remove(id: changed.id); temporaryID = nil
            let day = calendar.startOfDay(for: clock())
            let allDay = CalendarEventFields(title: "WorkFollow 全天连接测试", start: day,
                end: calendar.date(byAdding: .day, value: 1, to: day)!, allDay: true)
            let dayEvent = try client.save(allDay, calendarID: target, sourceURL: url,
                notes: "全天日期边界验证，完成后自动移除。", timeZone: calendar.timeZone, existingID: nil)
            temporaryID = dayEvent.id
            guard client.event(id: dayEvent.id)?.fields == allDay else {
                throw CalendarIntegrationError.message("系统返回的全天日期范围不一致。")
            }
            try client.remove(id: dayEvent.id); temporaryID = nil
            connectionTestResult = "日历读写与全天日期验证通过，临时日程已移除。"
            NativeAcceptanceInteractionTrace.record("calendar.connection-test", ["passed": true])
        } catch {
            if let temporaryID { try? client.remove(id: temporaryID) }
            message = error.localizedDescription
            connectionTestResult = "日历连接测试失败：\(error.localizedDescription)"
            NativeAcceptanceInteractionTrace.record("calendar.connection-test", ["passed": false])
        }
    }
    func requestSync(tasks: [Task], activeLists: [String]) {
        self.tasks = tasks; activeListNames = activeLists; generation += 1
        guard work == nil else { return }
        work = _Concurrency.Task {
            syncing = true
            while true {
                let revision = generation
                await synchronize()
                if generation == revision { break }
            }
            syncing = false; work = nil
        }
    }
    func waitForSync() async { await work?.value }

    func showEvents(in range: DateInterval) {
        displayRange = range; reloadDisplayedEvents()
    }
    private func reloadDisplayedEvents() {
        guard store.snapshot.enabled, authorization == .fullAccess, let range = displayRange else {
            externalEvents = []; return
        }
        externalEvents = client.events(in: range, calendarIDs: store.snapshot.visibleCalendarIDs).filter { value in
            !store.snapshot.bindings.contains { !$0.detached && ($0.eventID == value.id || $0.reference.url == value.sourceURL) }
        }.sorted { $0.fields.start < $1.fields.start }
    }
    func previewCount(tasks: [Task]) -> Int {
        tasks.filter { store.snapshot.includes($0) && $0.schedule.dueAt != nil && !$0.isClosed && $0.deletedAt == nil && $0.parentID == nil }.count
    }
    func status(for task: Task) -> String {
        guard store.snapshot.includes(task) else { return "未同步" }
        if !store.snapshot.enabled { return "同步已暂停" }
        if authorization != .fullAccess { return "需要日历授权" }
        if store.snapshot.targetCalendarID == nil { return "请选择目标日历" }
        let related = store.snapshot.bindings.filter { $0.reference.taskID == task.id || (task.series != nil && $0.reference.occurrence?.seriesID == task.series?.id) }
        if related.contains(where: \.detached) { return "日程已移除，可重新关联" }
        if conflicts.contains(where: { related.map(\.id).contains($0.id) }) { return "日历修改待处理" }
        return related.isEmpty ? "等待同步" : "已关联 Apple 日历"
    }
    func reconnect(_ task: Task) {
        store.setBindings(store.snapshot.bindings.filter {
            !($0.detached && ($0.reference.taskID == task.id || (task.series != nil && $0.reference.occurrence?.seriesID == task.series?.id)))
        })
        onNeedsSync?()
    }
    func unlinkKeepingEvents(_ task: Task) {
        var bindings = store.snapshot.bindings
        for index in bindings.indices where bindings[index].reference.taskID == task.id ||
            (task.series != nil && bindings[index].reference.occurrence?.seriesID == task.series?.id) {
            bindings[index].detached = true
        }
        store.setBindings(bindings)
        store.setTask(task, enabled: false)
    }
    func resolve(_ conflict: CalendarSyncConflict, useCalendar: Bool) {
        choices[conflict.id] = useCalendar; onNeedsSync?()
    }

    private func synchronize() async {
        refreshAccess()
        defer { reloadDisplayedEvents() }
        guard store.snapshot.enabled, authorization == .fullAccess else { return }
        guard let target = store.snapshot.targetCalendarID,
              calendars.contains(where: { $0.id == target && $0.writable }) else {
            message = store.snapshot.autoSyncLists.isEmpty && !store.snapshot.taskOverrides.values.contains(true)
                ? nil : "请选择一个可写的目标日历。"
            return
        }
        let config = store.snapshot
        let now = clock()
        let range = DateInterval(start: calendar.date(byAdding: .day, value: -30, to: now)!,
                                 end: calendar.date(byAdding: .day, value: 90, to: now)!)
        let active = tasks.filter { activeListNames.contains($0.list.name) && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned }
        let occurrences = TaskOccurrenceProjection.occurrences(tasks: active, in: range, calendar: calendar)
        let exports = occurrences.compactMap { occurrence -> CalendarTaskExport? in
            guard config.includes(occurrence.task) else { return nil }
            return CalendarTaskMapping.export(occurrence.task,
                reference: .init(taskID: occurrence.sourceTaskID, occurrence: occurrence.task.recurrence != .never || occurrence.task.occurrenceKey != nil ? occurrence.key : nil),
                duration: config.defaultDurationMinutes, calendar: calendar)
        }
        // Fetch the managed calendar once. URLs repair bindings after account refreshes.
        let managed = client.events(in: range, calendarIDs: [target])
        var bindings = config.bindings
        var pendingConflicts: [CalendarSyncConflict] = []
        var errors: [String] = []
        for value in exports {
            do {
                let index = bindings.firstIndex { $0.id == value.reference.id }
                let old = index.map { bindings[$0] }
                if old?.detached == true { continue }
                let existing = old.flatMap { client.event(id: $0.eventID) }
                    ?? managed.first { $0.sourceURL == value.reference.url }
                if let old, existing == nil {
                    var detached = old; detached.detached = true
                    bindings[index!] = detached; continue
                }
                var result = value.fields
                if let old, let existing, existing.fields != old.lastSynced {
                    let choice = choices.removeValue(forKey: old.id)
                    let merge = CalendarTaskMapping.merge(base: old.lastSynced, task: value.fields, event: existing.fields)
                    if choice == false { result = value.fields }
                    else if choice == true || (config.bidirectional && merge != nil) {
                        result = choice == true ? existing.fields : merge!
                        if result != value.fields {
                            guard await applyExternal?(value.reference, result, old.lastSynced, old.derivedDuration) == true else {
                                throw CalendarIntegrationError.message("任务已变化，无法应用日历修改，请重试。")
                            }
                        }
                    } else {
                        pendingConflicts.append(.init(id: old.id, title: value.fields.title, task: value.fields, event: existing.fields))
                        continue
                    }
                }
                let saved: SystemCalendarEvent
                if let existing, existing.fields == result && existing.calendarID == target { saved = existing }
                else {
                    saved = try client.save(result, calendarID: target, sourceURL: value.reference.url,
                        notes: value.notes, timeZone: value.timeZone, existingID: existing?.id)
                }
                let binding = CalendarTaskBinding(reference: value.reference, eventID: saved.id, calendarID: saved.calendarID,
                    lastSynced: result, derivedDuration: value.derivedDuration)
                if let index { bindings[index] = binding } else { bindings.append(binding) }
            } catch { errors.append(error.localizedDescription) }
        }
        let desiredIDs = Set(exports.map { $0.reference.id })
        for old in bindings where !desiredIDs.contains(old.id) && !old.detached {
            // Past history remains in Calendar; only future managed copies are removed.
            guard (client.event(id: old.eventID)?.fields.end ?? old.lastSynced.end) > now else { continue }
            do {
                try client.remove(id: old.eventID)
                bindings.removeAll { $0.id == old.id }
            } catch { errors.append(error.localizedDescription) }
        }
        store.setBindings(bindings)
        conflicts = pendingConflicts
        message = errors.first
        reloadDisplayedEvents()
    }

    func flush(_ completion: @escaping (Error?) -> Void) { store.flush(completion) }
}
