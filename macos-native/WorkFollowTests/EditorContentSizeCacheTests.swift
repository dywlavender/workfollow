import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorContentSizeCacheTests: XCTestCase {
    private func fixture(_ body: String) -> (NativeTextView, DocumentEditorCoordinator) {
        let id = UUID()
        let document = NativeDocument(plainText: body)
        let text = NativeTextView(frame: .zero, textContainer: nil)
        text.documentIdentity = id
        text.usesHostScrollView = true
        text.isVerticallyResizable = false
        let coordinator = DocumentEditorCoordinator(documentID: id, document: document,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        text.textStorage?.setAttributedString(text.renderDocument(document))
        text.delegate = coordinator
        coordinator.didLoadDocument(in: text)
        return (text, coordinator)
    }

    func testRepeatedLayoutAndUnchangedUpdatesReuseMeasurement() throws {
        let (text, coordinator) = fixture(String(repeating: "长正文布局缓存\n", count: 100))
        coordinator.invalidateContentSizeIfNeeded(in: text)
        let size = try XCTUnwrap(coordinator.contentSize(for: 520, in: text))
        let invalidations = coordinator.contentInvalidationCount
        for _ in 0..<30 {
            coordinator.invalidateContentSizeIfNeeded(in: text)
            XCTAssertEqual(coordinator.contentSize(for: 520, in: text), size)
        }
        XCTAssertEqual(coordinator.contentMeasurementCount, 1)
        XCTAssertEqual(coordinator.contentInvalidationCount, invalidations)
        XCTAssertNotNil(text.textLayoutManager)
    }

    func testTextWidthAndFormattingStillChangeMeasuredHeight() throws {
        let (text, coordinator) = fixture(String(repeating: "长段落换行与字号变化的高度检查。", count: 80))
        let wide = try XCTUnwrap(coordinator.contentSize(for: 600, in: text))
        let narrow = try XCTUnwrap(coordinator.contentSize(for: 260, in: text))
        XCTAssertGreaterThan(narrow.height, wide.height)
        text.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 28),
                                      range: NSRange(location: 0, length: text.textStorage!.length))
        let large = try XCTUnwrap(coordinator.contentSize(for: 260, in: text))
        XCTAssertGreaterThan(large.height, narrow.height)
        text.insertText("\n追加一行", replacementRange: NSRange(location: (text.string as NSString).length, length: 0))
        let appended = try XCTUnwrap(coordinator.contentSize(for: 260, in: text))
        XCTAssertGreaterThan(appended.height, large.height)
        XCTAssertEqual(coordinator.contentMeasurementCount, 4)
    }

    func testMarkedTextAndDocumentRebindCannotReuseOldHeight() throws {
        let (text, coordinator) = fixture("")
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.addSubview(text)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 400, height: 300)
        defer { window.close() }
        window.makeFirstResponder(text)
        let empty = try XCTUnwrap(coordinator.contentSize(for: 340, in: text))
        text.setMarkedText(String(repeating: "中文组合输入", count: 90),
            selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: 0, length: 0))
        let marked = try XCTUnwrap(coordinator.contentSize(for: 340, in: text))
        XCTAssertGreaterThan(marked.height, empty.height)
        coordinator.update(text, documentID: UUID(), document: NativeDocument(plainText: "切换后的短正文"),
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        let rebound = try XCTUnwrap(coordinator.contentSize(for: 340, in: text))
        XCTAssertLessThan(rebound.height, marked.height)
        XCTAssertFalse(text.hasMarkedText())
        XCTAssertEqual(text.string, "切换后的短正文")
    }
    func testDuplicateTextNotificationsDecodeOnceAndStillCommitNewInput() {
        let (text, coordinator) = fixture("起始正文")
        text.insertText("新增", replacementRange: NSRange(location: (text.string as NSString).length, length: 0))
        XCTAssertEqual(coordinator.decodeCount, 1)
        let event = Notification(name: NSText.didChangeNotification, object: text)
        coordinator.textDidChange(event)
        coordinator.textDidChange(event)
        XCTAssertEqual(coordinator.decodeCount, 1)
        text.insertText("再新增", replacementRange: NSRange(location: (text.string as NSString).length, length: 0))
        XCTAssertEqual(coordinator.decodeCount, 2)
        XCTAssertEqual(text.string, "起始正文新增再新增")
    }

    func testWebKitInputGrowsTheRealSwiftUIEditor() throws {
        let handle = DocumentEditorHandle()
        var commits = 0
        let host = NSHostingView(rootView: ScrollView {
            DocumentEditor(documentID: UUID(), document: .empty, onDocumentChange: { _ in commits += 1 },
                onEscape: { .keepInspector }, onEditingChanged: { _ in }, contentSized: true, handle: handle)
        }.frame(width: 420, height: 300))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 300)
        defer { window.contentView = nil; window.close() }
        let editor = try MilkdownTestSupport.editor(in: host)
        let client = try MilkdownTestSupport.inputClient(editor)
        client.setMarkedText(String(repeating: "中文组合输入", count: 120),
            selectedRange: NSRange(location: 0, length: 0), replacementRange: client.selectedRange())
        try MilkdownTestSupport.wait("WebKit 输入未撑开正文") { editor.frame.height > 300 }
        XCTAssertGreaterThan(commits, 0)

    }

}
