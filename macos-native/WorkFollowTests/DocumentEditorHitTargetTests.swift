import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentEditorHitTargetTests: XCTestCase {
    func testInspectorBodyRetainsWebKitHitTargetWhileMoreCloses() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "空正文点击验收", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        let editor = try MilkdownTestSupport.editor(in: host, id: id)
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.title]), in: host, window: window)
        XCTAssertFalse(MilkdownTestSupport.isFocused(editor))
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.footerMore]), in: host, window: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertTrue(editor.window === window)
        let point = try XCTUnwrap(host.superview).convert(CGPoint(x: 90, y: editor.bounds.midY), from: editor)
        let hit = host.hitTest(point)
        XCTAssertTrue(hit === editor.webView || hit?.isDescendant(of: editor.webView) == true)
        XCTAssertFalse(editor.enclosingScrollView?.documentView === editor)
        try InspectorPanelTestSupport.click(CGRect(x: 80, y: 8, width: 20, height: 20), in: editor, window: window)
        XCTAssertFalse(more.isVisible)
        XCTAssertTrue(editor.window === window)
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
        let editor = try MilkdownTestSupport.editor(in: host, id: id), shortHeight = editor.frame.height
        let content = (1...80).map { "第\($0)段正文用于检查宿主滚动" }.joined(separator: "\n")
        _ = workspace.setDocument(id, NativeDocument(plainText: content))
        try MilkdownTestSupport.wait("长正文没有撑开宿主") { editor.document.plainText == content && editor.frame.height > shortHeight + 500 }
        let selection = NSRange(location: 5, length: 10)
        try MilkdownTestSupport.select(editor, selection)
        _ = workspace.setPriority(id, .high)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(try MilkdownTestSupport.range(editor), selection)
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        XCTAssertFalse(scroll.documentView === editor)
        try MilkdownTestSupport.command(editor, "focusEnd")
        try MilkdownTestSupport.wait("文末定位没有滚动外层视口") { scroll.contentView.bounds.minY > 0 }
    }

    func testEmptyContentSizedEditorHasVisibleWebKitHitAreaBeforeFocus() throws {
        let host = NSHostingView(rootView: DocumentEditor(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in }, contentSized: true)
            .frame(width: 500, height: 48))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 500, height: 48)
        defer { window.close() }
        let editor = try MilkdownTestSupport.editor(in: host)
        XCTAssertGreaterThanOrEqual(editor.frame.height, 48)
        let point = try XCTUnwrap(host.superview).convert(CGPoint(x: 80, y: editor.bounds.midY), from: editor)
        let hit = host.hitTest(point)
        XCTAssertTrue(hit === editor.webView || hit?.isDescendant(of: editor.webView) == true)
    }
}
