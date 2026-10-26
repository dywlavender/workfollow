import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRowTitleFocusTests: XCTestCase {
    func testSingleClickEditsTitleAndOpensMatchingInspectorInProductionShell() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-title-focus-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(seed.createTask(title: "第一条待改标题", in: .inbox).taskID)
        let second = try XCTUnwrap(seed.createTask(title: "第二条待改标题", in: .inbox).taskID)
        try NativePreviewRepository(directory: directory)
            .save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        environment.navigation.destination = .inbox
        let workspace = environment.taskWorkspace
        var frames: [TaskTreeRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.recordsTaskTreeFrames, true)
            .coordinateSpace(name: "task-tree-render")
            .onPreferenceChange(TaskTreeFramesKey.self) { frames = $0 }
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.close() }
        func clickTitle(_ id: UUID) throws {
            try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.init(taskID: id, part: .title)]),
                                               in: host, window: window)
        }
        func inspector(in view: NSView) -> NativeTextView? {
            if let native = view as? NativeTextView { return native }
            return view.subviews.lazy.compactMap { inspector(in: $0) }.first
        }
        try clickTitle(first)
        let firstField = try XCTUnwrap(titleFields(in: host).first { $0.stringValue == "第一条待改标题" })
        XCTAssertTrue(window.firstResponder === firstField.currentEditor())
        XCTAssertEqual(workspace.selectedTaskID, first)
        XCTAssertEqual(inspector(in: host)?.documentIdentity, first)
        let editor = try XCTUnwrap(firstField.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("已经修改的第一条", replacementRange: editor.selectedRange())

        try clickTitle(second)
        XCTAssertEqual(workspace.task(for: first)?.title, "已经修改的第一条")
        XCTAssertEqual(workspace.selectedTaskID, second)
        XCTAssertEqual(inspector(in: host)?.documentIdentity, second)
        let secondField = try XCTUnwrap(titleFields(in: host).first { $0.stringValue == "第二条待改标题" })
        XCTAssertTrue(window.firstResponder === secondField.currentEditor())
        XCTAssertFalse(firstField.editingSession)
        try clickTitle(second)
        XCTAssertEqual(workspace.selectedTaskID, second, "再次点击当前任务不能收起详情")
        XCTAssertTrue(window.firstResponder === secondField.currentEditor())
        XCTAssertEqual(inspector(in: host)?.documentIdentity, second)
    }

    func testDeferredFocusRestoreDoesNotTakeFocusBackFromTheNextTask() throws {
        var committed: String?
        let host = NSHostingView(rootView: VStack {
            TaskRowTitleField(title: "第一条任务", color: .primary,
                onEditingRequested: {}, onEditingBegan: {},
                onEditingEnded: {}, onCommit: { committed = $0 }).frame(height: 30)
            TaskRowTitleField(title: "第二条任务", color: .primary,
                onEditingRequested: {}, onEditingBegan: {},
                onEditingEnded: {}, onCommit: { _ in }).frame(height: 30)
        })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 90)
        defer { window.close() }
        let fields = titleFields(in: host)
        let first = try XCTUnwrap(fields.first { $0.stringValue == "第一条任务" })
        let second = try XCTUnwrap(fields.first { $0.stringValue == "第二条任务" })
        defer { first.editingSession = false; second.editingSession = false }
        first.editingSession = true
        first.selectText(nil)
        try XCTUnwrap(first.currentEditor()).string = "第一条的修改"
        second.editingSession = true
        second.selectText(nil)
        // A selection refresh can have queued this callback before focus moved.
        first.restoreEditingFocus()
        XCTAssertTrue(window.firstResponder === second.currentEditor())
        XCTAssertNotNil(second.currentEditor())
        XCTAssertFalse(first.editingSession)
        XCTAssertEqual(committed, "第一条的修改")
    }

    func testDeferredFocusRestoreDoesNotTakeFocusFromTheDetailBody() throws {
        let titleHost = NSHostingView(rootView: TaskRowTitleField(title: "任务", color: .primary,
            onEditingRequested: {}, onEditingBegan: {},
            onEditingEnded: {}, onCommit: { _ in }).frame(height: 30))
        let body = NativeTextView(frame: CGRect(x: 0, y: 40, width: 390, height: 60), textContainer: nil)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        titleHost.frame = CGRect(x: 0, y: 0, width: 390, height: 30)
        host.addSubview(titleHost); host.addSubview(body)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 100)
        defer { window.close() }
        let field = try XCTUnwrap(titleFields(in: host).first)
        defer { field.editingSession = false }
        field.editingSession = true
        field.selectText(nil)
        XCTAssertTrue(window.makeFirstResponder(body))
        field.restoreEditingFocus()
        XCTAssertTrue(window.firstResponder === body)
        XCTAssertFalse(field.editingSession)
    }

    private func titleFields(in view: NSView) -> [TaskRowTitleField.Field] {
        if let field = view as? TaskRowTitleField.Field { return [field] }
        return view.subviews.flatMap { titleFields(in: $0) }
    }
}
