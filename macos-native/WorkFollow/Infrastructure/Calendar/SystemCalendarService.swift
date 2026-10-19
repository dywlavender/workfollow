import EventKit
import AppKit

struct SystemCalendarInfo: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var colorARGB: UInt32
    var writable: Bool
}

struct CalendarEventFields: Codable, Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
}

struct SystemCalendarEvent: Equatable, Identifiable {
    var id: String
    var calendarID: String
    var fields: CalendarEventFields
    var sourceURL: URL?
    var location: String
    var calendarTitle: String
    var colorARGB: UInt32
}

/// macOS EventKit treats the date containing an all-day end as included.
/// The application uses a half-open interval, while the system adapter writes
/// the last second of the included day and normalizes fetched values back.
enum EventKitDayBoundary {
    static func systemEnd(exclusiveEnd: Date) -> Date { exclusiveEnd.addingTimeInterval(-1) }
    static func exclusiveEnd(systemEnd: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: systemEnd))!
    }
}

@MainActor
protocol SystemCalendarClient: AnyObject {
    var authorization: EKAuthorizationStatus { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [SystemCalendarInfo]
    func createCalendar(title: String) throws -> SystemCalendarInfo
    func events(in range: DateInterval, calendarIDs: [String]) -> [SystemCalendarEvent]
    func event(id: String) -> SystemCalendarEvent?
    func save(_ fields: CalendarEventFields, calendarID: String, sourceURL: URL,
              notes: String, timeZone: TimeZone, existingID: String?) throws -> SystemCalendarEvent
    func remove(id: String) throws
    var onChange: (() -> Void)? { get set }
}

@MainActor
final class SystemCalendarService: SystemCalendarClient {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?
    var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.onChange?() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func calendars() -> [SystemCalendarInfo] {
        guard authorization == .fullAccess else { return [] }
        return store.calendars(for: .event).map(info).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func createCalendar(title: String) throws -> SystemCalendarInfo {
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
            throw CalendarIntegrationError.message("没有可用的日历账户，请先在系统日历中添加账户或日历。")
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title; calendar.source = source
        calendar.cgColor = NSColor.systemBlue.cgColor
        try store.saveCalendar(calendar, commit: true)
        return info(calendar)
    }
    func events(in range: DateInterval, calendarIDs: [String]) -> [SystemCalendarEvent] {
        guard authorization == .fullAccess else { return [] }
        let calendars = calendarIDs.compactMap(store.calendar(withIdentifier:))
        guard !calendars.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)).map(value)
    }
    func event(id: String) -> SystemCalendarEvent? {
        guard authorization == .fullAccess else { return nil }
        return store.event(withIdentifier: id).map(value)
    }
    func save(_ fields: CalendarEventFields, calendarID: String, sourceURL: URL,
              notes: String, timeZone: TimeZone, existingID: String?) throws -> SystemCalendarEvent {
        guard authorization == .fullAccess, let calendar = store.calendar(withIdentifier: calendarID),
              calendar.allowsContentModifications else {
            throw CalendarIntegrationError.message("目标日历不可写，请重新选择日历。")
        }
        let event: EKEvent
        if let existingID {
            guard let existing = store.event(withIdentifier: existingID) else {
                throw CalendarIntegrationError.message("日程已被移除，请重新关联。")
            }
            event = existing
        } else { event = EKEvent(eventStore: store) }
        event.calendar = calendar; event.title = fields.title; event.isAllDay = fields.allDay
        event.timeZone = fields.allDay ? nil : timeZone
        event.startDate = fields.start
        event.endDate = fields.allDay ? EventKitDayBoundary.systemEnd(exclusiveEnd: fields.end) : fields.end
        event.url = sourceURL; event.notes = notes
        // WorkFollow owns task reminders. Clear event alarms on every write.
        event.alarms = []
        try store.save(event, span: .thisEvent, commit: true)
        return value(event)
    }
    func remove(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }
    private func info(_ calendar: EKCalendar) -> SystemCalendarInfo {
        let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemBlue
        let argb = UInt32(255) << 24 | UInt32(color.redComponent * 255) << 16
            | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255)
        return SystemCalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                  colorARGB: argb, writable: calendar.allowsContentModifications)
    }
    private func value(_ event: EKEvent) -> SystemCalendarEvent {
        let calendar = info(event.calendar)
        let end = event.isAllDay ? EventKitDayBoundary.exclusiveEnd(systemEnd: event.endDate, calendar: .autoupdatingCurrent) : event.endDate!
        return SystemCalendarEvent(id: event.eventIdentifier, calendarID: calendar.id,
            fields: .init(title: event.title ?? "无标题日程", start: event.startDate, end: end, allDay: event.isAllDay),
            sourceURL: event.url, location: event.location ?? "", calendarTitle: calendar.title, colorARGB: calendar.colorARGB)
    }
}

enum CalendarIntegrationError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): return text } }
}
