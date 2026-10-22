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

struct SystemCalendarEvent: Codable, Equatable, Identifiable {
    var id: String
    var calendarID: String
    var fields: CalendarEventFields
    var sourceURL: URL?
    var location: String
    var calendarTitle: String
    var colorARGB: UInt32
    var notes = ""
    var timeZoneIdentifier: String?
    var availabilityRawValue: Int?
    var hasAdditionalDetails = false
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
    func events(in range: DateInterval, calendarIDs: [String]) -> [SystemCalendarEvent]
    func event(id: String) -> SystemCalendarEvent?
    func removeLegacyCopy(id: String) throws
    func restoreLegacyCopy(_ event: SystemCalendarEvent) throws -> SystemCalendarEvent
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
    func restoreLegacyCopy(_ original: SystemCalendarEvent) throws -> SystemCalendarEvent {
        guard authorization == .fullAccess, let calendar = store.calendar(withIdentifier: original.calendarID),
              calendar.allowsContentModifications else {
            throw CalendarIntegrationError.message("原日历当前不可写，暂时无法撤销清理。")
        }
        let event = EKEvent(eventStore: store)
        let fields = original.fields
        event.calendar = calendar; event.title = fields.title; event.isAllDay = fields.allDay
        event.timeZone = original.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        event.startDate = fields.start
        event.endDate = fields.allDay ? EventKitDayBoundary.systemEnd(exclusiveEnd: fields.end) : fields.end
        event.url = original.sourceURL; event.notes = original.notes; event.location = original.location
        if let raw = original.availabilityRawValue, let availability = EKEventAvailability(rawValue: raw) { event.availability = availability }
        try store.save(event, span: .thisEvent, commit: true)
        return value(event)
    }
    func removeLegacyCopy(id: String) throws {
        guard authorization == .fullAccess else { throw CalendarIntegrationError.message("需要允许日历访问。") }
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
            sourceURL: event.url, location: event.location ?? "", calendarTitle: calendar.title, colorARGB: calendar.colorARGB,
            notes: event.notes ?? "", timeZoneIdentifier: event.timeZone?.identifier,
            availabilityRawValue: event.availability.rawValue,
            hasAdditionalDetails: event.hasAttendees || event.hasRecurrenceRules || event.hasAlarms || event.structuredLocation != nil)
    }
}

enum CalendarIntegrationError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): return text } }
}
