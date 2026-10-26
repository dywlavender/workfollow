import XCTest
@testable import WorkFollow

/// P3：列表/看板显示清单进度，优先于子任务，且不水合正文。
@MainActor
final class ChecklistListProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecklistListProgressTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testChecklistProgressTakesPrecedenceOverSubtaskProgress() {
        let task = checklistTask(states: [true, false, false])
        let items = TaskSecondaryMetadata.items(for: task, subtaskProgress: "1/2",
                                                checklistProgress: "1/3")
        XCTAssertEqual(items.first?.id, "checklist")
        XCTAssertEqual(items.first?.value, "1/3")
        XCTAssertEqual(items.first?.accessibilityLabel, "检查事项进度：1/3")
        XCTAssertFalse(items.contains { $0.id == "subtasks" })
    }

    func testChecklistTaskWithoutItemsFallsBackToSubtasks() {
        let task = checklistTask(states: [])
        let items = TaskSecondaryMetadata.items(for: task, subtaskProgress: "2/4",
                                                checklistProgress: nil)
        XCTAssertEqual(items.first?.id, "subtasks")
        XCTAssertEqual(items.first?.value, "2/4")
    }

    func testTextTaskWithInlineCheckboxesShowsNoChecklistProgress() {
        var task = checklistTask(states: [true, false])
        task.kind = .text
        XCTAssertNil(TaskSecondaryMetadata.items(for: task, subtaskProgress: nil,
                                                 checklistProgress: nil)
            .first { $0.id == "checklist" })
    }

    func testKanbanCardUsesTheSameChecklistProgressAndHonorsHiddenDetails() {
        let task = checklistTask(states: [true, false, false])
        let visible = TaskKanbanCardDetails(task: task, subtaskProgress: "1/2",
                                            checklistProgress: "1/3", showsListBadge: true,
                                            hidesDetails: false, hiddenFields: [])
        XCTAssertEqual(visible.indicators.first?.id, "checklist")
        XCTAssertEqual(visible.indicators.first?.value, "1/3")

        let hidden = TaskKanbanCardDetails(task: task, subtaskProgress: "1/2",
                                           checklistProgress: "1/3", showsListBadge: true,
                                           hidesDetails: true, hiddenFields: [])
        XCTAssertTrue(hidden.indicators.isEmpty)
    }

    func testHundredDeferredChecklistTasksDoNotHydrateBodies() throws {
        let tasks = (0..<100).map { index -> Task in
            var task = checklistTask(states: [true, false])
            task.title = "清单 \(index)"
            return task
        }
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: tasks, notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks)
        XCTAssertEqual(lazy.count, 100)
        XCTAssertEqual(repository.documentReadCount, 0)

        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: lazy)
        for task in lazy {
            let progress = try XCTUnwrap(workspace.task(for: task.id).flatMap(workspace.checklistProgress))
            XCTAssertEqual(progress, "1/2")
            XCTAssertFalse(try XCTUnwrap(workspace.task(for: task.id)).document.isLoaded)
        }
        XCTAssertEqual(repository.documentReadCount, 0, "列表进度只能读摘要")
    }

    func testSearchMatchesChecklistTextWithoutHydratingTheBody() throws {
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [checklistTask(states: [false, true])], notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)

        XCTAssertTrue(lazy.document.matches("事项"))
        XCTAssertFalse(lazy.document.isLoaded)
        XCTAssertEqual(repository.documentReadCount, 0)
    }

    // MARK: - Helpers

    private func checklistTask(states: [Bool]) -> Task {
        var task = Task(id: UUID(), title: "清单",
                        document: NativeDocument(blocks: states.map { checked in
                            DocumentBlock(kind: .checklist(checked), runs: [DocumentRun(text: "事项")])
                        }),
                        list: .inbox, priority: .none, schedule: TaskSchedule(),
                        parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        task.kind = .checklist
        return task
    }
}
