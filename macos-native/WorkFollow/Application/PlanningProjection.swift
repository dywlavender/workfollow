import Foundation

enum PlanningProjection {
    /// Flutter baseline: medium/high are important; scheduled within three days
    /// (including overdue) is urgent. Deadline does not define matrix urgency.
    static func quadrant(_ task: Task, now: Date, calendar: Calendar = .current) -> Int {
        let important = task.priority == .high || task.priority == .medium
        let horizon = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let urgent = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= horizon } ?? false
        return important ? (urgent ? 0 : 1) : (urgent ? 2 : 3)
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func tasks(on day: Date, from tasks: [Task], calendar: Calendar = .current) -> [Task] {
        tasks.filter { task in
            task.deletedAt == nil && task.schedule.dueAt.map { calendar.isDate($0, inSameDayAs: day) } == true
        }.sorted { ($0.schedule.dueAt ?? .distantPast) < ($1.schedule.dueAt ?? .distantPast) }
    }

    /// First day of each of the twelve months in `year` (year view cards).
    static func yearMonths(containing year: Int, calendar: Calendar = .current) -> [Date] {
        (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    /// 6x7 mini-month grid for the year view. Week-start alignment reuses
    /// `monthDays(containing:)`; slots outside the month are `nil` placeholders.
    static func monthGrid(in month: Date, calendar: Calendar = .current) -> [Date?] {
        monthDays(containing: month, calendar: calendar).map { day -> Date? in
            calendar.isDate(day, equalTo: month, toGranularity: .month) ? day : nil
        }
    }

    /// Day-bucketed counts for the year heat map. The day rule mirrors
    /// `tasks(on:)`: only the scheduled `dueAt` counts, compared in calendar
    /// days. The task rule mirrors the workspace's visible-task filter:
    /// deleted, skipped and abandoned tasks never count, closed tasks only
    /// when `includeCompleted`. Keys are `calendar.startOfDay` dates in `year`.
    static func countsByDay(tasks: [Task], in year: Int, calendar: Calendar = .current,
                            includeCompleted: Bool) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in tasks {
            guard task.deletedAt == nil, task.skippedAt == nil, !task.isAbandoned,
                  includeCompleted || !task.isClosed, let dueAt = task.schedule.dueAt,
                  calendar.component(.year, from: dueAt) == year else { continue }
            counts[calendar.startOfDay(for: dueAt), default: 0] += 1
        }
        return counts
    }

    /// Heat buckets for the year view: 0 / 1 / 2 / 3-4 / 5+.
    static func heatLevel(count: Int) -> Int {
        switch count {
        case ..<1: return 0
        case 1: return 1
        case 2: return 2
        case 3...4: return 3
        default: return 4
        }
    }

    // MARK: - View logic (pure, unit-tested)

    /// Chip classification for a task's due date in list rows:
    /// overdue (red) / today (accent) / upcoming (gray) / no chip.
    enum DateChipKind: Equatable {
        case overdue, today, upcoming, none
    }

    /// Size of the list color palette the view maps indices onto.
    static let listPaletteCount = 8

    /// Stable palette slot for a list name. Hand-rolled FNV-1a over Unicode
    /// scalars — deliberately NOT `String.hashValue`, which is randomized per
    /// launch and would recolor every list each time the app starts.
    static func listColorIndex(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for scalar in name.unicodeScalars {
            hash ^= UInt64(truncatingIfNeeded: scalar.value)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(listPaletteCount))
    }

    static func dateChipKind(dueAt: Date?, now: Date, calendar: Calendar) -> DateChipKind {
        guard let dueAt = dueAt else { return .none }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dueAt)
        if day < today { return .overdue }
        if day == today { return .today }
        return .upcoming
    }

    /// Chip copy delegates to TaskDateLabel so list rows and the inspector
    /// always phrase the same date identically (今天/明天/昨天/M月d日).
    static func dateChipText(_ dueAt: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        TaskDateLabel.text(dueAt, hasTime: hasTime, now: now, calendar: calendar)
    }
}
