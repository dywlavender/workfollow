import UserNotifications
import Combine

@MainActor
final class NativeReminderService: ObservableObject {
    @Published private(set) var message: String?
    private var pendingWork: _Concurrency.Task<Void, Never>?

    // Permission is requested only by the user's explicit enable button.
    func enable(for tasks: [Task]) {
        _Concurrency.Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                message = allowed ? nil : "请在系统设置中允许 WorkFollow Native 通知。"
                if allowed { reconcile(tasks) }
            } catch { message = error.localizedDescription }
        }
    }

    func reconcile(_ tasks: [Task]) {
        pendingWork?.cancel()
        pendingWork = _Concurrency.Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard !_Concurrency.Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let pending = await center.pendingNotificationRequests()
            guard !_Concurrency.Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("task.") }.map(\.identifier))
            for task in tasks where task.deletedAt == nil && task.status == .active {
                guard !_Concurrency.Task.isCancelled else { return }
                guard let reminder = task.reminderAt, reminder > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = task.title.isEmpty ? "任务提醒" : task.title
                content.body = task.list.name
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: reminder), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: "task.\(task.id.uuidString)", content: content, trigger: trigger)) }
                catch { message = error.localizedDescription }
            }
        }
    }
}
