import Foundation

/// 一条跨天色带：跨天任务裁剪到某个周行（7 天）后的一份。
///
/// 对齐打勾 calendar_spans.dart 的 CalendarSpan：同一任务跨出周行时，每周各画
/// 一份圆角色带——月网格里被周边界裁剪的一端取方角，读起来仍是同一条延续。
/// lane（槽位）按周行独立计算：周行是唯一需要内部一致的单位，中途进入本周
/// 的任务没有上一行可继承。
///
/// 字段口径：打勾的跨天区间来自任务的 dueEndAt（安排结束日）字段，原生 Task
/// 尚未迁移该字段，这里用「安排日 dueAt → 截止日 deadlineAt」构造区间，仅当
/// 截止日晚于安排日所在天时视为跨天。色带先服务"带截止日期的长任务"；将来
/// dueEndAt 迁移后只需改 CalendarSpans.spanRange(of:) 一处，全部视图自动受益。
struct CalendarSpanBar: Identifiable, Equatable {
    let task: Task
    /// 任务真实的首日与末日（未裁剪，取 startOfDay）。
    let startDay: Date
    let endDay: Date
    /// 本周行内覆盖的日下标（0...6，含首尾，已裁剪到周内）。
    let startDayIndex: Int
    let endDayIndex: Int
    /// 周行内分配到的槽位。lane 按行独立，行与行之间不继承。
    let laneIndex: Int
    /// 任务开始于本周之前：左端被裁剪（方角、非起始段）。
    let startClamped: Bool
    /// 任务结束于本周之后：右端被裁剪（方角、非收尾段）。
    let endClamped: Bool

    var id: UUID { task.id }

    /// 本周行内横跨的天数（含首尾）。
    var spanDays: Int { endDayIndex - startDayIndex + 1 }
    /// 左端压在周边界上（从上一周延续进来）。
    var continuesFromPreviousWeek: Bool { startClamped }
    /// 右端压在周边界上（延续进下一周）。
    var continuesIntoNextWeek: Bool { endClamped }
}

/// 月/周视图跨天色带的纯布局逻辑（对齐打勾 layOutWeekSpans / spanSlotsOver）。
/// 不做任务状态过滤——调用方传入的是视图已过滤的可见任务。
enum CalendarSpans {
    /// 是否渲染为跨天色带：有安排日、有截止日、且截止日晚于安排日所在天。
    /// 否则是单日任务，留在格内小条。
    static func isMultiDay(_ task: Task, calendar: Calendar) -> Bool {
        guard let dueAt = task.schedule.dueAt, let deadline = task.schedule.deadlineAt else { return false }
        return calendar.startOfDay(for: deadline) > calendar.startOfDay(for: dueAt)
    }

    /// 跨天区间（含首尾的自然日）；单日任务返回 nil。
    /// 跨天字段的唯一口径：见 CalendarSpanBar 头注释（dueEndAt 未迁移）。
    static func spanRange(of task: Task, calendar: Calendar) -> (start: Date, end: Date)? {
        guard isMultiDay(task, calendar: calendar),
              let dueAt = task.schedule.dueAt, let deadline = task.schedule.deadlineAt else { return nil }
        return (calendar.startOfDay(for: dueAt), calendar.startOfDay(for: deadline))
    }

    /// 一周 7 天的跨天色带 lane 布局。
    ///
    /// 与本周有交集的跨天任务各得一条色带，覆盖列取本周内的裁剪区间；列区间
    /// 重叠的任务叠进不同 lane。分配是贪心的：按「最早开始优先、同日开始更长
    /// 优先」排序后逐条放进第一个不冲突的 lane（打勾依赖投影预排序，原生调用
    /// 方不保证顺序，这里显式排序，id 兜底保证确定性）。返回按 lane、起始列
    /// 排序；`week` 不是 7 天时返回空。
    static func lanes(for week: [Date], tasks: [Task], calendar: Calendar) -> [CalendarSpanBar] {
        guard week.count == 7 else { return [] }
        let weekStart = calendar.startOfDay(for: week[0])

        // 相对周首日的整天偏移；负数 = 本周之前。Calendar 按自然日计数，
        // 窗口内的夏令时跳变不会把一天的间隔算成零。
        func offset(_ day: Date) -> Int {
            calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: day)).day ?? 0
        }

        struct Candidate {
            let task: Task
            let startDay: Date
            let endDay: Date
            let rawStart: Int
            let rawEnd: Int
            let fromColumn: Int
            let toColumn: Int
            let startClamped: Bool
            let endClamped: Bool
        }

        var candidates: [Candidate] = []
        for task in tasks {
            guard let range = spanRange(of: task, calendar: calendar) else { continue }
            let rawStart = offset(range.start)
            let rawEnd = offset(range.end)
            guard rawEnd >= 0, rawStart <= 6 else { continue }  // 与本周无交集
            candidates.append(Candidate(
                task: task, startDay: range.start, endDay: range.end,
                rawStart: rawStart, rawEnd: rawEnd,
                fromColumn: max(rawStart, 0), toColumn: min(rawEnd, 6),
                startClamped: rawStart < 0, endClamped: rawEnd > 6))
        }

        candidates.sort {
            if $0.rawStart != $1.rawStart { return $0.rawStart < $1.rawStart }
            if $0.rawEnd != $1.rawEnd { return $0.rawEnd > $1.rawEnd }
            return $0.task.id.uuidString < $1.task.id.uuidString
        }

        var occupied: [[ClosedRange<Int>]] = []
        var placed: [CalendarSpanBar] = []
        for candidate in candidates {
            let range = candidate.fromColumn...candidate.toColumn
            var lane = 0
            while lane < occupied.count,
                  occupied[lane].contains(where: { $0.overlaps(range) }) {
                lane += 1
            }
            if lane == occupied.count { occupied.append([]) }
            occupied[lane].append(range)
            placed.append(CalendarSpanBar(
                task: candidate.task, startDay: candidate.startDay, endDay: candidate.endDay,
                startDayIndex: candidate.fromColumn, endDayIndex: candidate.toColumn,
                laneIndex: lane,
                startClamped: candidate.startClamped, endClamped: candidate.endClamped))
        }

        return placed.sorted {
            $0.laneIndex != $1.laneIndex ? $0.laneIndex < $1.laneIndex : $0.startDayIndex < $1.startDayIndex
        }
    }

    /// `column` 这天的格内小条要给色带让出多少个槽位：取覆盖它的最高 lane + 1，
    /// 而不是色带条数——一行可以把 lane 0 和 2 分给经过某列的色带，把 lane 1
    /// 留给没到达这列的任务（对齐打勾 spanSlotsOver）。无覆盖时为 0。
    static func slotsOver(_ spans: [CalendarSpanBar], column: Int) -> Int {
        spans.reduce(0) { result, span in
            span.startDayIndex <= column && column <= span.endDayIndex
                ? max(result, span.laneIndex + 1) : result
        }
    }

    /// 拖动色带 = 平移整个区间，而不是只挪抓取的那天（对齐打勾）。
    ///
    /// 返回按「目标日 − 原安排日」的整天偏移平移后的 dueAt（保留原时点，交给
    /// moveDueDate 写回）与 deadlineAt（startOfDay）；区间长度不变。非跨天任务
    /// 返回 nil，走原有的单日改期路径。
    static func intervalShift(task: Task, to targetDay: Date,
                              calendar: Calendar) -> (dueAt: Date, deadlineAt: Date?)? {
        guard let dueAt = task.schedule.dueAt, let deadline = task.schedule.deadlineAt,
              isMultiDay(task, calendar: calendar) else { return nil }
        let offset = calendar.dateComponents([.day],
                                             from: calendar.startOfDay(for: dueAt),
                                             to: calendar.startOfDay(for: targetDay)).day ?? 0
        let movedDue = calendar.date(byAdding: .day, value: offset, to: dueAt) ?? dueAt
        let movedDeadline = calendar.date(byAdding: .day, value: offset,
                                          to: calendar.startOfDay(for: deadline)) ?? deadline
        return (movedDue, movedDeadline)
    }
}
