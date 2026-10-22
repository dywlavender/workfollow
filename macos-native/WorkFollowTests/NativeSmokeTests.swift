import XCTest
@testable import WorkFollow

final class NativeSmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(NativeDestination.today.title, "今天")
    }

    func testTaskNavigationMatchesFlutterWithoutStandaloneOverdueDestination() {
        // `weekPlan` 与 `summary` 已并入任务导航：摘要是任务模块里的一个目的地，
        // 不再单独占图标栏（见 docs/editor-optimization-plan-2026-10-16.md）。
        XCTAssertEqual(NativeDestination.taskDestinations,
                       [.weekPlan, .nextSevenDays, .today, .tomorrow, .inbox, .summary,
                        .allTasks, .completed, .abandoned, .trash])
        XCTAssertFalse(NativeDestination.taskDestinations.contains { $0.title == "过期" })
        XCTAssertFalse(NativeDestination.allCases.contains { $0.title == "过期" })
    }
}
