import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskInspectorSelectionTests: XCTestCase {
    func testTaskSwitchingInTheRealWorkspaceRetainsListAndEditorHosts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-selection-workspace-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(seed.createTask(title: "第一条任务", in: .inbox).taskID)
        let second = try XCTUnwrap(seed.createTask(title: "第二条任务", in: .inbox).taskID)
        _ = seed.setDocument(first, NativeDocument(plainText: "第一条的正文"))
        _ = seed.setDocument(second, NativeDocument(plainText: "第二条的正文\n第二段"))
        try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.navigation.destination = .inbox
        let workspace = environment.taskWorkspace
        workspace.setTaskListPaneWidth(390)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 820)
        defer { window.close() }
        func outline(_ view: NSView) -> NSOutlineView? {
            if let value = view as? NSOutlineView { return value }
            return view.subviews.lazy.compactMap { outline($0) }.first
        }
        func editor(_ view: NSView) -> NativeTextView? {
            if let value = view as? NativeTextView { return value }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        let list = try XCTUnwrap(outline(host))
        XCTAssertEqual(list.frame.width, 390, accuracy: 1)
        var editorHost: NativeTextView?
        for id in [first, second, first, second] {
            workspace.select(id)
            InspectorPanelTestSupport.settle(window)
            XCTAssertEqual(workspace.selectedTaskID, id)
            let current = try XCTUnwrap(editor(host))
            XCTAssertEqual(current.documentIdentity, id)
            XCTAssertEqual(current.string, seed.task(for: id)?.document.plainText)
            if let editorHost { XCTAssertTrue(current === editorHost) }
            else { editorHost = current }
            XCTAssertTrue(outline(host) === list)
            XCTAssertEqual(list.frame.width, 390, accuracy: 1)
        }
        workspace.select(nil)
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(outline(host) === list)
        XCTAssertEqual(list.frame.width, 390, accuracy: 1)
        XCTAssertEqual(workspace.task(for: first)?.title, seed.task(for: first)?.title)
        XCTAssertEqual(workspace.task(for: second)?.title, seed.task(for: second)?.title)
    }

    func testSwitchingTasksReusesTheInspectorWithoutChangingTitlesOrDocuments() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "短任务", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: String(repeating: "需要换行的任务标题", count: 8), in: .inbox).taskID)
        let third = try XCTUnwrap(workspace.createTask(title: "带子任务的任务", in: .inbox).taskID)
        _ = workspace.setDocument(first, NativeDocument(plainText: "第一条任务的正文"))
        _ = workspace.setDocument(second, NativeDocument(plainText: (1...60).map { "第\($0)段正文" }.joined(separator: "\n")))
        _ = workspace.createChild(third, title: "检查子任务")
        let ids = [first, second, third]
        let originals = ids.compactMap { workspace.task(for: $0) }
        workspace.select(first)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, width: 500)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 500)
        defer { window.close() }
        func editor(_ view: NSView) -> NativeTextView? {
            if let value = view as? NativeTextView { return value }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        let initialEditor = try XCTUnwrap(editor(host))
        for id in ids + ids.reversed() {
            workspace.select(id)
            InspectorPanelTestSupport.settle(window)
            let current = try XCTUnwrap(editor(host))
            XCTAssertTrue(current === initialEditor)
            XCTAssertEqual(current.documentIdentity, id)
            XCTAssertEqual(current.string, workspace.task(for: id)?.document.plainText)
        }
        XCTAssertEqual(ids.compactMap { workspace.task(for: $0) }, originals)
    }
}
