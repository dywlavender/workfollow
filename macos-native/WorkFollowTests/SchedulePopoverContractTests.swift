import SwiftUI
import XCTest
@testable import WorkFollow

/// 固定容器：属性截断展开仅改变内部滚动内容。
@MainActor
final class SchedulePopoverContractTests: XCTestCase {

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }

    private func makeTask(recurrence: TaskRepeat = .never) -> Task {
        let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9, minute: 0))!
        return Task(id: UUID(), title: "验收", tags: [], recurrence: recurrence,
                    list: .inbox, priority: .none,
                    schedule: TaskSchedule(dueAt: due, hasTime: false), status: .active,
                    parentID: nil, childOrder: 0, createdAt: due, updatedAt: due)
    }

    private func workspace(now: Date) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
    }

    /// 定时区间任务：打开时落在时间段页签，属性区多出「结束时间」一行。
    private func makeRangedTask() -> Task {
        let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28,
                                                     hour: 9, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29,
                                                     hour: 17, minute: 45))!
        return Task(id: UUID(), title: "验收", tags: [], recurrence: .never,
                    list: .inbox, priority: .none,
                    schedule: TaskSchedule(dueAt: due, hasTime: true, dueEndAt: end),
                    status: .active, parentID: nil, childOrder: 0,
                    createdAt: due, updatedAt: due)
    }

    private func size(of popover: TaskDatePopoverV2) -> CGSize {
        NSHostingController(rootView: AnyView(popover))
            .sizeThatFits(in: CGSize(width: 600, height: 900))
    }

    func testMetricsAreFixedContract() {
        XCTAssertEqual(ScheduleMetrics.panelWidth, 260)
        XCTAssertEqual(ScheduleMetrics.horizontalPadding, 14)
        XCTAssertEqual(ScheduleMetrics.rowHeight, 30)
        XCTAssertEqual(ScheduleMetrics.optionRowHeight, 34)
        XCTAssertEqual(ScheduleMetrics.timeOptionsHeight, 280)
        XCTAssertEqual(ScheduleMetrics.optionPanelWidth, 252)
        XCTAssertEqual(ScheduleMetrics.childInset, 4)
        XCTAssertEqual(ScheduleMetrics.childHorizontalOutset, 10)
    }

    func testPanelWidthIsContract() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let task = makeTask()
        let measured = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now)) {})
        XCTAssertEqual(measured.width, ScheduleMetrics.panelWidth, accuracy: 0.5)
    }

    func testExpandingEditorKeepsPanelSize() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let task = makeTask()
        let base = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now)) {})
        for page in [TaskDatePopoverV2.Page.time, .reminder, .recurrence] {
            let sheet = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now),
                                                   initialPage: page) {})
            XCTAssertEqual(sheet.height, base.height, accuracy: 0.5, "initialPage=\(page)")
            XCTAssertEqual(sheet.width, base.width, accuracy: 0.5, "initialPage=\(page)")
        }
    }

    func testRepeatEndAddsOnePropertyRowToContainer() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let base = size(of: TaskDatePopoverV2(task: makeTask(recurrence: .never),
                                              workspace: workspace(now: now)) {})
        let repeating = size(of: TaskDatePopoverV2(task: makeTask(recurrence: .daily),
                                                   workspace: workspace(now: now)) {})
        XCTAssertEqual(repeating.height, base.height + ScheduleMetrics.rowHeight, accuracy: 0.5)
    }

    func testDeadlineUsesSameFixedContainer() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let base = size(of: TaskDatePopoverV2(task: makeTask(), workspace: workspace(now: now)) {})
        let deadline = size(of: TaskDatePopoverV2(task: makeTask(), workspace: workspace(now: now),
                                                  deadline: true) {})
        XCTAssertEqual(deadline.height, base.height, accuracy: 0.5)
    }

    /// 时间段页签增加结束时间行和区间说明区域，宽度契约不变。
    func testPeriodTabAddsTheEndTimeRow() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let dateOnly = size(of: TaskDatePopoverV2(task: makeTask(), workspace: workspace(now: now)) {})
        let ranged = size(of: TaskDatePopoverV2(task: makeRangedTask(),
                                                workspace: workspace(now: now)) {})
        XCTAssertEqual(ranged.width, ScheduleMetrics.panelWidth, accuracy: 0.5)
        XCTAssertEqual(ranged.height, dateOnly.height + ScheduleMetrics.rowHeight + 24, accuracy: 0.5)
    }
}
