import Foundation

enum CalendarViewMode: String, CaseIterable, Codable {
    case month, week, day
    var label: String { switch self { case .month: "月"; case .week: "周"; case .day: "日" } }
    var previousLabel: String { switch self { case .month: "上个月"; case .week: "上一周"; case .day: "前一天" } }
    var nextLabel: String { switch self { case .month: "下个月"; case .week: "下一周"; case .day: "后一天" } }
}

enum CalendarColorSource: String, CaseIterable, Codable {
    case list, priority, tag, task
    var label: String { switch self { case .list: "清单"; case .priority: "优先级"; case .tag: "标签"; case .task: "任务" } }
}

struct CalendarPreferences: Equatable, Codable {
    var mode: CalendarViewMode = .month
    var showCompleted = true
    var showFutureOccurrences = true
    var showSubtasks = true
    var showArrangePane = false
    var colorSource: CalendarColorSource = .task
    var firstWeekday = 1
    var hourHeight: Double = 64
    var allDayHeight: Double = 96
    var listNames: [String] = []
    var tagNames: [String] = []

    func includes(_ task: Task) -> Bool {
        PlanningProjection.appearsOnCalendar(task)
            && (showCompleted || task.status != .completed)
            && (showSubtasks || task.parentID == nil)
            && (listNames.isEmpty || listNames.contains(task.list.name))
            && (tagNames.isEmpty || task.tags.contains(where: tagNames.contains))
    }
    func configuredCalendar(_ base: Calendar) -> Calendar {
        var value = base
        value.firstWeekday = min(7, max(1, firstWeekday))
        return value
    }
}

/// Browsing, selection and creation defaults move together. Month scrolling
/// preserves the selected day-of-month when it enters another month.
struct CalendarViewport: Equatable {
    var browseDate: Date
    var selectedDate: Date
    var mode: CalendarViewMode
    var scrollMinute = 480

    init(date: Date, mode: CalendarViewMode = .month, calendar: Calendar) {
        browseDate = calendar.startOfDay(for: date)
        selectedDate = calendar.startOfDay(for: date)
        self.mode = mode
    }
    func visibleRange(calendar: Calendar) -> DateInterval {
        if mode == .month {
            let days = PlanningProjection.monthGridDays(containing: browseDate, calendar: calendar)
            let first = days.first ?? browseDate
            let end = calendar.date(byAdding: .day, value: 1, to: days.last ?? first) ?? first
            return DateInterval(start: first, end: end)
        }
        if mode == .week { return calendar.dateInterval(of: .weekOfYear, for: selectedDate)! }
        let start = calendar.startOfDay(for: selectedDate)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
    mutating func select(_ day: Date, calendar: Calendar) {
        selectedDate = calendar.startOfDay(for: day)
        browseDate = selectedDate
    }
    mutating func browseMonth(_ month: Date, calendar: Calendar) {
        let currentDay = calendar.component(.day, from: selectedDate)
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var parts = calendar.dateComponents([.year, .month], from: month)
        parts.day = min(currentDay, count)
        selectedDate = calendar.date(from: parts) ?? month
        browseDate = selectedDate
    }
    mutating func step(_ direction: Int, calendar: Calendar) {
        let component: Calendar.Component = mode == .month ? .month : .day
        let amount = mode == .week ? 7 * direction : direction
        guard let date = calendar.date(byAdding: component, value: amount, to: selectedDate) else { return }
        select(date, calendar: calendar)
    }
}

enum CalendarPlacementKind: Equatable { case allDay, crossDay, timePoint, timeRange }

struct CalendarTimedPlacement: Identifiable, Equatable {
    let task: Task
    let day: Date
    let startMinute: Double
    let endMinute: Double?
    let lane: Int
    let laneCount: Int
    var id: UUID { task.id }
    var kind: CalendarPlacementKind { endMinute == nil ? .timePoint : .timeRange }
}

enum CalendarProjection {
    static func agenda(on day: Date, tasks: [Task], preferences: CalendarPreferences,
                       calendar: Calendar) -> [Task] {
        let target = calendar.startOfDay(for: day)
        return tasks.filter { task in
            guard preferences.includes(task), let start = PlanningProjection.startDay(of: task, calendar: calendar),
                  let end = PlanningProjection.endDay(of: task, calendar: calendar) else { return false }
            return start <= target && target <= end
        }.sorted(by: taskOrder)
    }
    static func allDay(tasks: [Task], range: DateInterval, preferences: CalendarPreferences,
                       calendar: Calendar) -> [Task] {
        tasks.filter { task in
            guard preferences.includes(task), let start = PlanningProjection.startDay(of: task, calendar: calendar),
                  let end = PlanningProjection.endDay(of: task, calendar: calendar),
                  !task.schedule.hasTime || end > start else { return false }
            return start < range.end && end >= range.start
        }.sorted(by: taskOrder)
    }
    static func arrangePool(tasks: [Task], preferences: CalendarPreferences) -> [Task] {
        tasks.filter { preferences.includes($0) && $0.schedule.dueAt == nil && $0.status == .active }
            .sorted(by: taskOrder)
    }
    /// Half-open interval partitioning. A point gets a presentation footprint
    /// for hit testing, while its domain schedule keeps a nil end.
    static func timed(on day: Date, tasks: [Task], preferences: CalendarPreferences,
                      calendar: Calendar, pointFootprintMinutes: Double = 20) -> [CalendarTimedPlacement] {
        let startDay = calendar.startOfDay(for: day)
        let candidates = tasks.filter {
            preferences.includes($0) && $0.schedule.hasTime
                && !PlanningProjection.spansMultipleDays($0, calendar: calendar)
                && PlanningProjection.startDay(of: $0, calendar: calendar) == startDay
        }.sorted(by: taskOrder)
        struct Entry { let task: Task; let start: Double; let end: Double?; let layoutEnd: Double }
        let entries: [Entry] = candidates.compactMap { task in
            guard let start = task.schedule.dueAt else { return nil }
            func minute(_ date: Date) -> Double {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
                return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
            }
            let low = minute(start)
            let high = task.schedule.dueEndAt.flatMap { $0 > start ? minute($0) : nil }
            return Entry(task: task, start: low, end: high,
                         layoutEnd: high ?? min(1440, low + pointFootprintMinutes))
        }
        var result: [CalendarTimedPlacement] = []
        var index = 0
        while index < entries.count {
            var endIndex = index + 1
            var clusterEnd = entries[index].layoutEnd
            while endIndex < entries.count && entries[endIndex].start < clusterEnd {
                clusterEnd = max(clusterEnd, entries[endIndex].layoutEnd)
                endIndex += 1
            }
            var laneEnds: [Double] = []
            var allocations: [(Entry, Int)] = []
            for entry in entries[index..<endIndex] {
                let lane = laneEnds.firstIndex(where: { $0 <= entry.start }) ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(entry.layoutEnd) }
                else { laneEnds[lane] = entry.layoutEnd }
                allocations.append((entry, lane))
            }
            result += allocations.map { entry, lane in
                CalendarTimedPlacement(task: entry.task, day: startDay, startMinute: entry.start,
                                       endMinute: entry.end, lane: lane, laneCount: laneEnds.count)
            }
            index = endIndex
        }
        return result
    }
    static func taskOrder(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.schedule.dueAt != rhs.schedule.dueAt {
            return (lhs.schedule.dueAt ?? .distantFuture) < (rhs.schedule.dueAt ?? .distantFuture)
        }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        return lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
    }
}

struct CalendarOccurrenceCacheKey: Equatable {
    var revision: Int
    var dateRevision: Int
    var range: DateInterval
    var firstWeekday: Int
    var timeZone: String
}

final class CalendarOccurrenceCache {
    private var key: CalendarOccurrenceCacheKey?
    private var cached: [TaskOccurrence] = []
    private var displayKey: CalendarOccurrenceCacheKey?
    private var displayPreferences: CalendarPreferences?
    private var displayed: [Task] = []
    private var tasksByID: [UUID: Task] = [:]
    private(set) var buildCount = 0
    func occurrences(tasks: [Task], in range: DateInterval, revision: Int,
                     dateRevision: Int, calendar: Calendar) -> [TaskOccurrence] {
        let next = CalendarOccurrenceCacheKey(revision: revision, dateRevision: dateRevision,
                                              range: range, firstWeekday: calendar.firstWeekday,
                                              timeZone: calendar.timeZone.identifier)
        if next == key { return cached }
        key = next
        cached = TaskOccurrenceProjection.occurrences(tasks: tasks, in: range, calendar: calendar)
        buildCount += 1
        return cached
    }
    func visibleTasks(tasks: [Task], preferences: CalendarPreferences, in range: DateInterval,
                      revision: Int, dateRevision: Int, calendar: Calendar) -> [Task] {
        let next = CalendarOccurrenceCacheKey(revision: revision, dateRevision: dateRevision,
            range: range, firstWeekday: calendar.firstWeekday, timeZone: calendar.timeZone.identifier)
        if displayKey == next && displayPreferences == preferences { return displayed }
        let future = preferences.showFutureOccurrences
            ? occurrences(tasks: tasks, in: range, revision: revision, dateRevision: dateRevision, calendar: calendar)
                .filter(\.isVirtual).map(\.task) : []
        displayed = (tasks + future).filter(preferences.includes)
        tasksByID = Dictionary(displayed.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        displayKey = next; displayPreferences = preferences
        return displayed
    }
    func task(for id: UUID) -> Task? { tasksByID[id] }
}

enum CalendarGestureDraft {
    static func date(on day: Date, minute: Double, calendar: Calendar, step: Int = 15) -> Date {
        let snapped = min(1439, max(0, Int((minute / Double(step)).rounded()) * step))
        return calendar.date(bySettingHour: snapped / 60, minute: snapped % 60, second: 0, of: day)!
    }
    static func creation(on day: Date, from startMinute: Double, to endMinute: Double?,
                         calendar: Calendar) -> TaskSchedule {
        let first = date(on: day, minute: startMinute, calendar: calendar)
        guard let endMinute else { return TaskSchedule(dueAt: first, hasTime: true) }
        let second = date(on: day, minute: endMinute, calendar: calendar)
        return TaskSchedule(dueAt: min(first, second), hasTime: true,
                            dueEndAt: first == second ? nil : max(first, second))
    }
    static func moved(_ schedule: TaskSchedule, to start: Date, hasTime: Bool,
                      calendar: Calendar) -> TaskSchedule {
        var changed = schedule
        if let old = schedule.dueAt, let oldEnd = schedule.dueEndAt {
            if !hasTime {
                let length = calendar.dateComponents([.day], from: calendar.startOfDay(for: old),
                                                      to: calendar.startOfDay(for: oldEnd)).day ?? 0
                changed.dueEndAt = calendar.date(byAdding: .day, value: length, to: calendar.startOfDay(for: start))
            } else { changed.dueEndAt = start.addingTimeInterval(oldEnd.timeIntervalSince(old)) }
        }
        changed.dueAt = start
        changed.hasTime = hasTime
        return changed
    }
}

enum CalendarResizeEdge { case start, end }

struct CalendarTimeBlockGeometry: Equatable {
    var startMinute: Double
    var endMinute: Double?
    var displayMinutes: Double { max(0, (endMinute ?? startMinute + 20) - startMinute) }

    init(schedule: TaskSchedule, day: Date, calendar: Calendar) {
        let midnight = calendar.startOfDay(for: day)
        let start = max(0, min(1440, (schedule.dueAt ?? midnight).timeIntervalSince(midnight) / 60))
        startMinute = start
        endMinute = schedule.dueEndAt.map { max(start, min(1440, $0.timeIntervalSince(midnight) / 60)) }
    }
}

/// Resizing owns a local schedule until mouse-up. Esc also suppresses later
/// movement in the same press, so a cancelled draft cannot be committed.
struct CalendarResizeDraft {
    private(set) var schedule: TaskSchedule?
    private var original: TaskSchedule?
    private var session = CalendarGestureSession()

    mutating func update(_ value: TaskSchedule, day: Date, edge: CalendarResizeEdge,
                         translationMinutes: Double, calendar: Calendar) {
        if session.beginIfNeeded() { original = value }
        guard !session.isCancelled, let original, let start = original.dueAt else { return }
        var changed = original
        let midnight = calendar.startOfDay(for: day)
        let startMinute = start.timeIntervalSince(midnight) / 60
        let endMinute = (original.dueEndAt?.timeIntervalSince(midnight)).map { $0 / 60 } ?? startMinute
        switch edge {
        case .start:
            changed.dueAt = CalendarGestureDraft.date(on: day,
                minute: min(endMinute - 15, startMinute + translationMinutes), calendar: calendar)
        case .end:
            changed.dueEndAt = CalendarGestureDraft.date(on: day,
                minute: max(startMinute + 15, endMinute + translationMinutes), calendar: calendar)
        }
        schedule = changed
    }
    mutating func cancel() { session.cancel(); schedule = nil }
    mutating func finish() -> TaskSchedule? {
        defer { schedule = nil; original = nil }
        return session.finish() ? schedule : nil
    }
}

enum CalendarDisplaySizing {
    static let hourHeightRange: ClosedRange<Double> = 40...120
    static let allDayHeightRange: ClosedRange<Double> = 60...200
    static func allDayHeight(_ value: Double) -> Double {
        min(allDayHeightRange.upperBound, max(allDayHeightRange.lowerBound, value))
    }
    static func acceptsZoomWheel(control: Bool, deltaX: Double, deltaY: Double) -> Bool {
        control && deltaY != 0 && abs(deltaY) > abs(deltaX)
    }
}

/// The same time stays at the pointer (wheel) or viewport centre (pinch).
struct CalendarTimelineScaleDraft: Equatable {
    let initialHourHeight: Double
    let anchorMinute: Double
    let anchorY: Double
    let viewportHeight: Double
    private(set) var hourHeight: Double

    init(hourHeight: Double, scrollOffset: Double, viewportHeight: Double, anchorY: Double? = nil) {
        initialHourHeight = hourHeight
        self.hourHeight = hourHeight
        self.viewportHeight = viewportHeight
        let y = min(viewportHeight, max(0, anchorY ?? viewportHeight / 2))
        self.anchorY = y
        anchorMinute = (scrollOffset + y) / hourHeight * 60
    }
    var scrollOffset: Double {
        min(max(0, hourHeight * 24 - viewportHeight), max(0, anchorMinute / 60 * hourHeight - anchorY))
    }
    mutating func magnify(_ factor: Double) { setHeight(initialHourHeight * factor) }
    mutating func scroll(_ delta: Double) { setHeight(hourHeight * exp(delta * 0.01)) }
    private mutating func setHeight(_ value: Double) {
        hourHeight = min(CalendarDisplaySizing.hourHeightRange.upperBound,
                         max(CalendarDisplaySizing.hourHeightRange.lowerBound, value))
    }
}

/// Esc cancels the entire mouse session, including any subsequent movement
/// before mouse-up. A new press starts a fresh draft.
struct CalendarGestureSession: Equatable {
    private(set) var isActive = false
    private(set) var isCancelled = false
    mutating func beginIfNeeded() -> Bool {
        guard !isActive else { return false }
        isActive = true; isCancelled = false
        return true
    }
    mutating func cancel() { if isActive { isCancelled = true } }
    mutating func finish() -> Bool {
        let accepted = isActive && !isCancelled
        isActive = false; isCancelled = false
        return accepted
    }
}
