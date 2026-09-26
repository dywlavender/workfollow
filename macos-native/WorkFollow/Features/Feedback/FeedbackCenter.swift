import Combine
import Foundation

/// 反馈档位。rawValue 即仲裁优先级：数值越大越重要，同级后来者替换前者。
/// 对齐 Flutter `WorkFollowFeedbackKind`：error 100 > undoable 80 > completion 60 > success 40 > info 20。
enum FeedbackKind: Int {
    case info = 20
    case success = 40
    case completion = 60
    case undoable = 80
    case error = 100

    var priority: Int { rawValue }
    var isFailure: Bool { self == .error }
}

/// 反馈可携带的音效。completion 是"完成任务"专属（与提示 failures 的系统警告音区分开）。
enum FeedbackSound: String { case none, completion }

/// 停留档位与节流窗口，对齐 Flutter `WorkFollowFeedbackTiming` / `FeedbackSoundService`。
/// 独立成无实例枚举：事件模型与测试需要在主线程之外也能读取这些常量。
enum FeedbackTiming {
    static let undoHold: TimeInterval = 4.0
    static let errorHold: TimeInterval = 5.0
    static let completionHold: TimeInterval = 2.6
    static let defaultHold: TimeInterval = completionHold
    /// 连续完成是噪音大头：窗口内的音效全部并入第一次。
    static let soundThrottle: TimeInterval = 1.0
}

/// 一次瞬态结果。只描述"发生了什么"与节奏；颜色、圆角、位置归 FeedbackHostView。
struct FeedbackEvent {
    var kind: FeedbackKind
    var message: String
    /// 唯一的尾部动作（撤销）。kind 决定不了它；可撤销条目在这里给"撤销"。
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var sound: FeedbackSound = .none
    /// 标识一族可互换的结果：同 key 的条目合并成一条而不是叠两条。
    var coalesceKey: String? = nil
    /// 合并条目的文案构造器，收到新的总数（"已完成 2 个任务"）。
    var coalescedMessage: ((Int) -> String)? = nil
    /// 覆盖默认档位的停留时长。
    var duration: TimeInterval? = nil

    /// HUD 停留多久。有可撤销动作时停留更久：撤销入口在用户伸手时消失比没有更糟。
    var hold: TimeInterval {
        if let duration { return duration }
        if action != nil { return FeedbackTiming.undoHold }
        switch kind {
        case .error: return FeedbackTiming.errorHold
        case .completion: return FeedbackTiming.completionHold
        default: return FeedbackTiming.defaultHold
        }
    }

    /// 与 other 同族（合并）与否。
    func coalesces(with other: FeedbackEvent) -> Bool {
        guard let coalesceKey else { return false }
        return coalesceKey == other.coalesceKey
    }

    func aggregatedMessage(count: Int) -> String {
        coalescedMessage?(count) ?? message
    }
}

/// 当前正在展示的一条。稳定 id 让视图区分"替换条目"与"原地更新文案"：
/// 合并出的"已完成 3 个任务"不重放入场过渡。
struct FeedbackPresentation: Identifiable {
    let id: UUID
    var event: FeedbackEvent
    var coalescedCount: Int
}

/// 全应用唯一的瞬态结果通道（对齐 Flutter FeedbackController）。
/// 动作层、菜单、状态栏只管上报一条 FeedbackEvent 就撒手——
/// 谁也不自绘 toast、不持有计时器、不决定一件结果值不值得展示。
///
/// 这里管：当前条目、停留时长、竞争仲裁、合并计数、是否出声；
/// `FeedbackHostView` 管：一切视觉与过渡。
@MainActor
final class FeedbackCenter: ObservableObject {
    @Published private(set) var presentation: FeedbackPresentation?

    /// "完成任务时播放提示音"设置（UserDefaults 键 completionSoundEnabled，默认开）。
    var completionSoundEnabled: Bool

    private let now: () -> Date
    private let playSound: (FeedbackSound) -> Void
    private var holdTimer: _Concurrency.Task<Void, Never>?
    /// 每次展示自增：属于旧一次展示的计时器不得收起新条目。
    private var generation = 0
    private var lastSoundAt: Date?

    init(now: @escaping () -> Date = Date.init,
         completionSoundEnabled: Bool = true,
         playSound: @escaping (FeedbackSound) -> Void = { _ in }) {
        self.now = now
        self.completionSoundEnabled = completionSoundEnabled
        self.playSound = playSound
    }

    /// 展示一条反馈；同族合并计数，被更重要者抢占，不重要者让路。
    func show(_ event: FeedbackEvent) {
        if let showing = presentation, showing.event.coalesces(with: event) {
            let count = showing.coalescedCount + 1
            var folded = event
            folded.message = event.aggregatedMessage(count: count)
            presentation = FeedbackPresentation(id: showing.id, event: folded, coalescedCount: count)
            restartHold()
            playSoundIfDue(event)
            return
        }
        // 屏上有更重要的事：放过这条反馈，好过替换掉用户正伸手去点的撤销或一条失败。
        if let showing = presentation, showing.event.kind.priority > event.kind.priority { return }
        presentation = FeedbackPresentation(id: UUID(), event: event, coalescedCount: 1)
        playSoundIfDue(event)
        restartHold()
    }

    /// 收起当前条目。空场调用无副作用。
    func dismiss() {
        generation += 1
        holdTimer?.cancel()
        holdTimer = nil
        guard presentation != nil else { return }
        presentation = nil
    }

    /// 执行当前条目的撤销动作，随后弹"已撤销"。
    /// HUD 随动作一起离开：留着只会引来对已执行动作的第二次点击。
    func undo() {
        guard let event = presentation?.event, let action = event.action else { return }
        dismiss()
        action()
        show(FeedbackEvent(kind: .success, message: "已撤销"))
    }

    private func restartHold() {
        holdTimer?.cancel()
        generation += 1
        let token = generation
        let hold = presentation?.event.hold ?? FeedbackTiming.defaultHold
        // 模块内 Task 实体遮蔽了并发 Task，须显式 _Concurrency.Task。
        holdTimer = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard let self, token == self.generation else { return }
            self.dismiss()
        }
    }

    private func playSoundIfDue(_ event: FeedbackEvent) {
        guard completionSoundEnabled, event.sound != .none else { return }
        let timestamp = now()
        if let lastSoundAt, timestamp.timeIntervalSince(lastSoundAt) < FeedbackTiming.soundThrottle { return }
        lastSoundAt = timestamp
        playSound(event.sound)
    }
}
