import AppKit
import UserNotifications

/// 专注阶段的系统通知与应用内铃声；由 AppEnvironment 挂载到 FocusStore，
/// 单元测试不设置它，因此不会弹授权或发声。
@MainActor
final class FocusNotifier {
    private var authorizationRequested = false
    /// `NSSound.play()` 不保证调用方之外还有强引用；保留当前铃声避免播到一半被释放。
    private var playingSound: NSSound?

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 阶段切换：应用内铃声立即响，系统通知保证切走后也能看到。
    func announce(bell: String?, title: String, body: String) {
        play(bell)
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
        play(bell)
    }

    private func play(_ bell: String?) {
        guard let bell, let sound = FocusBellAudio.sound(bell) else { return }
        playingSound?.stop()
        playingSound = sound
        sound.play()
    }
}

/// 专注铃声先查应用内资源，再回退到系统音；内置铃声不依赖 macOS 音色库。
@MainActor
enum FocusBellAudio {
    static func sound(_ name: String) -> NSSound? {
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: true)
        }
        return NSSound(named: name)
    }
}
