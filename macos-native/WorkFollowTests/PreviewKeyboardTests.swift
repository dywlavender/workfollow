import XCTest
@testable import WorkFollow

final class PreviewKeyboardTests: XCTestCase {
    func testAdjacentSelectionClampsAndResetsAcrossNavigation() async {
        await MainActor.run {
            let workspace = PreviewWorkspace()
            let rows = workspace.visibleTasks
            workspace.selectAdjacent(1)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(1)
            XCTAssertEqual(workspace.selectedTaskID, rows[1].id)
            workspace.selectAdjacent(-1)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(-1)
            XCTAssertEqual(workspace.selectedTaskID, rows.first?.id)
            workspace.selectAdjacent(100)
            XCTAssertEqual(workspace.selectedTaskID, rows.last?.id)
            workspace.navigate(to: .trash)
            workspace.selectAdjacent(1)
            XCTAssertNil(workspace.selectedTaskID)
        }
    }
}
