import Foundation
import Combine
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagPresentationOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ title: String, tags: [String]) -> Task {
        Task(id: UUID(), title: title, tags: tags, list: .inbox, priority: .none,
             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    func testLegacyMissingDirectoryKeepsAlphabeticalOrderAndExistingPrimaryTags() {
        let first = task("原有首标签", tags: ["Zebra", "Apple"])
        let second = task("另一标签", tags: ["Apple"])
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
                                           initialTasks: [first, second])
        XCTAssertEqual(workspace.orderedTags.map(\.name), ["Apple", "Zebra"])
        XCTAssertEqual(QuickAddTagCatalog(tags: workspace.taskTags).names, ["Apple", "Zebra"])
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).map(\.label),
                       ["Apple", "Zebra"])
        XCTAssertEqual(workspace.task(for: first.id)?.tags, first.tags)
        XCTAssertFalse(workspace.canUndo)
    }

    func testDirectoryReorderAndUndoStayConsistentAcrossSidebarCandidatesAndColumns() throws {
        let parent = TaskTag(name: "Zebra", colorARGB: 0xFFB95D45, sortOrder: 0)
        let child = TaskTag(name: "Apple", colorARGB: 0xFF4587B9, parentID: parent.id)
        let other = TaskTag(name: "Middle", sortOrder: 1)
        let first = task("父标签任务", tags: [parent.name, other.name])
        let second = task("子标签任务", tags: [child.name])
        let third = task("其他标签任务", tags: [other.name])
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [first, second, third], initialTags: [other, child, parent])
        let originalTasks = workspace.allTasks

        func assertSharedOrder(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
            let sidebar = workspace.orderedTags.map(\.name)
            let candidates = QuickAddTagCatalog(tags: workspace.taskTags)
            XCTAssertEqual(sidebar, expected, file: file, line: line)
            XCTAssertEqual(QuickAddComposition.candidates(candidates.names, matching: ""), expected, file: file, line: line)
            XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).compactMap(\.label),
                           expected, file: file, line: line)
            XCTAssertEqual(candidates.colors[child.name], child.colorARGB, file: file, line: line)
            XCTAssertEqual(candidates.depths[child.name], 1, file: file, line: line)
            XCTAssertEqual(candidates.depths[parent.name], 0, file: file, line: line)
        }

        assertSharedOrder([parent.name, child.name, other.name])
        XCTAssertTrue(workspace.reorderTag(other.id, before: parent.id))
        assertSharedOrder([other.name, parent.name, child.name])
        XCTAssertEqual(workspace.allTasks, originalTasks)
        workspace.undo()
        assertSharedOrder([parent.name, child.name, other.name])
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        assertSharedOrder([other.name, parent.name, child.name])
    }

    func testTagProjectionAppendsUnknownNamesAlphabeticallyAndUntaggedLast() {
        let known = TaskTag(name: "Known", sortOrder: 1)
        let empty = TaskTag(name: "Empty", sortOrder: 0)
        let unknownB = task("未知乙", tags: ["Unknown B"])
        let tagged = task("已有标签", tags: [known.name, "Unknown B"])
        let unknownA = task("未知甲", tags: ["Unknown A"])
        let untagged = task("无标签", tags: [])
        let groups = TaskListProjection.tagGroups([unknownB, tagged, unknownA, untagged], directory: [known, empty])
        XCTAssertEqual(groups.compactMap(\.label), [known.name, "Unknown A", "Unknown B", "无标签"])
        XCTAssertEqual(groups.first?.tasks.map(\.id), [tagged.id])
        XCTAssertEqual(groups.last?.tasks.map(\.id), [untagged.id])
        XCTAssertEqual(tagged.tags, [known.name, "Unknown B"])
    }

    func testQuotedQuickAddTagUsesDirectoryIdentityAndUndoKeepsOriginalCatalog() throws {
        let tag = TaskTag(name: "客户 A", colorARGB: 0xFFB95D45, sortOrder: 4)
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
                                           initialTasks: [], initialTags: [tag])
        let text = QuickAddComposition.replacingTrailingMarker(in: "跟进 #客", with: tag.name)
        let id = try XCTUnwrap(workspace.submitCapture(QuickCaptureSession(text: text)).first)
        let created = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(created.title, "跟进")
        XCTAssertEqual(created.tags, [tag.name])
        XCTAssertEqual(created.tagReferences, [TaskTagReference(id: tag.id, name: tag.name)])
        XCTAssertEqual(workspace.taskTags, [tag])
        workspace.undo()
        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertEqual(workspace.taskTags, [tag])
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.task(for: id), created)
    }

    func testLegacyDirectoryFallbackKeepsAlphabeticalOrderWithoutReorderingTaskTags() {
        let source = task("旧导入任务", tags: ["Zebra", "Apple"])
        let tags = TaskTag.reconciled([], tasks: [source])
        XCTAssertEqual(TaskTag.ordered(tags).map(\.name), ["Apple", "Zebra"])
        let explicit = TaskTag(name: "Zebra", sortOrder: 0)
        let next = TaskTag.reconciled([explicit], tasks: [source])
        XCTAssertEqual(TaskTag.ordered(next).map(\.name), ["Zebra", "Apple"])
        XCTAssertEqual(source.tags, ["Zebra", "Apple"])
    }

    func testPendingPickerSelectionFollowsRenameAndUndoWithoutRecreatingOldTag() throws {
        let tag = TaskTag(name: "客户", colorARGB: 0xFF4587B9)
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [], initialTags: [tag])
        var selected: [String]? = [tag.name]
        let subscription = NotificationCenter.default.publisher(for: .workspaceOrganizationRenamed).sink {
            selected = QuickAddPropertiesOverrides.renamedTags(selected, notification: $0)
        }
        defer { subscription.cancel() }
        XCTAssertTrue(workspace.renameTag(tag.id, to: "客户 A"))
        XCTAssertEqual(selected, ["客户 A"])
        workspace.undo()
        XCTAssertEqual(selected, ["客户"])
        workspace.redo()
        let id = try XCTUnwrap(workspace.submitCapture(QuickCaptureSession(text: "跟进", tagsOverride: selected)).first)
        XCTAssertEqual(workspace.task(for: id)?.tagReferences, [TaskTagReference(id: tag.id, name: "客户 A")])
        XCTAssertEqual(workspace.taskTags.map(\.id), [tag.id])
        XCTAssertNil(workspace.tag(named: "客户"))
    }
}
