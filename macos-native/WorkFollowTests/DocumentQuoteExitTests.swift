import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentQuoteExitTests: XCTestCase {
    @MainActor private final class Draft: ObservableObject {
        @Published var document: NativeDocument
        init(_ document: NativeDocument) { self.document = document }
    }

    private struct EditorSurface: View {
        @ObservedObject var draft: Draft
        let documentID: UUID
        let profile: DocumentProfile
        let handle: DocumentEditorHandle

        var body: some View {
            VStack(spacing: 0) {
                DocumentFormatToolbarView(handle: handle, maxWidth: 760)
                    .frame(height: 38)
                DocumentEditor(documentID: documentID, document: draft.document,
                    onDocumentChange: { draft.document = $0 }, onEscape: { .keepInspector },
                    onEditingChanged: { _ in }, profile: profile, handle: handle)
            }.frame(width: 760, height: 500)
        }
    }

    @MainActor private final class Fixture {
        let draft: Draft
        let handle: DocumentEditorHandle
        let host: NSHostingView<EditorSurface>
        let window: NSWindow
        let editor: NativeTextView

        init(document: NativeDocument = .empty, profile: DocumentProfile = DocumentProfile(noteSlash: true)) throws {
            let draft = Draft(document)
            let handle = DocumentEditorHandle()
            self.draft = draft; self.handle = handle
            host = NSHostingView(rootView: EditorSurface(draft: draft, documentID: UUID(), profile: profile, handle: handle))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 500)
            editor = try XCTUnwrap(handle.textView)
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            InspectorPanelTestSupport.settle(window)
        }

        func pressReturn() throws { try InspectorPanelTestSupport.sendReturn(to: window) }
        func close() { window.contentView = nil; window.close() }
    }

    func testQuoteContinuesThenSecondReturnExitsFromCommandAndMarkdownInTaskAndNoteProfiles() throws {
        for profile in [DocumentProfile(taskSlash: true), DocumentProfile(noteSlash: true)] {
            for useCommand in [true, false] {
                let fixture = try Fixture(profile: profile)
                defer { fixture.close() }
                if useCommand {
                    fixture.handle.format(try XCTUnwrap(EditorCommandCatalog.format("format.quote")))
                } else {
                    fixture.editor.insertText("> ", replacementRange: fixture.editor.selectedRange())
                }
                fixture.editor.insertText("引用内容", replacementRange: fixture.editor.selectedRange())
                try fixture.pressReturn()
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .quote])
                XCTAssertEqual(fixture.editor.pendingTrailingBlock, .quote)
                try fixture.pressReturn()
                XCTAssertEqual(fixture.editor.string, "引用内容\n", "第二次回车退出格式，不继续增加空引用行")
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph])
                XCTAssertEqual(fixture.editor.pendingTrailingBlock, .paragraph)
                XCTAssertTrue(fixture.handle.style.isBlock(.paragraph))
                fixture.editor.insertText("正常正文", replacementRange: fixture.editor.selectedRange())
                InspectorPanelTestSupport.settle(fixture.window)
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph])
                XCTAssertEqual(fixture.draft.document.blocks.map(\.plainText), ["引用内容", "正常正文"])
                let paragraph = try XCTUnwrap(fixture.editor.textStorage?.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(paragraph.firstLineHeadIndent, DocumentEditorGeometry.decorationLane)
            }
        }
    }

    func testEmptyQuoteInMiddleExitsWithoutChangingAdjacentQuotes() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "上")]),
            DocumentBlock(kind: .quote),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "下")])
        ])
        let fixture = try Fixture(document: document)
        defer { fixture.close() }
        fixture.editor.setSelectedRange(NSRange(location: 2, length: 0))
        try fixture.pressReturn()
        XCTAssertEqual(fixture.editor.string, "上\n\n下")
        XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph, .quote])
        fixture.editor.insertText("正文", replacementRange: fixture.editor.selectedRange())
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph, .quote])
        XCTAssertEqual(fixture.draft.document.blocks.map(\.plainText), ["上", "正文", "下"])
    }

    func testExitQuoteUndoAndRedoRestoreTheInputFormat() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用")]),
            DocumentBlock(kind: .quote)
        ])
        let fixture = try Fixture(document: document)
        defer { fixture.close() }
        try fixture.pressReturn()
        XCTAssertEqual(fixture.draft.document.blocks.last?.kind, .paragraph)
        fixture.editor.undo(nil)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.editor.string, "引用\n")
        XCTAssertEqual(fixture.draft.document.blocks.last?.kind, .quote)
        XCTAssertEqual(fixture.editor.pendingTrailingBlock, .quote)
        fixture.editor.redo(nil)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.editor.string, "引用\n")
        XCTAssertEqual(fixture.draft.document.blocks.last?.kind, .paragraph)
        XCTAssertEqual(fixture.editor.pendingTrailingBlock, .paragraph)
    }
}
