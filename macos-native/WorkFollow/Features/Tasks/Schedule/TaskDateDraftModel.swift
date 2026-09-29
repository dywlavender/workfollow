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

    struct CommitPlan: Equatable {
        var schedule: TaskSchedule
        var reminder: Date?
        /// Ascending offsets in minutes (0 = on time, negative = early); an
        /// empty list clears stored offsets so the legacy reminder applies.
        var reminderOffsets: [Int]
        var frequency: TaskRepeat
        var recurrenceRule: RecurrenceRule?
    }

    static let presetOffsets: [(option: ReminderOption, offset: TimeInterval, title: String)] = [
        (.onTime, 0, "准时"),
        (.minutes5, -5 * 60, "提前5分钟"),
        (.minutes15, -15 * 60, "提前15分钟"),
        (.minutes30, -30 * 60, "提前30分钟"),
        (.hour1, -60 * 60, "提前1小时"),
        (.day1, -24 * 60 * 60, "提前1天"),
    ]
    /// All-day tasks anchor presets to this hour of the scheduled day.
    static let allDayAnchorHour = 9

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
            let base = Self.reminderBase(for: due, hasTime: task.schedule.hasTime, calendar: calendar)
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
            setTime(evening)
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

    /// The draft the time controls edit: range start in 时间段 mode.
    var timeAnchor: Date? {
        tab == .period ? periodStart : selectedDate
    }

    func setHasTime(_ on: Bool) {
        hasTime = on
        // Enabling time on an all-day draft would confirm as 00:00; default to 9:00.
        if on, let anchor = timeAnchor,
           calendar.component(.hour, from: anchor) == 0, calendar.component(.minute, from: anchor) == 0 {
            setTime(calendar.date(bySettingHour: Self.allDayAnchorHour, minute: 0, second: 0, of: anchor) ?? anchor)
        }
    }

    func setTime(_ value: Date) {
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
        let raw = tab == .period ? periodStart : selectedDate
        guard let raw else { return nil }
        return hasTime ? raw
            : calendar.date(bySettingHour: Self.allDayAnchorHour, minute: 0, second: 0, of: calendar.startOfDay(for: raw))
    }

    func reminderDate(for option: ReminderOption) -> Date? {
        switch option {
        case .none: return nil
        case .custom: return customReminder
        default:
            guard let base = Self.reminderBase(for: dueDraft, hasTime: hasTime, calendar: calendar) else { return customReminder }
            let offset = Self.presetOffsets.first { $0.option == option }?.offset ?? 0
            return base.addingTimeInterval(offset)
        }
    }

    var reminderValue: Date? {
        reminderDate(for: reminderOption)
    }

    private var dueDraft: Date? {
        tab == .period ? periodStart : selectedDate
    }

    private static func reminderBase(for due: Date?, hasTime: Bool, calendar: Calendar) -> Date? {
        guard let due else { return nil }
        return hasTime ? due
            : calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0, of: calendar.startOfDay(for: due))
    }

    /// 重复规则锚定的日期：时间段取开始日，否则取选中日（面板以它生成周/月/年
    /// 规则与行文案）。
    var recurrenceAnchorDate: Date {
        (tab == .period ? periodStart : nil) ?? selectedDate
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

    // MARK: Commit

    func commitPlan(for current: Task) -> CommitPlan {
        var schedule = current.schedule
        if deadline {
            schedule.deadlineAt = calendar.startOfDay(for: selectedDate)
            return CommitPlan(schedule: schedule, reminder: current.reminderAt,
                              reminderOffsets: current.reminderOffsets ?? [],
                              frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
        }
        switch tab {
        case .date:
            schedule.dueAt = hasTime ? selectedDate : calendar.startOfDay(for: selectedDate)
            schedule.hasTime = hasTime
        case .period:
            schedule.dueAt = periodStart.map { hasTime ? $0 : calendar.startOfDay(for: $0) }
            schedule.hasTime = periodStart != nil && hasTime
            schedule.dueEndAt = periodEnd.map { calendar.startOfDay(for: $0) }
        }
        // Offsets need a schedulable anchor; without a due they clear (Flutter
        // parity), and the legacy single reminder then applies again.
        var offsets = reminderOffsetsDraft
        if schedule.dueAt == nil { offsets = [] }
        let reminder: Date?
        if offsets.isEmpty {
            reminder = reminderValue
        } else if let base = Self.reminderBase(for: schedule.dueAt, hasTime: schedule.hasTime, calendar: calendar) {
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
