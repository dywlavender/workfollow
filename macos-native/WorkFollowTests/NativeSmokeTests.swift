import XCTest
@testable import WorkFollow

final class NativeSmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(NativeDestination.today.title, "今天")
    }

    func testTaskNavigationMatchesFlutterWithoutStandaloneOverdueDestination() {
        // `summary` 已并入任务导航：摘要是任务模块里的一个目的地，
        // 不再单独占图标栏（见 docs/editor-optimization-plan-2026-10-16.md）。
        // 周计划不再是独立页面，计划动作回到日历周视图。
        XCTAssertEqual(NativeDestination.taskDestinations,
                       [.nextSevenDays, .today, .tomorrow, .inbox, .summary,
                        .allTasks, .completed, .abandoned, .trash])
        XCTAssertFalse(NativeDestination.taskDestinations.contains { $0.title == "过期" })
        XCTAssertFalse(NativeDestination.allCases.contains { $0.title == "过期" })
    }
}
