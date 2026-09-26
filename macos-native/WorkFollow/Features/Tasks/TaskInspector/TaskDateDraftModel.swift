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

    @Published var tab: Tab
    @Published var displayedMonth: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var periodStart: Date?
    @Published private(set) var periodEnd: Date?
    @Published private(set) var hasTime: Bool
    @Published private(set) var reminderOption: ReminderOption
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
        let deadlineAt = task.schedule.deadlineAt
        let anchor = (deadline ? deadlineAt : due) ?? today

        _selectedDate = Published(initialValue: anchor)
        _periodStart = Published(initialValue: due)
        _periodEnd = Published(initialValue: deadlineAt)
        _tab = Published(initialValue: !deadline && due != nil && deadlineAt != nil ? .period : .date)
        _displayedMonth = Published(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor)
        _hasTime = Published(initialValue: !deadline && task.schedule.hasTime)

        if let reminderAt = task.reminderAt {
            _customReminder = Published(initialValue: reminderAt)
            let base = Self.reminderBase(for: due, hasTime: task.schedule.hasTime, calendar: calendar)
            let preset = base.flatMap { base in Self.presetOffsets.first { base.addingTimeInterval($0.offset) == reminderAt }?.option }
            _reminderOption = Published(initialValue: preset ?? .custom)
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

    func chooseReminderOption(_ value: ReminderOption) {
        reminderOption = value
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
                              frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
        }
        switch tab {
        case .date:
            schedule.dueAt = hasTime ? selectedDate : calendar.startOfDay(for: selectedDate)
            schedule.hasTime = hasTime
        case .period:
            schedule.dueAt = periodStart.map { hasTime ? $0 : calendar.startOfDay(for: $0) }
            schedule.hasTime = periodStart != nil && hasTime
            schedule.deadlineAt = periodEnd.map { calendar.startOfDay(for: $0) }
        }
        if recurrenceTouched {
            return CommitPlan(schedule: schedule, reminder: reminderValue,
                              frequency: frequency, recurrenceRule: builtRule)
        }
        return CommitPlan(schedule: schedule, reminder: reminderValue,
                          frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
    }

    /// 清除 semantics: deadline mode drops only the deadline; the date tab
    /// matches clearScheduledProperties (due, time, reminder, recurrence — the
    /// deadline stays); the period tab drops the whole range as well.
    func clearPlan(for current: Task) -> CommitPlan {
        var schedule = current.schedule
        if deadline {
            schedule.deadlineAt = nil
            return CommitPlan(schedule: schedule, reminder: current.reminderAt,
                              frequency: current.recurrence, recurrenceRule: current.recurrenceRule)
        }
        schedule.dueAt = nil
        schedule.hasTime = false
        if tab == .period { schedule.deadlineAt = nil }
        return CommitPlan(schedule: schedule, reminder: nil, frequency: .never, recurrenceRule: nil)
    }

    private var builtRule: RecurrenceRule? {
        guard frequency != .never else { return nil }
        return RecurrenceRule(
            interval: max(1, interval),
            endDate: ending == .untilDate ? calendar.startOfDay(for: repeatEndDate) : nil,
            remainingCount: ending == .count ? max(1, repeatCount) : nil,
            monthDay: monthDay, weekday: weekday, month: month)
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
