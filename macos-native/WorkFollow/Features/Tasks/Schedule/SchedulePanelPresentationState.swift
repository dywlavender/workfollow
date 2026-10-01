import Foundation

typealias ScheduleProperty = ScheduleExpandedSection

struct SchedulePanelPresentationState {
    enum RecurrencePage { case work, holiday }
    var expandedProperty: ScheduleProperty?
    var hoveredProperty: ScheduleProperty?
    var recurrencePage: RecurrencePage?

    mutating func hover(_ property: ScheduleProperty, inside: Bool) {
        if inside { hoveredProperty = property }
        else if hoveredProperty == property { hoveredProperty = nil }
    }
}

struct SchedulePropertyPresentation {
    enum TrailingControl { case chevronRight, chevronDown, clear }
    let title: String
    let value: String?
    let isActive: Bool
    let isExpanded: Bool
    let isHovered: Bool
    let canClear: Bool

    var trailingControl: TrailingControl {
        if canClear && isHovered { return .clear }
        return isExpanded ? .chevronDown : .chevronRight
    }
}

enum SchedulePanelInteraction {
    /// Choose the nearest half hour on the selected day, not a different due day.
    /// At a tie choose the later slot; midnight wraps the clock to 00:00.
    static func defaultTime(now: Date, date: Date, calendar: Calendar) -> Date {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let slot = ((minutes + 15) / 30 * 30) % (24 * 60)
        return calendar.date(bySettingHour: slot / 60, minute: slot % 60, second: 0, of: date) ?? date
    }

    @MainActor
    static func open(_ property: ScheduleProperty, state: inout SchedulePanelPresentationState,
                     model: TaskDateDraftModel, now: Date, calendar: Calendar) {
        if property == .time, !model.hasTime {
            let value = defaultTime(now: now, date: model.startTimeAnchor ?? now, calendar: calendar)
            model.setHasTime(true)
            model.setStartTime(value)
        }
        state.expandedProperty = property
    }

    @MainActor
    static func clear(_ property: ScheduleProperty, state: inout SchedulePanelPresentationState,
                      model: TaskDateDraftModel) {
        switch property {
        case .time: model.setHasTime(false)
        case .endTime: model.clearEndTime()
        case .reminder: model.clearReminder()
        case .repeat:
            model.chooseFrequency(.never)
            model.chooseEnding(.never)
            state.recurrencePage = nil
        case .repeatEnd: model.chooseEnding(.never)
        }
        state.expandedProperty = nil
    }
}
