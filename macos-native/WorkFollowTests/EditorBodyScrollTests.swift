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

    private func checkScrolling(body: String, paste: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notes-long-scroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = Note(id: UUID(), title: "虚构长笔记", document: NativeDocument(plainText: paste ? "起始正文" : body), folder: "未归档", updatedAt: Date())
        let short = Note(id: UUID(), title: "虚构短笔记", document: NativeDocument(plainText: "短正文"), folder: "未归档", updatedAt: Date())
        try NativePreviewRepository(directory: directory).save(.init(tasks: [], notes: [note, short]))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false; environment.notesWorkspace.aiPaneVisible = false
        environment.navigation.destination = .notes; environment.notesWorkspace.selectedID = short.id
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).frame(maxWidth: .infinity, maxHeight: .infinity))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        XCTAssertEqual(try MilkdownTestSupport.editor(in: host, id: short.id).document.plainText, "短正文")
        environment.notesWorkspace.selectedID = note.id
        let editor = try MilkdownTestSupport.editor(in: host, id: note.id)
        if paste {
            try MilkdownTestSupport.select(editor, NSRange(location: 0, length: editor.document.plainText.utf16.count))
            try MilkdownTestSupport.command(editor, "insertText", ["text": body])
        }
        try assertScrolling(in: host, window: window, body: body)
        environment.navigate(to: .inbox); InspectorPanelTestSupport.settle(window)
        environment.navigate(to: .notes); environment.notesWorkspace.selectedID = note.id
        try assertScrolling(in: host, window: window, body: body)
        window.setContentSize(NSSize(width: 980, height: 640)); InspectorPanelTestSupport.settle(window)
        try assertScrolling(in: host, window: window, body: body)
    }

    private func assertScrolling(in host: NSView, window: NSWindow, body: String) throws {
        let editor = try MilkdownTestSupport.editor(in: host)
        try MilkdownTestSupport.wait("长正文没有生成外层滚动范围") {
            host.layoutSubtreeIfNeeded()
            return editor.document.plainText == body && editor.frame.height > (editor.enclosingScrollView?.contentSize.height ?? 0) * 2
        }
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        XCTAssertTrue(editor.usesContentHeight)
        XCTAssertFalse(scroll.documentView === editor)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        let visible = editor.bounds.intersection(editor.visibleRect)
        XCTAssertGreaterThan(visible.height, 50)
        let point = editor.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
        let hit = window.contentView?.hitTest(window.contentView!.convert(point, from: nil))
        XCTAssertTrue(hit === editor.webView || hit?.isDescendant(of: editor.webView) == true)
        func wheel(_ amount: CGFloat, precise: Bool) {
            for phase: NSEvent.Phase in [.began, .changed, .changed, .ended] {
                NSApp.sendEvent(Wheel(owner: window, point: point, amount: phase == .ended ? 0 : amount,
                    phase: precise ? phase : [], precise: precise))
                InspectorPanelTestSupport.settle(window, duration: 0.04)
            }
        }
        let before = scroll.contentView.bounds.minY
        wheel(-80, precise: true)
        let after = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(after, before + 10, "正文上的触控板滚动应传给外层视口")
        wheel(80, precise: true)
        XCTAssertLessThan(scroll.contentView.bounds.minY, after - 10)
        let beforeMouse = scroll.contentView.bounds.minY
        wheel(-3, precise: false)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, beforeMouse + 5, "正文上的鼠标滚轮应传给外层视口")
        XCTAssertEqual(editor.document.plainText, body)
    }

    func testLoadedLongNoteScrollsUnderThePointerInFullShell() throws {
        try checkScrolling(body: (1...140).map { "第\($0)段：虚构项目进展，检查长笔记正文滚动、换行和页面布局。" }.joined(separator: "\n"), paste: false)
    }

    func testPastedLongParagraphScrollsUnderThePointerInFullShell() throws {
        try checkScrolling(body: String(repeating: "虚构长正文，用于检查粘贴后自动换行和滚动是否正常。", count: 220), paste: true)
    }

    func testLoadedLongTaskScrollsAfterMouseHoverInFullShell() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-body-scroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = (1...100).map { "第\($0)段：虚构任务的长正文滚动。" }.joined(separator: "\n")
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(seed.createTask(title: "虚构长任务", in: .inbox).taskID)
        _ = seed.setDocument(id, NativeDocument(plainText: body))
        try NativePreviewRepository(directory: directory).save(.init(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false; environment.navigation.destination = .inbox
        environment.taskWorkspace.select(id)
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation).environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        try assertScrolling(in: host, window: window, body: body)
    }

    func testAttachmentKeepsItsTooltipAndDocumentWhenHovered() throws {
        let file = NativeAttachment(id: UUID(), name: "虚构附件.pdf", storedName: "fixture.pdf")
        let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "正文 "), .init(text: "\u{FFFC}", attachment: file)])])
        let host = NSHostingView(rootView: ScrollView {
            DocumentEditor(documentID: UUID(), document: document, onDocumentChange: { _ in },
                onEscape: { .endEditing }, onEditingChanged: { _ in }, contentSized: true).padding(28)
        })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 400)
        defer { window.contentView = nil; window.close() }
        let editor = try MilkdownTestSupport.editor(in: host)
        XCTAssertEqual(try MilkdownTestSupport.script(editor, "document.querySelector('.wf-embed button').title") as? String, file.name)
        try MilkdownTestSupport.script(editor, "document.querySelector('.wf-embed').dispatchEvent(new MouseEvent('mouseover',{bubbles:true}))")
        XCTAssertEqual(editor.document, document)
    }
}
