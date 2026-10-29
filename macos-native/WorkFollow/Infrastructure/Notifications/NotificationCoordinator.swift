import AppKit
import UserNotifications

/// A single delegate owns all categories, including focus and countdowns.
@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let taskCategory = "workfollow.task-reminder"
    nonisolated static let focusCategory = "workfollow.focus"
    nonisolated static let snoozeAction = "workfollow.reminder.snooze"
    nonisolated static let stopAction = "workfollow.reminder.stop"
    var onOpen: ((ReminderDelivery) -> Void)?
    var onAction: ((ReminderDelivery, Bool) async -> Void)?
    var onPresent: ((ReminderDelivery) -> Bool)?

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.taskCategory, actions: [
                UNNotificationAction(identifier: Self.snoozeAction, title: "稍后提醒", options: []),
                UNNotificationAction(identifier: Self.stopAction, title: "停止本次提醒", options: [])
            ], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Self.focusCategory, actions: [], intentIdentifiers: [])
        ])
    }

    nonisolated static func delivery(from content: UNNotificationContent) -> ReminderDelivery? {
        guard let string = content.userInfo["workfollowReminder"] as? String,
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReminderDelivery.self, from: data)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let delivery = Self.delivery(from: notification.request.content)
        return await MainActor.run {
            if let delivery, self.onPresent?(delivery) == true { return [.banner, .list] }
            return notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard let delivery = Self.delivery(from: response.notification.request.content) else { return }
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.onOpen?(delivery) }
        } else if response.actionIdentifier == Self.snoozeAction {
            await self.onAction?(delivery, true)
        } else if response.actionIdentifier == Self.stopAction || response.actionIdentifier == UNNotificationDismissActionIdentifier {
            await self.onAction?(delivery, false)
        }
    }
}

struct ScheduledTaskNotification: Equatable {
    var delivery: ReminderDelivery
    var sound: Bool
    var bell: String = "Jingle"
}

@MainActor
protocol TaskNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func authorize() async throws -> Bool
    func pending() async -> [ScheduledTaskNotification]
    func pendingManagedIDs() async -> [String]
    func delivered() async -> [ReminderDelivery]
    func add(_ value: ScheduledTaskNotification, calendar: Calendar) async throws
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

@MainActor
final class SystemTaskNotificationClient: TaskNotificationClient {
    private var center: UNUserNotificationCenter { .current() }
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func authorize() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pending() async -> [ScheduledTaskNotification] {
        await center.pendingNotificationRequests().compactMap {
            guard let value = NotificationCoordinator.delivery(from: $0.content) else { return nil }
            return ScheduledTaskNotification(delivery: value, sound: $0.content.sound != nil,
                bell: $0.content.userInfo["workfollowReminderBell"] as? String ?? "Glass")
        }
    }
    func pendingManagedIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix("task.") || $0.hasPrefix("countdown.") || $0.hasPrefix("checklist.")
        }
    }
    func delivered() async -> [ReminderDelivery] {
        await center.deliveredNotifications().compactMap { NotificationCoordinator.delivery(from: $0.request.content) }
    }
    func add(_ value: ScheduledTaskNotification, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = value.delivery.title; content.body = value.delivery.body
        content.categoryIdentifier = NotificationCoordinator.taskCategory
        content.sound = value.sound ? UNNotificationSound(named: UNNotificationSoundName(ReminderAudio.filename(value.bell))) : nil
        content.userInfo = ["workfollowReminder": String(data: try JSONEncoder().encode(value.delivery), encoding: .utf8)!,
                            "workfollowReminderBell": value.bell]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value.delivery.fireDate)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: value.delivery.id, content: content, trigger: trigger))
    }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}
