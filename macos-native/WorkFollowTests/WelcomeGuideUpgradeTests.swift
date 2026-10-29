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

    func testUpgradeMovesItemsToTheirCurrentGroupAndOrder() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let item = try XCTUnwrap(WelcomeGuide.items.first { $0.action == .list })
        let task = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == item.action.rawValue })
        let modules = try XCTUnwrap(workspace.listSections(forList: WelcomeGuide.listName)
            .first { $0.title == "功能模块" })
        _ = workspace.setTaskSection(task.id, sectionID: modules.id)
        XCTAssertEqual(workspace.task(for: task.id)?.sectionID, modules.id)

        XCTAssertTrue(workspace.upgradeWelcomeGuide())

        let expectedSection = try XCTUnwrap(workspace.listSections(forList: WelcomeGuide.listName)
            .first { $0.title == item.section.title })
        let moved = try XCTUnwrap(workspace.task(for: task.id))
        XCTAssertEqual(moved.sectionID, expectedSection.id)
        XCTAssertEqual(moved.childOrder, WelcomeGuide.items.firstIndex { $0.action == item.action })
    }

    func testUpgradeAddsAgentInstructionsAndKeepsExistingProgress() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let agent = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.agentAccess.rawValue })
        let existing = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.quickAdd.rawValue })
        _ = workspace.delete(agent.id)
        _ = workspace.complete(existing.id)

        XCTAssertTrue(workspace.upgradeWelcomeGuide())
        XCTAssertEqual(workspace.task(for: existing.id)?.status, .completed)
        let instructions = try XCTUnwrap(workspace.allTasks.first {
            $0.guideAction == WelcomeGuide.Action.agentAccess.rawValue && $0.deletedAt == nil
        })
        XCTAssertTrue(instructions.document.plainText.contains("复制给 AI"))
        XCTAssertTrue(instructions.document.plainText.contains("终端手动执行"))
        XCTAssertEqual(workspace.allTasks.filter { $0.guideAction != nil && $0.deletedAt == nil }.count, WelcomeGuide.items.count)
    }

    func testUpgradeAddsAIConfigurationAndKeepsCompletedGuideTasks() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let ai = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.aiConfiguration.rawValue })
        let existing = try XCTUnwrap(workspace.allTasks.first { $0.guideAction == WelcomeGuide.Action.quickAdd.rawValue })
        _ = workspace.delete(ai.id)
        _ = workspace.complete(existing.id)
        XCTAssertTrue(workspace.upgradeWelcomeGuide())
        XCTAssertEqual(workspace.task(for: existing.id)?.status, .completed)
        let restored = try XCTUnwrap(workspace.allTasks.first {
            $0.guideAction == WelcomeGuide.Action.aiConfiguration.rawValue && $0.deletedAt == nil
        })
        for text in ["node --version", "Pi 安装命令", "API URL", "API Key", "models.json", "刷新 Pi 模型"] {
            XCTAssertTrue(restored.document.plainText.contains(text), text)
        }
    }
}
