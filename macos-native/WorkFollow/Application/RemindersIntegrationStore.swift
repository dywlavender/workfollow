import Combine
import Foundation

struct ReminderTaskBinding: Codable, Equatable, Identifiable {
    var reference: CalendarTaskReference
    var reminderID: String
    var listID: String
    var lastSynced: ReminderTaskFields
    var detached = false
    var id: String { reference.id }
}

struct RemindersIntegrationSnapshot: Codable {
    static let allTasksScope = "__all_active_task_lists__"
    var enabled = false
    var targetListID: String?
    var autoSyncLists: [String] = []
    var taskOverrides: [String: Bool] = [:]
    var bidirectional = true
    var useSystemAlerts = true
    var bindings: [ReminderTaskBinding] = []
    var syncsAllTasks: Bool { autoSyncLists.contains(Self.allTasksScope) }

    func includes(_ task: Task) -> Bool {
        taskOverrides[(task.series?.id ?? task.id).uuidString] ?? (syncsAllTasks || autoSyncLists.contains(task.list.name))
    }
}

@MainActor
final class RemindersIntegrationStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var snapshot: RemindersIntegrationSnapshot
    private let file: JSONFileStore<RemindersIntegrationSnapshot>
    var onSettingsChange: (() -> Void)?
    init(directory: URL = JSONFileStore<RemindersIntegrationSnapshot>.moduleDirectory) {
        file = JSONFileStore(filename: "reminders-integration.json", directory: directory)
        snapshot = file.load() ?? RemindersIntegrationSnapshot()
        // The simpler setup expands the scope to all active lists. Keep old
        // connections paused until the user enables that scope explicitly.
        if snapshot.enabled && !snapshot.syncsAllTasks {
            snapshot.enabled = false
            file.schedule(snapshot)
        }
    }
    func configure(_ edit: (inout RemindersIntegrationSnapshot) -> Void) {
        edit(&snapshot); file.schedule(snapshot); onSettingsChange?()
    }
    func setTask(_ task: Task, enabled: Bool) {
        configure { state in
            state.taskOverrides[(task.series?.id ?? task.id).uuidString] = enabled
            if enabled {
                state.bindings.removeAll { $0.detached && Self.matches($0, task) }
            }
        }
    }
    static func matches(_ binding: ReminderTaskBinding, _ task: Task) -> Bool {
        binding.reference.taskID == task.id || binding.reference.occurrence?.seriesID == (task.series?.id ?? task.id)
    }
    func setBindings(_ value: [ReminderTaskBinding]) {
        guard value != snapshot.bindings else { return }
        snapshot.bindings = value; file.schedule(snapshot)
    }
    func flush(_ completion: @escaping (Error?) -> Void) { file.flush(completion) }
}

struct ReminderTaskExport {
    var reference: CalendarTaskReference
    var fields: ReminderTaskFields
    var notes: String
    var suppressesAlerts = false
}

enum ReminderTaskMapping {
    static func reference(_ task: Task, calendar: Calendar) -> CalendarTaskReference {
        let key = task.occurrenceKey ?? task.series?.initialKey
            ?? (task.recurrence == .never ? nil : TaskSeries(task: task, calendar: calendar, now: task.createdAt).initialKey)
        return .init(taskID: task.id, occurrence: key)
    }
    static func fields(_ task: Task, calendar: Calendar) -> ReminderTaskFields {
        let cal = task.series?.calendar(matching: calendar) ?? calendar
        let due = task.schedule.dueAt.map { date -> Date in
            if task.schedule.hasTime { return rounded(date) }
            return calendar.date(from: cal.dateComponents([.year, .month, .day], from: date))!
        }
        return .init(title: task.title, due: due, hasTime: task.schedule.hasTime,
            priority: task.priority, completed: task.status == .completed,
            alarms: Array(Set(ReminderSchedule.fireDates(for: task, calendar: cal).map(rounded))).sorted(),
            completedAt: task.status == .completed ? task.completedAt.map(rounded) : nil)
    }
    static func export(_ task: Task, reference: CalendarTaskReference, calendar: Calendar) -> ReminderTaskExport {
        var notes = "来自 WorkFollow · " + task.list.name
        if task.parentID != nil { notes += "\n子任务以独立提醒事项显示，层级保留在 WorkFollow。" }
        if let deadline = task.schedule.deadlineAt {
            notes += "\n独立截止日期：" + deadline.formatted(.dateTime.year().month().day().hour().minute().locale(.appDate))
        }
        if task.recurrence != .never { notes += "\n重复期次由 WorkFollow 管理。" }
        return .init(reference: reference, fields: fields(task, calendar: calendar), notes: notes)
    }
    private static func rounded(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }

    static func merge(base: ReminderTaskFields, task: ReminderTaskFields, reminder: ReminderTaskFields) -> ReminderTaskFields? {
        var value = task
        func merge<T: Equatable>(_ key: WritableKeyPath<ReminderTaskFields, T>) -> Bool {
            guard reminder[keyPath: key] != base[keyPath: key] else { return true }
            guard task[keyPath: key] == base[keyPath: key] || task[keyPath: key] == reminder[keyPath: key] else { return false }
            value[keyPath: key] = reminder[keyPath: key]; return true
        }
        // Date and reminder instants are one unit: a phone reschedule must not
        // combine its new date with an independently changed desktop alarm.
        let baseTiming = Timing(base), taskTiming = Timing(task), remoteTiming = Timing(reminder)
        if remoteTiming != baseTiming {
            guard taskTiming == baseTiming || taskTiming == remoteTiming else { return nil }
            value.due = reminder.due; value.hasTime = reminder.hasTime; value.alarms = reminder.alarms
        }
        guard merge(\.title), merge(\.priority), merge(\.completed) else { return nil }
        if value.completed {
            value.completedAt = reminder.completed != base.completed
                ? (reminder.completedAt ?? task.completedAt)
                : (task.completedAt ?? reminder.completedAt)
        } else { value.completedAt = nil }
        return value
    }
    private struct Timing: Equatable {
        var due: Date?; var hasTime: Bool; var alarms: [Date]
        init(_ value: ReminderTaskFields) { due = value.due; hasTime = value.hasTime; alarms = value.alarms }
    }
    static func schedule(_ fields: ReminderTaskFields, original: TaskSchedule, calendar: Calendar) -> TaskSchedule {
        var result = original
        if let old = original.dueAt, let new = fields.due, let end = original.dueEndAt {
            result.dueEndAt = end.addingTimeInterval(new.timeIntervalSince(old))
        } else if fields.due == nil { result.dueEndAt = nil }
        result.dueAt = fields.due; result.hasTime = fields.due != nil && fields.hasTime
        return result
    }
    static func reminderValues(_ fields: ReminderTaskFields, calendar: Calendar) -> (absolute: Date?, offsets: [Int]) {
        guard let due = fields.due else { return (fields.alarms.first, []) }
        let base = fields.hasTime ? due : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due)!
        let offsets = fields.alarms.map { Int(($0.timeIntervalSince(base) / 60).rounded()) }
        return (nil, Array(Set(offsets)).sorted())
    }
}
