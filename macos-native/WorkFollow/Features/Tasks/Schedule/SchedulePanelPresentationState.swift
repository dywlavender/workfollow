import Foundation

typealias ScheduleProperty = ScheduleExpandedSection

struct SchedulePanelPresentationState {
    enum RecurrencePage { case work, holiday, lunar }

    /// 属性子卡里再往里一层的子页。它们是三个独立 `@State`
    /// （`reminderCustomOpen` / `repeatCustomOpen` / `repeatEndEdit`）演化来的，
    /// 开合与"返回 / Esc / ×"各写一份判断。收成一个栈之后只有一个判据。
    enum SubPage: Equatable {
        case reminderCustom      // 自定义提前量
        case repeatCustom        // 自定义重复
        case repeatEnd(Edit)     // 重复结束条件（日期 / 次数两种编辑，互斥）

        enum Edit: Equatable { case date, count }
    }

    var expandedProperty: ScheduleProperty?
    var hoveredProperty: ScheduleProperty?
    var recurrencePage: RecurrencePage?
    /// 子页栈：末尾是最深一层。
    private(set) var subPages: [SubPage] = []

    /// 最深的子页（Esc / 返回先弹它）。
    var subPage: SubPage? { subPages.last }

    func shows(_ page: SubPage) -> Bool { subPages.contains(page) }

    /// 重复结束当前在编辑哪一种（日期 / 次数）。
    var repeatEndEdit: SubPage.Edit? {
        if case .repeatEnd(let edit) = subPage { return edit }
        return nil
    }

    /// 打开子页（重复打开同一页不叠加）。重复结束的两种编辑互斥：切过去而不是叠加。
    mutating func open(_ page: SubPage) {
        if case .repeatEnd = page { closeRepeatEnd() }
        guard subPages.last != page else { return }
        subPages.append(page)
    }

    /// 收起重复结束层（不论当前是日期还是次数编辑）。
    mutating func closeRepeatEnd() {
        subPages.removeAll { if case .repeatEnd = $0 { return true } else { return false } }
    }

    /// 收起指定子页，连同它更深的所有层。
    mutating func close(_ page: SubPage) {
        guard let index = subPages.firstIndex(of: page) else { return }
        subPages.removeSubrange(index...)
    }

    /// 收起属性子卡：子页与二级页一并清掉，避免下次打开残留。
    mutating func collapseProperty() {
        expandedProperty = nil
        subPages.removeAll()
        recurrencePage = nil
    }

    /// 清空某属性时，跟它绑定的子页一并收掉
    /// （清提醒 → 自定义提前量；清重复结束 → 重复结束页）。
    mutating func propertyCleared(_ property: ScheduleProperty) {
        switch property {
        case .time, .endTime: break
        case .reminder: close(.reminderCustom)
        case .repeat: close(.repeatCustom)
        case .repeatEnd: closeRepeatEnd()
        }
    }

    /// 一级返回（Esc / 返回箭头）：先弹最深子页，再收二级页，最后收属性子卡。
    /// 返回 `false` 表示已经到底，调用方可以把 Esc 交给宿主关面板。
    @discardableResult
    mutating func back() -> Bool {
        if !subPages.isEmpty {
            subPages.removeLast()
            return true
        }
        if recurrencePage != nil {
            recurrencePage = nil
            return true
        }
        if expandedProperty != nil {
            expandedProperty = nil
            return true
        }
        return false
    }

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
        case .repeatEnd: model.chooseEnding(.never)
        }
        // 清空属性 = 连同它的子页一起收掉（此前只清 expandedProperty，
        // 自定义提前量/自定义重复会残留到下次打开）。
        state.propertyCleared(property)
        state.collapseProperty()
    }
}
