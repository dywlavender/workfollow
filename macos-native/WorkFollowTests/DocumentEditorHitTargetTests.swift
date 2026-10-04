import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentEditorHitTargetTests: XCTestCase {
    func testInspectorBodyRetainsNativeHitTargetWhileMoreCloses() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "空正文点击验收", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace,
            onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        func editor(in view: NSView) -> NativeTextView? {
            if let value = view as? NativeTextView { return value }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let textView = try XCTUnwrap(editor(in: host))
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.title]), in: host, window: window)
        XCTAssertFalse(window.firstResponder === textView)
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.footerMore]), in: host, window: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertTrue(textView.window === window, "Editor must remain mounted across panel open")
        // NSView.hitTest takes its superview's coordinates, not its own.
        let point = try XCTUnwrap(host.superview).convert(CGPoint(x: 90, y: 18), from: textView)
        XCTAssertTrue(host.hitTest(point) === textView)
        XCTAssertFalse(textView.enclosingScrollView?.documentView === textView,
                       "Content-sized body must not introduce a second native scroll viewport")
        try InspectorPanelTestSupport.click(CGRect(x: 80, y: 8, width: 20, height: 20),
                                           in: textView, window: window)
        XCTAssertFalse(more.isVisible)
        XCTAssertTrue(textView.window === window)
        XCTAssertTrue(host.hitTest(point) === textView)
        // Full first-click focus is verified with actual mouse input. Synthetic
        // NSApplication dispatch in this harness does not deliver NSTextView's
        // mouseDown, so it cannot stand in for that physical acceptance gate.
    }

    func testNativeMouseDownTakesFocusFromAnotherField() throws {
        let field = NSTextField(string: "标题")
        let textView = NativeTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 48), textContainer: nil)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 100))
        host.addSubview(field)
        host.addSubview(textView)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 500, height: 100)
        defer { window.close() }
        window.makeFirstResponder(field)
        let point = textView.convert(CGPoint(x: 90, y: 18), to: nil)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: true)
        textView.mouseDown(with: try event(.leftMouseDown))
        XCTAssertTrue(window.firstResponder === textView)
    }

    func testContentSizedBodyGrowthSelectionAndOuterScrolling() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "长正文宿主验收", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        func editor(in view: NSView) -> NativeTextView? {
            if let value = view as? NativeTextView { return value }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let textView = try XCTUnwrap(editor(in: host))
        let shortHeight = textView.frame.height
        let content = (1...80).map { "第\($0)段正文用于检查宿主滚动" }.joined(separator: "\n")
        _ = workspace.setDocument(id, NativeDocument(plainText: content))
        InspectorPanelTestSupport.settle(window)
        XCTAssertGreaterThan(textView.frame.height, shortHeight + 500)
        XCTAssertEqual(textView.string, content)
        let selection = NSRange(location: 5, length: 10)
        textView.setSelectedRange(selection)
        _ = workspace.setPriority(id, .high)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(textView.selectedRange(), selection)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        XCTAssertFalse(scrollView.documentView === textView)
        textView.scrollRangeToVisible(NSRange(location: (content as NSString).length - 1, length: 1))
        InspectorPanelTestSupport.settle(window)
        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, 0,
                             "Native \(textView.frame), host \(String(describing: scrollView.documentView?.frame)), viewport \(scrollView.contentView.bounds)")
    }

    func testEmptyContentSizedEditorHasVisibleNativeHitAreaBeforeFocus() throws {
        let handle = DocumentEditorHandle()
        let host = NSHostingView(rootView: DocumentEditor(
            documentID: UUID(), document: .empty, onDocumentChange: { _ in },
            onEscape: { .keepInspector }, onEditingChanged: { _ in },
            contentSized: true, handle: handle).frame(width: 500, height: 48))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 500, height: 48),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let textView = try XCTUnwrap(handle.textView)
        XCTAssertGreaterThanOrEqual(textView.frame.height, 48,
            "SwiftUI's visible editor height must be backed by a native hit target before first focus")
        let point = try XCTUnwrap(host.superview).convert(CGPoint(x: 80, y: 12), from: textView)
        let hit = host.hitTest(point)
        XCTAssertTrue(hit === textView || hit?.isDescendant(of: textView) == true,
                      "Visible empty paragraph must hit the native editor, not its scroll container")
    }
}
