import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorBodyScrollTests: XCTestCase {
    private final class Wheel: NSEvent {
        let owner: NSWindow
        let point: NSPoint
        let amount: CGFloat
        let gesturePhase: NSEvent.Phase
        let precise: Bool
        init(owner: NSWindow, point: NSPoint, amount: CGFloat, phase: NSEvent.Phase, precise: Bool = true) {
            self.owner = owner; self.point = point; self.amount = amount; gesturePhase = phase
            self.precise = precise
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("not intended") }
        override var type: NSEvent.EventType { .scrollWheel }
        override var window: NSWindow? { owner }
        override var locationInWindow: NSPoint { point }
        override var scrollingDeltaX: CGFloat { 0 }
        override var scrollingDeltaY: CGFloat { amount }
        override var deltaY: CGFloat { amount }
        override var hasPreciseScrollingDeltas: Bool { precise }
        override var phase: NSEvent.Phase { gesturePhase }
        override var momentumPhase: NSEvent.Phase { [] }
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    private func findEditor(in view: NSView) -> NativeTextView? {
        if let editor = view as? NativeTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
    }

    private func checkScrolling(body: String, paste: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notes-long-scroll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = Note(id: UUID(), title: "虚构长笔记", document: NativeDocument(plainText: paste ? "起始正文" : body), folder: "未归档", updatedAt: Date())
        let short = Note(id: UUID(), title: "虚构短笔记", document: NativeDocument(plainText: "短正文"), folder: "未归档", updatedAt: Date())
        try NativePreviewRepository(directory: directory).save(.init(tasks: [], notes: [note, short]))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.notesWorkspace.aiPaneVisible = false
        environment.navigation.destination = .notes
        environment.notesWorkspace.selectedID = short.id
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).frame(maxWidth: .infinity, maxHeight: .infinity))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        let original = try XCTUnwrap(findEditor(in: host))
        XCTAssertEqual(original.string, "短正文")
        environment.notesWorkspace.selectedID = note.id
        InspectorPanelTestSupport.settle(window)
        let editor = try XCTUnwrap(findEditor(in: host))
        if paste {
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
            editor.insertText(body, replacementRange: editor.selectedRange())
            InspectorPanelTestSupport.settle(window)
        }
        try assertScrolling(in: host, window: window, body: body)
        environment.navigate(to: .inbox)
        InspectorPanelTestSupport.settle(window)
        environment.navigate(to: .notes)
        environment.notesWorkspace.selectedID = note.id
        InspectorPanelTestSupport.settle(window)
        try assertScrolling(in: host, window: window, body: body)
        window.setContentSize(NSSize(width: 980, height: 640))
        InspectorPanelTestSupport.settle(window)
        try assertScrolling(in: host, window: window, body: body)
    }

    private func assertScrolling(in host: NSView, window: NSWindow, body: String) throws {
        let editor = try XCTUnwrap(findEditor(in: host))
        XCTAssertEqual(editor.string, body)
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(editor.frame.height, scroll.contentSize.height * 2)
        XCTAssertGreaterThan(document.frame.height, editor.frame.height)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNotNil(editor.textLayoutManager)
        let pointer = editor.bounds.intersection(editor.visibleRect)
        let hoverPoint = editor.convert(NSPoint(x: pointer.midX, y: pointer.midY), to: nil)
        let hover = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        editor.mouseMoved(with: hover)
        XCTAssertNotNil(editor.textLayoutManager, "Attachment hover must keep the shared editor on TextKit 2, even over plain text")
        editor.invalidateIntrinsicContentSize()
        InspectorPanelTestSupport.settle(window)
        XCTAssertGreaterThan(editor.frame.height, scroll.contentSize.height * 2,
                             "Pointer movement must not collapse the long document to its viewport")
        let before = scroll.contentView.bounds.minY
        let visible = editor.bounds.intersection(editor.visibleRect)
        XCTAssertGreaterThan(visible.height, 50)
        let point = editor.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
        let hit = window.contentView?.hitTest(window.contentView!.convert(point, from: nil))
        XCTAssertTrue(hit === editor, "The wheel must hit the actual editor, got \(String(describing: hit))")
        for phase: NSEvent.Phase in [.began, .changed, .changed, .ended] {
            window.sendEvent(Wheel(owner: window, point: point, amount: phase == .ended ? 0 : -80, phase: phase))
            InspectorPanelTestSupport.settle(window, duration: 0.04)
        }
        InspectorPanelTestSupport.settle(window)
        let after = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(after, before + 10, "Scrolling over the long note body must move its outer viewport")
        for phase: NSEvent.Phase in [.began, .changed, .changed, .ended] {
            window.sendEvent(Wheel(owner: window, point: point, amount: phase == .ended ? 0 : 80, phase: phase))
            InspectorPanelTestSupport.settle(window, duration: 0.04)
        }
        InspectorPanelTestSupport.settle(window)
        XCTAssertLessThan(scroll.contentView.bounds.minY, after - 10, "Upward scrolling must also work")
        let beforeMouse = scroll.contentView.bounds.minY
        for _ in 0..<4 {
            window.sendEvent(Wheel(owner: window, point: point, amount: -3, phase: [], precise: false))
            InspectorPanelTestSupport.settle(window, duration: 0.04)
        }
        InspectorPanelTestSupport.settle(window)
        let afterMouse = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(afterMouse, beforeMouse + 5, "An ordinary mouse wheel must scroll over the body")
        XCTAssertEqual(editor.string, body)
    }

    func testLoadedLongNoteScrollsUnderThePointerInFullShell() throws {
        let body = (1...140).map { "第\($0)段：这是一段虚构的项目进展，用来检查长笔记正文的滚动、换行以及标题和底栏的布局。" }.joined(separator: "\n")
        try checkScrolling(body: body, paste: false)
    }

    func testPastedLongParagraphScrollsUnderThePointerInFullShell() throws {
        try checkScrolling(body: String(repeating: "这是一段虚构的长正文，用于检查粘贴后自动换行和滚动是否正常。", count: 220), paste: true)
    }

    func testLoadedLongTaskScrollsAfterMouseHoverInFullShell() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-body-scroll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = (1...100).map { "第\($0)段：虚构任务的长正文滚动。" }.joined(separator: "\n")
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(seed.createTask(title: "虚构长任务", in: .inbox).taskID)
        _ = seed.setDocument(id, NativeDocument(plainText: body))
        try NativePreviewRepository(directory: directory).save(.init(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.navigation.destination = .inbox
        environment.taskWorkspace.select(id)
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        try assertScrolling(in: host, window: window, body: body)
    }
    func testAttachmentHoverKeepsItsTooltipAndTextKit2() throws {
        let file = NativeAttachment(id: UUID(), name: "虚构附件.pdf", storedName: "fixture.pdf")
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "正文 "), DocumentRun(text: "\u{FFFC}", attachment: file)
        ])])
        let handle = DocumentEditorHandle()
        let host = NSHostingView(rootView: ScrollView {
            DocumentEditor(documentID: UUID(), document: document, onDocumentChange: { _ in },
                onEscape: { .endEditing }, onEditingChanged: { _ in }, contentSized: true, handle: handle)
                .padding(28)
        })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 400)
        defer { HoverTipCenter.shared.hide(); window.contentView = nil; window.close() }
        let editor = try XCTUnwrap(handle.textView)
        let rect = try XCTUnwrap(editor.viewRect(forCharacterAt: 3))
        let point = editor.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        editor.mouseMoved(with: event)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNotNil(editor.textLayoutManager)
        XCTAssertEqual(HoverTipCenter.shared.activeTitle, file.name)
    }

}
