import Foundation

enum CalendarDisplayItem: Identifiable, Equatable {
    case task(Task), event(SystemCalendarEvent)
    var id: String {
        switch self {
        case let .task(task): "task.\(task.id.uuidString)"
        case let .event(event): "event.\(event.displayID)"
        }
    }
    var start: Date {
        switch self {
        case let .task(task): task.schedule.dueAt ?? .distantFuture
        case let .event(event): event.fields.start
        }
    }
}

extension SystemCalendarEvent {
    /// Recurrences may share an EventKit identifier; UI identity includes the date.
    var displayID: String { id + "." + String(fields.start.timeIntervalSince1970) }
}

struct ExternalCalendarPlacement: Identifiable, Equatable {
    var event: SystemCalendarEvent
    var startMinute: Double
    var endMinute: Double
    var lane: Int
    var laneCount: Int
    var id: String { event.displayID }
}

enum ExternalCalendarProjection {
    static func events(on day: Date, events: [SystemCalendarEvent], calendar: Calendar) -> [SystemCalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.fields.start < end && $0.fields.end > start }
            .sorted { $0.fields.start < $1.fields.start }
    }
    static func items(tasks: [Task], events: [SystemCalendarEvent]) -> [CalendarDisplayItem] {
        (tasks.map(CalendarDisplayItem.task) + events.map(CalendarDisplayItem.event))
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    /// The same interval partition includes tasks and events. Neither type is
    /// converted into the other, and read-only events never acquire task gestures.
    static func timed(on day: Date, tasks: [CalendarTimedPlacement], events: [SystemCalendarEvent], calendar: Calendar)
        -> (tasks: [CalendarTimedPlacement], events: [ExternalCalendarPlacement]) {
        struct Entry { var id: String; var start: Double; var end: Double }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var external = self.events(on: day, events: events, calendar: calendar).filter { !$0.fields.allDay }.map { event in
            let low = max(start, event.fields.start)
            let high = min(end, event.fields.end)
            func minute(_ date: Date) -> Double {
                if date == end { return 1440 }
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
            return ExternalCalendarPlacement(event: event, startMinute: minute(low), endMinute: minute(high), lane: 0, laneCount: 1)
        }
        var entries = tasks.map { Entry(id: "task." + $0.id.uuidString, start: $0.startMinute, end: $0.endMinute ?? $0.startMinute + 20) }
        entries += external.map { Entry(id: "event." + $0.id, start: $0.startMinute, end: max($0.startMinute + 20, $0.endMinute)) }
        entries.sort { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var allocation: [String: (Int, Int)] = [:]
        var first = 0
        while first < entries.count {
            var last = first + 1; var clusterEnd = entries[first].end
            while last < entries.count && entries[last].start < clusterEnd {
                clusterEnd = max(clusterEnd, entries[last].end); last += 1
            }
            var laneEnds: [Double] = []; var lanes: [String: Int] = [:]
            for entry in entries[first..<last] {
                let lane = laneEnds.firstIndex { $0 <= entry.start } ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(entry.end) } else { laneEnds[lane] = entry.end }
                lanes[entry.id] = lane
            }
            for entry in entries[first..<last] { allocation[entry.id] = (lanes[entry.id]!, laneEnds.count) }
            first = last
        }
        let result = tasks.map { item in
            let lanes = allocation["task." + item.id.uuidString]!
            return CalendarTimedPlacement(task: item.task, day: item.day, startMinute: item.startMinute,
                endMinute: item.endMinute, lane: lanes.0, laneCount: lanes.1)
        }
        for index in external.indices {
            let lanes = allocation["event." + external[index].id]!
            external[index].lane = lanes.0; external[index].laneCount = lanes.1
        }
        return (result, external)
    }
}
