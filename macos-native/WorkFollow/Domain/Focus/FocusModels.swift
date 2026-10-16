import Foundation

enum FocusMode: String, Codable, CaseIterable {
    case pomodoro, stopwatch, legacy
    var title: String {
        switch self { case .pomodoro: "番茄计时"; case .stopwatch: "正计时"; case .legacy: "历史专注" }
    }
}

enum FocusRecordSource: String, Codable { case timer, manual, legacy }
enum FocusTermination: String, Codable { case targetReached, manuallyEnded, abandoned, manualEntry, legacy }
enum FocusDurationPrecision: String, Codable { case second, legacyMinute }

struct FocusPauseRange: Codable, Equatable {
    var startedAt: Date
    var endedAt: Date
    var seconds: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }
}

struct FocusRecordDetails: Codable, Equatable {
    var mode: FocusMode
    var source: FocusRecordSource
    var termination: FocusTermination
    var endedAt: Date?
    var activeSeconds: Int
    var pausedSeconds: Int
    var pauseRanges: [FocusPauseRange]
    var targetSeconds: Int?
    var presetID: UUID?
    var creditedPomodoros: Int
    var accountingPolicyVersion: Int
    var precision: FocusDurationPrecision
    var durationCorrectionSeconds: Int? = nil
}

struct PomodoroRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var taskID: UUID?
    var startedAt: Date
    var minutes: Int
    var completed: Bool
    var note: String? = nil
    var details: FocusRecordDetails? = nil

    var mode: FocusMode { details?.mode ?? .legacy }
    var source: FocusRecordSource { details?.source ?? .legacy }
    var activeSeconds: Int { max(0, details?.activeSeconds ?? minutes * 60) }
    var creditedPomodoros: Int { details?.creditedPomodoros ?? (completed ? 1 : 0) }
    var endedAt: Date? { details?.endedAt }
}

/// 本项目当前计数口径集中在这里。已实测有效 15 秒结束不保存、320 秒确认保存计 1。
/// 原始秒数独立保留，显示分钟和统计分钟不改变原记录。
enum FocusAccountingPolicy {
    static let version = 1
    static let minimumAbandonedSeconds = 5 * 60
    static let minimumUserEndedPomodoroSeconds = 5 * 60
    /// 8.0.80 已实测 15 有效秒后「结束」丢弃；5 分钟分界暂沿用原最短记录门槛。
    /// 有效时长由引擎排除暂停，分界附近的客户端行为仍待补测。
    static func discardsUserEndedSession(mode: FocusMode, activeSeconds: Int) -> Bool {
        mode == .pomodoro && activeSeconds < minimumUserEndedPomodoroSeconds
    }
    static func creditedPomodoros(mode: FocusMode, termination: FocusTermination) -> Int {
        guard mode == .pomodoro else { return 0 }
        return termination == .abandoned || termination == .manualEntry ? 0 : 1
    }
    static func displayedMinutes(seconds: Int) -> Int { max(1, Int(ceil(Double(max(0, seconds)) / 60))) }
    static func aggregatedMinutes(seconds: Int) -> Int { max(0, seconds) / 60 }
}

struct FocusCompletionContext: Codable, Equatable {
    var recordID: UUID
    var completedAt: Date
    var extraTimeAnchor: Date
    var pendingExtraSeconds: Int? = nil
    var extraTimeStartedAt: Date? = nil
    var tracksPendingExtraTime: Bool? = nil
    var pendingExtraStartedAt: Date? = nil
    var extraTimeWasAppended: Bool? = nil
    var recordActiveSeconds: Int? = nil
}

struct FocusCycleProgress: Codable, Equatable {
    var completedFocusCount = 0
    var automaticCompletedCount = 0
}

enum FocusCommand: String, CaseIterable {
    case start, pause, resume, end, abandon, startBreak, skipBreak
    var title: String {
        switch self {
        case .start: "开始"; case .pause: "暂停"; case .resume: "继续"; case .end: "结束"
        case .abandon: "放弃专注"; case .startBreak: "开始休息"; case .skipBreak: "跳过休息"
        }
    }
}

struct FocusEndConfirmation: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let activeSeconds: Int
}

enum FocusEndConfirmationChoice { case save, discard, cancel }

/// 工作区导航是临时展示状态，不改变会话、预设来源或下次默认值。
enum FocusWorkspacePage: Equatable {
    case library, timer
}

enum FocusPresetLibrarySection: String, CaseIterable {
    case active, archived
    var title: String { self == .active ? "坚持中" : "已归档" }
}

enum FocusPresetStatisticsPeriod: String, CaseIterable {
    case week, month
    var title: String { self == .week ? "周" : "月" }
    var calendarComponent: Calendar.Component { self == .week ? .weekOfYear : .month }
}

struct FocusPresetDayTotal: Identifiable, Equatable {
    let day: Date
    let activeSeconds: Int
    var id: Date { day }
}

struct FocusPresetStatistics: Equatable {
    let focusDays: Int
    let todayActiveSeconds: Int
    let totalActiveSeconds: Int
    let periodActiveSeconds: Int
    let periodInterval: DateInterval
    let days: [FocusPresetDayTotal]
    let records: [PomodoroRecord]
}

struct FocusPresentation: Equatable {
    var mode: FocusMode
    var phase: PomodoroPhase
    var phaseTitle: String
    var displaySeconds: Int
    var elapsedSeconds: Int
    var targetSeconds: Int?
    var progress: Double
    var isPaused: Bool
    var taskID: UUID?
    var availableActions: [FocusCommand]
    var completion: FocusCompletionContext?
}

/// 编辑草稿只在确认后提交；旧记录起止未知时仅编辑已有分钟/任务/笔记。
struct FocusRecordDraft: Identifiable, Equatable {
    var id: UUID
    var isNew: Bool
    var taskID: UUID?
    var mode: FocusMode
    var startedAt: Date
    var endedAt: Date
    var note: String
    var durationMinutes: Int
    var preservesLegacyTiming: Bool
    var presetID: UUID? = nil
    var creditedPomodoros = 0

    init(record: PomodoroRecord) {
        id = record.id; isNew = false; taskID = record.taskID; mode = record.mode
        startedAt = record.startedAt
        endedAt = record.endedAt ?? record.startedAt.addingTimeInterval(TimeInterval(record.activeSeconds))
        note = record.note ?? ""; durationMinutes = record.minutes
        preservesLegacyTiming = record.details == nil; presetID = record.details?.presetID
        creditedPomodoros = record.creditedPomodoros
    }

    init(now: Date, taskID: UUID? = nil, mode: FocusMode = .pomodoro, presetID: UUID? = nil) {
        id = UUID(); isNew = true; self.taskID = taskID; self.mode = mode
        startedAt = now.addingTimeInterval(-25 * 60); endedAt = now
        note = ""; durationMinutes = 25; preservesLegacyTiming = false; self.presetID = presetID
    }
}

/// 分钟表单的显示值不等于原始精确秒数；未改动时不产生时长修正。
struct FocusRecordDurationDraft: Equatable {
    let recordID: UUID
    let originalMinutes: Int
    let alignsEndWithDuration: Bool
    var minutes: Int

    init(record: PomodoroRecord, displayedMinutes: Int? = nil, alignsEndWithDuration: Bool = false) {
        recordID = record.id
        originalMinutes = max(1, displayedMinutes ?? record.minutes)
        self.alignsEndWithDuration = alignsEndWithDuration
        minutes = originalMinutes
    }

    var hasChanges: Bool { minutes != originalMinutes }

    func previewEnd(startedAt: Date) -> Date {
        startedAt.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 已实测的番茄完成页从 5 分钟至本次已用整分钟；待追加时间只参与可选上限。
    static func completionMinuteRange(record: PomodoroRecord, pendingExtraSeconds: Int) -> ClosedRange<Int> {
        let minimum = record.mode == .pomodoro ? 5 : 1
        let elapsed = record.activeSeconds + max(0, pendingExtraSeconds)
        let maximum = record.mode == .pomodoro ? elapsed / 60 : FocusAccountingPolicy.displayedMinutes(seconds: elapsed)
        return minimum...max(minimum, maximum)
    }
}

struct FocusRecordFilter: Equatable {
    var taskID: UUID? = nil
    var mode: FocusMode? = nil
    var source: FocusRecordSource? = nil
    var from: Date? = nil
    var to: Date? = nil
    var presetID: UUID? = nil
    var associated: Bool? = nil
}
