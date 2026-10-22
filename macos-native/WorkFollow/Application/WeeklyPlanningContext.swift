import Combine
import Foundation

/// One selection shared by planning and reviewing, including cached pages.
@MainActor
final class WeeklyPlanningContext: ObservableObject {
    @Published var weekStart: Date
    @Published var listName: String?
    let calendar: Calendar
    let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
        weekStart = SummaryReviewBuilder.weekStart(of: clock(), calendar: calendar)
    }

    var weekKey: String { TaskWeeklyPlanning.key(for: weekStart, calendar: calendar) }
    var title: String { SummaryReviewBuilder.weekTitle(for: weekStart, calendar: calendar) }
    var isCurrent: Bool { weekKey == TaskWeeklyPlanning.key(for: clock(), calendar: calendar) }
    var nextWeek: Date { calendar.date(byAdding: .day, value: 7, to: weekStart)! }
    func shift(_ delta: Int) { weekStart = calendar.date(byAdding: .day, value: delta * 7, to: weekStart)! }
    func goCurrent() { weekStart = SummaryReviewBuilder.weekStart(of: clock(), calendar: calendar) }

    func scopeID(workspace: TaskWorkspaceModel?) -> String {
        guard let listName else { return "all" }
        return workspace?.listReferenceID(for: listName).uuidString ?? listName
    }
}
