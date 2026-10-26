import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentClipboardEditingTests: XCTestCase {
    func testExternalMarkdownPastesStructureAndUndoesOnce() throws {
        let destination = fixture(.empty)
        let board = namedBoard()
        board.setString("# 标题\n\n- [x] **完成**\n> 引用", forType: .string)
        XCTAssertTrue(destination.view.pasteExternalDocumentFragment(from: board, destinationKind: .paragraph))
        XCTAssertEqual(destination.document.blocks.map(\.kind),
                       [.heading(1), .paragraph, .checklist(true), .quote])
        XCTAssertTrue(destination.document.blocks[2].runs[0].marks.contains(.bold))
        destination.view.undo(nil)
        XCTAssertEqual(destination.view.string, "")
        destination.view.redo(nil)
        XCTAssertEqual(destination.document.blocks.first?.kind, .heading(1))
    }

    func testPublicHtmlKeepsCopiedStructureWithoutThePrivateFlavor() throws {
        let source = fixture(NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "摘要")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "步骤", marks: [.italic])])
        ]))
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        let board = namedBoard()
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        let html = try XCTUnwrap(board.string(forType: .html))
        board.clearContents()
        board.setString(html, forType: .html)
        let destination = fixture(.empty)
        XCTAssertTrue(destination.view.pasteExternalDocumentFragment(from: board, destinationKind: .paragraph))
        XCTAssertEqual(destination.document.blocks.map(\.kind), [.heading(2), .ordered])
        XCTAssertEqual(destination.document.plainText, "摘要\n步骤")
        XCTAssertFalse(destination.view.pasteExternalDocumentFragment(from: board, destinationKind: .code))
    }

    func testCopyPasteAcrossEditorsKeepsBlockStructureAndMarks() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "计划", marks: [.bold])]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用")])
        ])
        let source = fixture(document)
        let destination = fixture(.empty)
        let board = namedBoard()
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(destination.document.blocks.map(\.runs), document.blocks.map(\.runs))
        XCTAssertEqual(board.string(forType: .string), "## **计划**\n1. 第一项\n- [x] 已完成\n> 引用")
    }

    func testStructuredPasteHasOneUndoStep() throws {
        let source = fixture(NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "事项")])
        ]))
        let original = NativeDocument(plainText: "前后")
        let destination = fixture(original)
        let board = namedBoard()
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        destination.view.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.blocks.map(\.kind), [.paragraph, .heading(1), .ordered, .paragraph])
        destination.view.undo(nil)
        XCTAssertEqual(destination.document.plainText, original.plainText)
        XCTAssertEqual(destination.document.blocks.map(\.kind), [.paragraph])
        destination.view.redo(nil)
        XCTAssertEqual(destination.document.blocks.map(\.kind), [.paragraph, .heading(1), .ordered, .paragraph])
    }

    func testSelectedWordInHeadingDoesNotTurnDestinationIntoHeading() throws {
        let source = fixture(NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "整个标题", marks: [.italic])])
        ]))
        source.view.setSelectedRange(NSRange(location: 1, length: 2))
        let board = namedBoard()
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        let destination = fixture(NativeDocument(plainText: "前后"))
        destination.view.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.plainText, "前个标后")
        XCTAssertEqual(destination.document.blocks.first?.kind, .paragraph)
        XCTAssertTrue(destination.document.blocks.first?.runs.contains { $0.marks.contains(.italic) } == true)
    }

    func testPrivatePayloadDoesNotReinterpretLiteralMarkdown() throws {
        let literal = NativeDocument(plainText: "**保持字面**")
        let source = fixture(literal)
        let destination = fixture(.empty)
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        let board = namedBoard()
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.plainText, literal.plainText)
        XCTAssertTrue(destination.document.blocks.flatMap(\.runs).allSatisfy { $0.marks.isEmpty })
    }

    func testDiagramAndStructuredClipboardFlavorsCoexist() throws {
        let diagram = NativeDiagram(title: "架构图", xml: NativeDiagram.emptyXML, previewPNG: Data())
        let source = fixture(NativeDocument(blocks: [DocumentBlock(kind: .paragraph,
            runs: [DocumentRun(text: "\u{fffc}", diagram: diagram)])]))
        source.view.setSelectedRange(NSRange(location: 0, length: 1))
        let board = namedBoard()
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        XCTAssertNotNil(DocumentClipboardCodec.read(from: board))
        XCTAssertNotNil(board.data(forType: NSPasteboard.PasteboardType("com.workfollow.document.drawio")))
    }

    private final class Fixture {
        let view: NativeTextView
        let coordinator: DocumentEditorCoordinator
        let box: Box
        var document: NativeDocument { box.value }
        init(view: NativeTextView, coordinator: DocumentEditorCoordinator, box: Box) {
            self.view = view; self.coordinator = coordinator; self.box = box
        }
    }
    private final class Box {
        var value: NativeDocument
        init(_ value: NativeDocument) { self.value = value }
    }
    private func fixture(_ document: NativeDocument) -> Fixture {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 400), textContainer: nil)
        view.isEditable = true
        view.allowsUndo = true
        let box = Box(document)
        let id = UUID()
        view.documentIdentity = id
        let coordinator = DocumentEditorCoordinator(documentID: id, document: document,
            onDocumentChange: { box.value = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        view.delegate = coordinator
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.seedTrailingParagraphKind(document.blocks.last?.kind)
        coordinator.didLoadDocument(in: view)
        return Fixture(view: view, coordinator: coordinator, box: box)
    }
    private func namedBoard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("editor-fragment-\(UUID().uuidString)"))
        addTeardownBlock { board.releaseGlobally() }
        return board
    }
}
