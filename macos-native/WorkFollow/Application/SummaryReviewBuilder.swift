import Foundation

/// One row of the weekly review: the optional date prefix (`[9月22日]`, empty
/// for undated entries such as uncompleted tasks), the task title and the
/// list name shown on the right.
struct ReviewItem: Equatable {
    let datePrefix: String
    let title: String
    let listName: String
}

/// Auto-generated review of one calendar week, mirroring TickTick's 摘要
/// document: a week-range title plus 已完成 / 已放弃 / 未完成 sections.
struct WeeklyReview: Equatable {
    /// Monday 00:00 of the reviewed week.
    let weekStart: Date
    /// Exclusive end of the week (the next Monday 00:00).
    let weekEnd: Date
    /// TickTick-style range copy, e.g. "9月21日-9月27日".
    let weekTitle: String
    let completed: [ReviewItem]
    let abandoned: [ReviewItem]
    let uncompleted: [ReviewItem]

    var isEmpty: Bool {
        completed.isEmpty && abandoned.isEmpty && uncompleted.isEmpty
    }
}

/// One row of the review picker in the left column: a week plus its completed
/// count. `isCurrent` marks the always-present current week.
struct WeeklyReviewSummary: Equatable {
    let weekStart: Date
    let weekTitle: String
    let completedCount: Int
    let isCurrent: Bool
}

/// Pure weekly-review generator for the summary module (concept realignment
/// with TickTick's 摘要). Clock and calendar are injected so callers (and
/// tests) stay deterministic.
///
/// 统计口径：
/// - 已删除（`deletedAt != nil`）与已跳过（`skippedAt != nil`）的任务永远不参与。
/// - 已完成：`status == .completed` 且 `completedAt` 落在本周区间
///   `[周一00:00, 下周一00:00)`，日期前缀取 `completedAt`。
/// - 已放弃：`status != .completed && isAbandoned` 且 `abandonedAt` 落在本周，
///   日期前缀取 `abandonedAt`。（若同一任务既完成又带 abandonedAt，按完成归类。）
/// - 未完成：当前仍 open（`!isClosed`）且 `schedule.dueAt` 落在本周；与滴答
///   一致，未完成条目不带日期前缀。
/// - 已关闭但缺少 `completedAt` / `abandonedAt` 的历史数据无法定位到某一周，
///   不参与任何一周的回顾。
/// - 周起点固定为周一 00:00（中文语境，对齐滴答摘要），不随系统 `firstWeekday`
///   浮动；组内条目按参考时间（completedAt / abandonedAt / dueAt）倒序，同时
///   间按标题升序保证结果稳定。
struct SummaryReviewBuilder {
    let clock: () -> Date
    let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Week boundaries

    /// Monday 00:00 of the week containing `date`, independent of the
    /// calendar's `firstWeekday` (周一固定为一周起点).
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    /// Exclusive end of the week starting at `weekStart` (next Monday 00:00).
    static func weekEnd(of weekStart: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart)!
    }

    /// "9月21日-9月27日" style range title; the end day is start + 6 days.
    static func weekTitle(for weekStart: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let startParts = calendar.dateComponents([.month, .day], from: weekStart)
        let endParts = calendar.dateComponents([.month, .day], from: end)
        return "\(startParts.month ?? 0)月\(startParts.day ?? 0)日-\(endParts.month ?? 0)月\(endParts.day ?? 0)日"
    }

    /// "[9月22日]" style date prefix used by review rows.
    static func datePrefix(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "[\(parts.month ?? 0)月\(parts.day ?? 0)日]"
    }

    // MARK: Review generation

    /// Builds the weekly review for the week containing `date`.
    func review(for tasks: [Task], weekOf date: Date) -> WeeklyReview {
        let start = Self.weekStart(of: date, calendar: calendar)
        let end = Self.weekEnd(of: start, calendar: calendar)
        let participants = tasks.filter { $0.deletedAt == nil && $0.skippedAt == nil }

        let completed = Self.reviewItems(
            from: participants.filter { $0.status == .completed },
            reference: \.completedAt, in: start..<end,
            calendar: calendar, showsDatePrefix: true)
        let abandoned = Self.reviewItems(
            from: participants.filter { $0.status != .completed && $0.isAbandoned },
            reference: \.abandonedAt, in: start..<end,
            calendar: calendar, showsDatePrefix: true)
        let uncompleted = Self.reviewItems(
            from: participants.filter { !$0.isClosed },
            reference: \.schedule.dueAt, in: start..<end,
            calendar: calendar, showsDatePrefix: false)

        return WeeklyReview(weekStart: start, weekEnd: end,
                            weekTitle: Self.weekTitle(for: start, calendar: calendar),
                            completed: completed, abandoned: abandoned, uncompleted: uncompleted)
    }

    /// Buckets dated tasks into weeks and returns the picker rows: the current
    /// week always comes first (even when empty), followed by at most
    /// `maximum - 1` earlier weeks that have any review content, newest first.
    func availableWeeks(for tasks: [Task], maximum: Int = 12) -> [WeeklyReviewSummary] {
        let currentStart = Self.weekStart(of: clock(), calendar: calendar)
        var buckets: [Date: (completed: Int, hasContent: Bool)] = [:]
        for task in tasks where task.deletedAt == nil && task.skippedAt == nil {
            let reference: Date?
            let countsAsCompleted: Bool
            if task.status == .completed {
                reference = task.completedAt
                countsAsCompleted = true
            } else if task.isAbandoned {
                reference = task.abandonedAt
                countsAsCompleted = false
            } else {
                reference = task.schedule.dueAt
                countsAsCompleted = false
            }
            guard let reference else { continue }
            let start = Self.weekStart(of: reference, calendar: calendar)
            var bucket = buckets[start] ?? (0, false)
            if countsAsCompleted { bucket.completed += 1 }
            bucket.hasContent = true
            buckets[start] = bucket
        }

        var summaries = [WeeklyReviewSummary(
            weekStart: currentStart,
            weekTitle: Self.weekTitle(for: currentStart, calendar: calendar),
            completedCount: buckets[currentStart]?.completed ?? 0,
            isCurrent: true)]
        let pastStarts = buckets.keys.filter { $0 < currentStart }.sorted(by: >)
        for start in pastStarts where summaries.count < max(maximum, 1) {
            guard let bucket = buckets[start], bucket.hasContent else { continue }
            summaries.append(WeeklyReviewSummary(
                weekStart: start,
                weekTitle: Self.weekTitle(for: start, calendar: calendar),
                completedCount: bucket.completed,
                isCurrent: false))
        }
        return summaries
    }

    /// Plain-text rendering of a review for the 复制 button: title, then one
    /// row per item with its list name, sections separated by blank lines.
    func plainText(for review: WeeklyReview) -> String {
        var lines: [String] = [review.weekTitle, ""]
        func appendSection(_ name: String, items: [ReviewItem], showsDatePrefix: Bool) {
            lines.append(name)
            for item in items {
                var line = ""
                if showsDatePrefix && !item.datePrefix.isEmpty { line += item.datePrefix + " " }
                line += "\(item.title)（\(item.listName)）"
                lines.append(line)
            }
            lines.append("")
        }
        appendSection("已完成", items: review.completed, showsDatePrefix: true)
        appendSection("已放弃", items: review.abandoned, showsDatePrefix: true)
        appendSection("未完成", items: review.uncompleted, showsDatePrefix: false)
        return lines.dropLast().joined(separator: "\n")
    }

    // MARK: Helpers

    /// Filters `tasks` whose `reference` date falls inside `range`, sorts them
    /// by that date descending (title ascending on ties) and maps them to rows.
    private static func reviewItems(from tasks: [Task], reference: (Task) -> Date?,
                                    in range: Range<Date>, calendar: Calendar,
                                    showsDatePrefix: Bool) -> [ReviewItem] {
        tasks.filter { task in
            guard let date = reference(task) else { return false }
            return range.contains(date)
        }
        .sorted { lhs, rhs in
            let lhsDate = reference(lhs) ?? .distantPast
            let rhsDate = reference(rhs) ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.title < rhs.title
        }
        .map { task in
            let prefix = reference(task).map { datePrefix($0, calendar: calendar) } ?? ""
            return ReviewItem(datePrefix: showsDatePrefix ? prefix : "",
                              title: task.title, listName: task.list.name)
        }
    }
}
