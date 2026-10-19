import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTimelineDropTests: XCTestCase {
    func testPoolProviderSchedulesTheOriginalTaskAtTheDroppedDateAndUndoesOnce() async throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "任务池投放", in: .inbox).taskID)
        let original = try XCTUnwrap(workspace.task(for: id))
        let controller = TaskTimelineInteractionController(workspace: workspace, tasks: [original])
        let day = workspace.calendar.startOfDay(for: workspace.clock())
        let received = expectation(description: "Native String provider delivered")
        let point = CGPoint(x: 176, y: 74)

        XCTAssertTrue(TaskTimelineDropDelegate.receive(NSItemProvider(object: id.uuidString as NSString), at: point) {
            taskID, location in
            XCTAssertEqual(taskID, id)
            XCTAssertEqual(location, point)
            XCTAssertTrue(controller.drop([taskID.uuidString], on: day).acceptsDrop)
            received.fulfill()
        })
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(workspace.task(for: id)?.schedule.dueAt, day)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id), original)
    }

    func testBoardProviderKeepsTheTaskIdentityAndGridLocation() async {
        let id = UUID()
        let received = expectation(description: "Board payload delivered")
        let point = CGPoint(x: 352, y: 90)
        let provider = NSItemProvider(object: SidebarDragPayload.encode(.task(id)) as NSString)
        XCTAssertTrue(TaskTimelineDropDelegate.receive(provider, at: point) { taskID, location in
            XCTAssertEqual(taskID, id)
            XCTAssertEqual(location, point)
            received.fulfill()
        })
        await fulfillment(of: [received], timeout: 2)
    }
}
