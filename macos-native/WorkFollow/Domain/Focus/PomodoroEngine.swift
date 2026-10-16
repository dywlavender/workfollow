import Foundation

/// 暂停保留来源阶段，展示面共享这一状态机。
enum PomodoroPhase: Equatable, Codable { case idle, focusing, breaking, pausedFocus, pausedBreak }

struct PomodoroSettings: Equatable, Codable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    var longBreakInterval = 4
    var autoStartNextPomodoro = false
    /// 旧版本到点直接休息，迁移时保留原流程。
    var autoStartBreak = true
    /// 0 表示不限制；手动开始会重置本组自动轮数。
    var automaticCycleLimit = 0
    static let focusRange = 5...180
    static let breakRange = 1...60
    static let longBreakRange = 1...60
    static let intervalRange = 2...8
}

/// 兼容旧快照，新增事实字段都是可选值；V2 存储采用同一格式。
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
    var sessionID: UUID? = nil
    var mode: FocusMode? = nil
    var pauseRanges: [FocusPauseRange]? = nil
    var presetID: UUID? = nil
    var pendingBreak: Bool? = nil
    var automaticCompletedCount: Int? = nil
}

/// 计时器负责唤醒，时长始终来自时间锚点。偏好只配置下一会话。
final class PomodoroEngine {
    static let minimumRecordSeconds = TimeInterval(FocusAccountingPolicy.minimumAbandonedSeconds)
    let clock: () -> Date
    private(set) var settings: PomodoroSettings
    private(set) var phase: PomodoroPhase = .idle
    private(set) var isLongBreak = false
    private(set) var currentTaskID: UUID?
    private(set) var phaseSeconds = 0
    private(set) var completedFocusCount = 0
    private(set) var automaticCompletedCount = 0
    private(set) var currentMode: FocusMode = .pomodoro
    private(set) var currentPresetID: UUID?
    private(set) var pendingBreak = false
    private var breakCarriedTaskID: UUID?
    private var breakCarriedPresetID: UUID?
    private var sessionID = UUID()
    private var phaseStart: Date?
    private var phaseEnd: Date?
    private var pausedAt: Date?
    private var pausedSeconds: TimeInterval = 0
    private var pauseRanges: [FocusPauseRange] = []

    init(settings: PomodoroSettings = PomodoroSettings(), clock: @escaping () -> Date = Date.init) {
        self.settings = settings; self.clock = clock
    }

    var cycleProgress: FocusCycleProgress {
        FocusCycleProgress(completedFocusCount: completedFocusCount, automaticCompletedCount: automaticCompletedCount)
    }
    func restoreCycle(_ cycle: FocusCycleProgress) {
        completedFocusCount = cycle.completedFocusCount; automaticCompletedCount = cycle.automaticCompletedCount
    }
    var sessionSnapshot: FocusSessionSnapshot? {
        guard phase != .idle || pendingBreak, let start = phaseStart else { return nil }
        return FocusSessionSnapshot(phase: phase, isLongBreak: isLongBreak, taskID: currentTaskID,
            phaseStart: start, phaseEnd: phaseEnd, phaseSeconds: phaseSeconds, pausedAt: pausedAt,
            pausedSeconds: pausedSeconds, completedFocusCount: completedFocusCount,
            breakCarriedTaskID: breakCarriedTaskID, sessionID: sessionID, mode: currentMode,
            pauseRanges: pauseRanges, presetID: currentPresetID,
            pendingBreak: pendingBreak, automaticCompletedCount: automaticCompletedCount)
    }
    func restore(_ snapshot: FocusSessionSnapshot) {
        phase = snapshot.phase; isLongBreak = snapshot.isLongBreak; currentTaskID = snapshot.taskID
        phaseStart = snapshot.phaseStart; phaseEnd = snapshot.phaseEnd; phaseSeconds = snapshot.phaseSeconds
        pausedAt = snapshot.pausedAt; pausedSeconds = snapshot.pausedSeconds
        completedFocusCount = snapshot.completedFocusCount; breakCarriedTaskID = snapshot.breakCarriedTaskID
        sessionID = snapshot.sessionID ?? UUID()
        currentMode = snapshot.mode ?? ((phase == .focusing || phase == .pausedFocus)
            ? (snapshot.phaseEnd == nil ? .stopwatch : .pomodoro) : .legacy)
        pauseRanges = snapshot.pauseRanges ?? []; currentPresetID = snapshot.presetID
        breakCarriedPresetID = snapshot.presetID
        pendingBreak = snapshot.pendingBreak ?? false
        automaticCompletedCount = snapshot.automaticCompletedCount ?? 0
    }
    var remainingSeconds: Int {
        guard phase != .idle, let end = phaseEnd else { return 0 }
        return max(0, Int(end.timeIntervalSince(pausedAt ?? clock()).rounded()))
    }
    var elapsedSeconds: Int {
        guard phase == .focusing || phase == .pausedFocus else { return 0 }
        return Int(activeSeconds(at: pausedAt ?? clock()))
    }
    func apply(_ settings: PomodoroSettings) { self.settings = settings }

    @discardableResult
    func start(taskID: UUID? = nil, focusMinutes: Int? = nil, stopwatch: Bool = false,
               presetID: UUID? = nil, automatic: Bool = false) -> Bool {
        guard phase == .idle else { return false }
        let minutes = focusMinutes ?? settings.focusMinutes
        guard stopwatch || PomodoroSettings.focusRange.contains(minutes) else { return false }
        if let focusMinutes, !stopwatch { settings.focusMinutes = focusMinutes }
        if !automatic { automaticCompletedCount = 0 }
        let now = clock(); phase = .focusing; pendingBreak = false; isLongBreak = false
        currentTaskID = taskID; currentPresetID = presetID; sessionID = UUID()
        currentMode = stopwatch ? .stopwatch : .pomodoro
        phaseStart = now; phaseSeconds = stopwatch ? 0 : minutes * 60
        phaseEnd = stopwatch ? nil : now.addingTimeInterval(TimeInterval(phaseSeconds))
        pausedAt = nil; pausedSeconds = 0; pauseRanges = []
        return true
    }

    @discardableResult
    func adjustCurrentTarget(bySeconds delta: Int) -> Bool {
        guard currentMode == .pomodoro, phase == .focusing || phase == .pausedFocus,
              let end = phaseEnd else { return false }
        let target = phaseSeconds + delta
        guard (PomodoroSettings.focusRange.lowerBound * 60...PomodoroSettings.focusRange.upperBound * 60).contains(target),
              target > elapsedSeconds else { return false }
        phaseSeconds = target; phaseEnd = end.addingTimeInterval(TimeInterval(delta))
        return true
    }
    func reattach(taskID: UUID?) {
        guard phase == .focusing || phase == .pausedFocus else { return }
        currentTaskID = taskID; breakCarriedTaskID = taskID
    }
    @discardableResult
    func pause() -> Bool {
        guard phase == .focusing || phase == .breaking else { return false }
        pausedAt = clock(); phase = phase == .focusing ? .pausedFocus : .pausedBreak
        return true
    }
    @discardableResult
    func resume() -> Bool {
        guard phase == .pausedFocus || phase == .pausedBreak, let paused = pausedAt else { return false }
        let now = clock(); let duration = max(0, now.timeIntervalSince(paused))
        if let end = phaseEnd { phaseEnd = end.addingTimeInterval(duration) }
        pausedSeconds += duration
        pauseRanges.append(FocusPauseRange(startedAt: paused, endedAt: now))
        pausedAt = nil; phase = phase == .pausedFocus ? .focusing : .breaking
        return true
    }
    @discardableResult
    func giveUp() -> PomodoroRecord? {
        let record = (phase == .focusing || phase == .pausedFocus) && elapsedSeconds >= Int(Self.minimumRecordSeconds)
            ? makeRecord(termination: .abandoned, endedAt: clock(), seconds: elapsedSeconds) : nil
        reset(); return record
    }
    @discardableResult
    func finishEarly() -> PomodoroRecord? {
        guard phase == .focusing || phase == .pausedFocus else { return nil }
        let record = makeRecord(termination: .manuallyEnded, endedAt: clock(), seconds: elapsedSeconds)
        finishFocus(at: clock()); return record
    }
    /// 用户确认提前保存后直接空闲；显式 finishEarly 继续保留其原休息合同。
    @discardableResult
    func finishEarlyWithoutBreak() -> PomodoroRecord? {
        guard phase == .focusing || phase == .pausedFocus else { return nil }
        let record = makeRecord(termination: .manuallyEnded, endedAt: clock(), seconds: elapsedSeconds)
        if currentMode == .pomodoro { completedFocusCount += 1; automaticCompletedCount += 1 }
        reset(); return record
    }
    @discardableResult
    func discardCurrentFocus() -> Bool {
        guard phase == .focusing || phase == .pausedFocus else { return false }
        reset(); return true
    }
    func handleCompletion() -> PomodoroRecord? {
        switch phase {
        case .focusing:
            guard let end = phaseEnd, clock() >= end else { return nil }
            let record = makeRecord(termination: .targetReached, endedAt: end, seconds: phaseSeconds)
            // 休息从实际处理到点的此刻开始，避免重开时凭空跳过休息/生成下一轮。
            finishFocus(at: clock()); return record
        case .breaking:
            guard let end = phaseEnd, clock() >= end else { return nil }
            endBreak(); return nil
        case .idle, .pausedFocus, .pausedBreak: return nil
        }
    }
    @discardableResult
    func startBreak() -> Bool {
        guard pendingBreak, phase == .idle else { return false }
        enterBreak(at: clock()); return true
    }
    @discardableResult
    func skipBreak() -> Bool {
        guard phase == .breaking || phase == .pausedBreak || pendingBreak else { return false }
        endBreak(); return true
    }
    private func activeSeconds(at reference: Date) -> TimeInterval {
        guard let start = phaseStart else { return 0 }
        return max(0, reference.timeIntervalSince(start) - pausedSeconds)
    }
    private func makeRecord(termination: FocusTermination, endedAt: Date, seconds: Int) -> PomodoroRecord? {
        guard let start = phaseStart else { return nil }
        var pauses = pauseRanges
        if let pausedAt { pauses.append(FocusPauseRange(startedAt: pausedAt, endedAt: endedAt)) }
        let details = FocusRecordDetails(mode: currentMode, source: .timer, termination: termination,
            endedAt: endedAt, activeSeconds: max(0, seconds), pausedSeconds: pauses.reduce(0) { $0 + $1.seconds },
            pauseRanges: pauses, targetSeconds: currentMode == .pomodoro ? phaseSeconds : nil,
            presetID: currentPresetID,
            creditedPomodoros: FocusAccountingPolicy.creditedPomodoros(mode: currentMode, termination: termination),
            accountingPolicyVersion: FocusAccountingPolicy.version, precision: .second)
        return PomodoroRecord(id: sessionID, taskID: currentTaskID, startedAt: start,
            minutes: FocusAccountingPolicy.displayedMinutes(seconds: seconds), completed: termination != .abandoned,
            details: details)
    }
    private func finishFocus(at date: Date) {
        if currentMode == .stopwatch { reset(); return }
        completedFocusCount += 1; automaticCompletedCount += 1
        breakCarriedTaskID = currentTaskID; breakCarriedPresetID = currentPresetID
        isLongBreak = settings.longBreakInterval > 0 && completedFocusCount % settings.longBreakInterval == 0
        if settings.autoStartBreak { enterBreak(at: date) }
        else { phase = .idle; pendingBreak = true; currentTaskID = nil; phaseStart = date; phaseEnd = nil; phaseSeconds = 0 }
    }
    private func enterBreak(at date: Date) {
        phase = .breaking; pendingBreak = false; currentTaskID = nil
        phaseStart = date; phaseSeconds = (isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60
        phaseEnd = date.addingTimeInterval(TimeInterval(phaseSeconds))
        pausedAt = nil; pausedSeconds = 0; pauseRanges = []
    }
    private func endBreak() {
        let taskID = breakCarriedTaskID; let presetID = breakCarriedPresetID
        let canStart = settings.autoStartNextPomodoro
            && (settings.automaticCycleLimit == 0 || automaticCompletedCount < settings.automaticCycleLimit)
        reset()
        if canStart { start(taskID: taskID, presetID: presetID, automatic: true) }
    }
    private func reset() {
        phase = .idle; pendingBreak = false; isLongBreak = false; currentTaskID = nil; currentPresetID = nil
        phaseStart = nil; phaseEnd = nil; phaseSeconds = 0; pausedAt = nil; pausedSeconds = 0; pauseRanges = []
    }
}
