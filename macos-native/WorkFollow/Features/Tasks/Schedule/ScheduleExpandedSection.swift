/// Child cards never remove rows from the underlying date panel.
enum ScheduleExpandedSection: Hashable {
    case time, endTime, reminder, `repeat`, repeatEnd

    static func visibleRows(expanded: Self?, period: Bool, repeating: Bool) -> [Self] {
        var rows: [Self] = [.time]
        if period { rows.append(.endTime) }
        rows += [.reminder, .repeat]
        if repeating { rows.append(.repeatEnd) }
        return rows
    }
}
