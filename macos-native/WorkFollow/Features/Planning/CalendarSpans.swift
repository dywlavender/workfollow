import Foundation

/// 一条跨天任务裁剪到某个周行后的一份。
///
/// 一条「周三到下周周二」的任务会产生两份：一行是它开始的那周，一行是它结束
/// 的那周。每份画成一个整体圆角盒，这正是色带读起来是一件事而不是五段相邻
/// 同色块的原因——网格从来不曾把它握在手里一次。对齐 Flutter
/// `widgets/calendar/calendar_spans.dart` 的 `CalendarSpan`。
struct CalendarSpan: Identifiable, Equatable {
    let task: Task
    /// 任务真实的首日与末日（未裁剪，取 startOfDay）。它们通常在本行之外。
    let startDay: Date
    let endDay: Date
    /// 本行内覆盖的列，含首尾，周首日为第 0 列。
    let fromColumn: Int
    let toColumn: Int
    /// 这一份占用的条位。lane 按行独立——行是唯一需要内部一致的单位。
    let lane: Int
    /// 任务真实的首日落在本行，因此这一份带勾选框。续段不带：勾选框标记开始，
    /// 三行之后再出现一个是第二个开始。
    let startsInRow: Bool
    /// 任务真实的末日落在本行，因此这一份带时刻。时刻属于区间的末端，而区间
    /// 只结束一次。
    let endsInRow: Bool

    var id: String { "\(task.id.uuidString)-\(fromColumn)" }
    var columnCount: Int { toColumn - fromColumn + 1 }
    /// 区间在上一行已经开始：本份左端压平。
    var continuesFromPreviousRow: Bool { !startsInRow }
    /// 区间延续到下一行：右端压平。
    var continuesIntoNextRow: Bool { !endsInRow }
}

/// 月/周视图跨天色带的纯布局逻辑（对齐 Flutter `layOutWeekSpans` /
/// `spanSlotsOver`）。不做状态过滤——调用方传入的是视图已过滤的可见任务。
enum CalendarSpans {
    /// 把一条周行里所有跨天任务摆进条位。
    ///
    /// 与本周有交集的跨天任务各得一个横跨其列区间的盒；列区间重叠的叠进不同
    /// lane。lane 按行计算而不是按月：中途进入本周的任务没有上一行可以继承。
    /// `week` 不是 7 天时返回空。
    static func lanes(for week: [Date], tasks: [Task], calendar: Calendar = .current) -> [CalendarSpan] {
        guard week.count == 7 else { return [] }
        let weekStart = calendar.startOfDay(for: week[0])

        /// 相对周首日的整天偏移；负数 = 本周之前。按自然日计数，窗口内的
        /// 夏令时跳变不会把一天的间隔算成零。
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
            let startsInRow: Bool
            let endsInRow: Bool
        }

        var candidates: [Candidate] = []
        for task in tasks {
            guard PlanningProjection.appearsOnCalendar(task),
                  PlanningProjection.spansMultipleDays(task, calendar: calendar),
                  let start = PlanningProjection.startDay(of: task, calendar: calendar),
                  let end = PlanningProjection.endDay(of: task, calendar: calendar) else { continue }
            let rawStart = offset(start)
            let rawEnd = offset(end)
            guard rawEnd >= 0, rawStart <= 6 else { continue }   // 与本周无交集
            candidates.append(Candidate(
                task: task, startDay: start, endDay: end,
                rawStart: rawStart, rawEnd: rawEnd,
                fromColumn: max(rawStart, 0), toColumn: min(rawEnd, 6),
                startsInRow: rawStart >= 0, endsInRow: rawEnd <= 6))
        }

        // 调用方通常已按「开始早优先、同日时长优先」排过序，这里不假设它，
        // 显式再排一次并以 id 兜底保证确定性。
        candidates.sort {
            if $0.rawStart != $1.rawStart { return $0.rawStart < $1.rawStart }
            if $0.rawEnd != $1.rawEnd { return $0.rawEnd > $1.rawEnd }
            return $0.task.id.uuidString < $1.task.id.uuidString
        }

        var occupied: [[ClosedRange<Int>]] = []
        var placed: [CalendarSpan] = []
        for candidate in candidates {
            let range = candidate.fromColumn...candidate.toColumn
            var lane = 0
            while lane < occupied.count,
                  occupied[lane].contains(where: { $0.overlaps(range) }) {
                lane += 1
            }
            if lane == occupied.count { occupied.append([]) }
            occupied[lane].append(range)
            placed.append(CalendarSpan(
                task: candidate.task, startDay: candidate.startDay, endDay: candidate.endDay,
                fromColumn: candidate.fromColumn, toColumn: candidate.toColumn,
                lane: lane,
                startsInRow: candidate.startsInRow, endsInRow: candidate.endsInRow))
        }

        return placed.sorted {
            $0.lane != $1.lane ? $0.lane < $1.lane : $0.fromColumn < $1.fromColumn
        }
    }

    /// `column` 这一天的格内小条要给色带让出多少个槽位：取覆盖它的最高 lane + 1，
    /// 而不是色带条数——一行可以把 lane 0 和 2 分给经过某列的色带，把 lane 1
    /// 留给没有到达这列的任务（对齐 Flutter `spanSlotsOver`）。无覆盖时为 0。
    static func slotsOver(_ spans: [CalendarSpan], column: Int) -> Int {
        spans.reduce(0) { result, span in
            span.fromColumn <= column && column <= span.toColumn
                ? max(result, span.lane + 1) : result
        }
    }
}
