import Combine
import Foundation

@MainActor
final class TaskActivityStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var events: [TaskActivityEvent] = []

    private let persistence: JSONFileStore<[TaskActivityEvent]>
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store: JSONFileStore<[TaskActivityEvent]>
        if let directory {
            store = JSONFileStore(filename: "task-activity.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "task-activity.json")
        }
        persistence = store
        events = store.load() ?? []
    }

    /// 清单动态：该清单内任务的事件（新→旧）。
    /// 任务 → 清单的映射由调用方注入（store 不认识任务），所以被删掉的任务不会出现在这里。
    func events(forList listName: String,
                listNameOfTask: (UUID) -> String?) -> [TaskActivityEvent] {
        events.filter { listNameOfTask($0.taskID) == listName }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    func events(for taskID: UUID) -> [TaskActivityEvent] {
        events.enumerated()
            .filter { $0.element.taskID == taskID }
            .sorted {
                if $0.element.occurredAt != $1.element.occurredAt {
                    return $0.element.occurredAt > $1.element.occurredAt
                }
                return $0.offset > $1.offset
            }
            .map(\.element)
    }

    func recordChanges(_ changes: TaskChangeSet) {
        var changed = false

        for entry in changes.entries {
            switch entry.operation {
            case .insert:
                guard let task = entry.after else { continue }
                changed = append(event(taskID: task.id, kind: .created, afterValue: task.title)) || changed
                if let parentID = task.parentID {
                    changed = append(event(taskID: parentID, kind: .childCreated,
                                           afterValue: task.title)) || changed
                }
            case .delete:
                break
            case .update:
                guard let previous = entry.before, let task = entry.after else { continue }
                let fields = entry.changedFields

                if fields.contains(.title) {
                    changed = append(event(taskID: task.id, kind: .titleChanged,
                                           beforeValue: previous.title, afterValue: task.title)) || changed
                }

                if fields.contains(.schedule) || fields.contains(.recurrence)
                    || fields.contains(.recurrenceRule) || fields.contains(.reminderAt)
                    || fields.contains(.reminderOffsets) {
                    let previousDates = TemporalState(previous)
                    let currentDates = TemporalState(task)
                    if previousDates != currentDates {
                        changed = append(event(taskID: task.id, kind: .dateChanged,
                                               beforeValue: previousDates.displayValue,
                                               afterValue: currentDates.displayValue)) || changed
                    }
                }

                if fields.contains(.list) {
                    changed = append(event(taskID: task.id, kind: .listChanged,
                                           beforeValue: previous.list.name, afterValue: task.list.name)) || changed
                }

                if fields.contains(.priority) {
                    changed = append(event(taskID: task.id, kind: .priorityChanged,
                                           beforeValue: Self.priorityName(previous.priority),
                                           afterValue: Self.priorityName(task.priority))) || changed
                }

                if fields.contains(.tags) {
                    let previousTags = Self.canonicalTags(previous.tags)
                    let currentTags = Self.canonicalTags(task.tags)
                    if previousTags != currentTags {
                        changed = append(event(taskID: task.id, kind: .tagsChanged,
                                               beforeValue: previousTags.isEmpty ? nil : previousTags.joined(separator: ", "),
                                               afterValue: currentTags.isEmpty ? nil : currentTags.joined(separator: ", "))) || changed
                    }
                }

                if (fields.contains(.status) || fields.contains(.isAbandoned)
                    || fields.contains(.abandonedAt)),
                   let kind = Self.lifecycleChange(from: previous, to: task) {
                    changed = append(event(taskID: task.id, kind: kind)) || changed
                }
            }
        }

        if changed { persistence.schedule(events) }
    }

    /// Compatibility adapter for tests and callers that still hold snapshots.
    func recordChanges(from before: [Task], to after: [Task]) {
        recordChanges(TaskChangeSet(before: before, after: after))
    }

    func recordFocusStart(taskID: UUID, stopwatch: Bool) {
        _ = append(event(taskID: taskID, kind: .focusStarted,
                         afterValue: stopwatch ? "正计时" : "番茄计时"))
        persistence.schedule(events)
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    @discardableResult
    private func append(_ event: TaskActivityEvent) -> Bool {
        guard let previous = events.last,
              previous.kind == .titleChanged,
              event.kind == .titleChanged,
              previous.taskID == event.taskID,
              let originalTitle = previous.beforeValue else {
            events.append(event)
            return true
        }

        let elapsed = event.occurredAt.timeIntervalSince(previous.occurredAt)
        guard elapsed >= 0, elapsed <= 2 else {
            events.append(event)
            return true
        }

        if originalTitle == event.afterValue {
            events.removeLast()
        } else {
            events[events.count - 1] = TaskActivityEvent(
                id: previous.id, taskID: previous.taskID, occurredAt: previous.occurredAt,
                kind: .titleChanged, beforeValue: originalTitle, afterValue: event.afterValue)
        }
        return true
    }

    private func event(taskID: UUID, kind: TaskActivityEvent.Kind,
                       beforeValue: String? = nil, afterValue: String? = nil) -> TaskActivityEvent {
        TaskActivityEvent(taskID: taskID, occurredAt: clock(), kind: kind,
                          beforeValue: beforeValue, afterValue: afterValue)
    }

    private static func lifecycleChange(from before: Task, to after: Task) -> TaskActivityEvent.Kind? {
        switch (lifecycleState(before), lifecycleState(after)) {
        case (.active, .completed), (.abandoned, .completed): .completed
        case (.active, .abandoned), (.completed, .abandoned): .abandoned
        case (.completed, .active), (.abandoned, .active): .restored
        default: nil
        }
    }

    private static func lifecycleState(_ task: Task) -> LifecycleState {
        if task.status == .completed { return .completed }
        if task.isAbandoned { return .abandoned }
        return .active
    }

    private static func priorityName(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    private static func canonicalTags(_ tags: [String]) -> [String] {
        Array(Set(tags)).sorted()
    }

    private enum LifecycleState {
        case active
        case completed
        case abandoned
    }

    private struct TemporalState: Equatable {
        let schedule: TaskSchedule
        let recurrence: TaskRepeat
        let recurrenceRule: RecurrenceRule?
        let reminderAt: Date?
        let reminderOffsets: [Int]

        init(_ task: Task) {
            schedule = task.schedule
            recurrence = task.recurrence
            recurrenceRule = task.recurrenceRule
            reminderAt = task.reminderAt
            reminderOffsets = Array(Set(task.reminderOffsets ?? [])).sorted()
        }

        var displayValue: String {
            var parts: [String] = []
            if let dueAt = schedule.dueAt {
                parts.append("安排 \(Self.dateString(dueAt))（\(schedule.hasTime ? "定时" : "全天")）")
            }
            if let dueEndAt = schedule.dueEndAt { parts.append("结束 \(Self.dateString(dueEndAt))") }
            if let deadlineAt = schedule.deadlineAt { parts.append("截止 \(Self.dateString(deadlineAt))") }
            if recurrence != .never { parts.append("重复 \(recurrence.title)") }
            if let recurrenceRule { parts.append(Self.ruleSummary(recurrenceRule)) }
            if let reminderAt { parts.append("提醒 \(Self.dateString(reminderAt))") }
            if !reminderOffsets.isEmpty {
                parts.append("提醒偏移 \(reminderOffsets.map(String.init).joined(separator: ", ")) 分钟")
            }
            return parts.isEmpty ? "无日期安排" : parts.joined(separator: "；")
        }

        private static func ruleSummary(_ rule: RecurrenceRule) -> String {
            var fields = ["间隔 \(rule.interval)"]
            if let endDate = rule.endDate { fields.append("结束日 \(dateString(endDate))") }
            if let count = rule.remainingCount { fields.append("剩余 \(count) 次") }
            if let monthDay = rule.monthDay { fields.append("月日 \(monthDay)") }
            if let weekday = rule.weekday { fields.append("星期 \(weekday)") }
            if let month = rule.month { fields.append("月份 \(month)") }
            // Optional additive recurrence fields need not make Activity depend
            // on a particular version of the calendar editor's Domain model.
            if let data = try? JSONEncoder().encode(rule),
               let extras = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let month = extras["lunarMonth"] as? Int { fields.append("农历月 \(month)") }
                if let day = extras["lunarDay"] as? Int { fields.append("农历日 \(day)") }
                if let leap = extras["lunarIsLeapMonth"] as? Bool { fields.append(leap ? "闰月" : "平月") }
            }
            return "重复规则（\(fields.joined(separator: "，"))）"
        }

        private static func dateString(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
    }
}
