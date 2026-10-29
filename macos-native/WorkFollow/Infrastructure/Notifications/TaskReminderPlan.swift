import Foundation
import Combine

struct ReminderDelivery: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case task, countdown, checklistItem, test }
    var id: String
    var kind: Kind
    var sourceID: UUID
    var occurrence: OccurrenceKey?
    var title: String
    var body: String
    var originalDate: Date
    var fireDate: Date
    /// 检查项所在块；项级提醒打开时可选定位到该行。
    var checklistItemID: UUID? = nil

    /// 通知标识前缀。任务与检查项共用一个系统队列，容量裁剪必须按前缀
    /// 分别计算，否则项提醒多了会把任务提醒顶出队列（反之亦然）。
    var identifierPrefix: String { kind.identifierPrefix }
}

extension ReminderDelivery.Kind {
    var identifierPrefix: String {
        switch self {
        case .task: return "task."
        case .countdown: return "countdown."
        case .checklistItem: return "checklist."
        case .test: return "test."
        }
    }
}

struct ReminderDecision: Codable, Equatable {
    var snoozedUntil: Date?
    var acknowledged = false
}

struct TaskReminderPreferences: Codable, Equatable {
    static let supportedBells = ["Jingle", "Drip", "Knock", "Spiral"]
    static func normalizedBell(_ value: String?) -> String {
        guard let value, supportedBells.contains(value) else { return "Jingle" }
        return value
    }

    /// 本机提醒总开关（任务详情「提醒来源」用）。旧存档没有这个键 → 默认开，
    /// 既有 soundEnabled 等字段维持原来的解码行为不变。
    var enabled = true
    var soundEnabled = true
    var bell = "Jingle"
    var snoozeMinutes = 10

    enum CodingKeys: String, CodingKey { case enabled, soundEnabled, bell, snoozeMinutes }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        soundEnabled = try container.decode(Bool.self, forKey: .soundEnabled)
        bell = Self.normalizedBell(try container.decodeIfPresent(String.self, forKey: .bell))
        snoozeMinutes = try container.decode(Int.self, forKey: .snoozeMinutes)
    }
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
        for task in tasks {
            append(task, sourceID: task.id, occurrence: task.occurrenceKey)
            appendChecklistItems(of: task, decisions: decisions, into: &values)
        }
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

    /// 清单任务里未勾选、带提醒的检查项。摘要只投影未完成项：勾选、删除、
    /// 切回文本或完成任务后，下一次对账自然不再生成投递。
    private static func appendChecklistItems(of task: Task,
                                             decisions: [String: ReminderDecision],
                                             into values: inout [ReminderDelivery]) {
        guard task.kind == .checklist, task.isActiveSeriesOccurrence,
              let reminders = task.document.checklistSummary?.reminders else { return }
        for item in reminders {
            let id = "checklist.\(task.id.uuidString).\(item.blockID.uuidString)"
                + ".at.\(Int64(item.fireDate.timeIntervalSince1970))"
            guard decisions[id]?.acknowledged != true else { continue }
            values.append(ReminderDelivery(
                id: id, kind: .checklistItem, sourceID: task.id,
                occurrence: task.occurrenceKey, title: item.title,
                body: task.title.isEmpty ? task.list.name : task.title,
                originalDate: item.fireDate,
                fireDate: decisions[id]?.snoozedUntil ?? item.fireDate,
                checklistItemID: item.blockID))
        }
    }
}
