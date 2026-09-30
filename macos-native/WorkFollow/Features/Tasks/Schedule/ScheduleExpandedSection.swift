/// Single-panel presentation: retain rows up to the expanded editor and hide the rest.
enum ScheduleExpandedSection: Hashable {
    case time, endTime, reminder, `repeat`, repeatEnd

    static func visibleRows(expanded: Self?, period: Bool, repeating: Bool) -> [Self] {
        var rows: [Self] = [.time]
        if period { rows.append(.endTime) }
        rows += [.reminder, .repeat]
        if repeating { rows.append(.repeatEnd) }
        guard let expanded, let index = rows.firstIndex(of: expanded) else { return rows }
        return Array(rows[...index])
    }
}
