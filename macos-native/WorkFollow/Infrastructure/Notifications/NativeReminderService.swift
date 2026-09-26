import UserNotifications
import Combine

/// Pure mapping from a task to its notification fire dates: the legacy absolute
/// `reminderAt`, or one date per configured offset (0 = on time, negative =
/// early; all-day tasks anchor to 09:00 of the due day, matching the schedule
/// panel's all-day reminder hint).
enum ReminderSchedule {
    static let allDayAnchorHour = 9

    /// The moment offsets anchor to: the due clock, or 09:00 for all-day tasks.
    static func reminderBase(for task: Task, calendar: Calendar) -> Date? {
        guard let due = task.schedule.dueAt else { return nil }
        guard task.schedule.hasTime else {
            return calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0,
                                 of: calendar.startOfDay(for: due))
        }
        return due
    }

    /// Ascending fire dates. Without stored offsets the legacy absolute
    /// reminder applies; offsets without a schedulable anchor produce none.
    static func fireDates(for task: Task, calendar: Calendar) -> [Date] {
        let offsets = task.reminderOffsets ?? []
        if !offsets.isEmpty, let base = reminderBase(for: task, calendar: calendar) {
            return offsets.map { base.addingTimeInterval(TimeInterval($0) * 60) }.sorted()
        }
        return task.reminderAt.map { [$0] } ?? []
    }
}

struct ReminderSignature: Equatable {
    let id: UUID
    let dates: [Date]
    let title: String
    let list: String

    static func values(_ tasks: [Task], calendar: Calendar = .current) -> [Self] {
        tasks.compactMap { task in
            guard !task.isClosed, task.deletedAt == nil, task.skippedAt == nil else { return nil }
            let dates = ReminderSchedule.fireDates(for: task, calendar: calendar)
            guard !dates.isEmpty else { return nil }
            return Self(id: task.id, dates: dates, title: task.title, list: task.list.name)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

@MainActor
final class NativeReminderService: ObservableObject {
    @Published private(set) var message: String?
    private var pendingWork: _Concurrency.Task<Void, Never>?
    private var signature: [ReminderSignature]?
    private let clock: () -> Date
    private let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    // Permission is requested only by the user's explicit enable button.
    func enable(for tasks: [Task]) {
        _Concurrency.Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                message = allowed ? nil : "请在系统设置中允许 WorkFollow Native 通知。"
                if allowed { reconcile(tasks, force: true) }
            } catch { message = error.localizedDescription }
        }
    }

    func reconcile(_ tasks: [Task], force: Bool = false) {
        let next = ReminderSignature.values(tasks, calendar: calendar)
        guard force || signature != next else { return }
        signature = next
        pendingWork?.cancel()
        pendingWork = _Concurrency.Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard !_Concurrency.Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let pending = await center.pendingNotificationRequests()
            guard !_Concurrency.Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("task.") }.map(\.identifier))
            for task in tasks where task.deletedAt == nil && task.skippedAt == nil && !task.isClosed {
                guard !_Concurrency.Task.isCancelled else { return }
                let dates = ReminderSchedule.fireDates(for: task, calendar: calendar)
                // One notification per offset; the legacy single reminder keeps
                // its bare identifier so older installs deduplicate cleanly.
                for (index, date) in dates.enumerated() where date > clock() {
                    guard !_Concurrency.Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = task.title.isEmpty ? "任务提醒" : task.title
                    content.body = task.list.name
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
                    let identifier = dates.count > 1
                        ? "task.\(task.id.uuidString)#\(index)"
                        : "task.\(task.id.uuidString)"
                    do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
                    catch { message = error.localizedDescription }
                }
            }
        }
    }
}
