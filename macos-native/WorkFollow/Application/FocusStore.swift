import Combine
import Foundation

struct FocusSessionTiming: Equatable {
    let phase: PomodoroPhase
    let phaseStart: Date
    let projectedEndAt: Date?
    let pausedAt: Date?
    let remainingSeconds: Int
}

enum FocusBell: String, CaseIterable {
    case crisp = "清脆", soft = "温和", chime = "灵动", off = "关闭"
    var identifier: String {
        switch self { case .crisp: "glass"; case .soft: "ping"; case .chime: "tink"; case .off: "off" }
    }
    var soundName: String? {
        switch self { case .crisp: "Glass"; case .soft: "Ping"; case .chime: "Tink"; case .off: nil }
    }
    static func resolve(_ value: String?) -> FocusBell {
        allCases.first { $0.identifier == value || $0.rawValue == value || $0.soundName == value } ?? .off
    }
}

struct FocusPreferences: Codable, Equatable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    var longBreakInterval = 4
    var dailyGoal = 8
    var lastTaskID: UUID?
    var autoStartNextPomodoro = false
    var stopwatchMode = false
    var bellSound: String?
    var bellID: String? = nil
    var autoStartBreak = true
    var automaticCycleLimit = 0
    static let dailyGoalRange = 1...24
    var bell: FocusBell { FocusBell.resolve(bellID ?? bellSound) }
    var pomodoroSettings: PomodoroSettings {
        PomodoroSettings(focusMinutes: focusMinutes, breakMinutes: breakMinutes,
            longBreakMinutes: longBreakMinutes, longBreakInterval: longBreakInterval,
            autoStartNextPomodoro: autoStartNextPomodoro, autoStartBreak: autoStartBreak,
            automaticCycleLimit: automaticCycleLimit)
    }
    func normalized() -> FocusPreferences {
        var value = self
        if !PomodoroSettings.focusRange.contains(value.focusMinutes) { value.focusMinutes = 25 }
        if !PomodoroSettings.breakRange.contains(value.breakMinutes) { value.breakMinutes = 5 }
        if !PomodoroSettings.longBreakRange.contains(value.longBreakMinutes) { value.longBreakMinutes = 15 }
        if !PomodoroSettings.intervalRange.contains(value.longBreakInterval) { value.longBreakInterval = 4 }
        if !Self.dailyGoalRange.contains(value.dailyGoal) { value.dailyGoal = 8 }
        if !(0...12).contains(value.automaticCycleLimit) { value.automaticCycleLimit = 0 }
        value.bellID = value.bell.identifier
        return value
    }
}

extension FocusPreferences {
    private enum CodingKeys: String, CodingKey {
        case focusMinutes, breakMinutes, longBreakMinutes, longBreakInterval, dailyGoal, lastTaskID
        case autoStartNextPomodoro, stopwatchMode, bellSound, bellID, autoStartBreak, automaticCycleLimit
    }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 5
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        longBreakInterval = try c.decodeIfPresent(Int.self, forKey: .longBreakInterval) ?? 4
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 8
        lastTaskID = try c.decodeIfPresent(UUID.self, forKey: .lastTaskID)
        autoStartNextPomodoro = try c.decodeIfPresent(Bool.self, forKey: .autoStartNextPomodoro) ?? false
        stopwatchMode = try c.decodeIfPresent(Bool.self, forKey: .stopwatchMode) ?? false
        bellSound = try c.decodeIfPresent(String.self, forKey: .bellSound)
        bellID = try c.decodeIfPresent(String.self, forKey: .bellID)
        autoStartBreak = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true
        automaticCycleLimit = try c.decodeIfPresent(Int.self, forKey: .automaticCycleLimit) ?? 0
    }
}

@MainActor
final class FocusStore: ObservableObject, ModuleStoreFlushable {
    var onTaskFocusStarted: ((UUID, Bool) -> Void)?
    struct Archive: Codable {
        var records: [PomodoroRecord] = []
        var preferences = FocusPreferences()
        var session: FocusSessionSnapshot?
        var timers: [TimerPreset] = []
        var sessionNote: String? = nil
        var sessionV2: FocusSessionSnapshot? = nil
        var completionContext: FocusCompletionContext? = nil
        var cycleProgress: FocusCycleProgress? = nil
        var selectedPresetID: UUID? = nil
    }
    struct TimerPreset: Codable, Equatable, Identifiable {
        let id: UUID
        var emoji: String
        var name: String
        var stopwatch: Bool
        var minutes: Int
        var taskID: UUID? = nil
        var archivedAt: Date? = nil
        var sortOrder: Int? = nil
    }
    struct TaskFocusTotal: Equatable { let taskID: UUID?; let minutes: Int }
    struct DailyFocusStats: Equatable { let dayKey: String; let day: Date; let minutes: Int; let pomodoros: Int }
    struct RecordDayGroup: Identifiable, Equatable {
        let dayKey: String; let day: Date; var records: [PomodoroRecord]
        var id: String { dayKey }
    }
    struct FilteredStats: Equatable { var seconds = 0; var pomodoros = 0; var records = 0 }
    enum ContentRoute: Equatable { case automatic, records, statistics }

    @Published private(set) var visibleRecords: [PomodoroRecord] = []
    @Published private(set) var historyRevision = 0
    @Published private(set) var historyLoading = false
    @Published private(set) var historyHasMore = false
    @Published private(set) var historyError: String?
    @Published private(set) var allTimePomodoros = 0
    @Published private(set) var allTimeMinutes = 0
    @Published private(set) var allTimeActiveSeconds = 0
    @Published private(set) var todayPomodoros = 0
    @Published private(set) var todayMinutes = 0
    @Published private(set) var todayActiveSeconds = 0
    @Published private(set) var preferences = FocusPreferences()
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var isLongBreak = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var phaseSeconds = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var currentMode: FocusMode = .pomodoro
    @Published private(set) var currentTaskID: UUID?
    @Published private(set) var currentSessionNote = ""
    @Published private(set) var completedSessionNote = ""
    @Published private(set) var timers: [TimerPreset] = []
    @Published private(set) var pendingBreak = false
    @Published private(set) var completionContext: FocusCompletionContext?
    @Published private(set) var pendingEndConfirmation: FocusEndConfirmation?
    @Published private(set) var selectedPresetID: UUID?
    @Published private(set) var contentRoute: ContentRoute = .automatic
    @Published private(set) var workspacePage: FocusWorkspacePage = .library
    @Published private(set) var presetLibrarySection: FocusPresetLibrarySection = .active
    @Published private(set) var browsedPresetID: UUID?
    @Published private(set) var recordFilter = FocusRecordFilter()
    var notifier: FocusNotifier?

    private var recordCount = 0
    private var historyGeneration = 0
    private var statsDay: String?
    private let historyPageSize = 50
    private let engine: PomodoroEngine
    private let persistence: SQLiteRecordStore<PomodoroRecord, Archive>
    private let clock: () -> Date
    private let calendar: Calendar
    private var timer: Timer?
    private var lastSessionSave = Date.distantPast
    private var completionRecordCache: PomodoroRecord?

    var records: [PomodoroRecord] { read(fallback: []) { try persistence.history(limit: Int.max) } }
    var hydratedRecordCount: Int { persistence.decodedRecordCount }
    var statisticsQueryCount: Int { persistence.aggregateQueryCount }
    var storageError: Error? { persistence.readError }
    var currentTime: Date { clock() }
    var presentationCalendar: Calendar { calendar }
    var activeTimers: [TimerPreset] {
        timers.filter { $0.archivedAt == nil }.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }
    var archivedTimers: [TimerPreset] {
        timers.filter { $0.archivedAt != nil }.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }
    var canStartTimerPreset: Bool {
        phase == .idle && !pendingBreak && completionContext?.extraTimeStartedAt == nil && pendingEndConfirmation == nil
    }
    var currentSessionPresetID: UUID? { engine.currentPresetID }
    var sessionTiming: FocusSessionTiming? {
        guard let s = engine.sessionSnapshot, s.phase != .idle else { return nil }
        return FocusSessionTiming(phase: s.phase, phaseStart: s.phaseStart,
            projectedEndAt: s.phaseEnd, pausedAt: s.pausedAt, remainingSeconds: remainingSeconds)
    }
    var displayedSessionTiming: FocusSessionTiming? {
        if phase == .focusing || phase == .pausedFocus { return sessionTiming }
        if let record = completedRecord {
            return FocusSessionTiming(phase: .focusing, phaseStart: record.startedAt,
                projectedEndAt: nil, pausedAt: nil, remainingSeconds: 0)
        }
        return sessionTiming ?? FocusSessionTiming(phase: .idle, phaseStart: clock(),
            projectedEndAt: nil, pausedAt: nil, remainingSeconds: 0)
    }
    var presentation: FocusPresentation {
        let active = phase == .focusing || phase == .pausedFocus
        let hasSession = phase != .idle || pendingBreak || completionContext != nil
        let mode = hasSession ? currentMode : (preferences.stopwatchMode ? .stopwatch : .pomodoro)
        let seconds = completionContext?.extraTimeStartedAt != nil ? availableExtraSeconds : (phase == .idle ? (completedDisplaySeconds ?? (mode == .stopwatch ? 0 : preferences.focusMinutes * 60))
            : (active && mode == .stopwatch ? elapsedSeconds : remainingSeconds))
        let actions: [FocusCommand]
        switch phase {
        case .idle: actions = completionContext?.extraTimeStartedAt != nil ? [.end, .abandon]
            : (pendingBreak ? [.startBreak, .skipBreak] : [.start])
        case .focusing: actions = [.pause, .end, .abandon]
        case .pausedFocus: actions = [.resume, .end, .abandon]
        case .breaking: actions = [.pause, .skipBreak]
        case .pausedBreak: actions = [.resume, .skipBreak]
        }
        let title: String
        switch phase {
        case .idle: title = completionContext?.extraTimeStartedAt != nil ? "追加专注中" : (pendingBreak ? "准备休息" : "就绪")
        case .focusing: title = "\(mode.title)中"
        case .pausedFocus: title = "已暂停"
        case .breaking: title = isLongBreak ? "长休息中" : "休息中"
        case .pausedBreak: title = "休息已暂停"
        }
        return FocusPresentation(mode: mode, phase: phase, phaseTitle: title, displaySeconds: seconds,
            elapsedSeconds: elapsedSeconds, targetSeconds: active && mode == .pomodoro ? phaseSeconds : nil,
            progress: phaseSeconds > 0 ? min(1, max(0, Double(phaseSeconds - remainingSeconds) / Double(phaseSeconds))) : 0,
            isPaused: phase == .pausedFocus || phase == .pausedBreak, taskID: currentTaskID,
            availableActions: actions, completion: completionContext)
    }

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current, directory: URL? = nil) {
        self.clock = clock; self.calendar = calendar; engine = PomodoroEngine(clock: clock)
        let store = SQLiteRecordStore<PomodoroRecord, Archive>(filename: "focus",
            directory: directory ?? JSONFileStore<Archive>.moduleDirectory, newestFirst: true,
            timestamp: { $0.startedAt }, taskID: { $0.taskID },
            metrics: { ($0.activeSeconds, $0.creditedPomodoros) }, metricsVersion: "focus-seconds-v1",
            migrate: { data in
                var archive = try JSONDecoder().decode(Archive.self, from: data)
                let records = archive.records; archive.records = []
                return .init(records: records, metadata: archive)
            })
        persistence = store
        let loaded = store.load(recentLimit: 0)?.metadata ?? Archive()
        let totals = read(fallback: SQLiteRecordStore<PomodoroRecord, Archive>.Totals()) { try store.totals() }
        allTimeActiveSeconds = totals.value; allTimeMinutes = FocusAccountingPolicy.aggregatedMinutes(seconds: totals.value)
        allTimePomodoros = totals.count; recordCount = totals.records; historyHasMore = recordCount > 0
        preferences = loaded.preferences.normalized(); timers = loaded.timers; selectedPresetID = loaded.selectedPresetID
        completionContext = loaded.completionContext
        engine.apply(preferences.pomodoroSettings)
        if let cycle = loaded.cycleProgress { engine.restoreCycle(cycle) }
        if let session = loaded.sessionV2 ?? loaded.session { engine.restore(session) }
        if engine.phase == .focusing || engine.phase == .pausedFocus || (engine.phase == .idle && completionContext == nil) {
            currentSessionNote = loaded.sessionNote ?? ""
        }
        sync()
        workspacePage = phase != .idle || pendingBreak || completionContext != nil ? .timer : .library
        if phase != .idle || hasExtraTimeClock { startTimer() }
    }
    deinit { timer?.invalidate() }

    // MARK: Shared commands
    @discardableResult
    func perform(_ command: FocusCommand, taskID: UUID? = nil) -> Bool {
        switch command {
        case .start: start(taskID: taskID ?? preferences.lastTaskID)
        case .pause: pause()
        case .resume: resume()
        case .end: endFromUserAction()
        case .abandon: completionContext?.extraTimeStartedAt != nil ? cancelCompletionExtraTime() : abandon()
        case .startBreak: startBreak()
        case .skipBreak: skipBreak()
        }
    }
    @discardableResult
    func start(taskID: UUID? = nil, minutes: Int? = nil, stopwatch: Bool? = nil) -> Bool {
        guard engine.phase == .idle, completionContext?.extraTimeStartedAt == nil else { return false }
        let mode = stopwatch ?? preferences.stopwatchMode
        if let minutes, !mode {
            guard PomodoroSettings.focusRange.contains(minutes) else { return false }
            preferences.focusMinutes = minutes
        }
        preferences.stopwatchMode = mode; preferences.lastTaskID = taskID
        engine.apply(preferences.pomodoroSettings)
        notifier?.requestAuthorizationIfNeeded()
        guard engine.start(taskID: taskID, stopwatch: mode, presetID: selectedPresetID) else { return false }
        let preparedNote = completionContext == nil ? currentSessionNote : ""
        completionContext = nil; currentSessionNote = preparedNote; showTimerWorkspace()
        sync(); startTimer(); schedulePersistence()
        if let taskID { onTaskFocusStarted?(taskID, mode) }
        return true
    }
    @discardableResult
    func pause() -> Bool {
        guard engine.pause() else { return false }; sync(); schedulePersistence(); return true
    }
    @discardableResult
    func resume() -> Bool {
        guard engine.resume() else { return false }; sync(); startTimer(); schedulePersistence(); return true
    }
    @discardableResult
    func adjustCurrentTarget(byMinutes delta: Int) -> Bool {
        guard engine.adjustCurrentTarget(bySeconds: delta * 60) else { return false }
        sync(); schedulePersistence(); return true
    }
    @discardableResult
    func reattach(taskID: UUID?) -> Bool {
        guard phase == .focusing || phase == .pausedFocus else { return false }
        engine.reattach(taskID: taskID); preferences.lastTaskID = taskID; sync(); schedulePersistence(); return true
    }
    @discardableResult
    func abandon() -> Bool {
        guard phase == .focusing || phase == .pausedFocus else { return false }
        _ = giveUp(); return true
    }
    @discardableResult
    func giveUp() -> PomodoroRecord? {
        if phase == .breaking || phase == .pausedBreak || pendingBreak { _ = skipBreak(); return nil }
        let record = engine.giveUp().map { insert($0, sessionNote: currentSessionNote) }
        completionContext = nil; currentSessionNote = ""; showPresetLibrary(); sync(); stopTimerIfNeeded(); schedulePersistence()
        return record
    }
    @discardableResult
    func finishEarly() -> PomodoroRecord? {
        guard let value = engine.finishEarly() else { return nil }
        let record = insert(value, sessionNote: currentSessionNote)
        currentSessionNote = ""; setCompletion(record); sync(); stopTimerIfNeeded(); schedulePersistence()
        return record
    }
    private func endFromUserAction() -> Bool {
        guard pendingEndConfirmation == nil else { return false }
        if completionContext?.extraTimeStartedAt != nil { return appendCompletionExtraTime() }
        guard engine.phase == .focusing || engine.phase == .pausedFocus else { return false }
        if engine.currentMode != .pomodoro { return finishEarly() != nil }
        if FocusAccountingPolicy.discardsUserEndedSession(mode: engine.currentMode, activeSeconds: engine.elapsedSeconds) {
            _ = engine.discardCurrentFocus(); returnToOverviewAfterUserEnd(); return true
        }
        guard let sessionID = engine.sessionSnapshot?.sessionID else { return false }
        pendingEndConfirmation = FocusEndConfirmation(sessionID: sessionID, activeSeconds: engine.elapsedSeconds)
        return true
    }
    @discardableResult
    func resolveEndConfirmation(_ choice: FocusEndConfirmationChoice) -> Bool {
        guard let request = pendingEndConfirmation,
              request.sessionID == engine.sessionSnapshot?.sessionID else { return false }
        switch choice {
        case .cancel:
            pendingEndConfirmation = nil
        case .save:
            guard let value = engine.finishEarlyWithoutBreak() else { return false }
            _ = insert(value, sessionNote: currentSessionNote)
            returnToOverviewAfterUserEnd()
        case .discard:
            guard engine.discardCurrentFocus() else { return false }
            returnToOverviewAfterUserEnd()
        }
        return true
    }
    private func returnToOverviewAfterUserEnd() {
        pendingEndConfirmation = nil
        completionContext = nil; completionRecordCache = nil
        currentSessionNote = ""; completedSessionNote = ""
        showPresetLibrary(); showOverview(); sync(); stopTimerIfNeeded(); schedulePersistence()
    }
    @discardableResult
    func startBreak() -> Bool {
        guard engine.startBreak() else { return false }
        stopPendingExtraClock()
        sync(); startTimer(); schedulePersistence(); return true
    }
    @discardableResult
    func skipBreak() -> Bool {
        guard engine.skipBreak() else { return false }
        stopPendingExtraClock()
        afterAutomaticStart(); sync(); stopTimerIfNeeded(); schedulePersistence(); return true
    }
    func refresh() {
        let oldPhase = engine.phase
        if let value = engine.handleCompletion() {
            let record = insert(value, sessionNote: currentSessionNote); currentSessionNote = ""; setCompletion(record)
            notifier?.announce(bell: preferences.bell.soundName, title: "番茄完成", body: "本次专注已保存")
        } else if oldPhase == .breaking, engine.phase != .breaking {
            afterAutomaticStart()
            notifier?.announce(bell: preferences.bell.soundName, title: "休息结束",
                body: engine.phase == .focusing ? "下一个番茄已开始" : "准备好了就开始下一个番茄")
        }
        sync(); stopTimerIfNeeded()
    }
    private func afterAutomaticStart() {
        guard engine.phase == .focusing else { return }
        completionContext = nil; currentSessionNote = ""; contentRoute = .automatic
        if let taskID = engine.currentTaskID { onTaskFocusStarted?(taskID, false) }
    }
    func updateCurrentSessionNote(_ note: String) {
        let canEdit = phase == .focusing || phase == .pausedFocus
            || (phase == .idle && completionContext == nil && !pendingBreak)
        guard canEdit, currentSessionNote != note else { return }
        currentSessionNote = note; schedulePersistence()
    }
    private func setCompletion(_ record: PomodoroRecord) {
        completionRecordCache = record; completedSessionNote = record.note ?? ""
        let completedAt = record.endedAt ?? clock()
        let tracksPending = record.mode == .pomodoro && record.details?.termination == .targetReached
            && engine.phase == .idle && engine.pendingBreak
        completionContext = FocusCompletionContext(recordID: record.id, completedAt: completedAt,
            extraTimeAnchor: clock(), pendingExtraSeconds: max(0, Int(clock().timeIntervalSince(completedAt))),
            tracksPendingExtraTime: tracksPending, pendingExtraStartedAt: tracksPending ? clock() : nil,
            recordActiveSeconds: record.activeSeconds)
    }
    func dismissCompletion() {
        if engine.pendingBreak { _ = engine.giveUp() }
        completionContext = nil; showPresetLibrary(); sync(); stopTimerIfNeeded(); schedulePersistence()
    }
    var completedRecord: PomodoroRecord? {
        guard let context = completionContext else { return nil }
        if completionRecordCache?.id != context.recordID {
            completionRecordCache = record(id: context.recordID)
        }
        return completionRecordCache
    }
    func prepareCompletedSessionNote() {
        completedSessionNote = completedRecord?.note ?? ""
    }
    func updateCompletedSessionNote(_ note: String) {
        guard var value = completedRecord, completedSessionNote != note else { return }
        completedSessionNote = note; value.note = trimmedNote(note)
        completionRecordCache = value
        if let index = visibleRecords.firstIndex(where: { $0.id == value.id }) { visibleRecords[index] = value }
        invalidateHistory(); persistence.schedule(upserts: [value], metadata: archive())
    }
    var completedDisplaySeconds: Int? {
        guard let context = completionContext, let seconds = context.recordActiveSeconds else { return nil }
        return context.tracksPendingExtraTime == true && context.extraTimeWasAppended == true
            ? seconds / 60 * 60 : seconds
    }
    var isTrackingPendingExtraTime: Bool { completionContext?.pendingExtraStartedAt != nil }
    private var hasExtraTimeClock: Bool {
        completionContext?.extraTimeStartedAt != nil || isTrackingPendingExtraTime
    }
    var availableExtraSeconds: Int {
        guard let context = completionContext else { return 0 }
        let running = context.extraTimeStartedAt.map { max(0, Int(clock().timeIntervalSince($0))) } ?? 0
        let pending = context.pendingExtraStartedAt.map { max(0, Int(clock().timeIntervalSince($0))) } ?? 0
        return (context.pendingExtraSeconds ?? 0) + running + pending
    }
    private func stopPendingExtraClock() {
        guard var context = completionContext, let startedAt = context.pendingExtraStartedAt else { return }
        context.pendingExtraSeconds = (context.pendingExtraSeconds ?? 0) + max(0, Int(clock().timeIntervalSince(startedAt)))
        context.pendingExtraStartedAt = nil; completionContext = context
    }
    @discardableResult
    func startCompletionExtraTime() -> Bool {
        guard var context = completionContext, context.extraTimeStartedAt == nil,
              context.tracksPendingExtraTime != true,
              phase != .focusing && phase != .pausedFocus else { return false }
        if phase == .breaking || phase == .pausedBreak || pendingBreak { _ = engine.giveUp() }
        context.extraTimeStartedAt = clock(); context.extraTimeAnchor = clock(); completionContext = context
        sync(); startTimer(); schedulePersistence(); return true
    }
    @discardableResult
    func appendCompletionExtraTime() -> Bool {
        guard var context = completionContext, var value = record(id: context.recordID), var details = value.details,
              context.tracksPendingExtraTime != true || context.pendingExtraStartedAt != nil,
              availableExtraSeconds > 0 else { return false }
        let extra = availableExtraSeconds
        // 两个有效专注段之间的间隔保持为暂停，休息不会进入有效时长。
        if let extraStart = context.extraTimeStartedAt, let previousEnd = details.endedAt, extraStart > previousEnd {
            let gap = FocusPauseRange(startedAt: min(extraStart, previousEnd.addingTimeInterval(TimeInterval(context.pendingExtraSeconds ?? 0))), endedAt: extraStart)
            details.pauseRanges.append(gap); details.pausedSeconds += gap.seconds
        }
        details.activeSeconds += extra
        details.endedAt = context.extraTimeStartedAt != nil || context.pendingExtraStartedAt != nil ? clock()
            : (details.endedAt?.addingTimeInterval(TimeInterval(extra)) ?? clock())
        details.durationCorrectionSeconds = (details.durationCorrectionSeconds ?? 0) + extra
        value.details = details; value.minutes = FocusAccountingPolicy.displayedMinutes(seconds: details.activeSeconds)
        context.extraTimeAnchor = clock(); context.pendingExtraSeconds = 0
        context.extraTimeStartedAt = nil; context.pendingExtraStartedAt = nil; context.extraTimeWasAppended = true
        completionContext = context; replace(value)
        stopTimerIfNeeded(); schedulePersistence(); return true
    }

    @discardableResult
    func cancelCompletionExtraTime() -> Bool {
        guard var context = completionContext, context.extraTimeStartedAt != nil else { return false }
        context.extraTimeStartedAt = nil; completionContext = context
        stopTimerIfNeeded(); schedulePersistence(); return true
    }

    // MARK: Next-session preferences
    @discardableResult func setFocusMinutes(_ value: Int) -> Bool {
        guard PomodoroSettings.focusRange.contains(value) else { return false }
        preferences.focusMinutes = value; updateSettings(); return true
    }
    @discardableResult func setBreakMinutes(_ value: Int) -> Bool {
        guard PomodoroSettings.breakRange.contains(value) else { return false }
        preferences.breakMinutes = value; updateSettings(); return true
    }
    @discardableResult func setLongBreakMinutes(_ value: Int) -> Bool {
        guard PomodoroSettings.longBreakRange.contains(value) else { return false }
        preferences.longBreakMinutes = value; updateSettings(); return true
    }
    @discardableResult func setLongBreakInterval(_ value: Int) -> Bool {
        guard PomodoroSettings.intervalRange.contains(value) else { return false }
        preferences.longBreakInterval = value; updateSettings(); return true
    }
    @discardableResult func setAutoStartNextPomodoro(_ enabled: Bool) -> Bool {
        preferences.autoStartNextPomodoro = enabled; updateSettings(); return true
    }
    @discardableResult func setAutoStartBreak(_ enabled: Bool) -> Bool {
        preferences.autoStartBreak = enabled; updateSettings(); return true
    }
    @discardableResult func setAutomaticCycleLimit(_ value: Int) -> Bool {
        guard (0...12).contains(value) else { return false }
        preferences.automaticCycleLimit = value; updateSettings(); return true
    }
    @discardableResult func setDailyGoal(_ value: Int) -> Bool {
        guard FocusPreferences.dailyGoalRange.contains(value) else { return false }
        preferences.dailyGoal = value; schedulePersistence(); return true
    }
    @discardableResult func setStopwatchMode(_ enabled: Bool) -> Bool {
        preferences.stopwatchMode = enabled; schedulePersistence(); return true
    }
    @discardableResult func setBell(_ value: String) -> Bool {
        let bell = FocusBell.resolve(value); preferences.bellID = bell.identifier; preferences.bellSound = bell.rawValue
        schedulePersistence(); notifier?.preview(bell: bell.soundName); return true
    }
    private func updateSettings() { engine.apply(preferences.pomodoroSettings); schedulePersistence() }

    // MARK: Presets
    func showPresetLibrary() {
        workspacePage = .library; contentRoute = .automatic
    }
    func showLibraryOverview() {
        browsedPresetID = nil; showPresetLibrary()
    }
    func showTimerWorkspace() {
        workspacePage = .timer; contentRoute = .automatic
    }
    func selectPresetForDetails(_ id: UUID) {
        guard let preset = timers.first(where: { $0.id == id }) else { return }
        presetLibrarySection = preset.archivedAt == nil ? .active : .archived
        browsedPresetID = id; showPresetLibrary()
    }
    func closePresetDetails() { browsedPresetID = nil }
    func setPresetLibrarySection(_ section: FocusPresetLibrarySection) {
        presetLibrarySection = section
        if let id = browsedPresetID, let preset = timers.first(where: { $0.id == id }),
           (preset.archivedAt == nil) != (section == .active) { browsedPresetID = nil }
    }
    @discardableResult
    func startTimerPreset(_ id: UUID) -> Bool {
        guard canStartTimerPreset, let preset = activeTimers.first(where: { $0.id == id }) else { return false }
        engine.apply(preferences.pomodoroSettings)
        notifier?.requestAuthorizationIfNeeded()
        guard engine.start(taskID: preset.taskID, focusMinutes: preset.stopwatch ? nil : preset.minutes,
                           stopwatch: preset.stopwatch, presetID: preset.id) else { return false }
        let preparedNote = completionContext == nil ? currentSessionNote : ""
        completionContext = nil; currentSessionNote = preparedNote
        browsedPresetID = id; showTimerWorkspace()
        sync(); startTimer(); schedulePersistence()
        if let taskID = preset.taskID { onTaskFocusStarted?(taskID, preset.stopwatch) }
        return true
    }
    @discardableResult
    func addTimer(name: String, emoji: String, stopwatch: Bool, minutes: Int, taskID: UUID? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, stopwatch || PomodoroSettings.focusRange.contains(minutes), activeTimers.count < 12 else { return false }
        timers.append(TimerPreset(id: UUID(), emoji: emoji, name: name, stopwatch: stopwatch,
            minutes: stopwatch ? 0 : minutes, taskID: taskID, sortOrder: timers.count))
        schedulePersistence(); return true
    }
    @discardableResult
    func updateTimer(_ preset: TimerPreset) -> Bool {
        guard let index = timers.firstIndex(where: { $0.id == preset.id }),
              !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              preset.stopwatch || PomodoroSettings.focusRange.contains(preset.minutes) else { return false }
        timers[index] = preset; schedulePersistence(); return true
    }
    func archiveTimer(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].archivedAt = clock(); if selectedPresetID == id { selectedPresetID = nil }
        if browsedPresetID == id { browsedPresetID = nil }
        schedulePersistence()
    }
    @discardableResult
    func restoreTimer(_ id: UUID) -> Bool {
        guard activeTimers.count < 12, let i = timers.firstIndex(where: { $0.id == id && $0.archivedAt != nil }) else { return false }
        timers[i].archivedAt = nil
        if browsedPresetID == id && presetLibrarySection == .archived { browsedPresetID = nil }
        schedulePersistence(); return true
    }
    func deleteTimer(_ id: UUID) {
        timers.removeAll { $0.id == id }; if selectedPresetID == id { selectedPresetID = nil }
        if browsedPresetID == id { browsedPresetID = nil }
        schedulePersistence()
    }
    func applyTimerPreset(_ preset: TimerPreset) {
        selectedPresetID = preset.id; preferences.lastTaskID = preset.taskID
        preferences.stopwatchMode = preset.stopwatch
        if !preset.stopwatch { preferences.focusMinutes = preset.minutes }
        updateSettings()
    }

    // MARK: History and edits
    func record(id: UUID) -> PomodoroRecord? { read(fallback: nil) { try persistence.record(id: id) } }
    func recordsForTask(_ taskID: UUID) -> [PomodoroRecord] {
        read(fallback: []) { try persistence.history(taskID: taskID, limit: Int.max) }
    }
    /// The summary only hydrates records in its date range. An aggregate query
    /// supplies lifetime activity for status without reading the whole history.
    func summarySnapshot(in range: SummaryDateRange) -> (records: [PomodoroRecord], startedTaskIDs: Set<UUID>) {
        let totals: [(UUID?, Int)] = read(fallback: []) { try persistence.taskTotals(from: .distantPast, limit: Int.max) }
        return (filteredRecords(FocusRecordFilter(from: range.start, to: range.end)),
                Set(totals.filter { $0.1 > 0 }.compactMap { $0.0 }))
    }
    func taskTotalActiveSeconds(taskID: UUID) -> Int {
        read(fallback: SQLiteRecordStore<PomodoroRecord, Archive>.Totals()) { try persistence.totals(taskID: taskID) }.value
    }
    func taskTotalPomodoros(taskID: UUID) -> Int {
        read(fallback: SQLiteRecordStore<PomodoroRecord, Archive>.Totals()) { try persistence.totals(taskID: taskID) }.count
    }
    func showRecords(taskID: UUID? = nil, presetID: UUID? = nil) {
        recordFilter = FocusRecordFilter(taskID: taskID, presetID: presetID); contentRoute = .records
        historyRevision += 1
    }
    func showStatistics() { contentRoute = .statistics }
    func showOverview() { contentRoute = .automatic; recordFilter = FocusRecordFilter(); historyRevision += 1 }
    func setRecordFilter(_ filter: FocusRecordFilter) { recordFilter = filter; historyRevision += 1 }
    func filteredRecords(_ filter: FocusRecordFilter? = nil) -> [PomodoroRecord] {
        let filter = filter ?? recordFilter
        return read(fallback: []) { try persistence.history(taskID: filter.taskID, from: filter.from, to: filter.to, limit: Int.max) }
            .filter { matches($0, filter: filter) }
    }
    func filteredStatistics(_ filter: FocusRecordFilter? = nil) -> FilteredStats {
        filteredRecords(filter).reduce(into: FilteredStats()) {
            $0.seconds += $1.activeSeconds; $0.pomodoros += $1.creditedPomodoros; $0.records += 1
        }
    }
    /// 常用项详情始终按全库 presetID 查询；概览的分页、任务筛选不会截断详情数据。
    func presetStatistics(presetID: UUID, period: FocusPresetStatisticsPeriod = .week,
                          anchor: Date? = nil) -> FocusPresetStatistics {
        let all = filteredRecords(FocusRecordFilter(presetID: presetID))
        let today = calendar.startOfDay(for: clock())
        let interval = calendar.dateInterval(of: period.calendarComponent, for: anchor ?? clock())
            ?? DateInterval(start: today, duration: 86_400)
        let grouped = Dictionary(grouping: all, by: { calendar.startOfDay(for: $0.startedAt) })
        var days: [FocusPresetDayTotal] = []
        var day = interval.start
        while day < interval.end {
            days.append(FocusPresetDayTotal(day: day,
                activeSeconds: grouped[day, default: []].reduce(0) { $0 + $1.activeSeconds }))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let records = all.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt > $1.startedAt }
        return FocusPresetStatistics(focusDays: grouped.values.filter { $0.contains { $0.activeSeconds > 0 } }.count,
            todayActiveSeconds: grouped[today, default: []].reduce(0) { $0 + $1.activeSeconds },
            totalActiveSeconds: all.reduce(0) { $0 + $1.activeSeconds },
            periodActiveSeconds: records.reduce(0) { $0 + $1.activeSeconds }, periodInterval: interval,
            days: days, records: records)
    }
    private func matches(_ record: PomodoroRecord, filter: FocusRecordFilter) -> Bool {
        (filter.mode == nil || filter.mode == record.mode)
            && (filter.source == nil || filter.source == record.source)
            && (filter.presetID == nil || filter.presetID == record.details?.presetID)
            && (filter.associated == nil || filter.associated == (record.taskID != nil))
            && (filter.from == nil || record.startedAt >= filter.from!)
            && (filter.to == nil || record.startedAt < filter.to!)
    }
    /// 旧分钟入口也复用完整编辑草稿，结束时间必须已经发生。
    @discardableResult
    func addRecord(taskID: UUID?, startedAt: Date, minutes: Int) -> Bool {
        guard minutes > 0, startedAt < clock() else { return false }
        var draft = FocusRecordDraft(now: clock(), taskID: taskID)
        draft.creditedPomodoros = 1 // 原分钟API保留其一次补记的兼容语义。
        draft.startedAt = startedAt; draft.endedAt = startedAt.addingTimeInterval(TimeInterval(minutes * 60))
        return saveRecordDraft(draft)
    }
    @discardableResult
    func saveRecordDraft(_ draft: FocusRecordDraft) -> Bool {
        if draft.preservesLegacyTiming, var old = record(id: draft.id), old.details == nil {
            guard draft.durationMinutes > 0, draft.startedAt <= clock() else { return false }
            old.taskID = draft.taskID; old.startedAt = draft.startedAt
            old.note = trimmedNote(draft.note); old.minutes = draft.durationMinutes
            replace(old); return true
        }
        guard draft.mode != .legacy, draft.creditedPomodoros >= 0, draft.startedAt < draft.endedAt, draft.endedAt <= clock() else { return false }
        let old = draft.isNew ? nil : record(id: draft.id)
        guard draft.isNew || old != nil else { return false }
        let pauses = old?.details?.pauseRanges.compactMap { range -> FocusPauseRange? in
            let start = max(range.startedAt, draft.startedAt); let end = min(range.endedAt, draft.endedAt)
            return start < end ? FocusPauseRange(startedAt: start, endedAt: end) : nil
        } ?? []
        let paused = pauses.reduce(0) { $0 + $1.seconds }
        let unchangedInterval = old?.startedAt == draft.startedAt && old?.endedAt == draft.endedAt
        let seconds = unchangedInterval ? (old?.activeSeconds ?? 0)
            : max(0, Int(draft.endedAt.timeIntervalSince(draft.startedAt)) - paused)
        guard seconds > 0 else { return false }
        let termination = old?.details?.termination ?? .manualEntry
        let details = FocusRecordDetails(mode: draft.mode, source: old?.details?.source ?? .manual,
            termination: termination, endedAt: draft.endedAt, activeSeconds: seconds, pausedSeconds: paused,
            pauseRanges: pauses, targetSeconds: old?.details?.targetSeconds, presetID: old?.details?.presetID ?? draft.presetID,
            creditedPomodoros: draft.mode == .pomodoro ? draft.creditedPomodoros : 0,
            accountingPolicyVersion: FocusAccountingPolicy.version, precision: .second,
            durationCorrectionSeconds: unchangedInterval ? old?.details?.durationCorrectionSeconds : nil)
        let value = PomodoroRecord(id: draft.id, taskID: draft.taskID, startedAt: draft.startedAt,
            minutes: FocusAccountingPolicy.displayedMinutes(seconds: seconds), completed: termination != .abandoned,
            note: trimmedNote(draft.note), details: details)
        if draft.isNew { accept(value) } else { replace(value) }
        return true
    }
    @discardableResult
    func saveRecordDurationDraft(_ draft: FocusRecordDurationDraft) -> Bool {
        guard draft.minutes > 0 else { return false }
        guard draft.hasChanges else { return record(id: draft.recordID) != nil }
        return correctRecordDuration(draft.recordID, seconds: draft.minutes * 60,
                                     alignsEndWithDuration: draft.alignsEndWithDuration)
    }
    @discardableResult
    func correctRecordDuration(_ id: UUID, seconds: Int, alignsEndWithDuration: Bool = false) -> Bool {
        guard seconds > 0, var value = record(id: id) else { return false }
        if var details = value.details {
            if alignsEndWithDuration {
                let end = value.startedAt.addingTimeInterval(TimeInterval(seconds))
                details.endedAt = end
                details.pauseRanges = details.pauseRanges.compactMap { range in
                    let pauseEnd = min(range.endedAt, end)
                    return range.startedAt < pauseEnd ? FocusPauseRange(startedAt: range.startedAt, endedAt: pauseEnd) : nil
                }
                details.pausedSeconds = details.pauseRanges.reduce(0) { $0 + $1.seconds }
                details.durationCorrectionSeconds = details.pausedSeconds == 0 ? nil : details.pausedSeconds
            } else {
                details.durationCorrectionSeconds = seconds - details.activeSeconds
            }
            details.activeSeconds = seconds; value.details = details
        }
        value.minutes = FocusAccountingPolicy.displayedMinutes(seconds: seconds); replace(value); return true
    }
    func deleteRecord(_ id: UUID) {
        guard let value = record(id: id) else { return }
        refreshDailyStats(); updateTotals(value, direction: -1); visibleRecords.removeAll { $0.id == id }
        if completionContext?.recordID == id { completionContext = nil }
        invalidateHistory(); persistence.schedule(deleted: [id], metadata: archive())
    }
    private func replace(_ value: PomodoroRecord) {
        let isCompleted = completionContext?.recordID == value.id
        guard let old = (isCompleted ? completionRecordCache : nil) ?? record(id: value.id) else { return }
        if isCompleted {
            completionRecordCache = value
            if completedSessionNote != (value.note ?? "") { completedSessionNote = value.note ?? "" }
            completionContext?.recordActiveSeconds = value.activeSeconds
        }
        refreshDailyStats(); updateTotals(old, direction: -1); updateTotals(value, direction: 1)
        visibleRecords.removeAll { $0.id == value.id }; visibleRecords.append(value)
        sortVisibleRecords(); invalidateHistory(); persistence.schedule(upserts: [value], metadata: archive())
    }
    func resetHistory() async {
        historyGeneration += 1; visibleRecords = []; historyOffset = 0; historyLoading = false
        historyHasMore = recordCount > 0; historyError = nil; await loadMoreHistory()
    }
    private var historyOffset = 0
    func loadMoreHistory() async {
        guard !historyLoading, historyHasMore else { return }
        let request = historyGeneration; historyLoading = true; historyError = nil
        do {
            let page = try await persistence.historyAsync(taskIDs: recordFilter.taskID.map { [$0] },
                limit: historyPageSize + 1, offset: historyOffset)
            guard request == historyGeneration, !_Concurrency.Task.isCancelled else { return }
            visibleRecords.append(contentsOf: page.prefix(historyPageSize).filter { matches($0, filter: recordFilter) })
            historyOffset += min(historyPageSize, page.count)
            historyHasMore = page.count > historyPageSize; historyLoading = false
        } catch {
            guard request == historyGeneration, !_Concurrency.Task.isCancelled else { return }
            historyError = error.localizedDescription; historyLoading = false
        }
    }
    func recentDailyStats(days: Int = 7) -> [DailyFocusStats] {
        let today = calendar.startOfDay(for: clock())
        return (0..<max(0, days)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let totals = read(fallback: SQLiteRecordStore<PomodoroRecord, Archive>.Totals()) { try persistence.totals(from: day, to: end) }
            return DailyFocusStats(dayKey: dayKey(day), day: day,
                minutes: FocusAccountingPolicy.aggregatedMinutes(seconds: totals.value), pomodoros: totals.count)
        }
    }
    func weeklyTaskTotals(days: Int = 7, limit: Int = 3) -> [TaskFocusTotal] {
        let cutoff = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: clock())) ?? clock()
        return read(fallback: []) { try persistence.taskTotals(from: cutoff, limit: limit) }
            .map { TaskFocusTotal(taskID: $0.0, minutes: FocusAccountingPolicy.aggregatedMinutes(seconds: $0.1)) }
    }
    var recordGroups: [RecordDayGroup] {
        var groups: [RecordDayGroup] = []
        for value in visibleRecords {
            let key = dayKey(value.startedAt)
            if groups.last?.dayKey == key { groups[groups.count - 1].records.append(value) }
            else { groups.append(RecordDayGroup(dayKey: key, day: calendar.startOfDay(for: value.startedAt), records: [value])) }
        }
        return groups
    }
    func flush(_ completion: @escaping (Error?) -> Void) { persistence.flush(completion) }
    private func trimmedNote(_ value: String?) -> String? {
        let note = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return note?.isEmpty == false ? note : nil
    }
    @discardableResult private func insert(_ value: PomodoroRecord, sessionNote: String? = nil) -> PomodoroRecord {
        var value = value; value.note = trimmedNote(sessionNote); accept(value); return value
    }
    private func accept(_ value: PomodoroRecord) {
        refreshDailyStats(); updateTotals(value, direction: 1); visibleRecords.insert(value, at: 0)
        sortVisibleRecords(); invalidateHistory(); persistence.schedule(upserts: [value], metadata: archive())
    }
    private func sortVisibleRecords() {
        visibleRecords.sort { $0.startedAt > $1.startedAt }; visibleRecords = Array(visibleRecords.prefix(historyPageSize))
    }
    private func invalidateHistory() {
        historyGeneration += 1; historyRevision += 1; historyHasMore = recordCount > visibleRecords.count
    }
    private func updateTotals(_ value: PomodoroRecord, direction: Int) {
        allTimeActiveSeconds += direction * value.activeSeconds
        allTimeMinutes = FocusAccountingPolicy.aggregatedMinutes(seconds: allTimeActiveSeconds)
        allTimePomodoros += direction * value.creditedPomodoros; recordCount += direction
        if dayKey(value.startedAt) == statsDay {
            todayActiveSeconds += direction * value.activeSeconds
            todayMinutes = FocusAccountingPolicy.aggregatedMinutes(seconds: todayActiveSeconds)
            todayPomodoros += direction * value.creditedPomodoros
        }
    }
    private func sync() {
        let changed = phase != engine.phase
        if phase != engine.phase { phase = engine.phase }
        if isLongBreak != engine.isLongBreak { isLongBreak = engine.isLongBreak }
        if currentTaskID != engine.currentTaskID { currentTaskID = engine.currentTaskID }
        if phaseSeconds != engine.phaseSeconds { phaseSeconds = engine.phaseSeconds }
        if remainingSeconds != engine.remainingSeconds { remainingSeconds = engine.remainingSeconds }
        if elapsedSeconds != engine.elapsedSeconds { elapsedSeconds = engine.elapsedSeconds }
        if currentMode != engine.currentMode { currentMode = engine.currentMode }
        if pendingBreak != engine.pendingBreak { pendingBreak = engine.pendingBreak }
        if engine.phase != .focusing && engine.phase != .pausedFocus && pendingEndConfirmation != nil {
            pendingEndConfirmation = nil
        }
        if hasExtraTimeClock { objectWillChange.send() }
        refreshDailyStats()
        if changed || ((engine.phase != .idle || hasExtraTimeClock) && clock().timeIntervalSince(lastSessionSave) > 5) {
            lastSessionSave = clock(); schedulePersistence()
        }
    }
    private func refreshDailyStats() {
        let key = dayKey(clock()); guard statsDay != key else { return }
        let day = calendar.startOfDay(for: clock()); let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        do {
            let totals = try persistence.totals(from: day, to: end)
            todayActiveSeconds = totals.value; todayMinutes = FocusAccountingPolicy.aggregatedMinutes(seconds: totals.value)
            todayPomodoros = totals.count; statsDay = key
        } catch { historyError = error.localizedDescription }
    }
    private func read<T>(fallback: T, _ operation: () throws -> T) -> T {
        do { return try operation() } catch { historyError = error.localizedDescription; return fallback }
    }
    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func archive() -> Archive {
        Archive(preferences: preferences, session: engine.sessionSnapshot, timers: timers,
            sessionNote: currentSessionNote.isEmpty ? nil : currentSessionNote,
            sessionV2: engine.sessionSnapshot, completionContext: completionContext,
            cycleProgress: engine.cycleProgress, selectedPresetID: selectedPresetID)
    }
    private func schedulePersistence() { persistence.schedule(metadata: archive()) }
    private func startTimer() {
        guard timer == nil else { return }
        let scheduled = Timer(timeInterval: 1, repeats: true) { [weak self] value in
            guard let self else { value.invalidate(); return }; MainActor.assumeIsolated { self.refresh() }
        }
        RunLoop.main.add(scheduled, forMode: .common); timer = scheduled
    }
    private func stopTimerIfNeeded() {
        guard engine.phase == .idle, !hasExtraTimeClock, let timer else { return }; timer.invalidate(); self.timer = nil
    }
}

extension FocusStore.Archive {
    private enum CodingKeys: String, CodingKey {
        case records, preferences, session, timers, sessionNote, sessionV2, completionContext, cycleProgress, selectedPresetID
    }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([PomodoroRecord].self, forKey: .records) ?? []
        preferences = try c.decodeIfPresent(FocusPreferences.self, forKey: .preferences) ?? FocusPreferences()
        session = try c.decodeIfPresent(FocusSessionSnapshot.self, forKey: .session)
        timers = try c.decodeIfPresent([FocusStore.TimerPreset].self, forKey: .timers) ?? []
        sessionNote = try c.decodeIfPresent(String.self, forKey: .sessionNote)
        sessionV2 = try c.decodeIfPresent(FocusSessionSnapshot.self, forKey: .sessionV2)
        completionContext = try c.decodeIfPresent(FocusCompletionContext.self, forKey: .completionContext)
        cycleProgress = try c.decodeIfPresent(FocusCycleProgress.self, forKey: .cycleProgress)
        selectedPresetID = try c.decodeIfPresent(UUID.self, forKey: .selectedPresetID)
    }
}
