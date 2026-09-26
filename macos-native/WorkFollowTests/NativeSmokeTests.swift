import XCTest
@testable import WorkFollow

final class NativeSmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(NativeDestination.today.title, "今天")
    }

    func testTaskNavigationMatchesFlutterWithoutStandaloneOverdueDestination() {
        XCTAssertEqual(NativeDestination.taskDestinations,
                       [.nextSevenDays, .today, .inbox, .allTasks, .completed, .trash])
        XCTAssertFalse(NativeDestination.taskDestinations.contains { $0.title == "过期" })
        XCTAssertFalse(NativeDestination.allCases.contains { $0.title == "过期" })
    }
}
