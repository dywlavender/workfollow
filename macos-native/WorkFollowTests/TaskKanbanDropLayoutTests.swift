import XCTest
@testable import WorkFollow

final class TaskKanbanDropLayoutTests: XCTestCase {
    func testPointerChoosesBeforeBetweenAndAfterWholeCards() {
        let first = UUID(), last = UUID()
        let frames = [first: CGRect(x: 4, y: 50, width: 256, height: 60),
                      last: CGRect(x: 4, y: 130, width: 256, height: 100)]
        let viewport = CGRect(x: 0, y: 32, width: 264, height: 368)
        func insertion(_ y: CGFloat) -> TaskKanbanInsertion {
            .resolve(at: y, orderedIDs: [first, last], frames: frames, viewport: viewport)
        }
        XCTAssertEqual(insertion(60).placement, .before(first))
        XCTAssertEqual(insertion(120).placement, .before(last))
        XCTAssertEqual(insertion(260).placement, .after(last))
        XCTAssertLessThan(insertion(60).y, frames[first]!.minY)
        XCTAssertGreaterThan(insertion(260).y, frames[last]!.maxY)
    }

    func testEmptyColumnMarkerStartsInsideTheScrollableContent() {
        let viewport = CGRect(x: 0, y: 84, width: 264, height: 316)
        let insertion = TaskKanbanInsertion.resolve(at: 200, orderedIDs: [], frames: [:],
                                                    viewport: viewport)
        XCTAssertNil(insertion.placement)
        XCTAssertGreaterThan(insertion.y, viewport.minY)
        XCTAssertLessThan(insertion.y, viewport.maxY)
    }

    func testMarkerStaysInViewportWhenTheCardGapIsScrolledOut() {
        let task = UUID()
        let viewport = CGRect(x: 0, y: 32, width: 264, height: 368)
        let insertion = TaskKanbanInsertion.resolve(at: 20, orderedIDs: [task],
            frames: [task: CGRect(x: 4, y: -40, width: 256, height: 160)], viewport: viewport)
        XCTAssertEqual(insertion.placement, .before(task))
        XCTAssertGreaterThanOrEqual(insertion.y, viewport.minY)
    }
}
