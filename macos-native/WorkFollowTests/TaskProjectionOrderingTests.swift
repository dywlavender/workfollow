import XCTest
@testable import WorkFollow

@MainActor
final class TaskProjectionOrderingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_548_800)

    private func tasks(_ names: [String]) -> [Task] {
        names.enumerated().map { index, name in
            Task(id: UUID(), title: name, list: .inbox, priority: .none,
                 schedule: TaskSchedule(), childOrder: index, createdAt: date, updatedAt: date)
        }
    }

    func testTitleOrderingReusesSortAndStillReflectsRenames() throws {
        let seed = tasks(["Zulu", "Bravo", "Charlie"])
        let workspace = TaskWorkspaceModel(clock: { self.date }, seedDemoData: false, initialTasks: seed)
        func read(_ descending: Bool = false) -> [TaskTreeNode] {
            workspace.groups(for: .inbox).flatMap {
                workspace.nodes(for: $0, scope: .inbox, sortMode: .title, sortDescending: descending)
            }
        }
        let initial = read().map(\.task.id)
        let sorts = workspace.projectionSortCount
        for _ in 0..<20 { XCTAssertEqual(read().map(\.task.id), initial) }
        XCTAssertEqual(workspace.projectionSortCount, sorts)
        XCTAssertEqual(read(true).map(\.task.id), Array(initial.reversed()))
        let beforeBody = workspace.projectionSortCount
        workspace.setDocument(seed[0].id, NativeDocument(plainText: "最新正文"))
        XCTAssertEqual(read().first { $0.task.id == seed[0].id }?.task.document.plainText, "最新正文")
        XCTAssertEqual(workspace.projectionSortCount, beforeBody)
        workspace.setTitle(seed[0].id, "Alpha")
        XCTAssertEqual(read().first?.task.id, seed[0].id)
        XCTAssertEqual(workspace.projectionSortCount, beforeBody + 1)
    }

    func testModifiedSortUpdatesWhenBodyChanges() throws {
        var now = date
        let seed = tasks(["一", "二", "三"])
        let workspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false, initialTasks: seed)
        func read() -> [TaskTreeNode] {
            workspace.groups(for: .inbox).flatMap {
                workspace.nodes(for: $0, scope: .inbox, sortMode: .modified, sortDescending: true)
            }
        }
        _ = read()
        let builds = workspace.projectionBuildCount
        let sorts = workspace.projectionSortCount
        now += 1
        workspace.setDocument(seed[2].id, NativeDocument(plainText: "修改正文"))
        XCTAssertEqual(read().first?.task.id, seed[2].id)
        XCTAssertEqual(workspace.projectionSortCount, sorts + 1)
        XCTAssertEqual(workspace.projectionBuildCount, builds + 1, "Only sorted nodes need rebuilding; grouping stays cached")
    }

    func testKeywordQueryAndSavedFilterReevaluateMembership() throws {
        let seed = tasks(["匹配原任务", "待修改任务"])
        let workspace = TaskWorkspaceModel(clock: { self.date }, seedDemoData: false, initialTasks: seed)
        let query = TaskListQuery(search: "匹配")
        func queried() -> Set<UUID> {
            Set(workspace.groups(for: .inbox, query: query).flatMap {
                workspace.nodes(for: $0, scope: .inbox, query: query).map(\.task.id)
            })
        }
        XCTAssertEqual(queried(), [seed[0].id])
        workspace.setDocument(seed[1].id, NativeDocument(plainText: "正文匹配"))
        XCTAssertEqual(queried(), Set(seed.map(\.id)))
        workspace.setTitle(seed[0].id, "已移出")
        XCTAssertEqual(queried(), [seed[1].id])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filters = FilterStore(directory: directory)
        let filter = SavedFilter(name: "关键词", keywords: ["匹配"])
        XCTAssertTrue(filters.add(filter))
        workspace.attachFilterStore(filters)
        workspace.activeFilterID = filter.id
        func filtered() -> Set<UUID> {
            Set(workspace.groups(for: .inbox).flatMap { workspace.nodes(for: $0, scope: .inbox).map(\.task.id) })
        }
        XCTAssertEqual(filtered(), [seed[1].id])
        workspace.setDocument(seed[1].id, NativeDocument(plainText: "不再命中"))
        XCTAssertTrue(filtered().isEmpty)
    }

    func testBusinessChangesInvalidateGroupingAndUndoRestoresIt() throws {
        let seed = tasks(["任务一", "任务二"])
        let workspace = TaskWorkspaceModel(clock: { self.date }, seedDemoData: false, initialTasks: seed)
        func groups() -> [TaskListGroup] { workspace.groups(for: .allTasks, grouping: .byPriority) }
        let initial = groups()
        let builds = workspace.projectionBuildCount
        workspace.setPriority(seed[0].id, .high)
        XCTAssertGreaterThan(groups().count, initial.count)
        XCTAssertGreaterThan(workspace.projectionBuildCount, builds)
        workspace.undo()
        XCTAssertEqual(groups().count, initial.count)
        XCTAssertEqual(workspace.task(for: seed[0].id)?.priority, TaskPriority.none)
    }
    func testChecklistTextWithDerivedCompletionStillInvalidatesMembership() throws {
        var seed = tasks(["检查任务"])[0]
        seed.kind = .checklist
        seed.document = NativeDocument(blocks: [DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "完成项")])])
        let workspace = TaskWorkspaceModel(clock: { self.date }, seedDemoData: false, initialTasks: [seed])
        _ = workspace.groups(for: .inbox, hidesCompleted: true)
        let builds = workspace.projectionBuildCount
        workspace.setDocument(seed.id, NativeDocument(blocks: [DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "完成项")])]))
        XCTAssertEqual(workspace.task(for: seed.id)?.status, .completed)
        let visible = workspace.groups(for: .inbox, hidesCompleted: true).flatMap(\.tasks)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertGreaterThan(workspace.projectionBuildCount, builds)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: seed.id)?.status, .active)
        XCTAssertEqual(workspace.groups(for: .inbox, hidesCompleted: true).flatMap(\.tasks).map(\.id), [seed.id])
    }

}
