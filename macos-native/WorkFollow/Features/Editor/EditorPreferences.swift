import Foundation

/// 编辑器偏好（UserDefaults 单一来源，供设置页与所有编辑器实例共用）。
///
/// 拼写检查：滴答把它做成偏好项（`isContinuousSpellCheckingEnabled`），默认关；
/// 智能替换不开放——它会破坏 Markdown 字面（见 `NativeTextView.init`）。
/// 正文字号：只作用于没有单独选字号档位的段落，存量文档按新值重排。
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

    /// 编辑栏「正文」的全局字号。只作用于没单独选字号档位的段落；
    /// 「正文 1/2/3」、标题、代码与列表保持各自字阶。
    static let bodyFontSizeKey = "workfollow.editor.bodyFontSize"
    static let defaultBodyFontSize: CGFloat = 14
    static let bodyFontSizeRange: ClosedRange<CGFloat> = 12...18

    static var bodyFontSize: CGFloat {
        let stored = UserDefaults.standard.object(forKey: bodyFontSizeKey) as? Double
        return clampedBodyFontSize(CGFloat(stored ?? Double(defaultBodyFontSize)))
    }

    static func clampedBodyFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, bodyFontSizeRange.lowerBound), bodyFontSizeRange.upperBound)
    }
}
