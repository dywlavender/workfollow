import AppKit

/// 任务完成瞬间的反馈音（对齐滴答的完成提示声）。
///
/// 声音开关落在标准 UserDefaults，设置页的开关读写同一个键；
/// 默认开启，关闭后 `play` 是空操作。
enum TaskCompletionFeedback {
    static let soundDefaultsKey = "WFTaskCompletionSoundEnabled"

    static var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundDefaultsKey) }
    }

    /// 「Tink」是系统自带音里最接近滴答勾选「嗒」的短促声。
    /// 批量完成会一次触发多行，80ms 内的重复触发合并成一声。
    private static var lastPlayAt = Date.distantPast
    static func play() {
        guard isSoundEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayAt) > 0.08 else { return }
        lastPlayAt = now
        NSSound(named: "Tink")?.play()
    }
}
