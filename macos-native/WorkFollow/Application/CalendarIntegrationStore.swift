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
    // Old bindings are retained only for one-time cleanup and duplicate filtering.
    var bindings: [CalendarTaskBinding] = []
    var removedTaskCopies: [SystemCalendarEvent]?
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
    func flush(_ completion: @escaping (Error?) -> Void) { file.flush(completion) }
}
