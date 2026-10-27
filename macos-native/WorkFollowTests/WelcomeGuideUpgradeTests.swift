import XCTest
@testable import WorkFollow

@MainActor
final class WelcomeGuideUpgradeTests: XCTestCase {
    private func makeWorkspace() -> TaskWorkspaceModel {
        TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
    }

    func testUpgradeRefreshesContentAndKeepsCompletion() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let task = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.quickAdd.rawValue })
        _ = workspace.setTitle(task.id, "被改过的标题")
        _ = workspace.setDocument(task.id, .empty)
        _ = workspace.complete(task.id)

        XCTAssertTrue(workspace.upgradeWelcomeGuide())

        let upgraded = try XCTUnwrap(workspace.allTasks.first { $0.id == task.id })
        XCTAssertNotEqual(upgraded.title, "被改过的标题")
        XCTAssertFalse(upgraded.document.isEmpty)
        XCTAssertEqual(upgraded.status, .completed)
    }

    func testUpgradeRecreatesDeletedGuideTask() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let task = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.matrix.rawValue })
        _ = workspace.delete(task.id)

        XCTAssertTrue(workspace.upgradeWelcomeGuide())

        let guideTasks = workspace.allTasks.filter { $0.guideAction != nil && $0.deletedAt == nil }
        XCTAssertEqual(guideTasks.count, WelcomeGuide.items.count)
        XCTAssertTrue(guideTasks.contains { $0.guideAction == WelcomeGuide.Action.matrix.rawValue })
    }

    func testUpgradeDoesNotResurrectWhenAllGuideTasksAreDeleted() {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        for task in workspace.allTasks where task.guideAction != nil {
            _ = workspace.delete(task.id)
        }

        XCTAssertFalse(workspace.upgradeWelcomeGuide())
        XCTAssertTrue(workspace.allTasks.filter { $0.guideAction != nil && $0.deletedAt == nil }.isEmpty)
    }

    func testUpgradeKeepsUserTasksInWelcomeList() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let userTask = try XCTUnwrap(workspace.createDraft(
            title: "我自己加的任务",
            list: WelcomeGuide.listName,
            schedule: TaskSchedule(),
            priority: .none,
            tags: [],
            reminder: nil,
            repeatFrequency: .never
        ).taskID)

        XCTAssertFalse(workspace.upgradeWelcomeGuide())
        XCTAssertTrue(workspace.allTasks.contains { $0.id == userTask })
    }
}
