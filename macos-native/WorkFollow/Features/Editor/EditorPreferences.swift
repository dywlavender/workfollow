import Foundation

/// 编辑器偏好（UserDefaults 单一来源，供设置页与所有编辑器实例共用）。
///
/// 目前只有拼写检查：滴答把它做成偏好项（`isContinuousSpellCheckingEnabled`），
/// 默认关。智能替换不开放——它会破坏 Markdown 字面（见 `NativeTextView.init`）。
enum EditorPreferences {
    static let spellCheckingKey = "workfollow.editor.spellChecking"
    static let spellCheckingDidChange = Notification.Name("workfollow.editor.spellCheckingDidChange")

    static var spellCheckingEnabled: Bool {
        UserDefaults.standard.bool(forKey: spellCheckingKey)
    }

    static func setSpellCheckingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: spellCheckingKey)
        NotificationCenter.default.post(name: spellCheckingDidChange, object: nil)
    }
}
