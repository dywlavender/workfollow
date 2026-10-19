import AppKit
import UserNotifications

/// 专注阶段的系统通知与应用内铃声；由 AppEnvironment 挂载到 FocusStore，
/// 单元测试不设置它，因此不会弹授权或发声。
@MainActor
final class FocusNotifier {
    private var authorizationRequested = false

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
        content.categoryIdentifier = NotificationCoordinator.focusCategory
        // 选中的声音由应用播放一次；关闭时通知也保持静默。
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func preview(bell: String?) {
        guard let bell else { return }
        NSSound(named: bell)?.play()
    }
}
