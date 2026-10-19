import Foundation
import Combine

struct CalendarTaskReference: Codable, Equatable {
    var taskID: UUID
    var occurrence: OccurrenceKey?
    var id: String { occurrence?.id ?? taskID.uuidString }
    static func resolve(_ reference: Self, tasks: [Task], calendar: Calendar) -> TaskOccurrence? {
        if let key = reference.occurrence {
            if let task = tasks.first(where: { $0.occurrenceKey == key && $0.deletedAt == nil && $0.skippedAt == nil }) {
                return TaskOccurrence(key: key, task: task, isVirtual: false, sourceTaskID: task.id)
            }
            let range = DateInterval(start: calendar.date(byAdding: .day, value: -1, to: key.nominalDate)!,
                                     end: calendar.date(byAdding: .day, value: 2, to: key.nominalDate)!)
            return TaskOccurrenceProjection.occurrences(tasks: tasks, in: range, calendar: calendar).first { $0.key == key }
        }
        guard let task = tasks.first(where: { $0.id == reference.taskID && $0.deletedAt == nil && $0.skippedAt == nil }) else { return nil }
        return TaskOccurrence(key: .init(seriesID: task.id, nominalDate: task.schedule.dueAt ?? task.createdAt, ordinal: 0),
            task: task, isVirtual: false, sourceTaskID: task.id)
    }
    var url: URL {
        var components = URLComponents(url: NativeResourceLink.task(taskID).url, resolvingAgainstBaseURL: false)!
        if let occurrence {
            components.queryItems = [URLQueryItem(name: "series", value: occurrence.seriesID.uuidString),
                URLQueryItem(name: "ordinal", value: String(occurrence.ordinal)),
                URLQueryItem(name: "nominal", value: String(occurrence.nominalDate.timeIntervalSince1970))]
        }
        return components.url!
    }
}

struct CalendarTaskExport: Equatable {
    var reference: CalendarTaskReference
    var fields: CalendarEventFields
    var derivedDuration: Bool
    var timeZone: TimeZone
    var notes: String
}

extension CalendarTaskReference {
    init?(url: URL) {
        guard url.scheme == "workfollow", url.host == "task", let taskID = UUID(uuidString: url.lastPathComponent),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let series = query.first(where: { $0.name == "series" })?.value.flatMap(UUID.init(uuidString:)),
              let ordinal = query.first(where: { $0.name == "ordinal" })?.value.flatMap(Int.init), ordinal >= 0,
              let timestamp = query.first(where: { $0.name == "nominal" })?.value.flatMap(Double.init), timestamp.isFinite else { return nil }
        self.init(taskID: taskID, occurrence: .init(seriesID: series, nominalDate: Date(timeIntervalSince1970: timestamp), ordinal: ordinal))
    }
}

struct CalendarTaskBinding: Codable, Equatable, Identifiable {
    var reference: CalendarTaskReference
    var eventID: String
    var calendarID: String
    var lastSynced: CalendarEventFields
    var derivedDuration: Bool
    var detached = false
    var id: String { reference.id }
}

struct CalendarIntegrationSnapshot: Codable {
    var enabled = false
    var targetCalendarID: String?
    var visibleCalendarIDs: [String] = []
    var autoSyncLists: [String] = []
    var taskOverrides: [String: Bool] = [:]
    var defaultDurationMinutes = 30
    var bidirectional = false
    var bindings: [CalendarTaskBinding] = []

    func includes(_ task: Task) -> Bool {
        let key = (task.series?.id ?? task.id).uuidString
        return taskOverrides[key] ?? autoSyncLists.contains(task.list.name)
    }
}

@MainActor
final class CalendarIntegrationStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var snapshot: CalendarIntegrationSnapshot
    private let file: JSONFileStore<CalendarIntegrationSnapshot>
    var onSettingsChange: (() -> Void)?
    init(directory: URL = JSONFileStore<CalendarIntegrationSnapshot>.moduleDirectory) {
        file = JSONFileStore(filename: "calendar-integration.json", directory: directory)
        snapshot = file.load() ?? CalendarIntegrationSnapshot()
    }
    func configure(_ edit: (inout CalendarIntegrationSnapshot) -> Void) {
        edit(&snapshot); file.schedule(snapshot); onSettingsChange?()
    }
    func setTask(_ task: Task, enabled: Bool) {
        configure { $0.taskOverrides[(task.series?.id ?? task.id).uuidString] = enabled }
    }
    func setBindings(_ bindings: [CalendarTaskBinding]) {
        guard snapshot.bindings != bindings else { return }
        snapshot.bindings = bindings; file.schedule(snapshot)
    }
    func flush(_ completion: @escaping (Error?) -> Void) { file.flush(completion) }
}

enum CalendarTaskMapping {
    static func export(_ task: Task, reference: CalendarTaskReference, duration: Int, calendar: Calendar) -> CalendarTaskExport? {
        guard let start = task.schedule.dueAt, task.parentID == nil, !task.isConverted else { return nil }
        let cal = task.series?.calendar(matching: calendar) ?? calendar
        let allDay = !task.schedule.hasTime
        func floatingDay(_ date: Date) -> Date { calendar.date(from: cal.dateComponents([.year, .month, .day], from: date))! }
        let low = allDay ? floatingDay(start) : Date(timeIntervalSince1970: floor(start.timeIntervalSince1970))
        let high: Date
        if allDay {
            high = calendar.date(byAdding: .day, value: 1, to: floatingDay(task.schedule.dueEndAt ?? start))!
        } else {
            high = task.schedule.dueEndAt.flatMap { $0 > start ? $0 : nil }
                ?? start.addingTimeInterval(Double(max(1, duration)) * 60)
        }
        let title = (task.status == .completed ? "[已完成] " : "") + task.title
        var notes = "来自 WorkFollow；任务提醒由 WorkFollow 负责。"
        if let deadline = task.schedule.deadlineAt {
            notes += "\n独立截止日期：" + deadline.formatted(.dateTime.year().month().day().hour().minute().locale(.appDate))
        }
        let roundedEnd = Date(timeIntervalSince1970: floor(high.timeIntervalSince1970))
        return CalendarTaskExport(reference: reference, fields: .init(title: title, start: low, end: max(low.addingTimeInterval(1), roundedEnd), allDay: allDay),
            derivedDuration: task.schedule.dueEndAt == nil, timeZone: cal.timeZone, notes: notes)
    }

    static func schedule(from fields: CalendarEventFields, original: TaskSchedule,
                         baseline: CalendarEventFields, derivedDuration: Bool, calendar: Calendar,
                         eventCalendar: Calendar? = nil) -> TaskSchedule {
        var value = original
        value.dueAt = fields.start; value.hasTime = !fields.allDay
        if fields.allDay {
            let source = eventCalendar ?? calendar
            func taskDay(_ date: Date) -> Date { calendar.date(from: source.dateComponents([.year, .month, .day], from: date))! }
            let last = source.date(byAdding: .day, value: -1, to: fields.end)!
            value.dueAt = taskDay(fields.start)
            value.dueEndAt = source.isDate(fields.start, inSameDayAs: last) && derivedDuration ? nil : taskDay(last)
        } else {
            let unchangedLength = abs(fields.end.timeIntervalSince(fields.start) - baseline.end.timeIntervalSince(baseline.start)) < 1
            value.dueEndAt = derivedDuration && unchangedLength && !baseline.allDay ? nil : fields.end
        }
        return value
    }

    static func merge(base: CalendarEventFields, task: CalendarEventFields, event: CalendarEventFields) -> CalendarEventFields? {
        var result = task
        if event.title != base.title {
            if task.title != base.title && task.title != event.title { return nil }
            result.title = event.title
        }
        func timing(_ value: CalendarEventFields) -> [String] {
            [String(value.start.timeIntervalSince1970), String(value.end.timeIntervalSince1970), String(value.allDay)]
        }
        if timing(event) != timing(base) {
            if timing(task) != timing(base) && timing(task) != timing(event) { return nil }
            result.start = event.start; result.end = event.end; result.allDay = event.allDay
        }
        return result.end > result.start ? result : nil
    }
}
