import Foundation

/// 番茄钟阶段；暂停保留来源阶段，恢复后回到原阶段。
enum PomodoroPhase: Equatable, Codable {
    case idle
    case focusing
    case breaking
    case pausedFocus
    case pausedBreak
}

/// 番茄偏好。focusMinutes 仅允许 5–180，其余范围供 store 校验持久化值。
struct PomodoroSettings: Equatable, Codable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    var longBreakInterval = 4
    /// 休息结束后自动开始下一番茄（同一任务）；additive Codable。
    var autoStartNextPomodoro = false

    static let focusRange = 5...180
    static let breakRange = 1...60
    static let longBreakRange = 1...60
    static let intervalRange = 2...8
}

/// 会话快照：应用重启时恢复进行中的专注/休息（additive Codable）。
struct FocusSessionSnapshot: Codable, Equatable {
    var phase: PomodoroPhase
    var isLongBreak: Bool
    var taskID: UUID?
    var phaseStart: Date
    var phaseEnd: Date?
    var phaseSeconds: Int
    var pausedAt: Date?
    var pausedSeconds: TimeInterval
    var completedFocusCount: Int
    var breakCarriedTaskID: UUID?
}

/// 纯逻辑番茄状态机：不持有真实计时器，时间推进与到点判定全部由注入 clock 驱动。
final class PomodoroEngine {
    /// 放弃专注也保留记录的最少秒数。
    static let minimumRecordSeconds: TimeInterval = 5 * 60

    let clock: () -> Date
    private(set) var settings: PomodoroSettings
    private(set) var phase: PomodoroPhase = .idle
    private(set) var isLongBreak = false
    private(set) var currentTaskID: UUID?
    /// 当前阶段计划总秒数，进入阶段时固定，暂停/恢复不变。
    private(set) var phaseSeconds = 0
    /// 引擎创建以来完成的专注数，驱动长休息节奏。
    private(set) var completedFocusCount = 0
    /// 休息结束自动开始时要续上的任务（进入休息时从当前任务暂存）。
    private var breakCarriedTaskID: UUID?

    /// 进行中的会话快照（空闲为 nil），供持久化层落盘与重启接续。
    var sessionSnapshot: FocusSessionSnapshot? {
        guard phase != .idle, let start = phaseStart else { return nil }
        return FocusSessionSnapshot(phase: phase, isLongBreak: isLongBreak, taskID: currentTaskID,
                                    phaseStart: start, phaseEnd: phaseEnd, phaseSeconds: phaseSeconds,
                                    pausedAt: pausedAt, pausedSeconds: pausedSeconds,
                                    completedFocusCount: completedFocusCount,
                                    breakCarriedTaskID: breakCarriedTaskID)
    }

    /// 从持久化快照恢复会话（应用重启接续）；是否已到点交给 handleCompletion 判定。
    func restore(_ snapshot: FocusSessionSnapshot) {
        phase = snapshot.phase
        isLongBreak = snapshot.isLongBreak
        currentTaskID = snapshot.taskID
        phaseStart = snapshot.phaseStart
        phaseEnd = snapshot.phaseEnd
        phaseSeconds = snapshot.phaseSeconds
        pausedAt = snapshot.pausedAt
        pausedSeconds = snapshot.pausedSeconds
        completedFocusCount = snapshot.completedFocusCount
        breakCarriedTaskID = snapshot.breakCarriedTaskID
    }

    private var phaseStart: Date?
    private var phaseEnd: Date?
    private var pausedAt: Date?
    private var pausedSeconds: TimeInterval = 0

    init(settings: PomodoroSettings = PomodoroSettings(), clock: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.clock = clock
    }

    /// 当前阶段剩余秒数；暂停时冻结，空闲为 0。
    var remainingSeconds: Int {
        guard let end = phaseEnd else { return 0 }
        let reference = pausedAt ?? clock()
        return max(0, Int(end.timeIntervalSince(reference).rounded()))
    }

    /// 应用偏好；进行中的阶段不受影响（时长在进入阶段时已固定）。
    func apply(_ settings: PomodoroSettings) {
        self.settings = settings
    }

    /// 开始一次专注；focusMinutes 越界或不在就绪状态时拒绝。
    /// stopwatch = true 时为正计时模式：无终止时间，计时只增不减。
    @discardableResult
    func start(taskID: UUID? = nil, focusMinutes: Int? = nil, stopwatch: Bool = false) -> Bool {
        guard phase == .idle else { return false }
        if let focusMinutes {
            guard PomodoroSettings.focusRange.contains(focusMinutes) else { return false }
            settings.focusMinutes = focusMinutes
        }
        let now = clock()
        phase = .focusing
        currentTaskID = taskID
        phaseStart = now
        if stopwatch {
            phaseSeconds = 0
            phaseEnd = nil
        } else {
            phaseSeconds = settings.focusMinutes * 60
            phaseEnd = now.addingTimeInterval(TimeInterval(phaseSeconds))
        }
        pausedAt = nil
        pausedSeconds = 0
        return true
    }

    /// 当前专注的实际经过秒数（正计时模式的显示值，暂停不计）。
    var elapsedSeconds: Int {
        guard phaseStart != nil, phase == .focusing || phase == .pausedFocus else { return 0 }
        return Int(focusElapsedSeconds())
    }

    /// 运行中换绑当前专注的任务（影响完成记录的归属）。
    func reattach(taskID: UUID?) {
        guard phase == .focusing || phase == .pausedFocus else { return }
        currentTaskID = taskID
        breakCarriedTaskID = taskID
    }

    @discardableResult
    func pause() -> Bool {
        guard phase == .focusing || phase == .breaking else { return false }
        pausedAt = clock()
        phase = phase == .focusing ? .pausedFocus : .pausedBreak
        return true
    }

    /// 恢复：用注入 clock 的差值顺延阶段结束时间，暂停时长不计入阶段。
    @discardableResult
    func resume() -> Bool {
        guard let paused = pausedAt else { return false }
        let now = clock()
        if let end = phaseEnd {
            phaseEnd = now.addingTimeInterval(end.timeIntervalSince(paused))
        }
        if phase == .pausedFocus { pausedSeconds += now.timeIntervalSince(paused) }
        pausedAt = nil
        phase = phase == .pausedFocus ? .focusing : .breaking
        return true
    }

    /// 放弃当前阶段回到就绪；专注满 5 分钟保留 completed=false 的记录。
    @discardableResult
    func giveUp() -> PomodoroRecord? {
        let record = abandonRecord()
        reset()
        return record
    }

    /// 提前完成当前专注：按实际分钟数（向上取整，至少 1）记录，随后进入休息。
    @discardableResult
    func finishEarly() -> PomodoroRecord? {
        guard phase == .focusing || phase == .pausedFocus, let start = phaseStart else { return nil }
        let elapsed = focusElapsedSeconds()
        let record = PomodoroRecord(id: UUID(), taskID: currentTaskID, startedAt: start,
                                    minutes: max(1, Int((elapsed / 60).rounded(.up))), completed: true)
        completedFocusCount += 1
        enterBreak(at: clock())
        return record
    }

    /// 阶段到点时调用（由 store 的 Timer 或测试推进 clock 驱动）：
    /// 专注完成→产生记录并进入休息；休息完成→回到就绪。
    func handleCompletion() -> PomodoroRecord? {
        switch phase {
        case .focusing:
            guard let start = phaseStart, let end = phaseEnd, clock() >= end else { return nil }
            let record = PomodoroRecord(id: UUID(), taskID: currentTaskID, startedAt: start,
                                        minutes: settings.focusMinutes, completed: true)
            completedFocusCount += 1
            enterBreak(at: end)
            return record
        case .breaking:
            guard let end = phaseEnd, clock() >= end else { return nil }
            if settings.autoStartNextPomodoro, let taskID = breakCarriedTaskID {
                reset()
                start(taskID: taskID)
                return nil
            }
            reset()
            return nil
        case .idle, .pausedFocus, .pausedBreak:
            return nil
        }
    }

    // MARK: - Private

    /// 本次专注的实际秒数，暂停时长不计入。
    private func focusElapsedSeconds() -> TimeInterval {
        guard let start = phaseStart else { return 0 }
        let reference = pausedAt ?? clock()
        return max(0, reference.timeIntervalSince(start) - pausedSeconds)
    }

    private func abandonRecord() -> PomodoroRecord? {
        guard phase == .focusing || phase == .pausedFocus, let start = phaseStart else { return nil }
        let elapsed = focusElapsedSeconds()
        guard elapsed >= Self.minimumRecordSeconds else { return nil }
        return PomodoroRecord(id: UUID(), taskID: currentTaskID, startedAt: start,
                              minutes: Int(elapsed / 60), completed: false)
    }

    private func enterBreak(at date: Date) {
        let long = settings.longBreakInterval > 0 && completedFocusCount % settings.longBreakInterval == 0
        isLongBreak = long
        phase = .breaking
        phaseStart = date
        phaseSeconds = (long ? settings.longBreakMinutes : settings.breakMinutes) * 60
        phaseEnd = date.addingTimeInterval(TimeInterval(phaseSeconds))
        breakCarriedTaskID = currentTaskID
        currentTaskID = nil
        pausedAt = nil
        pausedSeconds = 0
    }

    private func reset() {
        phase = .idle
        isLongBreak = false
        phaseStart = nil
        phaseEnd = nil
        phaseSeconds = 0
        currentTaskID = nil
        pausedAt = nil
        pausedSeconds = 0
    }
}
