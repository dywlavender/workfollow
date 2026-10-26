import AppKit
import XCTest
@testable import WorkFollow

/// Real native editor input exercises the task transaction and undo path.
@MainActor
final class StickyNoteWindowTests: XCTestCase {
    private let controller = StickyNoteWindowController.shared
    private let windows = FloatingEditorWindowController.shared

    override func setUp() { super.setUp(); windows.closeAll() }
    override func tearDown() { windows.closeAll(); super.tearDown() }

    private func create(_ title: String, in workspace: TaskWorkspaceModel,
                        document: NativeDocument = .empty) throws -> UUID {
        let id = try XCTUnwrap(workspace.createTask(title: title, in: .inbox).taskID)
        _ = workspace.setDocument(id, document)
        return id
    }

    private func open(_ id: UUID, in workspace: TaskWorkspaceModel) throws -> (FloatingEditorPanel, NativeTextView) {
        controller.attach(workspace: workspace)
        controller.open(taskID: id)
        let panel = try XCTUnwrap(windows.panel(for: .task(id)))
        InspectorPanelTestSupport.settle(panel)
        try InspectorPanelTestSupport.waitUntil("Floating native editor did not load") {
            panel.editorHandle.textView?.window === panel
        }
        return (panel, try XCTUnwrap(panel.editorHandle.textView))
    }

    func testOpenRegistersSingleInstancePerTask() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try create("便签", in: workspace)
        let (panel, _) = try open(id, in: workspace)
        controller.open(taskID: id)
        XCTAssertEqual(controller.openTaskIDs, [id])
        XCTAssertTrue(windows.panel(for: .task(id)) === panel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testEditorWriteBackUpdatesStoreDocumentImmediately() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try create("便签", in: workspace)
        let (_, editor) = try open(id, in: workspace)
        editor.insertText("便签里改的内容", replacementRange: editor.selectedRange())
        XCTAssertEqual(workspace.task(for: id)?.document.plainText, "便签里改的内容")
    }

    func testStoreChangeFeedsBackToPanel() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try create("便签", in: workspace)
        let (panel, editor) = try open(id, in: workspace)
        _ = workspace.setDocument(id, NativeDocument(plainText: "主窗口改的"))
        InspectorPanelTestSupport.settle(panel)
        XCTAssertEqual(editor.string, "主窗口改的")
        XCTAssertEqual(editor.documentIdentity, id)
    }

    func testNativeEditingKeepsRichStructureAndSupportsUndo() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题", marks: [.bold])]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "父项")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "子项")], indentLevel: 1)
        ])
        let id = try create("富文本", in: workspace, document: document)
        let (panel, editor) = try open(id, in: workspace)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("追加", replacementRange: editor.selectedRange())
        InspectorPanelTestSupport.settle(panel)
        let updated = try XCTUnwrap(workspace.task(for: id)?.document)
        XCTAssertEqual(updated.blocks[0].kind, .heading(1))
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.bold))
        XCTAssertEqual(updated.blocks[2].indentLevel, 1)
        XCTAssertTrue(updated.plainText.hasSuffix("子项追加"))
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        editor.undo(nil)
        XCTAssertEqual(workspace.task(for: id)?.document.plainText, document.plainText)
    }

    func testCloseCommitsMarkedTextWithoutWaiting() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try create("关闭保存", in: workspace, document: NativeDocument(plainText: "甲"))
        let (_, editor) = try open(id, in: workspace)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.setMarkedText("组合输入", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        controller.close(taskID: id)
        XCTAssertEqual(workspace.task(for: id)?.document.plainText, "甲组合输入")
        XCTAssertFalse(controller.isOpen(id))
    }

    func testTaskDeleteClosesStickyNote() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try create("删除", in: workspace)
        _ = try open(id, in: workspace)
        _ = workspace.delete(id)
        XCTAssertFalse(controller.isOpen(id))
        XCTAssertNil(windows.panel(for: .task(id)))
    }

    func testMultipleEditorsStayBoundWhenMainSelectionChanges() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let a = try create("A", in: workspace), b = try create("B", in: workspace)
        let (_, first) = try open(a, in: workspace)
        controller.open(taskID: b)
        workspace.select(b)
        first.insertText("只写入 A", replacementRange: first.selectedRange())
        XCTAssertEqual(first.documentIdentity, a)
        XCTAssertEqual(workspace.task(for: a)?.document.plainText, "只写入 A")
        XCTAssertEqual(workspace.task(for: b)?.document.plainText, "")
        XCTAssertEqual(Set(controller.openTaskIDs), [a, b])
    }
}
