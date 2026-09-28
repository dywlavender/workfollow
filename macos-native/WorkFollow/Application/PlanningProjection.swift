import Foundation

/// 日历与四象限共用的纯投影。所有口径逐条对齐 Flutter：
/// `features/tasks/application/task_projection.dart`（日期格/周列的取数）、
/// `state/workspace_controller.dart`（四象限归类）、`widgets/calendar/calendar_spans.dart`
/// （跨天色带的区间定义）。
///
/// 这里是唯一决定「哪天有什么」的地方：视图不自己筛任务，也不自己算区间，
/// 否则同一条任务在月格、周列和四象限里会得出三个答案。
enum PlanningProjection {
    // MARK: - 四象限

    /// 重要 = 高/中优先级。低优先级不算重要，无优先级也不算——这是原版的表。
    static func isImportant(_ task: Task) -> Bool {
        task.priority == .high || task.priority == .medium
    }

    /// 紧急 = 有安排日且不晚于今天 +3 天（过期的也算）。截止日期不参与判定，
    /// 它只是截止点，不是安排。
    static func isUrgent(_ task: Task, now: Date, calendar: Calendar = .current) -> Bool {
        guard let dueAt = task.schedule.dueAt else { return false }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueAt)
        guard let horizon = calendar.date(byAdding: .day, value: 3, to: today) else { return false }
        return dueDay <= horizon
    }

    /// 0 = 重要且紧急，1 = 重要不紧急，2 = 不重要但紧急，3 = 不重要不紧急。
    static func quadrant(_ task: Task, now: Date, calendar: Calendar = .current) -> Int {
        let important = isImportant(task)
        let urgent = isUrgent(task, now: now, calendar: calendar)
        if important { return urgent ? 0 : 1 }
        return urgent ? 2 : 3
    }

    // MARK: - 日期格与周列

    /// 一条任务是否出现在日历上（对齐 Flutter `_appearsInDay`）：
    /// 已删除、已跳过、已转笔记、已放弃的任务不上日历，与列表口径一致。
    static func appearsOnCalendar(_ task: Task) -> Bool {
        task.deletedAt == nil && task.skippedAt == nil && !task.isConverted && !task.isAbandoned
    }

    /// 任务开始的那一天：`dueAt` 的日期部分。
    static func startDay(of task: Task, calendar: Calendar = .current) -> Date? {
        guard let dueAt = task.schedule.dueAt else { return nil }
        return calendar.startOfDay(for: dueAt)
    }

    /// 任务覆盖的最后一天。口径见 `spansMultipleDays`。
    static func endDay(of task: Task, calendar: Calendar = .current) -> Date? {
        guard let start = startDay(of: task, calendar: calendar) else { return nil }
        guard let dueEnd = task.schedule.dueEndAt else { return start }
        let endDay = calendar.startOfDay(for: dueEnd)
        return endDay > start ? endDay : start
    }

    /// 是否跨天。区间由两个日期「日」的部分是否不同来判定，不看时间：`dueEndAt`
    /// 掉在开始日当天时它是**收工时刻**（14:00 – 15:00），不是第二天。
    static func spansMultipleDays(_ task: Task, calendar: Calendar = .current) -> Bool {
        guard let start = startDay(of: task, calendar: calendar),
              let end = endDay(of: task, calendar: calendar) else { return false }
        return end > start
    }

    /// 月格 / 周列里属于某一天的任务：**开始于**这一天（含跨天任务的起始日）。
    /// 跨天任务同时由色带层绘制，所以格内取数再过滤一道见 `singleDayTasks`。
    ///
    /// 不排序——原版 `forDay` 保留任务库自身的次序，列表、看板、周视图都读同一
    /// 个次序；在这里按时间重排会让同一批任务在日历与列表里换位。
    static func tasks(on day: Date,
                      from tasks: [Task],
                      calendar: Calendar = .current) -> [Task] {
        let target = calendar.startOfDay(for: day)
        return tasks.filter { task in
            appearsOnCalendar(task) &&
                startDay(of: task, calendar: calendar) == target
        }
    }

    /// 月格里由本格自己画的任务：开始并结束在这里。跨天任务整个交给色带层，
    /// 在这里再出现一次就是同一天画两遍。
    static func singleDayTasks(on day: Date,
                               from tasks: [Task],
                               calendar: Calendar = .current) -> [Task] {
        PlanningProjection.tasks(on: day, from: tasks, calendar: calendar)
            .filter { !spansMultipleDays($0, calendar: calendar) }
    }

    /// 与 `first ... last` 有交集、且以 `first` 为起点时能排进这一行的跨天任务。
    /// 排序即摆位顺序：开始早的在前，同日开始时长的在前——五天的带子因此压在
    /// 两天的带子之上，而不是反过来（对齐 Flutter `multiDayWithin`）。
    static func multiDayTasks(from tasks: [Task],
                              first: Date,
                              last: Date,
                              calendar: Calendar = .current) -> [Task] {
        let low = calendar.startOfDay(for: first)
        let high = calendar.startOfDay(for: last)
        return tasks.filter { task in
            guard appearsOnCalendar(task),
                  spansMultipleDays(task, calendar: calendar),
                  let start = startDay(of: task, calendar: calendar),
                  let end = endDay(of: task, calendar: calendar) else { return false }
            return end >= low && start <= high
        }.sorted { lhs, rhs in
            let leftStart = startDay(of: lhs, calendar: calendar) ?? .distantPast
            let rightStart = startDay(of: rhs, calendar: calendar) ?? .distantPast
            if leftStart != rightStart { return leftStart < rightStart }
            let leftLength = (endDay(of: lhs, calendar: calendar) ?? leftStart).timeIntervalSince(leftStart)
            let rightLength = (endDay(of: rhs, calendar: calendar) ?? rightStart).timeIntervalSince(rightStart)
            if leftLength != rightLength { return leftLength > rightLength }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - 网格

    /// 本工程的一周从周日开始。原版把这件事写死在两处（月网格的 `weekday % 7`
    /// 与周视图的 `weekday % 7`），原生交给 `Calendar.firstWeekday`；注入系统的
    /// `.current` 会随地区换周首日，所以日历页统一用这一份，周列与日号偏移不会
    /// 各说各话。
    static func sundayFirstWeek(_ base: Calendar) -> Calendar {
        var value = base
        value.firstWeekday = 1
        return value
    }

    /// 月网格要画的日期：从该月第一天所在周的周首日算起，到本月最后一天所在
    /// 周的周末为止。行数由月份决定，不补齐六行——五周的月份就画五周，
    /// 补出来的空白行会把日期压扁（对齐 Flutter `CalendarMonthView`）。
    static func monthGridDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let leading = (calendar.component(.weekday, from: startOfMonth) - calendar.firstWeekday + 7) % 7
        let rows = Int(ceil(Double(leading + daysInMonth) / 7.0))
        guard let first = calendar.date(byAdding: .day, value: -leading, to: startOfMonth) else {
            return []
        }
        return (0..<(rows * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// 一周 7 天，周首日由 `calendar.firstWeekday` 决定（本工程为周日）。
    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 一周从 `anchor` 所在周的周首日开始。
    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        weekDays(containing: date, calendar: calendar).first ?? calendar.startOfDay(for: date)
    }
}
