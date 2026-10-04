import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NativeResourceLinkTests: XCTestCase {
    func testTaskAndNoteURLsRoundTripAndBuiltAppDeclaresScheme() throws {
        for link in [NativeResourceLink.task(UUID()), .note(UUID())] {
            XCTAssertEqual(NativeResourceLink(url: link.url), link)
        }
        XCTAssertNil(NativeResourceLink(url: try XCTUnwrap(URL(string: "https://example.com/task"))))
        let declarations = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertTrue(declarations.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("workfollow") == true })
    }

    func testClipboardRoundTripUsesIsolatedPasteboard() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "复制链接", in: .inbox).taskID)
        let pasteboard = NSPasteboard(name: .init("workfollow-link-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(TaskLinkClipboard.copy(try XCTUnwrap(workspace.task(for: id)), to: pasteboard))
        let string = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertEqual(NativeResourceLink(url: try XCTUnwrap(URL(string: string))), .task(id))
    }

    func testTaskRouteClearsFiltersExpandsParentAndPreservesSelectedChildOnNavigation() throws {
        let tasks = TaskWorkspaceModel(seedDemoData: false)
        let notes = NotesWorkspaceModel(initialNotes: [], folders: [])
        let navigation = AppNavigation()
        let parent = try XCTUnwrap(tasks.createTask(title: "父任务", in: .inbox).taskID)
        let child = try XCTUnwrap(tasks.createChild(parent, title: "链接目标").taskID)
        tasks.toggleExpanded(parent)
        tasks.activeList = "不匹配清单"
        tasks.activeTag = "不匹配标签"
        tasks.activeFilterID = UUID()
        tasks.bulkSelection = [parent]
        XCTAssertTrue(NativeResourceLinkRouter.open(.task(child), tasks: tasks, notes: notes, navigation: navigation))
        XCTAssertEqual(navigation.destination, .allTasks)
        XCTAssertEqual(navigation.taskSelectionToPreserveOnNextNavigation, child)
        XCTAssertEqual(tasks.selectedTaskID, child)
        XCTAssertNil(tasks.activeList)
        XCTAssertNil(tasks.activeTag)
        XCTAssertNil(tasks.activeFilterID)
        XCTAssertTrue(tasks.bulkSelection.isEmpty)
        XCTAssertFalse(tasks.collapsedTaskIDs.contains(parent))
        navigation.taskSelectionToPreserveOnNextNavigation = nil // RootShell consumes this once.
        XCTAssertTrue(NativeResourceLinkRouter.open(.task(child), tasks: tasks, notes: notes, navigation: navigation))
        XCTAssertNil(navigation.taskSelectionToPreserveOnNextNavigation, "Same destination must not leave a stale preservation token")
        _ = tasks.complete(child)
        XCTAssertTrue(NativeResourceLinkRouter.open(.task(child), tasks: tasks, notes: notes, navigation: navigation))
        XCTAssertEqual(navigation.destination, .completed)
        let before = tasks.selectedTaskID
        XCTAssertFalse(NativeResourceLinkRouter.open(.task(UUID()), tasks: tasks, notes: notes, navigation: navigation))
        XCTAssertEqual(tasks.selectedTaskID, before)
    }

    func testExistingNoteLinksStillOpenAndColdLaunchDeliveryIsQueued() throws {
        let note = Note(id: UUID(), title: "已有笔记", document: .empty, folder: "", updatedAt: Date())
        let notes = NotesWorkspaceModel(initialNotes: [note], folders: [])
        let tasks = TaskWorkspaceModel(seedDemoData: false)
        let navigation = AppNavigation()
        let receiver = NativeResourceLinkReceiver()
        let url = NativeResourceLink.note(note.id).url
        receiver.receive([url])
        XCTAssertNil(notes.selectedID)
        var activations = 0
        receiver.configure(route: { url in
            guard let link = NativeResourceLink(url: url) else { return false }
            return NativeResourceLinkRouter.open(link, tasks: tasks, notes: notes, navigation: navigation)
        }, activate: { activations += 1 })
        XCTAssertEqual(notes.selectedID, note.id)
        XCTAssertEqual(navigation.destination, .notes)
        XCTAssertEqual(activations, 1)
        receiver.receive([url])
        XCTAssertEqual(activations, 2)
    }

    func testInspectorDuplicateEntryCreatesCopyAndClosesMenu() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "副本入口验收", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }

        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertEqual(more.frame.width, 208, accuracy: 1)
        try InspectorPanelTestSupport.clickButton(containing: "创建副本", in: more)
        XCTAssertFalse(InspectorPanelTestSupport.visibleWindows(below: window)
            .contains { $0.title == InspectorPanelTestSupport.actionPanelTitle })
        XCTAssertEqual(workspace.allTasks.count, 2)
        XCTAssertEqual(workspace.selectedTaskID, id)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks.count, 1)
    }
}
