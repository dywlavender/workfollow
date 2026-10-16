import Foundation

enum RecurrenceBase: String, CaseIterable, Codable {
    case dueDate, completionDate, selectedDates
    var title: String {
        switch self {
        case .dueDate: "到期日期"
        case .completionDate: "完成日期"
        case .selectedDates: "自选日期"
        }
    }
}

enum RecurrenceEditScope: String, CaseIterable, Identifiable {
    case onlyThis, thisAndFuture, allNotCompleted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .onlyThis: "仅此任务"
        case .thisAndFuture: "此任务及之后的任务"
        case .allNotCompleted: "所有未完成的任务"
        }
    }
}

/// Identity is the original nominal period, even after a single occurrence moves.
struct OccurrenceKey: Equatable, Codable, Hashable {
    var seriesID: UUID
    var nominalDate: Date
    var ordinal: Int
    var id: String { "\(seriesID.uuidString):\(ordinal):\(Int64(nominalDate.timeIntervalSince1970))" }
}

enum OccurrenceOutcome: String, Codable { case active, completed, skipped, abandoned }
struct OccurrenceOverride: Equatable, Codable {
    var occurrence: OccurrenceKey
    var actualSchedule: TaskSchedule?
    var outcome: OccurrenceOutcome = .active
}

extension Task {
    var isActiveSeriesOccurrence: Bool {
        deletedAt == nil && skippedAt == nil && !isConverted && !isClosed
    }
}

struct TaskSeriesTemplate: Equatable, Codable {
    var title: String
    var document: NativeDocument
    var tags: [String]
    var list: TaskList
    var listID: UUID?
    var tagReferences: [TaskTagReference]?
    var priority: TaskPriority
    var schedule: TaskSchedule
    var reminderAt: Date?
    var reminderOffsets: [Int]?
    var attachments: [NativeAttachment]
    var sourceNoteID: UUID?
    var sectionID: String?
    var focusEstimate: TaskFocusEstimate?

    init(_ task: Task) {
        title = task.title; document = task.document; tags = task.tags; list = task.list
        listID = task.listID; tagReferences = task.tagReferences
        priority = task.priority; schedule = task.schedule; reminderAt = task.reminderAt
        reminderOffsets = task.reminderOffsets; attachments = task.attachments
        sourceNoteID = task.sourceNoteID; sectionID = task.sectionID; focusEstimate = task.focusEstimate
    }

    func task(id: UUID, at date: Date, series: TaskSeries, key: OccurrenceKey, createdAt: Date? = nil) -> Task {
        let delta = date.timeIntervalSince(schedule.dueAt ?? series.anchorDate)
        var value = Task(id: id, title: title, document: document, tags: tags,
            recurrence: series.frequency, recurrenceRule: series.rule, list: list,
            priority: priority, schedule: schedule, childOrder: 0,
            createdAt: createdAt ?? series.createdAt, updatedAt: series.createdAt)
        value.schedule.dueAt = date
        value.schedule.dueEndAt = schedule.dueEndAt?.addingTimeInterval(delta)
        value.schedule.deadlineAt = schedule.deadlineAt?.addingTimeInterval(delta)
        value.reminderAt = reminderAt?.addingTimeInterval(delta)
        value.reminderOffsets = reminderOffsets; value.attachments = attachments
        value.sourceNoteID = sourceNoteID; value.sectionID = sectionID; value.focusEstimate = focusEstimate
        if let count = series.rule.remainingCount { value.recurrenceRule?.remainingCount = max(1, count - key.ordinal) }
        if series.frequency == .ebbinghaus {
            value.recurrenceRule?.ebbinghausStep = (series.rule.ebbinghausStep ?? max(0, series.rule.interval - 1)) + key.ordinal
        }
        value.listID = listID; value.tagReferences = tagReferences
        value.series = series; value.occurrenceKey = key
        return value
    }
}

struct TaskSeries: Equatable, Codable {
    var id: UUID
    var template: TaskSeriesTemplate
    var frequency: TaskRepeat
    var rule: RecurrenceRule
    var timeZoneID: String
    var anchorDate: Date
    var createdAt: Date
    /// A split retains the past segment and prevents projected duplicates.
    var endBeforeOrdinal: Int?
    /// A split keeps historical tasks untouched while retaining their excluded periods.
    var excludedOrdinals: [Int]? = nil

    init(task: Task, calendar: Calendar, now: Date, id: UUID? = nil) {
        self.id = id ?? task.id
        template = TaskSeriesTemplate(task)
        frequency = task.recurrence
        rule = task.recurrenceRule ?? RecurrenceRule()
        anchorDate = task.schedule.dueAt ?? calendar.startOfDay(for: now)
        if rule.monthDay == nil { rule.monthDay = calendar.component(.day, from: anchorDate) }
        if rule.weekday == nil { rule.weekday = calendar.component(.weekday, from: anchorDate) }
        timeZoneID = calendar.timeZone.identifier
        createdAt = task.createdAt
    }

    var initialKey: OccurrenceKey { OccurrenceKey(seriesID: id, nominalDate: anchorDate, ordinal: 0) }

    func nominalDate(for ordinal: Int, calendar: Calendar) -> Date? {
        guard frequency != .never, ordinal >= 0,
              endBeforeOrdinal.map({ ordinal < $0 }) ?? true else { return nil }
        let cal = self.calendar(matching: calendar)
        if let end = rule.endDate, cal.startOfDay(for: anchorDate) > cal.startOfDay(for: end) { return nil }
        var cursor = anchorDate
        var currentRule = rule
        for _ in 0..<ordinal {
            guard let next = currentRule.nextOccurrence(after: cursor, frequency: frequency, calendar: cal),
                  next > cursor else { return nil }
            cursor = next
            currentRule = currentRule.following
            if frequency == .ebbinghaus {
                currentRule.ebbinghausStep = (currentRule.ebbinghausStep ?? max(0, currentRule.interval - 1)) + 1
            }
        }
        return cursor
    }

    func calendar(matching caller: Calendar) -> Calendar {
        var value = caller
        value.timeZone = TimeZone(identifier: timeZoneID) ?? caller.timeZone
        return value
    }
}

struct TaskOccurrence: Identifiable, Equatable {
    var key: OccurrenceKey
    var task: Task
    var isVirtual: Bool
    var sourceTaskID: UUID
    var id: String { key.id }
}

enum TaskOccurrenceProjection {
    /// Projects into a visible window without inserting future tasks in storage.
    /// Completion-based dates are unknown until completion, so they have no ghosts.
    static func occurrences(tasks: [Task], in window: DateInterval, calendar: Calendar) -> [TaskOccurrence] {
        let materialized = tasks.filter { $0.deletedAt == nil && $0.parentID == nil }
        var result: [TaskOccurrence] = []
        var seriesByID: [UUID: (series: TaskSeries, sourceID: UUID)] = [:]
        var byKey: [OccurrenceKey: Task] = [:]
        var occupiedOrdinals: [UUID: Set<Int>] = [:]
        for task in tasks {
            if let key = task.occurrenceKey {
                byKey[key] = task
                occupiedOrdinals[key.seriesID, default: []].insert(key.ordinal)
            }
        }
        for task in materialized {
            let series = task.series ?? (task.recurrence != .never && task.isActiveSeriesOccurrence
                ? TaskSeries(task: task, calendar: calendar, now: window.start) : nil)
            let key = task.occurrenceKey ?? series?.initialKey
            if let key { byKey[key] = task }
            if let series, task.recurrence != .never, task.isActiveSeriesOccurrence {
                let existingOrdinal = seriesByID[series.id].flatMap { entry in
                    tasks.first(where: { $0.id == entry.sourceID })?.occurrenceKey?.ordinal
                } ?? Int.max
                if (task.occurrenceKey?.ordinal ?? 0) <= existingOrdinal { seriesByID[series.id] = (series, task.id) }
            }
            guard task.skippedAt == nil, !task.isConverted, intersects(task.schedule, window: window, calendar: calendar) else { continue }
            let reference = key ?? OccurrenceKey(seriesID: task.id,
                nominalDate: task.schedule.dueAt ?? task.createdAt, ordinal: 0)
            result.append(TaskOccurrence(key: reference, task: task, isVirtual: false, sourceTaskID: task.id))
        }
        for (_, entry) in seriesByID {
            let series = entry.series
            guard series.rule.base != .completionDate else { continue }
            let cal = series.calendar(matching: calendar)
            let excludedOrdinals = Set(series.excludedOrdinals ?? [])
            var rule = series.rule
            var cursor = series.anchorDate
            var ordinal = 0
            // The visible date range is the stopping criterion. A high ceiling
            // bounds accidental non-progress while permitting years of daily data.
            while cursor < window.end, ordinal < 20_000 {
                if let stop = series.endBeforeOrdinal, ordinal >= stop { break }
                let key = OccurrenceKey(seriesID: series.id, nominalDate: cursor, ordinal: ordinal)
                if !excludedOrdinals.contains(ordinal), byKey[key] == nil,
                   !(occupiedOrdinals[series.id]?.contains(ordinal) ?? false) {
                    let value = series.template.task(id: virtualID(series.id, ordinal: ordinal),
                        at: cursor, series: series, key: key)
                    if intersects(value.schedule, window: window, calendar: cal) {
                        result.append(TaskOccurrence(key: key, task: value, isVirtual: true, sourceTaskID: entry.sourceID))
                    }
                }
                guard let next = rule.nextOccurrence(after: cursor, frequency: series.frequency, calendar: cal), next > cursor else { break }
                cursor = next; ordinal += 1; rule = rule.following
                if series.frequency == .ebbinghaus { rule.ebbinghausStep = (rule.ebbinghausStep ?? max(0, rule.interval - 1)) + 1 }
            }
        }
        return result.sorted {
            let left = $0.task.schedule.dueAt ?? .distantFuture
            let right = $1.task.schedule.dueAt ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
    }

    static func intersects(_ schedule: TaskSchedule, window: DateInterval, calendar: Calendar) -> Bool {
        guard let start = schedule.dueAt else { return false }
        let end = schedule.dueEndAt.map { schedule.hasTime ? $0 : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) ?? $0 } ?? start
        return start < window.end && end >= window.start
    }

    /// Derive a repeatable UI-only UUID directly from namespace and ordinal.
    /// Persisted instances receive a new real UUID once, then retain it in undo/redo.
    private static func virtualID(_ seriesID: UUID, ordinal: Int) -> UUID {
        var bytes = seriesID.uuid
        withUnsafeMutableBytes(of: &bytes) { buffer in
            let value = UInt64(max(0, ordinal)) + 1
            for index in 0..<8 { buffer[8 + index] ^= UInt8(truncatingIfNeeded: value >> (index * 8)) }
            buffer[6] = (buffer[6] & 0x0f) | 0x50
        }
        return UUID(uuid: bytes)
    }
}
