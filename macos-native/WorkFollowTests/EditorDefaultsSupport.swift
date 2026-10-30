import Foundation
@testable import WorkFollow

/// 正文字号存于 UserDefaults.standard，测试宿主与日用版共用同一个域。
/// 每条用例前后复位，避免用户改过的字号让字号断言飘。
enum EditorDefaultsSupport {
    static func takeBodyFontSize() -> Any? {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: EditorPreferences.bodyFontSizeKey)
        defaults.removeObject(forKey: EditorPreferences.bodyFontSizeKey)
        return previous
    }

    static func restoreBodyFontSize(_ previous: Any?) {
        let defaults = UserDefaults.standard
        if let previous {
            defaults.set(previous, forKey: EditorPreferences.bodyFontSizeKey)
        } else {
            defaults.removeObject(forKey: EditorPreferences.bodyFontSizeKey)
        }
    }
}
