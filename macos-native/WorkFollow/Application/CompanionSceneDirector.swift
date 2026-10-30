import Combine
import Foundation

enum CompanionCharacter: String, CaseIterable, Identifiable {
    case cat
    case bunny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cat: return "猫猫"
        case .bunny: return "兔兔"
        }
    }
}

enum CompanionPhase: Equatable {
    case idle
    case happy
    case focus
    case sleep
    case celebrate
}

/// 小伙伴的场景只做轻反馈，不接管真实流程。
/// 真实事件映射：任务 revision → 新建/完成/高优先级/连续完成；
/// 笔记 revision → 写下第一笔、笔记与任务互相转换；
/// 启动与日切 → 逾期；FocusStore.phase → 专注/休息；MeetingStore.recordingID → 会议；
/// AIConversationModel.isRunning → AI 思考；Apple 同步状态 → 同步；本地时间 → 夜间。
enum CompanionScene: String, CaseIterable, Equatable {
    case taskCreated
    case taskCompleted
    case priorityRaised
    case noteWritten
    case noteConverted
    case overdue
    case aiThinking
    case meeting
    case meetingFinished
    case aiFinished
    case focus
    case breakTime
    case focusCompleted
    case sync
    case syncFinished
    case night
    case streak
    case postponed
    case pet

    var priority: Int {
        switch self {
        case .meeting: return 100
        case .focus, .breakTime: return 90
        case .aiThinking: return 80
        case .overdue: return 70
        case .focusCompleted: return 65
        case .streak: return 60
        case .priorityRaised: return 50
        case .meetingFinished: return 48
        case .noteConverted: return 47
        case .taskCreated: return 45
        case .aiFinished: return 44
        case .taskCompleted: return 43
        case .noteWritten: return 42
        case .pet: return 42
        case .postponed: return 41
        case .syncFinished: return 40
        case .sync: return 30
        case .night: return 10
        }
    }

    var isSticky: Bool {
        switch self {
        case .meeting, .focus, .breakTime, .aiThinking, .sync: return true
        default: return false
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .meeting, .focus, .breakTime, .aiThinking, .sync: return nil
        case .taskCreated, .priorityRaised, .noteWritten, .noteConverted: return 3.0
        case .taskCompleted, .postponed: return 2.4
        case .overdue: return 12.0
        case .meetingFinished: return 2.6
        case .focusCompleted: return 2.6
        case .syncFinished, .pet, .aiFinished: return 2.2
        case .night: return 6.0
        case .streak: return 3.2
        }
    }

    var cooldown: TimeInterval {
        switch self {
        case .taskCreated: return 20
        case .taskCompleted: return 1.2
        case .priorityRaised: return 30
        case .noteWritten, .noteConverted: return 20
        case .overdue: return 600
        case .meetingFinished, .syncFinished, .aiFinished: return 5
        case .focusCompleted: return 30
        case .streak: return 60
        case .postponed, .pet: return 1.5
        case .night: return 0
        case .meeting, .focus, .breakTime, .aiThinking, .sync: return 0
        }
    }

    var phase: CompanionPhase {
        switch self {
        case .meeting, .focus, .aiThinking: return .focus
        case .overdue, .sync: return .idle
        case .night: return .sleep
        case .focusCompleted, .streak: return .celebrate
        default: return .happy
        }
    }

    var prop: String? {
        switch self {
        case .taskCreated: return "✏️"
        case .taskCompleted: return "💛"
        case .priorityRaised: return "🚩"
        case .noteWritten: return "📝"
        case .noteConverted: return "📌"
        case .overdue: return "⏰"
        case .meeting: return "🎙️"
        case .meetingFinished: return "📝"
        case .aiFinished: return "💡"
        case .focus: return nil
        case .breakTime: return "☕"
        case .focusCompleted, .aiThinking: return "✨"
        case .sync: return "☁️"
        case .syncFinished: return "✅"
        case .night: return "🌙"
        case .streak: return "🔥"
        case .postponed: return "🌤️"
        case .pet: return "💗"
        }
    }
}

/// 任务 revision 的快照。只在状态真的跨过边界时发事件：
/// active → completed 才算完成，priority 从非高变高才算升级。
struct CompanionTaskState: Equatable {
    let id: UUID
    let title: String
    let status: TaskStatus
    let priority: TaskPriority
    let isNote: Bool
    let isDeleted: Bool
    let isConverted: Bool
    /// 笔记的“写下第一笔”：空浮窗草稿不算，标题或正文有内容才算真记下。
    let hasContent: Bool

    init(id: UUID = UUID(), title: String, status: TaskStatus = .active,
         priority: TaskPriority = .none, isNote: Bool = false,
         isDeleted: Bool = false, isConverted: Bool = false,
         hasContent: Bool = true) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.isNote = isNote
        self.isDeleted = isDeleted
        self.isConverted = isConverted
        self.hasContent = hasContent
    }
}

struct CompanionOverdueTask: Equatable {
    let id: UUID
    let title: String
    let delayText: String

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名任务" : title
    }
}

struct CompanionPresentation: Equatable, Identifiable {
    let id: UUID
    let scene: CompanionScene
    let message: String
    let actionTitle: String?
    let phase: CompanionPhase
    let prop: String?
    let isSticky: Bool
    let endsAt: Date?
}

/// 逾期任务顺延到明天的目标日期：全天任务落在明天零点；
/// 定时任务保留原时分，区间长度由 moveDueDate 自己平移。
enum CompanionOverduePlanner {
    static func tomorrow(for schedule: TaskSchedule, now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        guard schedule.hasTime, let due = schedule.dueAt else { return tomorrow }
        let components = calendar.dateComponents([.hour, .minute, .second], from: due)
        return calendar.date(bySettingHour: components.hour ?? 9,
                             minute: components.minute ?? 0,
                             second: components.second ?? 0,
                             of: tomorrow) ?? tomorrow
    }
}

@MainActor
final class CompanionSceneDirector: ObservableObject {
    @Published private(set) var presentation: CompanionPresentation?
    private(set) var isEnabled = false

    var overdueProvider: (() -> CompanionOverdueTask?)?
    var onPostponeOverdue: ((UUID) -> Bool)?

    private let now: () -> Date
    private let calendar: Calendar
    private var taskBaseline: [UUID: CompanionTaskState]?
    private var focusPhase: PomodoroPhase = .idle
    private var meetingActive = false
    private var aiActive = false
    private var syncActive = false
    private var completionTimes: [Date] = []
    private var lastPresentedAt: [CompanionScene: Date] = [:]
    private var currentOverdue: CompanionOverdueTask?
    private var handledOverdueIDs: Set<UUID> = []
    private var lastNightKey: Date?
    private var lastOverdueCheckAt: Date?
    private var bubbleHovered = false

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            if enabled { refreshSticky(now: now()) }
            return
        }
        isEnabled = enabled
        if enabled {
            refreshSticky(now: now())
            checkOverdue(force: true)
            tick()
        } else {
            presentation = nil
            currentOverdue = nil
            bubbleHovered = false
            completionTimes.removeAll()
        }
    }

    /// 每次 workspace.revision 变化时调用。第一次调用只记录基线，不发事件。
    func updateTaskSnapshot(_ states: [CompanionTaskState]) {
        let next = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        guard let baseline = taskBaseline else {
            taskBaseline = next
            return
        }
        taskBaseline = next
        guard isEnabled else { return }
        let moment = now()

        if let overdue = currentOverdue {
            let stillOpen = next[overdue.id].map {
                $0.status != .completed && !$0.isDeleted && !$0.isConverted
            } ?? false
            if !stillOpen {
                currentOverdue = nil
                if presentation?.scene == .overdue {
                    presentation = nil
                    refreshSticky(now: moment)
                }
            }
        }

        let completed = next.values.filter { task in
            guard let old = baseline[task.id], !task.isNote, !task.isDeleted, !task.isConverted else { return false }
            return old.status != .completed && task.status == .completed
        }
        let created = next.values.filter { task in
            guard baseline[task.id] == nil, !task.isNote, !task.isDeleted, !task.isConverted else { return false }
            return task.status == .active
        }
        let raised = next.values.filter { task in
            guard let old = baseline[task.id], !task.isNote, !task.isDeleted, !task.isConverted else { return false }
            return task.status == .active && old.priority != .high && task.priority == .high
        }
        // 浮窗会先建一条空笔记、关闭时再丢弃，所以“点新建”不吭声；
        // 标题或正文第一次有内容时才当作用户真的写下了东西。
        let writtenNotes = next.values.filter { task in
            guard task.isNote, !task.isDeleted, !task.isConverted, task.hasContent else { return false }
            guard let old = baseline[task.id] else { return true }
            return old.isNote && !old.hasContent
        }
        let notesFromTasks = next.values.filter { task in
            guard let old = baseline[task.id], !old.isNote, task.isNote,
                  !task.isDeleted, !task.isConverted else { return false }
            return true
        }
        let notesToTasks = next.values.filter { task in
            guard let old = baseline[task.id], old.isNote, !task.isNote,
                  !task.isDeleted, !task.isConverted else { return false }
            return task.status == .active
        }

        if !completed.isEmpty {
            handleCompletions(completed, now: moment)
        }
        if !writtenNotes.isEmpty || !notesFromTasks.isEmpty {
            presentNoteWritten(notes: writtenNotes + notesFromTasks,
                               converted: Set(notesFromTasks.map(\.id)), now: moment)
        }
        if !notesToTasks.isEmpty {
            let message: String
            if notesToTasks.count == 1, let task = notesToTasks.first {
                message = "「\(shortTitle(task.title, limit: 8))」变成待办了，我帮你盯住"
            } else {
                message = "\(notesToTasks.count) 条笔记变成待办了，我帮你盯住"
            }
            presentTransient(.noteConverted, message: message, now: moment)
        }
        if !created.isEmpty, created.count <= 2 {
            let message: String
            if created.count == 1, let task = created.first {
                message = "「\(shortTitle(task.title))」记下啦，慢慢来"
            } else {
                message = "两件都记下了，脑子留给手上的事"
            }
            presentTransient(.taskCreated, message: message, now: moment)
        }
        if !raised.isEmpty {
            let message: String
            if raised.count == 1, let task = raised.first {
                message = "「\(shortTitle(task.title))」最重要，我帮你盯住"
            } else {
                message = "高优先级标好了，我帮你盯住"
            }
            presentTransient(.priorityRaised, message: message, now: moment)
        }
    }

    private func handleCompletions(_ tasks: [CompanionTaskState], now moment: Date) {
        completionTimes.append(contentsOf: Array(repeating: moment, count: tasks.count))
        completionTimes.removeAll { moment.timeIntervalSince($0) > 600 }

        if tasks.count == 1 {
            let phrases = ["又清掉一件！", "干得漂亮", "离清空又近一步"]
            presentTransient(.taskCompleted, message: phrases.randomElement() ?? "又清掉一件！", now: moment)
        } else {
            presentTransient(.taskCompleted, message: "一次清掉 \(tasks.count) 件，漂亮", now: moment)
        }

        guard completionTimes.count >= 3 else { return }
        completionTimes.removeAll()
        presentTransient(.streak, message: "连续清掉 3 件，节奏正好！", now: moment)
    }

    func setFocusPhase(_ phase: PomodoroPhase) {
        guard phase != focusPhase else { return }
        focusPhase = phase
        refreshSticky(now: now())
    }

    func handleFocusCompleted() {
        focusPhase = .idle
        refreshSticky(now: now())
        presentTransient(.focusCompleted, message: "这一轮很稳，休息一下", now: now())
    }

    func setMeetingActive(_ active: Bool) {
        guard active != meetingActive else { return }
        meetingActive = active
        refreshSticky(now: now())
        if !active {
            presentTransient(.meetingFinished, message: "会议结束，我把要点记下", now: now())
        }
    }

    func setAIThinking(_ active: Bool) {
        guard active != aiActive else { return }
        aiActive = active
        refreshSticky(now: now())
        if !active {
            presentTransient(.aiFinished, message: "想好了，你看看", now: now())
        }
    }

    func setSyncActive(_ active: Bool) {
        guard active != syncActive else { return }
        syncActive = active
        refreshSticky(now: now())
        if !active {
            presentTransient(.syncFinished, message: "都对齐了，放心", now: now())
        }
    }

    func tick() {
        guard isEnabled else { return }
        let moment = now()
        if let current = presentation, !current.isSticky, let endsAt = current.endsAt, moment >= endsAt,
           !hoverHoldsBubble(past: endsAt, now: moment) {
            presentation = nil
            currentOverdue = nil
            refreshSticky(now: moment)
        }
        checkOverdue(force: false)
        checkNight(now: moment)
    }

    /// 鼠标停在气泡上时先不收回，否则短气泡的 × 还没点到就消失了。
    /// 最多多留 20 秒，免得指针一直压着，气泡把后来的短事件全挡住。
    private func hoverHoldsBubble(past endsAt: Date, now moment: Date) -> Bool {
        bubbleHovered && moment.timeIntervalSince(endsAt) < 20
    }

    func setBubbleHovered(_ hovered: Bool) {
        bubbleHovered = hovered
    }

    func checkOverdue(force: Bool) {
        guard isEnabled, let provider = overdueProvider else { return }
        let moment = now()
        if !force, let last = lastOverdueCheckAt, moment.timeIntervalSince(last) < 120 { return }
        lastOverdueCheckAt = moment
        guard let task = provider(), !handledOverdueIDs.contains(task.id) else { return }
        // 带操作按钮的气泡固定一行：标题压到 6 个字，延迟只取最大单位
        // （2天3小时 → 2天），完整信息仍可在任务列表里看到。
        let title = shortTitle(task.displayTitle, limit: 6)
        let delay = compactDelay(task.delayText)
        let message = delay.isEmpty ? "「\(title)」逾期了" : "「\(title)」逾期\(delay)"
        guard presentTransient(.overdue, message: message, actionTitle: "顺延到明天", now: moment) else { return }
        currentOverdue = task
        handledOverdueIDs.insert(task.id)
    }

    func postponeOverdueTask() {
        guard isEnabled, let task = currentOverdue, let action = onPostponeOverdue else { return }
        guard action(task.id) else { return }
        currentOverdue = nil
        presentation = nil
        refreshSticky(now: now())
        presentTransient(.postponed, message: "挪到明天了，今天轻一点", now: now())
    }

    /// 点气泡上的 ×：只收起当前这条，不改变场景状态。
    /// 冷却从收起时重新计时，过一段时间同一件事还能再提醒；
    /// 逾期提醒要放回待处理集合，否则收起后它就再也不会出现了。
    func dismissPresentation() {
        guard isEnabled, let current = presentation, !current.isSticky else { return }
        let moment = now()
        presentation = nil
        bubbleHovered = false
        if current.scene == .overdue {
            if let overdue = currentOverdue {
                handledOverdueIDs.remove(overdue.id)
            }
            currentOverdue = nil
        }
        lastPresentedAt[current.scene] = moment
        refreshSticky(now: moment)
    }

    /// 摸一下是用户主动发起的，专注/会议里也该有回应：允许暂时盖住
    /// 常驻场景，气泡结束后 refreshSticky 会把耳机/麦克风状态接回来。
    /// 但正在提醒逾期时不能被摸掉，免得顺延按钮消失。
    func pet() {
        guard isEnabled else { return }
        if let current = presentation, !current.isSticky,
           current.scene.priority > CompanionScene.pet.priority {
            return
        }
        let moment = now()
        let phrases = ["我在呢", "今天也辛苦啦", "记得喝水", "慢慢来，不着急", "再摸一下嘛"]
        lastPresentedAt[.pet] = moment
        presentation = CompanionPresentation(
            id: UUID(),
            scene: .pet,
            message: phrases.randomElement() ?? "我在呢",
            actionTitle: nil,
            phase: CompanionScene.pet.phase,
            prop: CompanionScene.pet.prop,
            isSticky: false,
            endsAt: moment.addingTimeInterval(CompanionScene.pet.duration ?? 2.2))
    }

    @discardableResult
    private func presentTransient(_ scene: CompanionScene, message: String,
                                  actionTitle: String? = nil, now moment: Date) -> Bool {
        guard isEnabled else { return false }
        if let current = presentation {
            if current.scene == scene { return false }
            if current.scene.priority > scene.priority { return false }
            if current.isSticky && current.scene.priority >= scene.priority { return false }
        }
        if let last = lastPresentedAt[scene], moment.timeIntervalSince(last) < scene.cooldown {
            return false
        }
        lastPresentedAt[scene] = moment
        presentation = CompanionPresentation(
            id: UUID(),
            scene: scene,
            message: message,
            actionTitle: actionTitle,
            phase: scene.phase,
            prop: scene.prop,
            isSticky: false,
            endsAt: scene.duration.map { moment.addingTimeInterval($0) }
        )
        return true
    }

    private func refreshSticky(now moment: Date) {
        guard isEnabled else { return }
        if let current = presentation, !current.isSticky, let endsAt = current.endsAt, moment >= endsAt {
            presentation = nil
        }
        guard let sticky = stickyPresentation() else {
            if presentation?.isSticky == true { presentation = nil }
            return
        }
        if let current = presentation {
            if current.isSticky {
                if current.scene == sticky.scene,
                   current.message == sticky.message,
                   current.phase == sticky.phase {
                    return
                }
            } else if current.scene.priority >= sticky.scene.priority,
                      let endsAt = current.endsAt, moment < endsAt {
                return
            }
        }
        presentation = sticky
    }

    private func stickyPresentation() -> CompanionPresentation? {
        let scene: CompanionScene
        let message: String
        if meetingActive {
            scene = .meeting
            message = "我安静听着，先不打扰你"
        } else {
            switch focusPhase {
            case .focusing:
                scene = .focus
                message = "我陪你，先做最重要的那一件"
            case .pausedFocus:
                scene = .focus
                message = "暂停一下，我等你"
            case .breaking:
                scene = .breakTime
                message = "休息一下，站起来伸个懒腰"
            case .pausedBreak:
                scene = .breakTime
                message = "休息暂停，我等你"
            case .idle:
                if aiActive {
                    scene = .aiThinking
                    message = "我陪你一起想"
                } else if syncActive {
                    scene = .sync
                    message = "同步一下，马上就好"
                } else {
                    return nil
                }
            }
        }
        return CompanionPresentation(
            id: UUID(),
            scene: scene,
            message: message,
            actionTitle: nil,
            phase: scene.phase,
            prop: scene.prop,
            isSticky: true,
            endsAt: nil
        )
    }

    private func checkNight(now moment: Date) {
        guard isEnabled, presentation == nil else { return }
        let components = calendar.dateComponents([.hour, .minute], from: moment)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let isNight = minutes >= 22 * 60 + 30 || minutes < 5 * 60
        guard isNight else { return }
        let day = calendar.startOfDay(for: moment)
        let key: Date
        if minutes < 5 * 60 {
            key = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        } else {
            key = day
        }
        guard lastNightKey != key else { return }
        if presentTransient(.night, message: "夜深了，我陪你收个尾", now: moment) {
            lastNightKey = key
        }
    }

    private func shortTitle(_ title: String, limit: Int = 18) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未命名任务" }
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }

    /// 笔记允许无标题：没有标题时文案不引用标题，不硬造“未命名”。
    private func shortNoteTitle(_ title: String, limit: Int = 8) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }

    private func presentNoteWritten(notes: [CompanionTaskState], converted: Set<UUID>,
                                    now moment: Date) {
        let message: String
        if notes.count == 1, let note = notes.first {
            let fromTask = converted.contains(note.id)
            if let title = shortNoteTitle(note.title) {
                message = fromTask ? "「\(title)」整理成笔记了" : "「\(title)」记下了，慢慢写"
            } else {
                message = fromTask ? "整理成笔记了" : "新笔记记下了，慢慢写"
            }
        } else if notes.count > 1 {
            message = notes.allSatisfy { converted.contains($0.id) }
                ? "\(notes.count) 个任务整理成了笔记"
                : "记下 \(notes.count) 条笔记，脑子清爽了"
        } else {
            return
        }
        presentTransient(.noteWritten, message: message, now: moment)
    }

    /// 只保留延迟的最大单位，气泡一行放得下；任务列表仍有完整时长。
    private func compactDelay(_ text: String) -> String {
        for unit in ["天", "小时", "分钟"] {
            if let range = text.range(of: unit) {
                return String(text[..<range.upperBound])
            }
        }
        return text
    }
}
