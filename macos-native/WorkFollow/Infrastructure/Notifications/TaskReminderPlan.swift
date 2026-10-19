import Foundation
import Combine

struct ReminderDelivery: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case task, countdown, test }
    var id: String
    var kind: Kind
    var sourceID: UUID
    var occurrence: OccurrenceKey?
    var title: String
    var body: String
    var originalDate: Date
    var fireDate: Date
}

struct ReminderDecision: Codable, Equatable {
    var snoozedUntil: Date?
    var acknowledged = false
}

struct TaskReminderPreferences: Codable, Equatable {
    var soundEnabled = true
    var bell = "Glass"
    var snoozeMinutes = 10
}

@MainActor
final class TaskReminderStateStore: ObservableObject, ModuleStoreFlushable {
    struct Snapshot: Codable {
        var decisions: [String: ReminderDecision] = [:]
        var preferences = TaskReminderPreferences()
    }
    @Published private(set) var snapshot: Snapshot
    private let file: JSONFileStore<Snapshot>
    var onChange: (() -> Void)?

    init(directory: URL = JSONFileStore<Snapshot>.moduleDirectory) {
        file = JSONFileStore(filename: "task-reminder-state.json", directory: directory)
        snapshot = file.load() ?? Snapshot()
    }
    func decide(_ delivery: ReminderDelivery, snoozeUntil: Date?) {
        snapshot.decisions[delivery.id] = ReminderDecision(snoozedUntil: snoozeUntil,
                                                          acknowledged: snoozeUntil == nil)
        save()
    }
    func updatePreferences(_ edit: (inout TaskReminderPreferences) -> Void) {
        edit(&snapshot.preferences)
        snapshot.preferences.snoozeMinutes = max(1, min(120, snapshot.preferences.snoozeMinutes))
        save()
    }
    private func save() { file.schedule(snapshot); onChange?() }
    func flush(_ completion: @escaping (Error?) -> Void) { file.flush(completion) }
}

enum TaskReminderPlanner {
    /// The same occurrence identity is used by the task calendar and notifications.
    /// Stored tasks without dates still support the legacy absolute reminder.
    static func deliveries(tasks: [Task], countdowns: [CountdownEvent], now: Date,
                           calendar: Calendar, decisions: [String: ReminderDecision]) -> [ReminderDelivery] {
        let end = calendar.date(byAdding: .day, value: 30, to: now)!
        let start = calendar.date(byAdding: .day, value: -30, to: now)!
        let ghosts = TaskOccurrenceProjection.occurrences(tasks: tasks,
            in: DateInterval(start: start, end: end), calendar: calendar).filter(\.isVirtual)
        var values: [ReminderDelivery] = []
        func append(_ task: Task, sourceID: UUID, occurrence: OccurrenceKey?) {
            guard task.isActiveSeriesOccurrence else { return }
            let cal = task.series?.calendar(matching: calendar) ?? calendar
            for date in Array(Set(ReminderSchedule.fireDates(for: task, calendar: cal))).sorted() {
                let identity = occurrence?.id ?? task.id.uuidString
                let id = "task.\(identity).at.\(Int64(date.timeIntervalSince1970))"
                guard decisions[id]?.acknowledged != true else { continue }
                values.append(ReminderDelivery(id: id, kind: .task, sourceID: sourceID,
                    occurrence: occurrence, title: task.title.isEmpty ? "任务提醒" : task.title,
                    body: task.list.name, originalDate: date,
                    fireDate: decisions[id]?.snoozedUntil ?? date))
            }
        }
        for task in tasks { append(task, sourceID: task.id, occurrence: task.occurrenceKey) }
        for ghost in ghosts { append(ghost.task, sourceID: ghost.sourceTaskID, occurrence: ghost.key) }
        for event in countdowns {
            for date in ReminderSchedule.fireDates(for: event, calendar: calendar, now: now) {
                let id = "countdown.\(event.id.uuidString).at.\(Int64(date.timeIntervalSince1970))"
                guard decisions[id]?.acknowledged != true else { continue }
                values.append(ReminderDelivery(id: id, kind: .countdown, sourceID: event.id,
                    title: event.displayName, body: event.kind.title, originalDate: date,
                    fireDate: decisions[id]?.snoozedUntil ?? date))
            }
        }
        return values.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
    }
}
