import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentListHierarchyTests: XCTestCase {
    private func block(_ text: String, kind: DocumentBlockKind = .bullet,
                       depth: Int = 0, start: Int? = nil) -> DocumentBlock {
        DocumentBlock(kind: kind, runs: [DocumentRun(text: text)], indentLevel: depth, listStart: start)
    }

    func testLegacyBlocksAndDeltaRetainListDepthAndNumbering() throws {
        let legacy = block("旧列表")
        let decoded = try JSONDecoder().decode(DocumentBlock.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.indentLevel, 0)
        XCTAssertNil(decoded.listStart)
        let document = NativeDocument(blocks: [
            block("父项", kind: .ordered, start: 7), block("子项", depth: 1),
            block("子编号", kind: .ordered, depth: 2, start: 3), block("下一父项", kind: .ordered)
        ])
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored, document)
        XCTAssertEqual(DocumentListStructure.ordinal(at: 3, in: restored.blocks), 8)
    }

    func testTabMovesParentAndChildrenAndUndoRestoresExactly() {
        let document = NativeDocument(blocks: [block("父项"), block("子项", depth: 1), block("同级")])
        let session = Session(document)
        session.view.setSelectedRange(NSRange(location: 0, length: 0))
        session.view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(session.document.blocks.map(\.indentLevel), [1, 2, 0])
        XCTAssertEqual(session.view.string, document.plainText)
        XCTAssertEqual(session.view.selectedRange(), NSRange(location: 0, length: 0))
        session.view.undo(nil)
        XCTAssertEqual(session.document, document)
        session.view.redo(nil)
        XCTAssertEqual(session.document.blocks.map(\.indentLevel), [1, 2, 0])
        session.view.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(session.document.blocks.map(\.indentLevel), [0, 1, 0])
        XCTAssertFalse(session.view.string.contains("\t"))
    }

    func testSelectionIndentKeepsSiblingNumberingAndWrappingAligned() throws {
        let document = NativeDocument(blocks: [block("第一项", kind: .ordered),
            block("第二项", kind: .ordered), block("第三项", kind: .ordered)])
        let session = Session(document)
        session.view.setSelectedRange(NSRange(location: 4, length: 7))
        session.view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(session.document.blocks.map(\.indentLevel), [0, 1, 1])
        let style = try XCTUnwrap(session.view.textStorage?.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.firstLineHeadIndent, style.headIndent)
        XCTAssertEqual(style.headIndent, DocumentEditorGeometry.decorationLane
                       + DocumentEditorGeometry.listTextIndent + DocumentEditorGeometry.listIndentStep)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 8, in: session.view.attributedString()), 2)
    }

    func testReturnContinuesNestedOrderedListAndEmptyReturnOutdentsThenExits() {
        let session = Session(NativeDocument(blocks: [block("第七项", kind: .ordered, depth: 1, start: 7)]))
        session.view.setSelectedRange(NSRange(location: 3, length: 0))
        session.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(session.document.blocks.map(\.indentLevel), [1, 1])
        XCTAssertNil(session.document.blocks.last?.listStart)
        XCTAssertEqual(DocumentListStructure.ordinal(at: 1, in: session.document.blocks), 8)
        session.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(session.document.blocks.last?.indentLevel, 0)
        XCTAssertEqual(session.document.blocks.last?.kind, .ordered)
        session.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(session.document.blocks.last?.kind, .paragraph)
        XCTAssertEqual(session.view.string, "第七项\n")
    }

    func testNewChecklistItemIsUncheckedAndBackspaceAtStartOutdents() {
        let session = Session(NativeDocument(blocks: [block("完成", kind: .checklist(true), depth: 2)]))
        session.view.setSelectedRange(NSRange(location: 2, length: 0))
        session.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(session.document.blocks.map(\.kind), [.checklist(true), .checklist(false)])
        XCTAssertEqual(session.document.blocks.last?.indentLevel, 2)
        session.view.insertText("下一项", replacementRange: session.view.selectedRange())
        session.view.setSelectedRange(NSRange(location: 3, length: 0))
        session.view.deleteBackward(nil)
        XCTAssertEqual(session.document.blocks.last?.indentLevel, 1)
        XCTAssertEqual(session.document.blocks.last?.plainText, "下一项")
    }

    func testTypedOrderedStartAndEmptyNestedItemSurviveRebinding() {
        let session = Session(.empty)
        session.view.insertText("7. ", replacementRange: NSRange(location: 0, length: 0))
        session.view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(session.document.blocks.first?.indentLevel, 1)
        XCTAssertEqual(session.document.blocks.first?.listStart, 7)
        let reopened = Session(session.document)
        reopened.view.insertText("内容", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(reopened.document.blocks.first?.indentLevel, 1)
        XCTAssertEqual(reopened.document.blocks.first?.listStart, 7)
        reopened.view.applyFormat(EditorCommandCatalog.format("format.bold")!)
        XCTAssertEqual(reopened.document.blocks.first?.indentLevel, 1)
    }

    func testInternalClipboardPreservesHierarchyAndPublicMarkdown() throws {
        let original = NativeDocument(blocks: [block("父项", kind: .ordered, start: 3),
            block("子项", depth: 1), block("后续", kind: .ordered)])
        let source = Session(original), destination = Session(.empty)
        let board = NSPasteboard(name: .init("list-hierarchy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        XCTAssertEqual(board.string(forType: .string), "3. 父项\n  - 子项\n4. 后续")
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.blocks.map(\.indentLevel), [0, 1, 0])
        XCTAssertEqual(destination.document.blocks.first?.listStart, 3)
        XCTAssertEqual(destination.document.blocks.map(\.runs), original.blocks.map(\.runs))
    }

    func testEmptyNestedClipboardParagraphRetainsTypingDepth() {
        let original = NativeDocument(blocks: [block("父项"), block("", depth: 2)])
        let source = Session(original), destination = Session(.empty)
        let board = NSPasteboard(name: .init("list-empty-item-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        source.view.setSelectedRange(NSRange(location: 0, length: source.view.attributedString().length))
        XCTAssertTrue(source.view.copyDocumentFragment(to: board))
        XCTAssertTrue(destination.view.pasteDocumentFragment(from: board))
        XCTAssertEqual(destination.document.blocks.last?.indentLevel, 2)
        destination.view.insertText("继续输入", replacementRange: destination.view.selectedRange())
        XCTAssertEqual(destination.document.blocks.last?.kind, .bullet)
        XCTAssertEqual(destination.document.blocks.last?.indentLevel, 2)
    }

    func testFullTaskShellRoutesPhysicalTabToFocusedBody() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-shell-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "正文按键路由", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [block("父项"), block("子项", depth: 1), block("同级")]))
        workspace.select(id)
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 760)
        defer { window.close() }
        func findEditor(_ view: NSView) -> NativeTextView? {
            if let value = view as? NativeTextView { return value }
            return view.subviews.lazy.compactMap { findEditor($0) }.first
        }
        let body = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(body)
        body.setSelectedRange(NSRange(location: 0, length: 0))
        func tab(_ shift: Bool) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: shift ? "\u{19}" : "\t", charactersIgnoringModifiers: "\t",
                isARepeat: false, keyCode: 48))
            NSApp.sendEvent(event)
            InspectorPanelTestSupport.settle(window)
        }
        XCTAssertTrue(window.firstResponder === body)
        try tab(false)
        XCTAssertEqual(workspace.task(for: id)?.document.blocks.map(\.indentLevel), [1, 2, 0])
        XCTAssertEqual(environment.navigation.destination, .inbox)
        XCTAssertTrue(window.firstResponder === body)
        try tab(true)
        XCTAssertEqual(workspace.task(for: id)?.document.blocks.map(\.indentLevel), [0, 1, 0])
        XCTAssertEqual(environment.navigation.destination, .inbox)
        XCTAssertFalse(body.string.contains("\t"))
    }

    @MainActor private final class Session {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), textContainer: nil)
        var document: NativeDocument
        private var coordinator: DocumentEditorCoordinator!

        init(_ document: NativeDocument) {
            self.document = document
            coordinator = DocumentEditorCoordinator(documentID: UUID(), document: document,
                onDocumentChange: { [weak self] in self?.document = $0 },
                onEscape: { .keepInspector }, onEditingChanged: { _ in })
            view.delegate = coordinator
            view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            if let last = document.blocks.last, last.plainText.isEmpty {
                view.seedTrailingParagraphKind(last.kind, indentLevel: last.indentLevel, listStart: last.listStart)
            }
            coordinator.didLoadDocument(in: view)
        }
    }
}
