import Combine
import Foundation

/// 摘要的周次与清单选择。计划本身在日历周视图里完成，跳到日历时通过
/// `AppNavigation.calendarRevealRequest` 一次性传递日期，不共享这份状态。
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
}
