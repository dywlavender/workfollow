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
        let editor: MilkdownWebView

        init(document: NativeDocument = .empty, profile: DocumentProfile = DocumentProfile(noteSlash: true)) throws {
            let draft = Draft(document)
            let handle = DocumentEditorHandle()
            self.draft = draft; self.handle = handle
            host = NSHostingView(rootView: EditorSurface(draft: draft, documentID: UUID(), profile: profile, handle: handle))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 500)
            editor = try MilkdownTestSupport.editor(in: host)
            try MilkdownTestSupport.command(editor, "focusEnd")
            InspectorPanelTestSupport.settle(window)
        }

        func type(_ text: String) throws {
            let client = try MilkdownTestSupport.inputClient(editor)
            for character in text {
                client.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                InspectorPanelTestSupport.settle(window, duration: 0.025)
            }
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
                    InspectorPanelTestSupport.settle(fixture.window)
                } else {
                    try fixture.type("> ")
                }
                try fixture.type("引用内容")
                try fixture.pressReturn()
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .quote])
                try fixture.pressReturn()
                XCTAssertEqual(fixture.editor.document.plainText, "引用内容\n", "第二次回车退出格式，不继续增加空引用行")
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph])
                XCTAssertTrue(fixture.handle.style.isBlock(.paragraph))
                try fixture.type("正常正文")
                InspectorPanelTestSupport.settle(fixture.window)
                XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph])
                XCTAssertEqual(fixture.draft.document.blocks.map(\.plainText), ["引用内容", "正常正文"])
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
        try MilkdownTestSupport.select(fixture.editor, NSRange(location: 2, length: 0))
        try fixture.pressReturn()
        XCTAssertEqual(fixture.editor.document.plainText, "上\n\n下")
        XCTAssertEqual(fixture.draft.document.blocks.map(\.kind), [.quote, .paragraph, .quote])
        try fixture.type("正文")
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
        try MilkdownTestSupport.command(fixture.editor, "undo")
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.editor.document.plainText, "引用\n")
        XCTAssertEqual(fixture.draft.document.blocks.last?.kind, .quote)
        try MilkdownTestSupport.command(fixture.editor, "redo")
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.editor.document.plainText, "引用\n")
        XCTAssertEqual(fixture.draft.document.blocks.last?.kind, .paragraph)
    }
}
