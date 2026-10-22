import EventKit
import Foundation

struct SystemReminderAccount: Identifiable, Equatable {
    var id: String
    var title: String
}

struct SystemReminderList: Identifiable, Equatable {
    var id: String
    var title: String
    var accountID: String
    var accountTitle: String
    var writable: Bool
    var displayTitle: String { accountTitle + " · " + title }
}

struct ReminderTaskFields: Codable, Equatable {
    var title: String
    var due: Date?
    var hasTime: Bool
    var priority: TaskPriority
    var completed: Bool
    var alarms: [Date]
    var completedAt: Date? = nil
}

struct SystemReminderItem: Identifiable, Equatable {
    var id: String
    var listID: String
    var sourceURL: URL?
    var fields: ReminderTaskFields
}

@MainActor
protocol SystemRemindersClient: AnyObject {
    var authorization: EKAuthorizationStatus { get }
    var onChange: (() -> Void)? { get set }
    func requestAccess() async throws -> Bool
    func accounts() -> [SystemReminderAccount]
    func lists() -> [SystemReminderList]
    func createList(title: String, accountID: String) throws -> SystemReminderList
    func reminders(listIDs: [String]) async throws -> [SystemReminderItem]
    func save(_ fields: ReminderTaskFields, listID: String, sourceURL: URL, notes: String,
              existingID: String?) throws -> SystemReminderItem
    func remove(id: String) throws
}

@MainActor
final class SystemRemindersService: SystemRemindersClient {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private let calendar: Calendar
    var onChange: (() -> Void)?
    var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.onChange?() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToReminders() }

    func accounts() -> [SystemReminderAccount] {
        guard authorization == .fullAccess else { return [] }
        let available = Set(lists().map(\.accountID))
        return store.sources.filter { available.contains($0.sourceIdentifier) }.map {
            SystemReminderAccount(id: $0.sourceIdentifier, title: $0.title)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func lists() -> [SystemReminderList] {
        guard authorization == .fullAccess else { return [] }
        return store.calendars(for: .reminder).map(info).sorted {
            $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }
    private func info(_ value: EKCalendar) -> SystemReminderList {
        .init(id: value.calendarIdentifier, title: value.title, accountID: value.source.sourceIdentifier,
              accountTitle: value.source.title, writable: value.allowsContentModifications)
    }
    func createList(title: String, accountID: String) throws -> SystemReminderList {
        guard let source = store.sources.first(where: { $0.sourceIdentifier == accountID }),
              accounts().contains(where: { $0.id == accountID }) else {
            throw CalendarIntegrationError.message("请选择提醒事项账户；手机同步请使用 iCloud。")
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CalendarIntegrationError.message("请输入新清单名称。") }
        let value = EKCalendar(for: .reminder, eventStore: store)
        value.title = name; value.source = source
        try store.saveCalendar(value, commit: true)
        return info(value)
    }
    func reminders(listIDs: [String]) async throws -> [SystemReminderItem] {
        guard authorization == .fullAccess else { throw CalendarIntegrationError.message("需要提醒事项完整访问权限。") }
        let selected = listIDs.compactMap(store.calendar(withIdentifier:))
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: selected)
        let values: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { values in
                if let values { continuation.resume(returning: values) }
                else { continuation.resume(throwing: CalendarIntegrationError.message("暂时无法读取提醒事项，请稍后重新同步。")) }
            }
        }
        return values.map(item)
    }
    func save(_ fields: ReminderTaskFields, listID: String, sourceURL: URL, notes: String,
              existingID: String?) throws -> SystemReminderItem {
        guard let target = store.calendar(withIdentifier: listID), target.allowsContentModifications,
              target.allowedEntityTypes.contains(.reminder) else {
            throw CalendarIntegrationError.message("目标提醒事项清单不可写，请重新选择。")
        }
        let existing = existingID.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
        let value = existing ?? EKReminder(eventStore: store)
        value.calendar = target; value.title = fields.title; value.url = sourceURL
        if existing == nil { value.notes = notes }
        value.priority = Self.systemPriority(fields.priority)
        if let due = fields.due {
            var parts = calendar.dateComponents(fields.hasTime ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day], from: due)
            parts.calendar = calendar
            if fields.hasTime { parts.timeZone = calendar.timeZone }
            value.startDateComponents = parts; value.dueDateComponents = parts
        } else {
            value.dueDateComponents = nil; value.startDateComponents = nil
        }
        if existing == nil || item(value).fields.alarms != fields.alarms {
            value.alarms = fields.alarms.map { EKAlarm(absoluteDate: $0) }
        }
        value.isCompleted = fields.completed
        if fields.completed, let completedAt = fields.completedAt { value.completionDate = completedAt }
        try store.save(value, commit: true)
        return item(value)
    }
    func remove(id: String) throws {
        guard let value = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(value, commit: true)
    }
    private func item(_ value: EKReminder) -> SystemReminderItem {
        let components = value.dueDateComponents
        let hasTime = components?.hour != nil
        let due = components.flatMap { parts -> Date? in
            if hasTime { return (parts.calendar ?? calendar).date(from: parts) }
            return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
        }
        let base = due.map { hasTime ? $0 : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)! }
        let alarms = (value.alarms ?? []).compactMap { alarm -> Date? in
            alarm.absoluteDate ?? base?.addingTimeInterval(alarm.relativeOffset)
        }.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }
        let fields = ReminderTaskFields(title: value.title ?? "", due: due, hasTime: hasTime,
            priority: Self.taskPriority(value.priority), completed: value.isCompleted, alarms: Array(Set(alarms)).sorted(),
            completedAt: value.isCompleted ? value.completionDate.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) } : nil)
        return .init(id: value.calendarItemIdentifier, listID: value.calendar.calendarIdentifier,
                     sourceURL: value.url, fields: fields)
    }
    static func systemPriority(_ value: TaskPriority) -> Int {
        switch value { case .none: 0; case .high: 1; case .medium: 5; case .low: 9 }
    }
    static func taskPriority(_ value: Int) -> TaskPriority {
        switch value { case 1...4: .high; case 5: .medium; case 6...9: .low; default: .none }
    }
}
