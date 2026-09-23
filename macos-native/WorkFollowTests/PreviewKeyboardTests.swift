import XCTest
@testable import WorkFollow

final class PreviewKeyboardTests: XCTestCase {
    func testAdjacentSelectionClampsAndResetsAcrossNavigation() async {
        await MainActor.run {
            let workspace = PreviewWorkspace()
            let rows = workspace.projectedTasks(for: .today)
            workspace.selectAdjacent(1, in: .today)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(1, in: .today)
            XCTAssertEqual(workspace.selectedTaskID, rows[1].id)
            workspace.selectAdjacent(-1, in: .today)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(-1, in: .today)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(100, in: .today)
            XCTAssertEqual(workspace.selectedTaskID, rows.last?.id)
            workspace.select(nil)
            workspace.selectAdjacent(1, in: .trash)
            XCTAssertNil(workspace.selectedTaskID)
        }
    }
}
