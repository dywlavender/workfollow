import AppKit

/// 任务完成瞬间的反馈音（对齐滴答的完成提示声）。
///
/// 声音开关落在标准 UserDefaults，设置页的开关读写同一个键；
/// 默认开启，关闭后 `play` 是空操作。
@MainActor
enum TaskCompletionFeedback {
    static let soundDefaultsKey = "WFTaskCompletionSoundEnabled"
    static let soundChoiceKey = "WFTaskCompletionSound"

    enum Sound: String, CaseIterable {
        case jingle = "叮", drip = "水滴", knock = "敲击", spiral = "螺旋"
        var identifier: String {
            switch self {
            case .jingle: "jingle"; case .drip: "drip"
            case .knock: "knock"; case .spiral: "spiral"
            }
        }
        var soundName: String {
            switch self {
            case .jingle: "WorkFollowBellJingle"; case .drip: "WorkFollowBellDrip"
            case .knock: "WorkFollowBellKnock"; case .spiral: "WorkFollowBellSpiral"
            }
        }
        static func resolve(_ value: String?) -> Sound {
            guard let value else { return .jingle }
            return allCases.first { $0.identifier == value || $0.rawValue == value || $0.soundName == value } ?? .jingle
        }
    }

    static var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundDefaultsKey) }
    }

    static var sound: Sound {
        get { Sound.resolve(UserDefaults.standard.string(forKey: soundChoiceKey)) }
        set { UserDefaults.standard.set(newValue.identifier, forKey: soundChoiceKey) }
    }

    /// 批量完成会一次触发多行，80ms 内的重复触发合并成一声。
    private static var lastPlayAt = Date.distantPast
    private static var playingSound: NSSound?
    static func play() {
        guard isSoundEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayAt) > 0.08 else { return }
        lastPlayAt = now
        let name = sound.soundName
        let next: NSSound?
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            next = NSSound(contentsOf: url, byReference: true)
        } else {
            next = NSSound(named: name) ?? NSSound(named: "Tink")
        }
        playingSound?.stop()
        playingSound = next
        next?.play()
    }
}
