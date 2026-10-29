import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 浮窗接管编辑权后，原编辑栏应保留同一套富文本排版，但不能再编辑。
@MainActor
final class FloatingReadOnlyPreviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StickyNoteWindowController.shared.closeAll()
        FloatingNoteWindowController.shared.closeAll()
    }

    override func tearDown() {
        StickyNoteWindowController.shared.closeAll()
        FloatingNoteWindowController.shared.closeAll()
        super.tearDown()
    }

    private func fixture() throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floating-readonly-preview-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        FloatingNoteWindowController.shared.attach(environment: environment)
        StickyNoteWindowController.shared.attach(environment: environment)
        return environment
    }

    private func editors(in view: NSView) -> [NativeTextView] {
        ([view as? NativeTextView].compactMap { $0 }) + view.subviews.flatMap { editors(in: $0) }
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        ([view as? NSTextField].compactMap { $0 }) + view.subviews.flatMap { textFields(in: $0) }
    }

    func testFloatingNoteLeavesRichReadOnlyPreviewInMainPane() throws {
        let environment = try fixture()
        let notes = environment.notesWorkspace
        let id = notes.create()
        notes.edit(id) {
            $0.title = "只读预览"
            $0.document = NativeDocument(blocks: [
                DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
                DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用")]),
                DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            ])
        }
        environment.navigation.destination = .notes
        let host = NSHostingView(rootView: NotesWorkspaceView(notes: notes,
            navigation: environment.navigation, tasks: environment.taskWorkspace)
            .environmentObject(environment).frame(width: 1100, height: 720))
        let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { FloatingNoteWindowController.shared.close(noteID: id); owner.close() }
        InspectorPanelTestSupport.settle(owner)
        XCTAssertTrue(editors(in: host).contains { $0.isEditable && $0.documentIdentity == id })

        FloatingNoteWindowController.shared.open(noteID: id)
        InspectorPanelTestSupport.settle(owner)
        let preview = try XCTUnwrap(editors(in: host).first { !$0.isEditable },
                                    "浮窗打开后主编辑栏应保留只读预览")
        XCTAssertEqual(preview.string, "标题\n引用\n正文", "预览必须是富文本投影，不是 plainText")
        XCTAssertEqual(preview.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0,
                                                      effectiveRange: nil) as? String, "h1")
        XCTAssertEqual(preview.textStorage?.attribute(DocumentTextCodec.blockKey, at: 3,
                                                      effectiveRange: nil) as? String, "quote")
        XCTAssertTrue(preview.isSelectable)
        XCTAssertFalse(editors(in: host).contains { $0.isEditable && $0.documentIdentity == id })

        preview.setSelectedRange(NSRange(location: 0, length: 2))
        preview.refreshSelectionToolbar()
        XCTAssertNil(preview.selectionPanel, "只读预览不应弹出格式浮条")

        // 浮窗里的编辑要实时反映到原编辑栏的只读预览。
        let floating = try XCTUnwrap(FloatingEditorWindowController.shared.panel(for: .note(id)))
        InspectorPanelTestSupport.settle(floating)
        let floatingEditor = try XCTUnwrap(floating.editorHandle.textView)
        floatingEditor.setSelectedRange(NSRange(location: floatingEditor.string.utf16.count, length: 0))
        floatingEditor.insertText("新增", replacementRange: floatingEditor.selectedRange())
        InspectorPanelTestSupport.settle(owner)
        let refreshed = try XCTUnwrap(editors(in: host).first { !$0.isEditable })
        XCTAssertTrue(refreshed.string.contains("新增"), "预览应跟随浮窗内容更新")
        XCTAssertFalse(refreshed.isEditable)
    }

    func testFloatingTaskLeavesRichReadOnlyPreviewAndFreezesTitle() throws {
        let environment = try fixture()
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "浮窗只读", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
        ]))
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let owner = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { StickyNoteWindowController.shared.close(taskID: id); owner.close() }
        InspectorPanelTestSupport.settle(owner)
        let editableTitle = try XCTUnwrap(textFields(in: host).first { $0.accessibilityLabel() == "任务标题" })
        XCTAssertTrue(editableTitle.isEditable)

        StickyNoteWindowController.shared.open(taskID: id)
        InspectorPanelTestSupport.settle(owner)
        let preview = try XCTUnwrap(editors(in: host).first { !$0.isEditable },
                                    "浮窗打开后任务详情应保留只读预览")
        XCTAssertEqual(preview.string, "标题\n正文")
        XCTAssertEqual(preview.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0,
                                                      effectiveRange: nil) as? String, "h1")
        let readOnlyTitle = try XCTUnwrap(textFields(in: host).first { $0.accessibilityLabel() == "任务标题" })
        XCTAssertFalse(readOnlyTitle.isEditable, "浮窗接管期间标题也不能编辑")
        XCTAssertEqual(readOnlyTitle.stringValue, "浮窗只读")

        StickyNoteWindowController.shared.close(taskID: id)
        InspectorPanelTestSupport.settle(owner)
        let restoredTitle = try XCTUnwrap(textFields(in: host).first { $0.accessibilityLabel() == "任务标题" })
        XCTAssertTrue(restoredTitle.isEditable)
        XCTAssertTrue(editors(in: host).contains { $0.isEditable && $0.documentIdentity == id })
    }
}
