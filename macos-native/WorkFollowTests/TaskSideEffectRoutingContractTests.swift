import Foundation
import XCTest
@testable import WorkFollow

final class TaskSideEffectRoutingContractTests: XCTestCase {
    func testReminderRoutingConsumesCommittedChangesRatherThanUIRevisions() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WorkFollow/App/AppEnvironment.swift")
        let source = try String(contentsOf: app, encoding: .utf8)
        let revisionStart = try XCTUnwrap(source.range(of: "taskWorkspace.$revision.dropFirst()"))
        let revisionEnd = try XCTUnwrap(source.range(of: "}.store(in: &subscriptions)",
            range: revisionStart.upperBound..<source.endIndex))
        let revisionSubscription = source[revisionStart.lowerBound..<revisionEnd.upperBound]
        XCTAssertTrue(revisionSubscription.contains("savePreview()"), "Keep existing persistence scheduling")
        XCTAssertFalse(revisionSubscription.contains("reminders.reconcile"),
                       "A UI invalidation must not restart reminder work")
        XCTAssertTrue(source.contains("taskWorkspace.taskChanges"))
        XCTAssertTrue(source.contains(".reminderInvalidations()"))
    }
}
