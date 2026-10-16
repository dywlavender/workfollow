import Foundation

enum CalendarDropDestination: Equatable {
    /// A month cell keeps the task's existing time of day.
    case day(Date)
    case allDay(Date)
    case time(day: Date, minute: Double)
}

enum CalendarInteractionOutcome {
    case committed(TaskActionResult)
    case requiresScope(TaskOccurrence, SchedulePlan)
    case unchanged
    case missing
    var acceptsDrop: Bool {
        switch self {
        case .committed(let result): if case .success = result { return true }; return false
        case .requiresScope, .unchanged: return true
        case .missing: return false
        }
    }
}

/// Drop resolution uses workspace entities and virtual occurrences, never the
/// subset currently painted in a column. The arrange pool can therefore move
/// an unscheduled task into any calendar presentation.
@MainActor
struct CalendarInteractionController {
    let workspace: TaskWorkspaceModel
    let occurrences: [TaskOccurrence]
    let calendar: Calendar

    func resolve(_ id: UUID) -> Task? {
        workspace.task(for: id) ?? occurrences.first { $0.task.id == id }?.task
    }
    func drop(_ values: [String], at destination: CalendarDropDestination) -> CalendarInteractionOutcome {
        guard let id = values.first.flatMap(UUID.init(uuidString:)), let task = resolve(id) else { return .missing }
        let start: Date
        let timed: Bool
        switch destination {
        case .allDay(let day):
            start = calendar.startOfDay(for: day); timed = false
        case .time(let day, let minute):
            start = CalendarGestureDraft.date(on: day, minute: minute, calendar: calendar); timed = true
        case .day(let day):
            timed = task.schedule.hasTime
            if timed, let old = task.schedule.dueAt {
                let clock = calendar.dateComponents([.hour, .minute, .second], from: old)
                start = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                      second: clock.second ?? 0, of: day)!
            } else { start = calendar.startOfDay(for: day) }
        }
        let schedule = CalendarGestureDraft.moved(task.schedule, to: start, hasTime: timed, calendar: calendar)
        return apply(id, schedule: schedule)
    }
    func apply(_ id: UUID, schedule: TaskSchedule) -> CalendarInteractionOutcome {
        guard let task = resolve(id) else { return .missing }
        guard task.schedule != schedule else { return .unchanged }
        if task.recurrence != .never, let occurrence = occurrences.first(where: { $0.task.id == id }) {
            let delta = schedule.dueAt.flatMap { start in task.schedule.dueAt.map { start.timeIntervalSince($0) } } ?? 0
            let plan = SchedulePlan(schedule: schedule, reminder: task.reminderAt?.addingTimeInterval(delta),
                reminderOffsets: task.reminderOffsets ?? [], frequency: task.recurrence, recurrenceRule: task.recurrenceRule)
            return .requiresScope(occurrence, plan)
        }
        return .committed(workspace.updateAttributes(id, schedule: schedule))
    }
}
