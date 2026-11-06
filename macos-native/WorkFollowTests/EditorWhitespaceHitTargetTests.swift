import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorWhitespaceHitTargetTests: XCTestCase {
    private struct Fixture { let window: NSWindow; let host: NSView; let editor: MilkdownWebView }
    override func tearDown() { FloatingEditorWindowController.shared.closeAll(); super.tearDown() }

    private func fixture(_ document: NativeDocument, width: CGFloat = 400) throws -> Fixture {
        let id = UUID(), handle = DocumentEditorHandle()
        let host = NSHostingView(rootView: DocumentEditor(documentID: id, document: document,
            onDocumentChange: { _ in }, onEscape: { .endEditing }, onEditingChanged: { _ in }, contentSized: true, handle: handle)
            .padding(.horizontal, 28).frame(width: width, height: 360, alignment: .topLeading)
            .background(EditorWhitespaceHitTarget(handle: handle, documentID: id)))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 360)
        return Fixture(window: window, host: host, editor: try MilkdownTestSupport.editor(in: host))
    }
    private func target(in view: NSView) -> EditorWhitespaceHitTarget.TargetView? {
        (view as? EditorWhitespaceHitTarget.TargetView) ?? view.subviews.lazy.compactMap { self.target(in: $0) }.first
    }
    private func nearest(_ editor: MilkdownWebView, x: CGFloat, y: CGFloat) throws -> Int {
        try MilkdownTestSupport.command(editor, "hostPointer", ["x": x, "y": y, "phase": "down"])
        return try MilkdownTestSupport.range(editor).location
    }
    private func blockRect(_ editor: MilkdownWebView, index: Int) throws -> NSRect {
        let data = try XCTUnwrap(MilkdownTestSupport.script(editor, "(() => { const r=document.querySelectorAll('.wf-block-content')[\(index)].getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })()") as? [String: CGFloat])
        return NSRect(x: data["x"]!, y: data["y"]!, width: data["width"]!, height: data["height"]!)
    }
    private func click(_ point: NSPoint, in editor: MilkdownWebView, window: NSWindow) throws {
        try InspectorPanelTestSupport.click(NSRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1), in: editor, window: window)
    }
    private func nativePoint(_ point: NSPoint, editor: MilkdownWebView) -> NSPoint {
        NSPoint(x: point.x, y: editor.isFlipped ? point.y : editor.bounds.height - point.y)
    }
    private func environment() -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("editor-whitespace-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppEnvironment(directory: directory)
    }

    func testHostGuttersChooseTheNearestLineRatherThanTheDocumentEnd() throws {
        let text = "第一行\n第二行文字\n最后一行", fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let range = (text as NSString).range(of: "第二行文字"), rect = try blockRect(fixture.editor, index: 1)
        XCTAssertEqual(try nearest(fixture.editor, x: -20, y: rect.midY), range.location)
        XCTAssertEqual(try nearest(fixture.editor, x: fixture.editor.bounds.width + 20, y: rect.midY), NSMaxRange(range))
    }
    func testWrappedParagraphUsesTheNearestVisualLine() throws {
        let text = String(repeating: "甲乙丙丁戊己庚辛壬癸", count: 8), fixture = try fixture(NativeDocument(plainText: text), width: 260)
        defer { fixture.window.close() }
        let line = try MilkdownTestSupport.characterRect(fixture.editor, at: 24)
        var last = 24
        for index in 25..<text.utf16.count {
            let rect = try MilkdownTestSupport.characterRect(fixture.editor, at: index)
            if abs(rect.midY - line.midY) > 1 { break }; last = index
        }
        XCTAssertLessThan(last + 1, text.utf16.count)
        XCTAssertEqual(try nearest(fixture.editor, x: fixture.editor.bounds.width + 20, y: line.midY), last + 1)
    }
    func testEmptyParagraphsAndTrailingEmptyLineKeepTheirOwnInsertionPoints() throws {
        let text = "甲\n\n\n乙\n", fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let empty = try blockRect(fixture.editor, index: 1), last = try blockRect(fixture.editor, index: 4)
        XCTAssertEqual(try nearest(fixture.editor, x: fixture.editor.bounds.width + 20, y: empty.midY), 2)
        XCTAssertEqual(try nearest(fixture.editor, x: 1, y: last.midY), text.utf16.count)
    }
    func testChecklistSpacingUsesTheCloserRow() throws {
        let fixture = try fixture(NativeDocument(blocks: [.init(kind: .checklist(false), runs: [.init(text: "甲")]), .init(kind: .checklist(false), runs: [.init(text: "乙")])]))
        defer { fixture.window.close() }
        let first = try blockRect(fixture.editor, index: 0), second = try blockRect(fixture.editor, index: 1), x = fixture.editor.bounds.width + 20
        XCTAssertGreaterThan(second.minY, first.maxY + 2)
        XCTAssertEqual(try nearest(fixture.editor, x: x, y: first.maxY + 1), 1)
        XCTAssertEqual(try nearest(fixture.editor, x: x, y: second.minY - 1), 3)
    }
    func testPointerInsideTheEditorStillSelectsTheClosestLine() throws {
        let text = "第一行\n第二行文字\n最后一行", fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let range = (text as NSString).range(of: "第二行文字"), line = try blockRect(fixture.editor, index: 1)
        for (x, expected) in [(fixture.editor.bounds.width - 4, NSMaxRange(range)), (20.0, range.location)] {
            try click(NSPoint(x: x, y: line.midY), in: fixture.editor, window: fixture.window)
            try MilkdownTestSupport.wait("正文点击未定位") { (try? MilkdownTestSupport.range(fixture.editor)) == NSRange(location: expected, length: 0) }
        }
    }
    func testWhitespaceSupportsShiftSelectionAndDraggingWithoutChangingContent() throws {
        let text = "第一行\n第二行文字\n最后一行", fixture = try fixture(NativeDocument(plainText: text)), editor = fixture.editor
        defer { fixture.window.close() }
        let range = (text as NSString).range(of: "第二行文字"), first = try blockRect(editor, index: 0), second = try blockRect(editor, index: 1)
        let point = NSPoint(x: editor.bounds.width + 3, y: second.midY)
        let hit = try XCTUnwrap(target(in: fixture.host))
        func event(_ type: NSEvent.EventType, point: NSPoint, shift: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: editor.convert(nativePoint(point, editor: editor), to: nil),
                modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        try MilkdownTestSupport.select(editor, NSRange(location: 1, length: 0))
        hit.mouseDown(with: try event(.leftMouseDown, point: point, shift: true))
        try MilkdownTestSupport.wait("Shift 点击未扩展选区") { (try? MilkdownTestSupport.range(editor)) == NSRange(location: 1, length: NSMaxRange(range) - 1) }
        hit.mouseUp(with: try event(.leftMouseUp, point: point))
        hit.mouseDown(with: try event(.leftMouseDown, point: point))
        hit.mouseDragged(with: try event(.leftMouseDragged, point: NSPoint(x: -3, y: first.midY)))
        try MilkdownTestSupport.wait("空白拖选未扩展选区") { (try? MilkdownTestSupport.range(editor)) == NSRange(location: 0, length: NSMaxRange(range)) }
        hit.mouseUp(with: try event(.leftMouseUp, point: point))
        XCTAssertEqual(editor.document.plainText, text)
    }
    func testCursorStaysInsideEditorSoLinkedSectionsKeepTheArrow() throws {
        let fixture = try fixture(NativeDocument(plainText: "第一行\n第二行文字"))
        defer { fixture.window.close() }
        let target = try XCTUnwrap(target(in: fixture.host)), rect = target.convert(fixture.editor.bounds, from: fixture.editor)
        let spaces = target.cursorSpaces(for: fixture.editor)
        XCTAssertFalse(spaces.isEmpty)
        XCTAssertTrue(spaces.allSatisfy { $0.maxY <= rect.maxY + 0.5 })
    }
    func testTaskWhitespaceReceivesClicksWithoutClaimingTitleSubtasksOrSidebar() throws {
        let environment = environment(), workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(plainText: "第一行\n第二行文字\n最后一行")); _ = workspace.createChild(id, title: "子任务")
        environment.openTask(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).coordinateSpace(name: "inspector-render").onPreferenceChange(InspectorFramesKey.self) { frames = $0 }.frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.close() }
        let editor = try MilkdownTestSupport.editor(in: host, id: id), line = try blockRect(editor, index: 1)
        try click(NSPoint(x: editor.bounds.width + 3, y: line.midY), in: editor, window: window)
        try MilkdownTestSupport.wait("任务空白点击未定位") { (try? MilkdownTestSupport.range(editor)) == NSRange(location: 9, length: 0) }
        XCTAssertTrue(MilkdownTestSupport.isFocused(editor))
        let before = workspace.allTasks.filter { $0.parentID == id }.count
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.addChild]), in: host, window: window)
        XCTAssertEqual(workspace.allTasks.filter { $0.parentID == id }.count, before + 1)
        let sidebar = try XCTUnwrap(host.superview).convert(NSPoint(x: 20, y: 180), from: host)
        XCTAssertFalse(host.hitTest(sidebar) is EditorWhitespaceHitTarget.TargetView)
        let title = try XCTUnwrap(frames[.title])
        let titlePoint = try XCTUnwrap(host.superview).convert(NSPoint(x: title.midX, y: title.midY), from: host)
        XCTAssertFalse(host.hitTest(titlePoint) is EditorWhitespaceHitTarget.TargetView)
    }
    func testNotesAndFloatingEditorPlaceCaretOnClosestLineAndAtBottom() throws {
        let environment = environment(), notes = environment.notesWorkspace, id = notes.create(), text = "第一行\n第二行文字\n最后一行"
        notes.edit(id) { $0.title = "空白点击"; $0.document = NativeDocument(plainText: text) }
        environment.navigation.destination = .notes; FloatingNoteWindowController.shared.attach(environment: environment)
        let host = NSHostingView(rootView: NotesWorkspaceView(notes: notes, navigation: environment.navigation, tasks: environment.taskWorkspace).environmentObject(environment).frame(width: 1100, height: 720))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { FloatingNoteWindowController.shared.close(noteID: id); window.close() }
        let main = try MilkdownTestSupport.editor(in: host, id: id), line = try blockRect(main, index: 1)
        try click(NSPoint(x: main.bounds.width + 3, y: line.midY), in: main, window: window)
        try MilkdownTestSupport.wait("笔记空白点击未定位") { (try? MilkdownTestSupport.range(main)) == NSRange(location: 9, length: 0) }
        FloatingNoteWindowController.shared.open(noteID: id)
        let floating = try XCTUnwrap(FloatingEditorWindowController.shared.panel(for: .note(id)))
        let body = try MilkdownTestSupport.editor(in: try XCTUnwrap(floating.contentView)), row = try blockRect(body, index: 1)
        try click(NSPoint(x: body.bounds.width + 3, y: row.midY), in: body, window: floating)
        try MilkdownTestSupport.wait("浮窗空白点击未定位") { (try? MilkdownTestSupport.range(body)) == NSRange(location: 9, length: 0) }
        try click(NSPoint(x: body.bounds.midX, y: body.bounds.height + 24), in: body, window: floating)
        try MilkdownTestSupport.wait("浮窗底部空白未定位文末") { (try? MilkdownTestSupport.range(body)) == NSRange(location: text.utf16.count, length: 0) }
        XCTAssertEqual(notes.notes.first { $0.id == id }?.document.plainText, text)
    }
}
