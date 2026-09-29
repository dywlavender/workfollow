import SwiftUI
import XCTest
@testable import WorkFollow

/// 日程浮层尺寸契约测试（"开子浮层主面板尺寸绝不变"等硬约定）。
///
/// 实现上：把 `TaskDatePopoverV2` 本体放进 NSHostingController 取 fitting size，
/// 不走系统 popover——子浮层（时间/提醒/重复）在架构上是独立弹窗，因此开子
/// 浮层时主面板内容尺寸必须保持基础高度，重复开启时才允许 +一行高。
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
        XCTAssertEqual(ScheduleMetrics.optionPanelWidth, 232)
    }

    func testPanelWidthIsContract() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let task = makeTask()
        let measured = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now)) {})
        XCTAssertEqual(measured.width, ScheduleMetrics.panelWidth, accuracy: 0.5)
    }

    func testOpeningSheetDoesNotChangeMainPanelSize() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let task = makeTask()
        let base = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now)) {})
        // 分别打开时间 / 提醒 / 重复子浮层：主面板宽高都不许变（硬契约）。
        for page in [TaskDatePopoverV2.Page.time, .reminder, .recurrence] {
            let sheet = size(of: TaskDatePopoverV2(task: task, workspace: workspace(now: now),
                                                   initialPage: page) {})
            XCTAssertEqual(sheet.height, base.height, accuracy: 0.5, "initialPage=\(page)")
            XCTAssertEqual(sheet.width, base.width, accuracy: 0.5, "initialPage=\(page)")
        }
    }

    func testRepeatAddsExactlyOneRowHeight() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let base = size(of: TaskDatePopoverV2(task: makeTask(recurrence: .never),
                                              workspace: workspace(now: now)) {})
        let repeating = size(of: TaskDatePopoverV2(task: makeTask(recurrence: .daily),
                                                   workspace: workspace(now: now)) {})
        XCTAssertEqual(repeating.height, base.height + ScheduleMetrics.rowHeight, accuracy: 1)
    }

    func testDeadlineVariantHidesPropertyRows() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let base = size(of: TaskDatePopoverV2(task: makeTask(), workspace: workspace(now: now)) {})
        let deadline = size(of: TaskDatePopoverV2(task: makeTask(), workspace: workspace(now: now),
                                                  deadline: true) {})
        // 截止日期面板没有属性行（时间/提醒/重复 + 重复结束隐藏）与分段。
        XCTAssertLessThan(deadline.height, base.height - ScheduleMetrics.rowHeight)
    }
}
