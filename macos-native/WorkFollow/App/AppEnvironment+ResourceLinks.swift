import Foundation

extension AppEnvironment {
    /// Returns true for recognized local links, including unavailable targets,
    /// so an internal link never falls back to opening an unrelated URL handler.
    @discardableResult
    func openResourceLink(_ url: URL) -> Bool {
        if let destination = TaskWidgetLink.destination(for: url) {
            if destination == .quickAdd {
                widgetQuickAdd.present()
                return true
            }
            navigation.taskSelectionToPreserveOnNextNavigation = nil
            taskWorkspace.activeList = nil
            taskWorkspace.activeTag = nil
            taskWorkspace.openFilter(nil)
            taskWorkspace.clearBulkSelection()
            taskWorkspace.select(nil)
            switch destination {
            case .today: navigate(to: .today)
            case .weekPlan:
                weeklyPlanning.goCurrent()
                weeklyPlanning.listName = nil
                navigation.calendarRevealRequest = weeklyPlanning.weekStart
                navigate(to: .calendar)
            case .quickAdd: break // Presented independently above.
            case .countdowns: navigate(to: .countdown)
            }
            return true
        }
        if let action = WelcomeGuide.Action(url: url) {
            return openGuideAction(action)
        }
        guard let link = NativeResourceLink(url: url) else { return false }
        if let reference = CalendarTaskReference(url: url) {
            if !openCalendarTask(reference) { feedback.show(FeedbackEvent(kind: .error, message: "该周期已不可用")) }
            return true
        }
        if !NativeResourceLinkRouter.open(link, tasks: taskWorkspace, notes: notesWorkspace, navigation: navigation, meetings: meetingStore) {
            feedback.show(FeedbackEvent(kind: .error, message: "链接目标不存在或已不可用"))
        }
        return true
    }
}
