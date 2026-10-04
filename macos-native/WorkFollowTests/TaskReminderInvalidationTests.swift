import Combine
import XCTest
@testable import WorkFollow

@MainActor
final class TaskReminderInvalidationTests: XCTestCase {
    func testBodyAndSelectionDoNotInvalidateRemindersButTitleBurstUsesLatestTask() async throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "初始", in: .inbox).taskID)
        var deliveries: [String] = []
        var domainChanges = 0
        let bodyChange = workspace.taskChanges.sink { _ in domainChanges += 1 }
        let delivery = expectation(description: "One reminder invalidation for the title burst")
        delivery.assertForOverFulfill = true
        let subscription = workspace.taskChanges.reminderInvalidations(delay: .milliseconds(30))
            .sink {
                deliveries.append(workspace.task(for: id)?.title ?? "")
                delivery.fulfill()
            }
        workspace.select(id)
        _ = workspace.setDocument(id, NativeDocument(plainText: "正文即时同步"))
        XCTAssertEqual(workspace.selectedTask?.document.plainText, "正文即时同步")
        XCTAssertEqual(domainChanges, 1)
        try await _Concurrency.Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(deliveries.isEmpty, "Body commits must not trigger reminder reconciliation")
        _ = workspace.setTitle(id, "标题一")
        _ = workspace.setTitle(id, "标题二")
        _ = workspace.setTitle(id, "最终标题")
        _ = workspace.setDocument(id, NativeDocument(plainText: "后续正文"))
        await fulfillment(of: [delivery], timeout: 1)
        try await _Concurrency.Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(deliveries, ["最终标题"])
        withExtendedLifetime((subscription, bodyChange)) {}
    }

    func testUndoOfReminderRelevantChangeInvalidatesAgain() async throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "任务", in: .inbox).taskID)
        let delivery = expectation(description: "Reminder edit and its undo both invalidate")
        delivery.expectedFulfillmentCount = 2
        var values: [Date?] = []
        let subscription = workspace.taskChanges.reminderInvalidations(delay: .milliseconds(10))
            .sink {
                values.append(workspace.task(for: id)?.reminderAt)
                delivery.fulfill()
            }
        let reminder = Date().addingTimeInterval(3600)
        workspace.setReminder(id, reminder)
        try await _Concurrency.Task.sleep(for: .milliseconds(60))
        workspace.undo()
        await fulfillment(of: [delivery], timeout: 1)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.first!, reminder)
        XCTAssertNil(values.last!)
        withExtendedLifetime(subscription) {}
    }
}
