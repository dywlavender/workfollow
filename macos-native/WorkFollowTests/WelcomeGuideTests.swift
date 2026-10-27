import XCTest
@testable import WorkFollow

@MainActor
final class WelcomeGuideTests: XCTestCase {
    private func makeWorkspace() -> TaskWorkspaceModel {
        TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
    }

    func testInstallCreatesListSectionsAndAllGuideTasks() {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())

        XCTAssertTrue(workspace.listNames.contains(WelcomeGuide.listName))
        XCTAssertEqual(workspace.listSections(forList: WelcomeGuide.listName).map(\.title),
                       WelcomeGuide.sectionTitles)

        let guideTasks = workspace.allTasks.filter { $0.list.name == WelcomeGuide.listName }
        XCTAssertEqual(guideTasks.count, WelcomeGuide.items.count)
        XCTAssertEqual(Set(guideTasks.map(\.title)), Set(WelcomeGuide.items.map(\.title)))
        XCTAssertTrue(guideTasks.allSatisfy { $0.guideAction != nil })
        XCTAssertTrue(guideTasks.allSatisfy { $0.schedule.dueAt == nil })
        XCTAssertTrue(guideTasks.allSatisfy { !$0.document.isEmpty })

        let sectionTitles = Dictionary(uniqueKeysWithValues:
            workspace.listSections(forList: WelcomeGuide.listName).map { ($0.id, $0.title) })
        for item in WelcomeGuide.items {
            guard let task = guideTasks.first(where: { $0.title == item.title }) else {
                XCTFail("missing guide task: \(item.title)")
                continue
            }
            XCTAssertEqual(sectionTitles[task.sectionID ?? ""], item.section.title)
            XCTAssertEqual(WelcomeGuide.action(for: task), item.action)
            XCTAssertTrue(task.document.plainText.contains(item.summary))
            XCTAssertTrue(task.document.plainText.contains(item.steps[0]))
        }
    }

    func testInstallIsIdempotent() {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let count = workspace.allTasks.count

        XCTAssertFalse(workspace.installWelcomeGuide())
        XCTAssertEqual(workspace.allTasks.count, count)
        XCTAssertEqual(workspace.listSections(forList: WelcomeGuide.listName).count,
                       WelcomeGuide.sectionTitles.count)
    }

    func testResetRecreatesGuideButKeepsUserTasksInTheSameList() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let guideTasks = workspace.allTasks.filter { $0.list.name == WelcomeGuide.listName }
        let first = try XCTUnwrap(guideTasks.first)
        _ = workspace.setTitle(first.id, "被改过的引导")

        let userTask = workspace.createDraft(
            title: "我自己加的任务",
            list: WelcomeGuide.listName,
            schedule: TaskSchedule(),
            priority: .none,
            tags: [],
            reminder: nil,
            repeatFrequency: .never
        )
        let userID = try XCTUnwrap(userTask.taskID)

        XCTAssertTrue(workspace.resetWelcomeGuide())

        let after = workspace.allTasks.filter { $0.list.name == WelcomeGuide.listName }
        XCTAssertEqual(after.count, WelcomeGuide.items.count + 1)
        XCTAssertEqual(Set(after.map(\.title)), Set(WelcomeGuide.items.map(\.title) + ["我自己加的任务"]))
        XCTAssertTrue(after.contains(where: { $0.id == userID }))
        XCTAssertFalse(after.contains(where: { $0.title == "被改过的引导" }))
        XCTAssertTrue(after.filter { $0.id != userID }.allSatisfy { $0.guideAction != nil })
        XCTAssertEqual(workspace.listSections(forList: WelcomeGuide.listName).map(\.title),
                       WelcomeGuide.sectionTitles)
    }

    func testGuideActionURLRoundTrip() {
        for action in WelcomeGuide.Action.allCases {
            XCTAssertEqual(WelcomeGuide.Action(url: action.url), action)
        }
        XCTAssertNil(WelcomeGuide.Action(url: URL(string: "workfollow://guide/unknown")!))
        XCTAssertNil(WelcomeGuide.Action(url: URL(string: "https://example.com/guide/matrix")!))
    }

    func testGuideActionFollowsTaskMarker() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let guideTask = try XCTUnwrap(workspace.allTasks.first { $0.guideAction != nil })
        let expected = try XCTUnwrap(WelcomeGuide.action(for: guideTask))

        var moved = guideTask
        moved.list = TaskList(name: "工作")
        XCTAssertEqual(WelcomeGuide.action(for: moved), expected)

        var noAction = guideTask
        noAction.guideAction = nil
        XCTAssertNil(WelcomeGuide.action(for: noAction))
    }

    func testGuideActionSurvivesTaskCodableRoundTrip() throws {
        let workspace = makeWorkspace()
        XCTAssertTrue(workspace.installWelcomeGuide())
        let task = try XCTUnwrap(workspace.allTasks.first { $0.guideAction != nil })

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(Task.self, from: data)
        XCTAssertEqual(decoded.guideAction, task.guideAction)
    }
}
