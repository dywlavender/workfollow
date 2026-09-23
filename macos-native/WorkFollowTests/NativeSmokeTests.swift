import XCTest
@testable import WorkFollow

final class NativeSmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(NativeDestination.today.title, "今天")
    }
}
