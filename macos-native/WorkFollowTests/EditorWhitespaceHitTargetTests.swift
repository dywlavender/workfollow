import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorWhitespaceHitTargetTests: XCTestCase {
    private struct Fixture {
        let window: NSWindow
        let host: NSView
        let editor: NativeTextView
    }

    override func tearDown() {
        FloatingEditorWindowController.shared.closeAll()
        super.tearDown()
    }

    private func fixture(_ document: NativeDocument, width: CGFloat = 400) throws -> Fixture {
        let id = UUID(), handle = DocumentEditorHandle()
        let root = DocumentEditor(documentID: id, document: document, onDocumentChange: { _ in },
            onEscape: { .endEditing }, onEditingChanged: { _ in }, contentSized: true, handle: handle)
            .padding(.horizontal, 28)
            .frame(width: width, height: 360, alignment: .topLeading)
            .background(EditorWhitespaceHitTarget(handle: handle, documentID: id))
        let host = NSHostingView(rootView: root)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 360)
        return Fixture(window: window, host: host, editor: try XCTUnwrap(handle.textView))
    }

    private func editor(in view: NSView, id: UUID) -> NativeTextView? {
        if let value = view as? NativeTextView, value.documentIdentity == id { return value }
        return view.subviews.lazy.compactMap { self.editor(in: $0, id: id) }.first
    }

    private func whitespaceTarget(in view: NSView) -> EditorWhitespaceHitTarget.TargetView? {
        if let target = view as? EditorWhitespaceHitTarget.TargetView { return target }
        return view.subviews.lazy.compactMap { self.whitespaceTarget(in: $0) }.first
    }

    private func click(_ point: NSPoint, in editor: NativeTextView, window: NSWindow) throws {
        try InspectorPanelTestSupport.click(NSRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1),
                                           in: editor, window: window)
    }

    private func makeEnvironment() -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-whitespace-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppEnvironment(directory: directory)
    }

    func testHostGuttersChooseTheNearestLineRatherThanTheDocumentEnd() throws {
        let text = "第一行\n第二行文字\n最后一行"
        let fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let range = (text as NSString).range(of: "第二行文字")
        let line = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: range.location))
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: -20, y: line.midY)), range.location)
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: fixture.editor.bounds.maxX + 20,
                                                                     y: line.midY)), NSMaxRange(range))
    }

    func testWrappedParagraphUsesTheNearestVisualLine() throws {
        let text = String(repeating: "甲乙丙丁戊己庚辛壬癸", count: 8)
        let fixture = try fixture(NativeDocument(plainText: text), width: 260)
        defer { fixture.window.close() }
        let line = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: 24))
        let lastOnLine = try XCTUnwrap((0..<text.utf16.count).last {
            guard let rect = fixture.editor.viewRect(forCharacterAt: $0) else { return false }
            return abs(rect.midY - line.midY) < 0.5
        })
        XCTAssertLessThan(lastOnLine + 1, text.utf16.count)
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: fixture.editor.bounds.maxX + 20,
                                                                     y: line.midY)), lastOnLine + 1)
    }

    func testEmptyParagraphsAndTrailingEmptyLineKeepTheirOwnInsertionPoints() throws {
        let text = "甲\n\n\n乙\n"
        let fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let empty = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: 2))
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: fixture.editor.bounds.maxX + 20,
                                                                     y: empty.midY)), 2)
        let last = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: text.utf16.count))
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: 1, y: last.midY)), text.utf16.count)
    }

    func testChecklistSpacingUsesTheCloserRow() throws {
        let fixture = try fixture(NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")])
        ]))
        defer { fixture.window.close() }
        let first = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: 0))
        let second = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: 2))
        XCTAssertGreaterThan(second.minY, first.maxY + 2)
        let x = fixture.editor.bounds.maxX + 20
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: x, y: first.maxY + 1)), 1)
        XCTAssertEqual(fixture.editor.insertionIndex(nearest: NSPoint(x: x, y: second.minY - 1)), 3)
    }

    func testNativeClicksInsideTheEditorStillSelectTheClosestLine() throws {
        let text = "第一行\n第二行文字\n最后一行"
        let fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let range = (text as NSString).range(of: "第二行文字")
        let line = try XCTUnwrap(fixture.editor.viewRect(forCharacterAt: range.location))
        for (x, expected) in [(fixture.editor.bounds.maxX - 4, NSMaxRange(range)), (20.0, range.location)] {
            let point = fixture.editor.convert(NSPoint(x: x, y: line.midY), to: nil)
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            NSApp.postEvent(try event(.leftMouseUp), atStart: true)
            fixture.editor.mouseDown(with: try event(.leftMouseDown))
            XCTAssertEqual(fixture.editor.selectedRange(), NSRange(location: expected, length: 0))
        }
    }

    func testWhitespaceSupportsShiftSelectionAndDraggingWithoutChangingContent() throws {
        let text = "第一行\n第二行文字\n最后一行"
        let fixture = try fixture(NativeDocument(plainText: text))
        defer { fixture.window.close() }
        let editor = fixture.editor
        let first = try XCTUnwrap(editor.viewRect(forCharacterAt: 0))
        let range = (text as NSString).range(of: "第二行文字")
        let second = try XCTUnwrap(editor.viewRect(forCharacterAt: range.location))
        let point = NSPoint(x: editor.bounds.maxX + 3, y: second.midY)
        let hit = try XCTUnwrap(fixture.host.hitTest(
            try XCTUnwrap(fixture.host.superview).convert(point, from: editor))
            as? EditorWhitespaceHitTarget.TargetView)
        func event(_ type: NSEvent.EventType, at point: NSPoint,
                   modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: editor.convert(point, to: nil),
                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        hit.mouseDown(with: try event(.leftMouseDown, at: point, modifiers: [.shift]))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: NSMaxRange(range) - 1))
        hit.mouseUp(with: try event(.leftMouseUp, at: point))
        hit.mouseDown(with: try event(.leftMouseDown, at: point))
        let start = NSPoint(x: -3, y: first.midY)
        hit.mouseDragged(with: try event(.leftMouseDragged, at: start))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: NSMaxRange(range)))
        hit.mouseUp(with: try event(.leftMouseUp, at: start))
        XCTAssertEqual(editor.string, text)
    }

    func testCursorStaysInsideEditorSoLinkedSectionsKeepTheArrow() throws {
        let fixture = try fixture(NativeDocument(plainText: "第一行\n第二行文字"))
        defer { fixture.window.close() }
        let target = try XCTUnwrap(whitespaceTarget(in: fixture.host))
        let editorFrame = target.convert(fixture.editor.bounds, from: fixture.editor)
        let spaces = target.cursorSpaces(for: fixture.editor)
        XCTAssertFalse(spaces.isEmpty)
        XCTAssertTrue(spaces.allSatisfy { $0.maxY <= editorFrame.maxY + 0.5 })
    }

    func testTaskWhitespaceReceivesClicksWithoutClaimingTitleSubtasksOrSidebar() throws {
        let environment = makeEnvironment(), workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let text = "第一行\n第二行文字\n最后一行"
        _ = workspace.setDocument(id, NativeDocument(plainText: text))
        _ = workspace.createChild(id, title: "子任务")
        environment.openTask(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.close() }
        let editor = try XCTUnwrap(editor(in: host, id: id))
        let range = (text as NSString).range(of: "第二行文字")
        let line = try XCTUnwrap(editor.viewRect(forCharacterAt: range.location))
        let point = NSPoint(x: editor.bounds.maxX + 3, y: line.midY)
        let hit = host.hitTest(try XCTUnwrap(host.superview).convert(point, from: editor))
        XCTAssertTrue(hit is EditorWhitespaceHitTarget.TargetView)
        window.makeFirstResponder(nil)
        try click(point, in: editor, window: window)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: NSMaxRange(range), length: 0))
        let add = try XCTUnwrap(frames[.addChild])
        let before = workspace.allTasks.filter { $0.parentID == id }.count
        try InspectorPanelTestSupport.click(add, in: host, window: window)
        XCTAssertEqual(workspace.allTasks.filter { $0.parentID == id }.count, before + 1)
        let sidebar = try XCTUnwrap(host.superview).convert(NSPoint(x: 20, y: 180), from: host)
        XCTAssertFalse(host.hitTest(sidebar) is EditorWhitespaceHitTarget.TargetView)
        let title = try XCTUnwrap(frames[.title])
        let titlePoint = try XCTUnwrap(host.superview).convert(NSPoint(x: title.midX, y: title.midY), from: host)
        XCTAssertFalse(host.hitTest(titlePoint) is EditorWhitespaceHitTarget.TargetView)
    }

    func testNotesAndFloatingEditorPlaceCaretOnClosestLineAndAtBottom() throws {
        let environment = makeEnvironment()
        let notes = environment.notesWorkspace
        let id = notes.create()
        let text = "第一行\n第二行文字\n最后一行"
        notes.edit(id) { $0.title = "空白点击"; $0.document = NativeDocument(plainText: text) }
        environment.navigation.destination = .notes
        FloatingNoteWindowController.shared.attach(environment: environment)
        let host = NSHostingView(rootView: NotesWorkspaceView(notes: notes, navigation: environment.navigation,
            tasks: environment.taskWorkspace).environmentObject(environment).frame(width: 1100, height: 720))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { FloatingNoteWindowController.shared.close(noteID: id); window.close() }
        let main = try XCTUnwrap(editor(in: host, id: id))
        let range = (text as NSString).range(of: "第二行文字")
        let line = try XCTUnwrap(main.viewRect(forCharacterAt: range.location))
        try click(NSPoint(x: main.bounds.maxX + 3, y: line.midY), in: main, window: window)
        XCTAssertEqual(main.selectedRange(), NSRange(location: NSMaxRange(range), length: 0))
        FloatingNoteWindowController.shared.open(noteID: id)
        let floating = try XCTUnwrap(FloatingEditorWindowController.shared.panel(for: .note(id)))
        InspectorPanelTestSupport.settle(floating)
        let native = try XCTUnwrap(floating.editorHandle.textView)
        let nativeLine = try XCTUnwrap(native.viewRect(forCharacterAt: range.location))
        try click(NSPoint(x: native.bounds.maxX + 3, y: nativeLine.midY), in: native, window: floating)
        XCTAssertEqual(native.selectedRange(), NSRange(location: NSMaxRange(range), length: 0))
        try click(NSPoint(x: native.bounds.midX, y: native.bounds.maxY + 24), in: native, window: floating)
        XCTAssertEqual(native.selectedRange(), NSRange(location: text.utf16.count, length: 0))
        XCTAssertEqual(notes.notes.first { $0.id == id }?.document.plainText, text)
    }
}
