import Combine
import Foundation

struct PomodoroRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var taskID: UUID?
    var startedAt: Date
    var minutes: Int
    var completed: Bool
}

/// Read-only timing data for Focus presentation. PomodoroEngine remains the owner
/// of the session clock and state transitions.
struct FocusSessionTiming: Equatable {
    let phase: PomodoroPhase
    let phaseStart: Date
    let projectedEndAt: Date?
    let pausedAt: Date?
    let remainingSeconds: Int
}

/// 结束铃声选项：系统音效名，关闭 = 静默。
enum FocusBell: String, CaseIterable {
    case crisp = "清脆"
    case soft = "温和"
    case chime = "灵动"
    case off = "关闭"

    var soundName: String? {
        switch self {
        case .crisp: "Glass"
        case .soft: "Ping"
        case .chime: "Tink"
        case .off: nil
        }
    }
}

/// 番茄偏好，与记录一起持久化到 focus.json。
struct FocusPreferences: Codable, Equatable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    var longBreakInterval = 4
    var dailyGoal = 8
    /// 上一次专注绑定的任务：进入专注页时默认带上（additive Codable）。
    var lastTaskID: UUID?
    /// 休息结束自动开始下一番茄（additive Codable）。
    var autoStartNextPomodoro = false
    /// 正计时模式（tab 切换；additive Codable）。
    var stopwatchMode = false
    /// 结束铃声：FocusBell rawValue，nil/关闭 = 静默（additive Codable）。
    var bellSound: String?

    static let dailyGoalRange = 1...24

    var pomodoroSettings: PomodoroSettings {
        PomodoroSettings(focusMinutes: focusMinutes, breakMinutes: breakMinutes,
                         longBreakMinutes: longBreakMinutes, longBreakInterval: longBreakInterval,
                         autoStartNextPomodoro: autoStartNextPomodoro)
    }

    /// 越界值回退默认，避免损坏或手改的存档影响会话。
    func normalized() -> FocusPreferences {
        var value = self
        if !PomodoroSettings.focusRange.contains(value.focusMinutes) { value.focusMinutes = 25 }
        if !PomodoroSettings.breakRange.contains(value.breakMinutes) { value.breakMinutes = 5 }
        if !PomodoroSettings.longBreakRange.contains(value.longBreakMinutes) { value.longBreakMinutes = 15 }
        if !PomodoroSettings.intervalRange.contains(value.longBreakInterval) { value.longBreakInterval = 4 }
        if !Self.dailyGoalRange.contains(value.dailyGoal) { value.dailyGoal = 8 }
        return value
    }
}

/// 专注模块 store：驱动 PomodoroEngine，持久化记录与偏好；剩余时间展示由本层 Timer 驱动。
@MainActor
final class FocusStore: ObservableObject, ModuleStoreFlushable {
    struct Archive: Codable {
        var records: [PomodoroRecord] = []
        var preferences = FocusPreferences()
        /// 进行中的会话快照：重启后接续计时，空闲时为 nil（additive Codable）。
        var session: FocusSessionSnapshot?
        /// 常用专注预设（additive Codable）。
        var timers: [TimerPreset] = []
    }

    struct TaskFocusTotal: Equatable {
        let taskID: UUID?
        let minutes: Int
    }

    /// 常用专注预设：emoji 头像 + 命名计时器（番茄计时 N 分钟 或 正计时）。
    struct TimerPreset: Codable, Equatable, Identifiable {
        let id: UUID
        var emoji: String
        var name: String
        var stopwatch: Bool
        var minutes: Int
    }

    struct DailyFocusStats: Equatable {
        let dayKey: String
        let day: Date  // 当天 0 点，供视图格式化标题。
        let minutes: Int
        let pomodoros: Int
    }

    struct RecordDayGroup: Identifiable, Equatable {
        let dayKey: String
        let day: Date
        var records: [PomodoroRecord]
        var id: String { dayKey }
    }

    @Published private(set) var records: [PomodoroRecord] = []  // 最新在前
    @Published private(set) var preferences = FocusPreferences()
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var isLongBreak = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var phaseSeconds = 0
    @Published private(set) var currentTaskID: UUID?
    @Published private(set) var todayPomodoros = 0
    @Published private(set) var todayMinutes = 0
    @Published private(set) var timers: [TimerPreset] = []
    /// 阶段切换提醒（通知 + 铃声）；由 AppEnvironment 挂载，测试下为 nil。
    var notifier: FocusNotifier?

    private let engine: PomodoroEngine
    private let persistence: JSONFileStore<Archive>
    private let clock: () -> Date
    private let calendar = Calendar.current
    private var timer: Timer?

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        engine = PomodoroEngine(clock: clock)
        let store: JSONFileStore<Archive>
        if let directory {
            store = JSONFileStore(filename: "focus.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "focus.json")
        }
        persistence = store
        let loaded = store.load() ?? Archive()
        records = loaded.records.sorted { $0.startedAt > $1.startedAt }
        preferences = loaded.preferences.normalized()
        engine.apply(preferences.pomodoroSettings)
        timers = loaded.timers
        if let session = loaded.session {
            engine.restore(session)
        }
        sync()
        if phase != .idle { startTimer() }
        refreshDailyStats()
    }

    deinit { timer?.invalidate() }

    // MARK: - 会话控制

    /// 开始专注；minutes 越界（合法范围 5–180）或已有会话时拒绝，成功后记忆为默认时长。
    /// 正计时模式（stopwatchMode）忽略 minutes。
    @discardableResult
    func start(taskID: UUID? = nil, minutes: Int? = nil, stopwatch: Bool? = nil) -> Bool {
        guard engine.phase == .idle else { return false }
        if let minutes {
            guard PomodoroSettings.focusRange.contains(minutes) else { return false }
            preferences.focusMinutes = minutes
            engine.apply(preferences.pomodoroSettings)
            schedulePersistence()
        }
        notifier?.requestAuthorizationIfNeeded()
        guard engine.start(taskID: taskID,
                           stopwatch: stopwatch ?? preferences.stopwatchMode) else { return false }
        if let taskID {
            preferences.lastTaskID = taskID
            schedulePersistence()
        }
        sync()
        startTimer()
        schedulePersistence()
        return true
    }

    @discardableResult
    func pause() -> Bool {
        guard engine.pause() else { return false }
        sync()
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard engine.resume() else { return false }
        sync()
        return true
    }

    /// 放弃当前阶段；专注满 5 分钟会保留一条未完成记录。
    @discardableResult
    func giveUp() -> PomodoroRecord? {
        let record = engine.giveUp()
        if let record { insert(record) }
        sync()
        stopTimerIfNeeded()
        return record
    }

    /// 提前完成当前专注，随后进入休息。
    @discardableResult
    func finishEarly() -> PomodoroRecord? {
        let record = engine.finishEarly()
        if let record { insert(record) }
        sync()
        return record
    }

    /// 立即同步引擎状态，到点阶段就地完成；Timer 与视图出现时都调用。
    func refresh() {
        if let record = engine.handleCompletion() { insert(record) }
        sync()
        stopTimerIfNeeded()
    }

    // MARK: - 偏好

    @discardableResult
    func setFocusMinutes(_ minutes: Int) -> Bool {
        guard PomodoroSettings.focusRange.contains(minutes) else { return false }
        preferences.focusMinutes = minutes
        engine.apply(preferences.pomodoroSettings)
        schedulePersistence()
        return true
    }

    @discardableResult
    func setBreakMinutes(_ minutes: Int) -> Bool {
        guard PomodoroSettings.breakRange.contains(minutes) else { return false }
        preferences.breakMinutes = minutes
        engine.apply(preferences.pomodoroSettings)
        schedulePersistence()
        return true
    }

    @discardableResult
    func setLongBreakMinutes(_ minutes: Int) -> Bool {
        guard PomodoroSettings.longBreakRange.contains(minutes) else { return false }
        preferences.longBreakMinutes = minutes
        engine.apply(preferences.pomodoroSettings)
        schedulePersistence()
        return true
    }

    @discardableResult
    func setLongBreakInterval(_ count: Int) -> Bool {
        guard PomodoroSettings.intervalRange.contains(count) else { return false }
        preferences.longBreakInterval = count
        engine.apply(preferences.pomodoroSettings)
        schedulePersistence()
        return true
    }

    @discardableResult
    func setAutoStartNextPomodoro(_ enabled: Bool) -> Bool {
        preferences.autoStartNextPomodoro = enabled
        engine.apply(preferences.pomodoroSettings)
        schedulePersistence()
        return true
    }

    @discardableResult
    func setDailyGoal(_ count: Int) -> Bool {
        guard FocusPreferences.dailyGoalRange.contains(count) else { return false }
        preferences.dailyGoal = count
        schedulePersistence()
        return true
    }

    /// 运行中换绑当前专注的任务。
    @discardableResult
    func reattach(taskID: UUID?) -> Bool {
        guard engine.phase == .focusing || engine.phase == .pausedFocus else { return false }
        engine.reattach(taskID: taskID)
        schedulePersistence()
        return true
    }

    /// 正计时模式已走过的秒数（非正计时返回 0）。
    var elapsedSeconds: Int { engine.elapsedSeconds }

    /// Read-only presentation snapshot; Views do not reach into PomodoroEngine.
    var sessionTiming: FocusSessionTiming? {
        guard let snapshot = engine.sessionSnapshot else { return nil }
        return FocusSessionTiming(phase: snapshot.phase,
                                  phaseStart: snapshot.phaseStart,
                                  projectedEndAt: snapshot.phaseEnd,
                                  pausedAt: snapshot.pausedAt,
                                  remainingSeconds: remainingSeconds)
    }

    /// Injected clock exposed to projections. Published timer values invalidate Views each second.
    var currentTime: Date { clock() }

    /// 全量累计（概览卡）：总番茄数与总专注分钟。
    var allTimePomodoros: Int { records.filter(\.completed).count }
    var allTimeMinutes: Int { records.reduce(0) { $0 + $1.minutes } }

    /// 最近 days 天按任务聚合的专注分钟（降序，前 limit 条）。
    func weeklyTaskTotals(days: Int = 7, limit: Int = 3) -> [TaskFocusTotal] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: clock()) ?? clock()
        var byTask: [UUID?: Int] = [:]
        for record in records where record.startedAt >= cutoff {
            byTask[record.taskID, default: 0] += record.minutes
        }
        return byTask
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { TaskFocusTotal(taskID: $0.key, minutes: $0.value) }
    }

    @discardableResult
    func setBell(_ rawValue: String) -> Bool {
        preferences.bellSound = rawValue
        schedulePersistence()
        return true
    }

    @discardableResult
    func setStopwatchMode(_ enabled: Bool) -> Bool {
        guard engine.phase == .idle else { return false }
        preferences.stopwatchMode = enabled
        schedulePersistence()
        return true
    }

    // MARK: - 常用专注

    /// 新建常用专注：名称必填、番茄计时需 5–180 分钟、上限 12 个（对齐滴答）。
    @discardableResult
    func addTimer(name: String, emoji: String, stopwatch: Bool, minutes: Int) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if !stopwatch {
            guard PomodoroSettings.focusRange.contains(minutes) else { return false }
        }
        guard timers.count < 12 else { return false }
        timers.append(TimerPreset(id: UUID(), emoji: emoji, name: trimmed, stopwatch: stopwatch,
                                  minutes: stopwatch ? 0 : minutes))
        schedulePersistence()
        return true
    }

    func deleteTimer(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers.remove(at: index)
        schedulePersistence()
    }

    /// 应用一个常用专注预设到当前设置。
    func applyTimerPreset(_ preset: TimerPreset) {
        setStopwatchMode(preset.stopwatch)
        if !preset.stopwatch { setFocusMinutes(preset.minutes) }
    }

    // MARK: - 记录

    /// 手动补记一条过去的专注记录（对齐滴答）：只允许此刻之前、且落在最近
    /// 7 天内的时段，分钟数 1–180；记录按开始时间归位排序。
    @discardableResult
    func addRecord(taskID: UUID?, startedAt: Date, minutes: Int) -> Bool {
        guard (1...180).contains(minutes) else { return false }
        let now = clock()
        guard startedAt < now else { return false }
        guard let days = calendar.dateComponents([.day], from: startedAt, to: now).day,
              days < 7 else { return false }
        let record = PomodoroRecord(id: UUID(), taskID: taskID, startedAt: startedAt,
                                    minutes: minutes, completed: true)
        records.append(record)
        records.sort { $0.startedAt > $1.startedAt }
        refreshDailyStats()
        schedulePersistence()
        return true
    }

    func deleteRecord(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records.remove(at: index)
        refreshDailyStats()
        schedulePersistence()
    }

    /// 最近 days 天逐日统计，旧→新；每天都会出现，便于看空档。
    func recentDailyStats(days: Int = 7) -> [DailyFocusStats] {
        let today = calendar.startOfDay(for: clock())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = dayKey(day)
            let dayRecords = records.filter { dayKey($0.startedAt) == key }
            return DailyFocusStats(dayKey: key, day: day,
                                   minutes: dayRecords.reduce(0) { $0 + $1.minutes },
                                   pomodoros: dayRecords.filter(\.completed).count)
        }
    }

    /// 记录按天分组，新→旧。
    var recordGroups: [RecordDayGroup] {
        var groups: [RecordDayGroup] = []
        for record in records {
            let key = dayKey(record.startedAt)
            if groups.last?.dayKey == key {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append(RecordDayGroup(dayKey: key,
                                             day: calendar.startOfDay(for: record.startedAt),
                                             records: [record]))
            }
        }
        return groups
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    // MARK: - Private

    private func insert(_ record: PomodoroRecord) {
        records.insert(record, at: 0)
        refreshDailyStats()
        schedulePersistence()
    }

    /// 把引擎状态镜像进 @Published 字段；值未变化时不重复发布。
    /// 阶段切换时发提醒；会话进行中每 5 秒落一次快照供重启接续。
    private func sync() {
        let previousPhase = phase
        if phase != engine.phase { phase = engine.phase }
        notifyTransitions(from: previousPhase, to: phase)
        if previousPhase != phase {
            // 阶段切换即落盘：会话快照与记录状态不因后续崩溃/退出丢失。
            schedulePersistence()
        }
        if engine.phase != .idle {
            let now = clock()
            if now.timeIntervalSince(lastSessionSave) > 5 {
                lastSessionSave = now
                schedulePersistence()
            }
        }
        if isLongBreak != engine.isLongBreak { isLongBreak = engine.isLongBreak }
        if currentTaskID != engine.currentTaskID { currentTaskID = engine.currentTaskID }
        if phaseSeconds != engine.phaseSeconds { phaseSeconds = engine.phaseSeconds }
        let remaining = engine.remainingSeconds
        if remainingSeconds != remaining { remainingSeconds = remaining }
        refreshDailyStats()
    }

    private func refreshDailyStats() {
        let key = dayKey(clock())
        let today = records.filter { dayKey($0.startedAt) == key }
        let pomodoros = today.filter(\.completed).count
        let minutes = today.reduce(0) { $0 + $1.minutes }
        if todayPomodoros != pomodoros { todayPomodoros = pomodoros }
        if todayMinutes != minutes { todayMinutes = minutes }
    }

    private var lastSessionSave = Date.distantPast

    /// 阶段切换提醒：番茄完成 / 休息结束 / 自动开始（放弃与手动跳过不打扰）。
    private func notifyTransitions(from old: PomodoroPhase, to new: PomodoroPhase) {
        guard let notifier else { return }
        switch (old, new) {
        case (.focusing, .breaking):
            notifier.announce(bell: preferences.bellSound, title: "番茄完成",
                              body: (isLongBreak ? "长休息 \(preferences.longBreakMinutes) 分钟开始"
                                     : "休息 \(preferences.breakMinutes) 分钟开始"))
        case (.breaking, .focusing):
            notifier.announce(bell: preferences.bellSound, title: "休息结束",
                              body: "已用同一任务自动开始下一个番茄")
        case (.breaking, .idle):
            notifier.announce(bell: preferences.bellSound, title: "休息结束",
                              body: "准备好了就开始下一个番茄")
        default:
            break
        }
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func schedulePersistence() {
        persistence.schedule(Archive(records: records, preferences: preferences,
                                     session: engine.sessionSnapshot, timers: timers))
    }

    private func startTimer() {
        guard timer == nil else { return }
        let scheduled = Timer(timeInterval: 1, repeats: true) { [weak self] value in
            guard let self else { value.invalidate(); return }
            MainActor.assumeIsolated { self.refresh() }
        }
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    private func stopTimerIfNeeded() {
        guard engine.phase == .idle, let scheduled = timer else { return }
        scheduled.invalidate()
        timer = nil
    }
}
