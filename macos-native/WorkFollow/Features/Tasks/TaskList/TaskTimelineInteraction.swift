import Foundation

enum TaskTimelineScale: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self { case .day: "日"; case .week: "周"; case .month: "月" }
    }
    var dayWidth: CGFloat {
        switch self { case .day: 88; case .week: 36; case .month: 18 }
    }
    var minimumVisibleDays: Int {
        switch self { case .day: 7; case .week: 14; case .month: 28 }
    }
}

enum TaskTimelineColorSource: String, CaseIterable, Identifiable {
    case list, tag, priority
    var id: String { rawValue }
    var title: String {
        switch self { case .list: "清单"; case .tag: "标签"; case .priority: "优先级" }
    }
}

/// The anchor belongs to browsing, never to the earliest task in the workspace.
struct TaskTimelineViewport: Equatable {
    var anchorDate: Date
    var scale: TaskTimelineScale = .day

    func range(availableWidth: CGFloat, calendar: Calendar) -> TaskTimelineRange {
        let visible = max(scale.minimumVisibleDays, Int(ceil(max(1, availableWidth) / scale.dayWidth)))
        let screenDays = max(1, Int(floor(max(1, availableWidth) / scale.dayWidth)))
        let leadingDays = min(max(3, visible / 2), screenDays - 1)
        let recentPast = calendar.date(byAdding: .day, value: -leadingDays, to: anchorDate) ?? anchorDate
        var start: Date
        switch scale {
        case .day: start = calendar.startOfDay(for: recentPast)
        case .week: start = calendar.dateInterval(of: .weekOfYear, for: recentPast)?.start ?? calendar.startOfDay(for: recentPast)
        case .month: start = calendar.dateInterval(of: .month, for: recentPast)?.start ?? calendar.startOfDay(for: recentPast)
        }
        // Calendar alignment must not move Today outside the first visible screen.
        let anchorIndex = calendar.dateComponents([.day], from: start,
            to: calendar.startOfDay(for: anchorDate)).day ?? 0
        if anchorIndex >= screenDays { start = calendar.startOfDay(for: recentPast) }
        // Three screens allow horizontal browsing; the toolbar advances one screen.
        return TaskTimelineRange(start: start, dayCount: visible * 3,
                                 visibleDayCount: visible, dayWidth: scale.dayWidth)
    }

    mutating func step(_ direction: Int, availableWidth: CGFloat, calendar: Calendar) {
        let count = range(availableWidth: availableWidth, calendar: calendar).visibleDayCount
        anchorDate = calendar.date(byAdding: .day, value: count * direction, to: anchorDate) ?? anchorDate
    }

    mutating func goToday(_ now: Date, calendar: Calendar) {
        anchorDate = calendar.startOfDay(for: now)
    }
}

struct TaskTimelineRange: Equatable {
    let start: Date
    let dayCount: Int
    let visibleDayCount: Int
    let dayWidth: CGFloat
    var contentWidth: CGFloat { CGFloat(dayCount) * dayWidth }

    func day(_ index: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: index, to: start) ?? start
    }

    func date(at x: CGFloat, calendar: Calendar) -> Date {
        let index = min(dayCount - 1, max(0, Int(floor(x / dayWidth))))
        return day(index, calendar: calendar)
    }
}

struct TaskTimelineTaskPartition {
    let scheduled: [Task]
    let unscheduled: [Task]
}

struct TaskTimelineBarGeometry: Equatable {
    let x: CGFloat
    let width: CGFloat
    let clippedStart: Bool
    let clippedEnd: Bool
}

struct TaskTimelineHeaderSegment: Identifiable, Equatable {
    let startIndex: Int
    let dayCount: Int
    let date: Date
    var id: Int { startIndex }
}

enum TaskTimelineLayout {
    static let rowHeight: CGFloat = 38
    static let headerRowHeight: CGFloat = 24
    static let headerVerticalPadding: CGFloat = 6
    static let headerHeight = headerRowHeight * 2 + headerVerticalPadding * 2
    static let minimumBarWidth: CGFloat = 24

    /// Inputs have already passed scope/filter/completion rules. Keep their order.
    static func partition(_ tasks: [Task]) -> TaskTimelineTaskPartition {
        var seen = Set<UUID>()
        let unique = tasks.filter { seen.insert($0.id).inserted }
        return TaskTimelineTaskPartition(scheduled: unique.filter { $0.schedule.dueAt != nil },
                                         unscheduled: unique.filter { $0.schedule.dueAt == nil })
    }

    static func headerSegments(in range: TaskTimelineRange, scale: TaskTimelineScale,
                               calendar: Calendar) -> [TaskTimelineHeaderSegment] {
        var segments: [TaskTimelineHeaderSegment] = []
        var start = 0
        while start < range.dayCount {
            let day = range.day(start, calendar: calendar)
            let interval: DateInterval?
            switch scale {
            case .day: interval = calendar.dateInterval(of: .day, for: day)
            case .week: interval = calendar.dateInterval(of: .weekOfYear, for: day)
            case .month: interval = calendar.dateInterval(of: .month, for: day)
            }
            let length = interval.map { calendar.dateComponents([.day], from: day, to: $0.end).day ?? 1 } ?? 1
            let count = min(range.dayCount - start, max(1, length))
            segments.append(TaskTimelineHeaderSegment(startIndex: start, dayCount: count, date: day))
            start += count
        }
        return segments
    }

    static func coordinate(for date: Date, in range: TaskTimelineRange, calendar: Calendar) -> CGFloat {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        let index = calendar.dateComponents([.day], from: range.start, to: day).day ?? 0
        let fraction = date.timeIntervalSince(day) / next.timeIntervalSince(day)
        return (CGFloat(index) + CGFloat(fraction)) * range.dayWidth
    }

    static func bar(for schedule: TaskSchedule, in range: TaskTimelineRange,
                    calendar: Calendar) -> TaskTimelineBarGeometry? {
        guard let due = schedule.dueAt else { return nil }
        let start = schedule.hasTime ? due : calendar.startOfDay(for: due)
        let x = coordinate(for: start, in: range, calendar: calendar)
        let width: CGFloat
        if schedule.hasTime {
            if let end = schedule.dueEndAt {
                width = max(minimumBarWidth, coordinate(for: end, in: range, calendar: calendar) - x)
            } else {
                // A readable point marker does not add an implicit persisted duration.
                width = max(minimumBarWidth, range.dayWidth * 0.7)
            }
        } else {
            let finalDay = calendar.startOfDay(for: schedule.dueEndAt ?? due)
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
            width = max(range.dayWidth, coordinate(for: exclusiveEnd, in: range, calendar: calendar) - x)
        }
        let end = x + width
        guard end > 0, x < range.contentWidth else { return nil }
        let clippedX = max(0, x)
        return TaskTimelineBarGeometry(x: clippedX, width: min(range.contentWidth, end) - clippedX,
                                       clippedStart: x < 0, clippedEnd: end > range.contentWidth)
    }

    static func creation(at x: CGFloat, in range: TaskTimelineRange, calendar: Calendar) -> TaskSchedule {
        TaskSchedule(dueAt: range.date(at: x, calendar: calendar))
    }
}

enum TaskTimelineGestureOperation: Equatable { case move, start, end }

enum TaskTimelineScheduleDraft {
    static func changed(_ original: TaskSchedule, operation: TaskTimelineGestureOperation,
                        days: Int, calendar: Calendar) -> TaskSchedule? {
        guard let start = original.dueAt else { return nil }
        guard days != 0 else { return original }
        var next = original
        switch operation {
        case .move:
            guard let moved = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
            return CalendarGestureDraft.moved(original, to: moved,
                                               hasTime: original.hasTime, calendar: calendar)
        case .start:
            guard let moved = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
            next.dueAt = original.hasTime ? moved : calendar.startOfDay(for: moved)
            next.dueEndAt = original.dueEndAt ?? start
        case .end:
            guard let moved = calendar.date(byAdding: .day, value: days, to: original.dueEndAt ?? start) else { return nil }
            next.dueEndAt = original.hasTime ? moved : calendar.startOfDay(for: moved)
        }
        guard let first = next.dueAt, let last = next.dueEndAt, last >= first else { return nil }
        return next
    }
}

/// Owns a local preview until mouse-up; Escape suppresses the rest of that press.
struct TaskTimelineGestureDraft {
    private(set) var schedule: TaskSchedule?
    private var original: TaskSchedule?
    private var operation: TaskTimelineGestureOperation = .move
    private var session = CalendarGestureSession()
    var isActive: Bool { session.isActive }

    mutating func update(_ value: TaskSchedule, operation: TaskTimelineGestureOperation,
                         translation: CGFloat, dayWidth: CGFloat, calendar: Calendar) {
        if session.beginIfNeeded() { original = value; self.operation = operation }
        guard !session.isCancelled, let original, dayWidth > 0 else { return }
        schedule = TaskTimelineScheduleDraft.changed(original, operation: self.operation,
            days: Int((translation / dayWidth).rounded()), calendar: calendar)
    }

    mutating func cancel() { session.cancel(); schedule = nil }

    mutating func finish() -> TaskSchedule? {
        let accepted = session.finish()
        defer { schedule = nil; original = nil }
        return accepted && schedule != original ? schedule : nil
    }
}

struct TaskTimelinePendingSchedule {
    let occurrence: TaskOccurrence
    let plan: SchedulePlan
}

/// Only the final drop/mouse-up reaches this boundary. Previews never write.
@MainActor
struct TaskTimelineInteractionController {
    let workspace: TaskWorkspaceModel
    let tasks: [Task]

    func resolve(_ id: UUID) -> Task? {
        guard let projected = tasks.first(where: { $0.id == id }) else { return nil }
        return workspace.task(for: id) ?? projected
    }

    private func calendarInteraction(for task: Task) -> CalendarInteractionController {
        CalendarInteractionController(workspace: workspace,
            occurrences: [workspace.occurrence(for: task)], calendar: workspace.calendar)
    }

    func apply(_ id: UUID, schedule: TaskSchedule) -> CalendarInteractionOutcome {
        guard let task = resolve(id) else { return .missing }
        if let start = schedule.dueAt, let end = schedule.dueEndAt, end < start {
            return .committed(.failure(.invalidSchedule))
        }
        return calendarInteraction(for: task).apply(id, schedule: schedule)
    }

    func move(_ id: UUID, byDays days: Int) -> CalendarInteractionOutcome {
        change(id, operation: .move, days: days)
    }

    func resize(_ id: UUID, edge: CalendarResizeEdge, byDays days: Int) -> CalendarInteractionOutcome {
        change(id, operation: edge == .start ? .start : .end, days: days)
    }

    private func change(_ id: UUID, operation: TaskTimelineGestureOperation, days: Int) -> CalendarInteractionOutcome {
        guard let task = resolve(id) else { return .missing }
        guard let schedule = TaskTimelineScheduleDraft.changed(task.schedule, operation: operation,
            days: days, calendar: workspace.calendar) else { return .committed(.failure(.invalidSchedule)) }
        return apply(id, schedule: schedule)
    }

    func drop(_ values: [String], on day: Date) -> CalendarInteractionOutcome {
        guard let id = values.first.flatMap(UUID.init(uuidString:)), let task = resolve(id) else { return .missing }
        return calendarInteraction(for: task).drop(values, at: .day(day))
    }

    @discardableResult
    func confirm(_ request: TaskTimelinePendingSchedule, scope: RecurrenceEditScope) -> TaskActionResult {
        workspace.saveOccurrenceSchedule(request.plan, occurrence: request.occurrence, scope: scope)
    }
}
