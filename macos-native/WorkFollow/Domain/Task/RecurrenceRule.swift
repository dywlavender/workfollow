import Foundation

/// Optional alongside the original frequency, so existing preview JSON remains readable.
struct RecurrenceRule: Equatable, Codable {
    var interval: Int = 1
    var endDate: Date?
    /// Includes the current occurrence, matching Flutter's count contract.
    var remainingCount: Int?
    var monthDay: Int?
    /// Gregorian weekday 1=Sunday … 7=Saturday.
    var weekday: Int?
    var month: Int?
    /// 农历重复目标：月 1–12、日 1–30（每月最后一天按钳制取齐），
    /// 闰月显式标记。additive Codable：旧快照缺失时为 nil，按锚定日换算。
    var lunarMonth: Int?
    var lunarDay: Int?
    var lunarIsLeapMonth: Bool?
}

extension RecurrenceRule {
    /// The rule carried by the next occurrence: the count boundary is consumed
    /// by the occurrence that just completed (Flutter's followingConfig).
    var following: RecurrenceRule {
        var value = self
        value.remainingCount = remainingCount.map { max(0, $0 - 1) }
        return value
    }

    /// 艾宾浩斯记忆曲线间隔（天）。滴答 scratch 实测校正前用标准序列；
    /// 校正后只改这里（引擎与测试金标联动）。
    static let ebbinghausIntervals = [1, 2, 4, 7, 15, 30]

    /// Validates and repairs the rule; nil marks a structurally invalid rule
    /// (out-of-range weekday/month fields) that must not drive a recurrence —
    /// mirroring Flutter's RecurrenceDraft.normalized. A count below 1 is
    /// dropped (never-ending) rather than rejected, and endDate collapses to
    /// the start of its day so the whole day stays inside the boundary.
    func normalized(calendar: Calendar = .current) -> RecurrenceRule? {
        if let weekday, !(1...7).contains(weekday) { return nil }
        if let monthDay, !(1...31).contains(monthDay) { return nil }
        if let month, !(1...12).contains(month) { return nil }
        if let lunarMonth, !(1...12).contains(lunarMonth) { return nil }
        if let lunarDay, !(1...30).contains(lunarDay) { return nil }
        var value = self
        value.interval = max(1, interval)
        if let remainingCount, remainingCount < 1 { value.remainingCount = nil }
        value.endDate = endDate.map { calendar.startOfDay(for: $0) }
        return value
    }

    /// Next occurrence strictly after `after` (the current due moment), keeping
    /// the anchor's wall-clock time. Shifting child dates, deadlines and
    /// reminders deliberately lives in TaskActions. Years without an official
    /// holiday table degrade to the ordinary Monday–Friday calendar.
    func nextOccurrence(after base: Date?, frequency: TaskRepeat, calendar: Calendar) -> Date? {
        guard frequency != .never, let base else { return nil }
        guard remainingCount.map({ $0 > 1 }) ?? true else { return nil }
        let interval = max(1, self.interval)
        let time = calendar.dateComponents([.hour, .minute, .second], from: base)
        var next: Date?
        switch frequency {
        case .never:
            return nil
        case .daily:
            next = calendar.date(byAdding: .day, value: interval, to: base)
        case .weekly:
            let current = calendar.component(.weekday, from: base)
            let target = weekday ?? current
            let distance = (target - current + 7) % 7
            next = calendar.date(byAdding: .day, value: (distance == 0 ? 7 : distance) + 7 * (interval - 1), to: base)
        case .monthly, .yearly:
            // Advance from the first day, then clamp the original target day.
            // Jan 31 → Feb 28 → Mar 31, not Mar 28.
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
            let target = monthDay ?? parts.day ?? 1
            parts.day = 1
            if frequency == .yearly, let month { parts.month = min(12, max(1, month)) }
            if let first = calendar.date(from: parts),
               let anchor = calendar.date(byAdding: frequency == .yearly ? .year : .month, value: interval, to: first),
               let days = calendar.range(of: .day, in: .month, for: anchor) {
                next = calendar.date(byAdding: .day, value: min(max(1, target), days.count) - 1, to: anchor)
            }
        case .weekdays, .weekends, .workdays, .holidays:
            var candidate = base
            var remaining = interval
            while remaining > 0 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                if matches(candidate, frequency: frequency, calendar: calendar) { remaining -= 1 }
            }
            next = candidate
        case .lunarYearly:
            // 逐日扫描，用农历历匹配目标月/日。农历重复的钳制语义与公历
            // monthly/yearly 一致：目标日超过月长时取当月最后一天（三十在
            // 小月取廿九）。闰月策略：目标标了闰月只落在闰月 occurrence
            // （无闰月的年份跳过，不落到平月）；目标为平月则永不落闰月。
            var lunarCal = Calendar(identifier: .chinese)
            lunarCal.timeZone = calendar.timeZone
            let targetMonth = lunarMonth ?? lunarCal.component(.month, from: base)
            let targetDay = lunarDay ?? lunarCal.component(.day, from: base)
            let wantLeap = lunarIsLeapMonth ?? false
            var candidate = base
            var stepsLeft = interval
            // 农历十九年七闰，闰月最大间隔约三年；1500 天覆盖任意目标。
            for _ in 0..<1500 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                let comps = lunarCal.dateComponents([.month, .day], from: candidate)
                guard comps.month == targetMonth,
                      (comps.isLeapMonth == true) == wantLeap else { continue }
                let monthLength = lunarCal.range(of: .day, in: .month, for: candidate)?.count ?? 30
                guard comps.day == min(targetDay, monthLength) else { continue }
                stepsLeft -= 1
                if stepsLeft == 0 {
                    next = candidate
                    break
                }
            }
        case .lunarMonthly:
            // 农历每月：只按农历日推进，每个月（含闰月）的该日都算一次。
            var lunarCal = Calendar(identifier: .chinese)
            lunarCal.timeZone = calendar.timeZone
            let targetDay = lunarDay ?? lunarCal.component(.day, from: base)
            var candidate = base
            var stepsLeft = interval
            for _ in 0..<200 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                let comps = lunarCal.dateComponents([.month, .day], from: candidate)
                let monthLength = lunarCal.range(of: .day, in: .month, for: candidate)?.count ?? 30
                guard comps.day == min(targetDay, monthLength) else { continue }
                stepsLeft -= 1
                if stepsLeft == 0 {
                    next = candidate
                    break
                }
            }
        case .ebbinghaus:
            // 艾宾浩斯记忆法：完成后按记忆曲线间隔推进。interval 承载"已完成
            // 次数"（TaskActions.makeNextOccurrence 每次完成时递增），第 N 次
            // 完成取序列[N-1]；走完从头循环（滴答实测校正前先用标准曲线）。
            let intervals = Self.ebbinghausIntervals
            let step = (max(1, interval) - 1) % intervals.count
            next = calendar.date(byAdding: .day, value: intervals[step], to: base)
        }
        guard let next else { return nil }
        // Rules above only move the day; rebuild so the clock survives exactly.
        var shifted = calendar.dateComponents([.year, .month, .day], from: next)
        shifted.hour = time.hour
        shifted.minute = time.minute
        shifted.second = time.second
        let result = calendar.date(from: shifted) ?? next
        if let end = endDate, calendar.startOfDay(for: result) > calendar.startOfDay(for: end) { return nil }
        return result
    }

    /// Up to `limit` future occurrence days for calendar previews; the count
    /// boundary is consumed step by step, so count rules terminate early.
    func occurrenceDays(after base: Date, frequency: TaskRepeat, calendar: Calendar, limit: Int) -> Set<Date> {
        var rule = self
        var cursor = base
        var days: Set<Date> = []
        for _ in 0..<max(0, limit) {
            guard let next = rule.nextOccurrence(after: cursor, frequency: frequency, calendar: calendar) else { break }
            days.insert(calendar.startOfDay(for: next))
            rule = rule.following
            cursor = next
        }
        return days
    }

    private func matches(_ date: Date, frequency: TaskRepeat, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isWeekday = weekday != 1 && weekday != 7
        switch frequency {
        case .weekdays: return isWeekday
        case .weekends: return !isWeekday
        case .workdays: return ChineseWorkCalendar.isWorkday(date: date, calendar: calendar)
        case .holidays: return !ChineseWorkCalendar.isWorkday(date: date, calendar: calendar)
        default: return false
        }
    }
}

enum RecurrenceEngine {
    /// Task-level convenience kept for callers that hold a Task: resolves the
    /// rule (defaulting when unset) and anchors on the due moment, or on the
    /// start of `now` for undated tasks. Rule-level callers use
    /// `RecurrenceRule.nextOccurrence` directly.
    static func next(for task: Task, now: Date, calendar: Calendar) -> Date? {
        guard task.recurrence != .never else { return nil }
        let rule = task.recurrenceRule ?? RecurrenceRule()
        return rule.nextOccurrence(after: task.schedule.dueAt ?? calendar.startOfDay(for: now),
                                   frequency: task.recurrence, calendar: calendar)
    }
}
