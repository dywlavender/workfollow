import AppKit
import UserNotifications

/// 专注阶段的系统通知与应用内铃声；由 AppEnvironment 挂载到 FocusStore，
/// 单元测试不设置它，因此不会弹授权或发声。
@MainActor
final class FocusNotifier {
    private let delegate = FocusNotificationDelegate()
    private var authorizationRequested = false

    init() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 阶段切换：应用内铃声立即响，系统通知保证切走后也能看到。
    func announce(bell: String?, title: String, body: String) {
        if let bell { NSSound(named: bell)?.play() }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// 应用在前台也横幅展示（专注提醒往往发生在还没切走的时候）。
private final class FocusNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
