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
        } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            let blockID = items.first(where: { $0.name == "block" })?.value.flatMap(UUID.init(uuidString:))
            let query = items.first(where: { $0.name == "match" })?.value ?? ""
            switch link {
            case .task(let id):
                if taskWorkspace.task(for: id)?.isNoteTask == true {
                    notesWorkspace.requestSearchReveal(noteID: id, query: query, blockID: blockID)
                } else { taskWorkspace.requestSearchReveal(taskID: id, query: query, blockID: blockID) }
            case .note(let id):
                notesWorkspace.requestSearchReveal(noteID: id, query: query, blockID: blockID)
            case .meeting(let id):
                if let line = items.first(where: { $0.name == "line" })?.value.flatMap(UUID.init(uuidString:)) {
                    meetingStore.revealTranscript(meetingID: id, lineID: line)
                }
            }
        }
        return true
    }
}
