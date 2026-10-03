import Combine
import Foundation

/// Draft state and interaction rules for TaskDatePopoverV2. Pure logic: it
/// never touches the task store; `commitPlan`/`clearPlan` produce the values
/// the view writes through TaskWorkspaceModel after re-reading the current
/// task, so an open popover cannot overwrite concurrent edits.
final class TaskDateDraftModel: ObservableObject {
    enum Tab: Equatable {
        case date, period
    }

    /// Reminder anchored to the due moment; `.custom` keeps an absolute date.
    enum ReminderOption: Equatable {
        case none, onTime, minutes5, minutes15, minutes30, hour1, day1, custom
    }

    enum Ending: Equatable {
        case never, untilDate, count
    }

    /// 面板产出的写入载荷 = application 层的 `SchedulePlan`。
    /// 定义只有一处（`Application/Schedule/SchedulePlan.swift`），宿主不再各自拆字段。
    typealias CommitPlan = SchedulePlan

    static let presetOffsets: [(option: ReminderOption, offset: TimeInterval, title: String)] = [
        (.onTime, 0, "准时"),
        (.minutes5, -5 * 60, "提前5分钟"),
        (.minutes15, -15 * 60, "提前15分钟"),
        (.minutes30, -30 * 60, "提前30分钟"),
        (.hour1, -60 * 60, "提前1小时"),
        (.day1, -24 * 60 * 60, "提前1天"),
    ]
    /// Flutter panel parity: the reminder row multi-selects these offsets
    /// (minutes relative to the anchor; 0 = on time, negative = early).
    static let offsetChoices = [0, -5, -30, -60, -1440]

    static func offsetTitle(_ minutes: Int) -> String {
        guard minutes != 0 else { return "准时" }
        let value = abs(minutes)
        if value % 1440 == 0 { return "提前\(value / 1440)天" }
        if value % 60 == 0 { return "提前\(value / 60)小时" }
        return "提前\(value)分钟"
    }

    @Published var tab: Tab
    @Published var displayedMonth: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var periodStart: Date?
    @Published private(set) var periodEnd: Date?
    @Published private(set) var hasTime: Bool
    @Published private(set) var reminderOption: ReminderOption
    /// Multi-select reminder offsets (Flutter panel parity); non-empty takes
    /// precedence over the legacy single `reminderOption`.
    @Published private(set) var reminderOffsets: Set<Int>
    @Published private(set) var customReminder: Date
    @Published private(set) var frequency: TaskRepeat
    @Published private(set) var interval: Int
    @Published private(set) var weekday: Int
    @Published private(set) var monthDay: Int
    @Published private(set) var month: Int
    @Published private(set) var ending: Ending
    @Published private(set) var repeatCount: Int
    @Published private(set) var repeatEndDate: Date
    private(set) var recurrenceTouched = false

    let calendar: Calendar
    let deadline: Bool
    private let now: () -> Date

    init(task: Task, calendar: Calendar, now: @escaping () -> Date, deadline: Bool) {
        self.calendar = calendar
        self.now = now
        self.deadline = deadline
        let today = calendar.startOfDay(for: now())
        let due = task.schedule.dueAt
        let dueEnd = task.schedule.dueEndAt
        let deadlineAt = task.schedule.deadlineAt
        let anchor = (deadline ? deadlineAt : due) ?? today

        _selectedDate = Published(initialValue: anchor)
        _periodStart = Published(initialValue: due)
        // 时间段的结束是 `dueEndAt`（安排结束），不是 `deadlineAt`（截止日期）。
        // 两者在 Flutter 里是两个字段：前者定义区间，后者只是截止点。
        _periodEnd = Published(initialValue: dueEnd)
        _tab = Published(initialValue: !deadline && due != nil && dueEnd != nil ? .period : .date)
        _displayedMonth = Published(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor)
        _hasTime = Published(initialValue: !deadline && task.schedule.hasTime)

        let storedOffsets = Set(task.reminderOffsets ?? [])
        _reminderOffsets = Published(initialValue: storedOffsets)
        if let reminderAt = task.reminderAt {
            _customReminder = Published(initialValue: reminderAt)
            let base = ScheduleSemantics.anchor(due: due, hasTime: task.schedule.hasTime, calendar: calendar)
            let preset = base.flatMap { base in Self.presetOffsets.first { base.addingTimeInterval($0.offset) == reminderAt }?.option }
            // With multi-offsets stored, the row shows the offsets and the
            // legacy single option stays out of the way.
            _reminderOption = Published(initialValue: storedOffsets.isEmpty ? (preset ?? .custom) : .none)
        } else {
            _customReminder = Published(initialValue: now().addingTimeInterval(3600))
            _reminderOption = Published(initialValue: .none)
        }

        let rule = task.recurrenceRule
        _frequency = Published(initialValue: task.recurrence)
        _interval = Published(initialValue: rule?.interval ?? 1)
        _weekday = Published(initialValue: rule?.weekday ?? calendar.component(.weekday, from: due ?? now()))
        _monthDay = Published(initialValue: rule?.monthDay ?? calendar.component(.day, from: due ?? now()))
        _month = Published(initialValue: rule?.month ?? calendar.component(.month, from: due ?? now()))
        _ending = Published(initialValue: rule?.endDate != nil ? .untilDate : rule?.remainingCount != nil ? .count : .never)
        _repeatCount = Published(initialValue: rule?.remainingCount ?? 10)
        _repeatEndDate = Published(initialValue: rule?.endDate ?? calendar.date(byAdding: .day, value: 30, to: today) ?? today)
    }

    // MARK: Selection

    func select(_ day: Date) {
        let day = calendar.startOfDay(for: day)
        displayedMonth = day
        if deadline || tab == .date {
            selectedDate = TaskDateDraft.movingDay(selectedDate, to: day, calendar: calendar)
        } else if let start = periodStart, periodEnd == nil, day > start {
            periodEnd = day
        } else {
            periodStart = day
            periodEnd = nil
        }
    }

    func quick(_ offset: Int) {
        select(dateFromToday(offset))
    }

    /// 今晚 shortcut: today at 20:00, timed (Flutter's tonight quick action).
    func selectTonight() {
        let today = dateFromToday(0)
        select(today)
        setHasTime(true)
        if let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today) {
            setStartTime(evening)
        }
    }

    /// Next Saturday, or today when today is Saturday.
    func nextWeekend() -> Date {
        let today = dateFromToday(0)
        let delta = (7 - calendar.component(.weekday, from: today)) % 7
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }

    func selectWeekend() {
        select(nextWeekend())
    }

    func dateFromToday(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now())) ?? now()
    }

    func setTab(_ newTab: Tab) {
        guard !deadline, newTab != tab else { return }
        tab = newTab
        if newTab == .period {
            // The date tab owns the start day: carry it over on every switch,
            // keeping the range start's time of day.
            periodStart = TaskDateDraft.movingDay(periodStart ?? selectedDate,
                                                  to: calendar.startOfDay(for: selectedDate), calendar: calendar)
            if let start = periodStart, let end = periodEnd, end < start { periodEnd = nil }
            displayedMonth = calendar.startOfDay(for: periodStart ?? selectedDate)
        } else {
            if let start = periodStart {
                selectedDate = TaskDateDraft.movingDay(selectedDate, to: calendar.startOfDay(for: start), calendar: calendar)
            }
            displayedMonth = calendar.startOfDay(for: selectedDate)
        }
    }

    // MARK: Time

    /// 开始时间的编辑锚点：时间段取区间开始，日期取选中日。
    var startTimeAnchor: Date? {
        tab == .period ? periodStart : selectedDate
    }

    /// 结束时间的编辑锚点：区间结束。还没有结束日时落在区间开始那天，
    /// 让半小时列表与行内输入框都有可锚定的日子（Flutter 的 `end` 恒有值，
    /// 默认取开始 +1 小时；这里取开始那天，语义等价）。
    var endTimeAnchor: Date? {
        guard tab == .period, !deadline else { return nil }
        return periodEnd ?? periodStart
    }

    /// 结束时间是否已生效：时间段 + 定时 + 已选结束日。
    /// 全天区间没有「结束时间」可言（Flutter: `timed ? '结束 …' : '结束时间'`）。
    var hasEndTime: Bool {
        tab == .period && hasTime && periodEnd != nil
    }

    /// 开关「定时」。只有**全天 → 定时**这一次跃迁才补一个 09:00 起点。
    ///
    /// 为什么必须限定在跃迁上：Flutter 的 09:00 来自 `initState`
    /// （`time = timed ? TimeOfDay.fromDateTime(initial) : TimeOfDay(hour: 9)`），
    /// 那是**初值**，不是每次置位都发生的改写；`editTime` 里更是只写 `isEnd`
    /// 指定的那一个字段（`if (isEnd) endTime = …; else time = …;`），另一个字段
    /// 一个字节都不碰。如果这里不判跃迁，「已定时、开始时间 00:00」的任务点一次
    /// 结束时间，开始时间就会被悄悄改成 09:00 —— 用户没碰它，它却变了。
    func setHasTime(_ on: Bool) {
        let wasOn = hasTime
        hasTime = on
        // Enabling time on an all-day draft would confirm as 00:00; default to 9:00.
        guard on, !wasOn, let anchor = startTimeAnchor,
              calendar.component(.hour, from: anchor) == 0,
              calendar.component(.minute, from: anchor) == 0 else { return }
        setStartTime(ScheduleSemantics.allDayAnchor(on: anchor, calendar: calendar) ?? anchor)
    }

    /// 改开始时间：只动区间开始（日期页签则动选中日），结束时间不受影响。
    func setStartTime(_ value: Date) {
        if tab == .period {
            if let start = periodStart {
                periodStart = Self.replacingTime(of: start, with: value, calendar: calendar)
            } else {
                periodStart = value
                displayedMonth = calendar.startOfDay(for: value)
            }
        } else {
            selectedDate = Self.replacingTime(of: selectedDate, with: value, calendar: calendar)
        }
    }

    /// 改结束时间：只动区间结束，开始时间与截止日期都不受影响。
    /// 还没有结束日时把结束落到开始那天（单日定时区间）。
    func setEndTime(_ value: Date) {
        guard tab == .period, !deadline else { return }
        let day = calendar.startOfDay(for: periodEnd ?? periodStart ?? value)
        periodEnd = Self.replacingTime(of: day, with: value, calendar: calendar)
    }

    /// 清掉区间结束（回到「继续点选结束日期」）。开始时间与截止日期不动。
    func clearEndTime() {
        guard tab == .period, !deadline else { return }
        periodEnd = nil
    }

    // MARK: Reminder

    /// Whether the reminder row shows an active value (offsets or legacy).
    var hasReminderDraft: Bool {
        !reminderOffsets.isEmpty || reminderOption != .none
    }

    /// Ascending (earliest-first) draft offsets in minutes.
    var reminderOffsetsDraft: [Int] {
        reminderOffsets.sorted()
    }

    func chooseReminderOption(_ value: ReminderOption) {
        reminderOption = value
        // A single absolute/preset reminder replaces any offset selection.
        if value != .none { reminderOffsets.removeAll() }
    }

    /// Row-level 清除: drops both the offsets and the legacy option.
    func clearReminder() {
        reminderOffsets.removeAll()
        reminderOption = .none
    }

    /// Toggles one preset offset; the first selection takes over the row.
    func toggleReminderOffset(_ minutes: Int) {
        if !reminderOffsets.insert(minutes).inserted { reminderOffsets.remove(minutes) }
        if !reminderOffsets.isEmpty { reminderOption = .none }
    }

    /// 自定义提前量: a positive amount in minutes becomes a negative offset.
    func addCustomReminderOffset(minutes: Int) {
        guard minutes > 0 else { return }
        reminderOffsets.insert(-minutes)
        reminderOption = .none
    }

    func chooseCustomReminder(_ value: Date) {
        customReminder = value
    }

    /// The due moment presets anchor to; nil when no start day is drafted yet.
    var dueAnchor: Date? {
        guard !deadline else { return nil }
        guard let raw = startTimeAnchor else { return nil }
        return ScheduleSemantics.anchor(due: raw, hasTime: hasTime, calendar: calendar)
    }

    func reminderDate(for option: ReminderOption) -> Date? {
        switch option {
        case .none: return nil
        case .custom: return customReminder
        default:
            guard let base = ScheduleSemantics.anchor(due: startTimeAnchor, hasTime: hasTime, calendar: calendar) else { return customReminder }
            let offset = Self.presetOffsets.first { $0.option == option }?.offset ?? 0
            return base.addingTimeInterval(offset)
        }
    }

    var reminderValue: Date? {
        reminderDate(for: reminderOption)
    }

    /// 重复规则锚定的日期：时间段取开始日，否则取选中日（面板以它生成周/月/年
    /// 规则与行文案）。
    var recurrenceAnchorDate: Date {
        startTimeAnchor ?? selectedDate
    }

    /// 子面板“确定”时批量替换提醒偏移（取消即不调用，语义同 Flutter 子菜单）。
    func setReminderOffsets(_ minutes: Set<Int>) {
        reminderOffsets = minutes
        reminderOption = .none
    }

    /// 把周/月/年规则里的星期、日、月同步到锚定日（Flutter 选择日期时同步）。
    func syncRecurrenceAnchor() {
        let day = recurrenceAnchorDate
        weekday = calendar.component(.weekday, from: day)
        monthDay = calendar.component(.day, from: day)
        month = calendar.component(.month, from: day)
        recurrenceTouched = true
    }

    // MARK: Recurrence

    func chooseFrequency(_ value: TaskRepeat) {
        frequency = value
        recurrenceTouched = true
    }

    func chooseInterval(_ value: Int) { interval = value; recurrenceTouched = true }
    func chooseWeekday(_ value: Int) { weekday = value; recurrenceTouched = true }
    func chooseMonthDay(_ value: Int) { monthDay = value; recurrenceTouched = true }
    func chooseMonth(_ value: Int) { month = value; recurrenceTouched = true }
    func chooseEnding(_ value: Ending) { ending = value; recurrenceTouched = true }
    func chooseRepeatCount(_ value: Int) { repeatCount = value; recurrenceTouched = true }
    func chooseRepeatEndDate(_ value: Date) { repeatEndDate = value; recurrenceTouched = true }

    // MARK: Effective range

    /// 生效的区间起点 —— 与 `commitPlan` 共用**同一处**映射，校验与提交不会
    /// 各写一套而漂移（上一版 dueEndAt 掉时间，正是提交处单独写了一份）。
    var effectiveStart: Date? {
        guard !deadline else { return nil }
        switch tab {
        case .date:
            return ScheduleSemantics.normalized(selectedDate, hasTime: hasTime, calendar: calendar)
        case .period:
            return ScheduleSemantics.normalized(periodStart, hasTime: hasTime, calendar: calendar)
        }
    }

    /// 生效的区间终点。只有时间段页签有区间；日期页签**恒为 nil** ——
    /// 这就是「切回日期必须清掉旧 dueEndAt」的判据。
    /// 定时区间保留结束的时分（`dueEndAt` 不再被压成 startOfDay）。
    var effectiveEnd: Date? {
        guard !deadline, tab == .period else { return nil }
        return periodEnd.map { hasTime ? $0 : calendar.startOfDay(for: $0) }
    }

    /// 结束早于开始 → 禁止确认。判据在 `ScheduleSemantics.rangeError`（单一来源）。
    var rangeError: String? {
        ScheduleSemantics.rangeError(start: effectiveStart, end: effectiveEnd)
    }

    var canCommit: Bool { rangeError == nil }

    // MARK: Commit

    func commitPlan(for current: Task) -> CommitPlan {
        var schedule = current.schedule
        if deadline {
            schedule.deadlineAt = calendar.startOfDay(for: selectedDate)
            return CommitPlan(schedule: schedule, reminder: current.reminderAt,
                              reminderOffsets: current.reminderOffsets ?? [],
                              frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
        }
        // 三个字段各归各的：dueAt（开始）/ dueEndAt（区间结束）/ deadlineAt（截止）。
        // deadlineAt 在上面 deadline 分支之外**从不**被这段逻辑碰到。
        schedule.dueAt = effectiveStart
        schedule.hasTime = tab == .period ? (periodStart != nil && hasTime) : hasTime
        schedule.dueEndAt = effectiveEnd
        // Offsets need a schedulable anchor; without a due they clear (Flutter
        // parity), and the legacy single reminder then applies again.
        var offsets = reminderOffsetsDraft
        if schedule.dueAt == nil { offsets = [] }
        let reminder: Date?
        if offsets.isEmpty {
            reminder = reminderValue
        } else if let base = ScheduleSemantics.anchor(due: schedule.dueAt, hasTime: schedule.hasTime, calendar: calendar) {
            // The stored reminderAt mirrors the earliest fire date, matching
            // what Flutter persists alongside its offsets.
            reminder = base.addingTimeInterval(TimeInterval(offsets.first ?? 0) * 60)
        } else {
            reminder = nil
        }
        if recurrenceTouched {
            return CommitPlan(schedule: schedule, reminder: reminder, reminderOffsets: offsets,
                              frequency: frequency, recurrenceRule: builtRule)
        }
        return CommitPlan(schedule: schedule, reminder: reminder, reminderOffsets: offsets,
                          frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
    }

    /// 清除 semantics: deadline mode drops only the deadline; otherwise the
    /// whole 安排 goes — start, time, range end, reminder and recurrence. The
    /// 截止日期 stays: it is a separate field, and the panel's 清除 button is
    /// the same one on both tabs (Flutter pops an empty `TaskScheduleSettings`,
    /// which carries no deadline at all).
    func clearPlan(for current: Task) -> CommitPlan {
        var schedule = current.schedule
        if deadline {
            schedule.deadlineAt = nil
            return CommitPlan(schedule: schedule, reminder: current.reminderAt,
                              reminderOffsets: current.reminderOffsets ?? [],
                              frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
        }
        schedule.dueAt = nil
        schedule.hasTime = false
        schedule.dueEndAt = nil
        return CommitPlan(schedule: schedule, reminder: nil, reminderOffsets: [],
                          frequency: .never, recurrenceRule: nil)
    }

    /// The recurrence rule as currently drafted (used for previews and commit).
    var draftRule: RecurrenceRule? {
        guard frequency != .never else { return nil }
        return RecurrenceRule(
            interval: max(1, interval),
            endDate: ending == .untilDate ? calendar.startOfDay(for: repeatEndDate) : nil,
            remainingCount: ending == .count ? max(1, repeatCount) : nil,
            monthDay: monthDay, weekday: weekday, month: month)
    }

    private var builtRule: RecurrenceRule? {
        frequency == .never ? nil : draftRule?.normalized(calendar: calendar)
    }

    /// Future occurrence days for the calendar preview (pale accent discs),
    /// anchored on the drafted start day.
    func occurrencePreviewDays(limit: Int = 12) -> Set<Date> {
        guard let rule = draftRule else { return [] }
        let base = (tab == .period ? periodStart : selectedDate) ?? selectedDate
        return rule.occurrenceDays(after: base, frequency: frequency, calendar: calendar, limit: limit)
    }

    // MARK: Range

    var periodRange: ClosedRange<Date>? {
        guard let start = periodStart else { return nil }
        let end = periodEnd ?? start
        return min(start, end)...max(start, end)
    }

    // MARK: Helpers

    private static func replacingTime(of day: Date, with value: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = calendar.component(.hour, from: value)
        components.minute = calendar.component(.minute, from: value)
        return calendar.date(from: components) ?? day
    }
}
