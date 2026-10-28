import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NativeTextViewTests: XCTestCase {
    func testCleanDocumentSwitchSkipsDecodeButExternalStorageChangesStillFlush() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let original = NativeDocument(plainText: "原正文")
        var outgoing: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: original,
            onDocumentChange: { outgoing.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        coordinator.didLoadDocument(in: editor)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(coordinator.decodeCount, 0)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "未提交正文")))
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "新正文"),
            onDocumentChange: { _ in XCTFail("Outgoing text must not commit to the new task") },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(outgoing.last?.plainText, "未提交正文")
        XCTAssertEqual(coordinator.decodeCount, 1)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(coordinator.decodeCount, 1)
    }

    func testCleanFlushStillCommitsPendingEmptyHeading() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var changes: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { changes.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        coordinator.didLoadDocument(in: editor)
        editor.seedTrailingParagraphKind(.heading(1))
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(changes.last?.blocks.last?.kind, .heading(1))
        XCTAssertEqual(coordinator.decodeCount, 1)
    }

    func testRebindFlushesCompositionToOldDocumentOnly() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var oldChanges: [NativeDocument] = []
        var newChanges: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { oldChanges.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let newID = UUID()
        coordinator.update(editor, documentID: newID, document: NativeDocument(plainText: "新文档"),
            onDocumentChange: { newChanges.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(oldChanges.last?.plainText, "中文")
        XCTAssertTrue(newChanges.isEmpty)
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "新文档")
        XCTAssertEqual(editor.documentIdentity, newID)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    func testRebindRemovesActualSlashWindowAndObservers() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let editor = NativeTextView(frame: scroll.bounds, textContainer: nil)
        scroll.documentView = editor
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        let panel = editor.slashPanel
        XCTAssertNotNil(panel)
        XCTAssertFalse(editor.slashObservers.isEmpty)
        XCTAssertTrue(panel?.parent === window)
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "second"),
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertNil(editor.slashPanel)
        XCTAssertNil(editor.slashSession)
        XCTAssertTrue(editor.slashObservers.isEmpty)
        XCTAssertNil(panel?.parent)
        XCTAssertFalse(panel?.isVisible ?? true)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    func testDetachClosesSelectionToolbarAndDisconnectsCallbacks() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NativeTextView(frame: window.contentLayoutRect, textContainer: nil)
        window.contentView = editor
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.profile = NoteDocumentProfile.make(host: NoteEditorHostActions(createTaskFromSelection: { _ in }))
        editor.onEscape = { .keepInspector }
        editor.onEditingChanged = { _ in }
        editor.onSelectionChanged = {}
        editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.refreshSelectionToolbar()
        let panel = editor.selectionPanel
        XCTAssertNotNil(panel)
        XCTAssertTrue(panel?.parent === window)
        coordinator.detach(editor)
        XCTAssertNil(editor.selectionPanel)
        XCTAssertNil(panel?.parent)
        XCTAssertFalse(panel?.isVisible ?? true)
        XCTAssertNil(editor.delegate)
        XCTAssertNil(editor.onEscape)
        XCTAssertNil(editor.onEditingChanged)
        XCTAssertNil(editor.onSelectionChanged)
        XCTAssertTrue(editor.profile.selectionActions.isEmpty)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    func testSelectionToolbarReadsAndAppliesInlineColors() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NativeTextView(frame: window.contentLayoutRect, textContainer: nil)
        window.contentView = editor
        window.orderFront(nil)
        defer { window.close() }
        editor.profile = NoteDocumentProfile.make(host: NoteEditorHostActions(createTaskFromSelection: { _ in }))
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "彩色正文", marks: [.textColor("#ff3b30"), .highlightColor("#ffe58a")])
            ])
        ])))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.refreshSelectionToolbar()
        let host = try XCTUnwrap(editor.selectionPanel?.contentView
            as? NSHostingView<DocumentSelectionToolbarView>)
        XCTAssertEqual(host.rootView.textColorHex, "#ff3b30")
        XCTAssertEqual(host.rootView.highlightHex, "#ffe58a")

        host.rootView.onTextColor("#0b7bff")
        XCTAssertEqual(editor.textStorage?.attribute(DocumentTextCodec.textColorKey, at: 0,
                                                     effectiveRange: nil) as? String, "#0b7bff")
        let refreshed = try XCTUnwrap(editor.selectionPanel?.contentView
            as? NSHostingView<DocumentSelectionToolbarView>)
        XCTAssertTrue(refreshed === host, "上色只换 rootView，不能重建浮条宿主")
        XCTAssertEqual(refreshed.rootView.textColorHex, "#0b7bff")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2))

        refreshed.rootView.onHighlightColor(nil)
        let cleared = try XCTUnwrap(editor.selectionPanel?.contentView
            as? NSHostingView<DocumentSelectionToolbarView>)
        XCTAssertNil(cleared.rootView.highlightHex)
        XCTAssertNil(editor.textStorage?.attribute(DocumentTextCodec.highlightColorKey,
                                                   at: 0, effectiveRange: nil))
    }

    func testUndoManagersAreDocumentScoped() {
        let first = NativeTextView(frame: .zero, textContainer: nil)
        let second = NativeTextView(frame: .zero, textContainer: nil)
        XCTAssertNotNil(first.undoManager)
        XCTAssertFalse(first.undoManager === second.undoManager)
        let manager = first.undoManager!
        manager.beginUndoGrouping()
        first.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        manager.endUndoGrouping()
        XCTAssertEqual(first.string, "正文")
        XCTAssertTrue(manager.canUndo)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(NativeTextView.undo(_:)), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(NativeTextView.redo(_:)), keyEquivalent: "Z")
        XCTAssertTrue(first.validateUserInterfaceItem(undoItem))
        XCTAssertFalse(second.undoManager!.canUndo)
        first.undo(nil)
        XCTAssertEqual(first.string, "")
        XCTAssertTrue(first.validateUserInterfaceItem(redoItem))
        first.redo(nil)
        XCTAssertEqual(first.string, "正文")
    }

    func testFindBarEscapeDoesNotDismissInspector() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let editor = NativeTextView(frame: scroll.bounds, textContainer: nil)
        scroll.documentView = editor
        var inspectorEscapes = 0
        editor.onEscape = { inspectorEscapes += 1; return .keepInspector }
        XCTAssertTrue(editor.usesFindBar)
        scroll.isFindBarVisible = true
        editor.cancelOperation(nil)
        XCTAssertFalse(scroll.isFindBarVisible)
        XCTAssertEqual(inspectorEscapes, 0)
        editor.cancelOperation(nil)
        XCTAssertEqual(inspectorEscapes, 1)
    }

    func testHoveringOverlayAboveBodyDoesNotChangeTextCursor() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let scroll = NSScrollView(frame: root.bounds)
        let editor = NativeTextView(frame: root.bounds, textContainer: nil)
        editor.isEditable = true
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文")))
        scroll.documentView = editor
        root.addSubview(scroll)
        // 格式工具条是叠在正文上方的兄弟视图（真实宿主为 NSHostingView）。
        let overlay = NSView(frame: NSRect(x: 0, y: 100, width: 300, height: 38))
        root.addSubview(overlay)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }

        func move(toWindow point: NSPoint) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0))
            editor.mouseMoved(with: event)
        }

        try move(toWindow: NSPoint(x: 150, y: 119))
        XCTAssertEqual(NSCursor.current, .arrow, "指针在工具条上不应出现文本 I-beam")
        try move(toWindow: editor.convert(NSPoint(x: 30, y: 250), to: nil))
        XCTAssertEqual(NSCursor.current, .iBeam, "正文区域仍保留文本光标")
    }

    /// 插入浮条是永不成为 key window 的非激活子面板：提示追踪必须用
    /// `.activeAlways`，否则 hover 名称根本不出现。
    func testHoverTipTrackingUsesActiveAlwaysForNonKeyPanels() {
        let view = HoverTipTrackingView()
        view.activeAlways = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.updateTrackingAreas()
        XCTAssertTrue(view.trackingAreas.contains { $0.options.contains(.activeAlways) })
        XCTAssertFalse(view.trackingAreas.contains { $0.options.contains(.activeInKeyWindow) })
        window.close()
    }

    func testCompositionIsNotPublishedUntilCommitted() {        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var changes: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(
            documentID: UUID(), document: .empty,
            onDocumentChange: { changes.append($0) },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(changes.isEmpty)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(changes.last?.plainText, "中文")
    }
}
