import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FloatingEditorIntegrationTests: XCTestCase {
    private let windows = FloatingEditorWindowController.shared

    override func setUp() { super.setUp(); windows.closeAll() }
    override func tearDown() { windows.closeAll(); super.tearDown() }

    private func fixture() throws -> (AppEnvironment, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floating-editor-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        FloatingNoteWindowController.shared.attach(environment: environment)
        StickyNoteWindowController.shared.attach(environment: environment)
        return (environment, directory)
    }

    private func editor(in panel: FloatingEditorPanel) throws -> MilkdownWebView {
        try MilkdownTestSupport.editor(in: try XCTUnwrap(panel.contentView))
    }

    private func editors(in view: NSView) -> [MilkdownWebView] { MilkdownTestSupport.editors(in: view) }

    func testNotesTopButtonOpensNativeFloatingEditorAndReturnsOwnership() throws {
        let (environment, _) = try fixture()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "入口验收"; $0.document = NativeDocument(plainText: "正文") }
        environment.navigation.destination = .notes
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: root)
        let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { windows.closeAll(); owner.close() }
        InspectorPanelTestSupport.settle(owner)
        XCTAssertTrue(editors(in: host).contains { $0.documentIdentity == id })
        let trigger = try XCTUnwrap(frames[.detach])
        XCTAssertLessThan(trigger.maxY, 100, "浮窗应从编辑栏顶部独立按钮打开")
        XCTAssertGreaterThan(trigger.midX, 800)
        try InspectorPanelTestSupport.click(trigger, in: host, window: owner)
        let floating = try XCTUnwrap(windows.panel(for: .note(id)))
        XCTAssertEqual(try editor(in: floating).documentIdentity, id)
        InspectorPanelTestSupport.settle(owner)
        XCTAssertFalse(editors(in: host).contains { $0.documentIdentity == id },
                       "同一篇正文只保留一个可编辑宿主")
        FloatingNoteWindowController.shared.close(noteID: id)
        InspectorPanelTestSupport.settle(owner)
        XCTAssertTrue(editors(in: host).contains { $0.documentIdentity == id })
    }

    func testTaskAndNoteUseSharedWindowPolicyAndRemainIndependent() throws {
        let (environment, _) = try fixture()
        let taskID = try XCTUnwrap(environment.taskWorkspace.createTask(title: "任务", in: .inbox).taskID)
        let noteID = environment.notesWorkspace.create()
        StickyNoteWindowController.shared.open(taskID: taskID)
        FloatingNoteWindowController.shared.open(noteID: noteID)
        let task = try XCTUnwrap(windows.panel(for: .task(taskID)))
        let note = try XCTUnwrap(windows.panel(for: .note(noteID)))
        XCTAssertEqual(task.level, note.level)
        XCTAssertEqual(task.styleMask, note.styleMask)
        XCTAssertEqual(task.minSize, note.minSize)
        XCTAssertEqual(task.collectionBehavior, note.collectionBehavior)
        let taskEditor = try editor(in: task), noteEditor = try editor(in: note)
        try MilkdownTestSupport.command(taskEditor, "insertText", ["text": "任务正文"])
        try MilkdownTestSupport.command(noteEditor, "insertText", ["text": "笔记正文"])
        XCTAssertEqual(environment.taskWorkspace.task(for: taskID)?.document.plainText, "任务正文")
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == noteID }?.document.plainText, "笔记正文")
        StickyNoteWindowController.shared.closeAll()
        XCTAssertTrue(FloatingNoteWindowController.shared.isOpen(noteID))
        environment.notesWorkspace.delete(noteID)
        XCTAssertNil(windows.panel(for: .note(noteID)))
    }

    func testTaskInspectorTransfersBodyToFloatingEditorAndRestoresItOnClose() throws {
        let (environment, _) = try fixture()
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "任务编辑权", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let owner = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { windows.closeAll(); owner.close() }
        let mainEditor = try MilkdownTestSupport.editor(in: host, id: id)
        let client = try MilkdownTestSupport.inputClient(mainEditor)
        client.setMarkedText("切出组合", selectedRange: NSRange(location: 4, length: 0), replacementRange: client.selectedRange())
        InspectorPanelTestSupport.settle(owner)
        try InspectorPanelTestSupport.clickButton(containing: "打开浮窗", in: owner)
        let floating = try XCTUnwrap(windows.panel(for: .task(id)))
        let editor = try editor(in: floating)
        InspectorPanelTestSupport.settle(owner)
        XCTAssertFalse(editors(in: host).contains { $0.documentIdentity == id })
        XCTAssertEqual(editor.document.plainText, "切出组合")
        try MilkdownTestSupport.command(editor, "focusEnd")
        try MilkdownTestSupport.command(editor, "insertText", ["text": "回到主页后保留"])
        StickyNoteWindowController.shared.close(taskID: id)
        InspectorPanelTestSupport.settle(owner)
        let restored = try MilkdownTestSupport.editor(in: host, id: id)
        XCTAssertEqual(restored.document.plainText, "切出组合回到主页后保留")
    }

    func testNoteCloseCommitsCompositionAndPersistsRichDocument() throws {
        let (environment, directory) = try fixture()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) {
            $0.document = NativeDocument(blocks: [
                DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题", marks: [.bold])]),
                DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "甲")])
            ])
        }
        FloatingNoteWindowController.shared.open(noteID: id)
        let panel = try XCTUnwrap(windows.panel(for: .note(id)))
        let editor = try editor(in: panel)
        try MilkdownTestSupport.command(editor, "focusEnd")
        let client = try MilkdownTestSupport.inputClient(editor)
        client.setMarkedText("组合输入", selectedRange: NSRange(location: 4, length: 0), replacementRange: client.selectedRange())
        InspectorPanelTestSupport.settle(panel)
        FloatingNoteWindowController.shared.close(noteID: id)
        let saved = expectation(description: "Floating note persisted")
        environment.flush { error in XCTAssertNil(error); saved.fulfill() }
        wait(for: [saved], timeout: 5)
        let snapshot = try XCTUnwrap(NativePreviewRepository(directory: directory).load())
        let document = try XCTUnwrap(snapshot.tasks.first { $0.id == id }?.document)
        XCTAssertEqual(document.plainText, "标题\n甲组合输入")
        XCTAssertEqual(document.blocks[0].kind, .heading(1))
        XCTAssertTrue(document.blocks[0].runs[0].marks.contains(.bold))
    }
}
