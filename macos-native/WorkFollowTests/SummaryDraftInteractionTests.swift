import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SummaryDraftInteractionTests: XCTestCase {
    private final class Draft: ObservableObject {
        @Published var document: NativeDocument
        var adopted = false
        init(_ value: NativeDocument) { document = value }
    }
    private struct EditorSurface: View {
        @ObservedObject var draft: Draft
        let handle: DocumentEditorHandle
        let id: UUID
        var body: some View {
            DocumentEditor(documentID: id, document: draft.document,
                onDocumentChange: { draft.document = $0 }, onEscape: { .keepInspector },
                onEditingChanged: { _ in }, profile: DocumentProfile(), handle: handle)
                .frame(width: 700, height: 400)
        }
    }
    private func document(_ results: String, reflection: String) -> NativeDocument {
        NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [.init(text: "本周成果")]),
            DocumentBlock(kind: .paragraph, runs: [.init(text: results)]),
            DocumentBlock(kind: .heading(2), runs: [.init(text: "本周复盘")]),
            DocumentBlock(kind: .paragraph, runs: [.init(text: reflection)])])
    }
    func testPartialAdoptionKeepsOriginalReflectionAndNoSelectionKeepsWholeOriginal() throws {
        let original = document("完成评审", reflection: "我写的复盘")
        let candidate = document("已完成方案评审", reflection: "AI 改写的复盘")
        let review = SummaryDraftReview(original: original, candidate: candidate)
        let results = try XCTUnwrap(review.sections.first { $0.title == "本周成果" })
        let adopted = review.applying([results.id])
        XCTAssertTrue(adopted.plainText.contains("已完成方案评审"))
        XCTAssertTrue(adopted.plainText.contains("我写的复盘"))
        XCTAssertFalse(adopted.plainText.contains("AI 改写的复盘"))
        XCTAssertEqual(review.applying([]), original)
        XCTAssertEqual(review.applying(review.changedIDs).plainText, candidate.plainText)
    }
    func testRewrittenTaskTitleKeepsLinkToOriginalTask() {
        let target = NativeResourceLink.task(UUID()).url.absoluteString
        let original = NativeDocument(blocks: [DocumentBlock(kind: .paragraph,
            runs: [DocumentRun(text: "方案评审", marks: [.link(target)])])])
        let candidate = NativeDocument(plainText: "已完成方案评审并确认结论")
        let review = SummaryDraftReview(original: original, candidate: candidate)
        let result = review.applying(review.changedIDs)
        XCTAssertTrue(result.blocks.flatMap(\.runs).contains { $0.text == "方案评审" && $0.marks.contains(.link(target)) })
    }

    func testAdoptionUsesOneNativeUndoAndRedoWithHostState() throws {
        let original = document("完成评审", reflection: "手写复盘")
        let candidate = document("完成方案评审并确认结论", reflection: "手写复盘")
        let draft = Draft(original), handle = DocumentEditorHandle()
        let host = NSHostingView(rootView: EditorSurface(draft: draft, handle: handle, id: UUID()))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 700, height: 400)
        defer { window.contentView = nil; window.close() }
        let editor = try XCTUnwrap(handle.textView)
        window.makeFirstResponder(editor)
        XCTAssertTrue(handle.replaceDocument(candidate, commit: { updated in
            draft.document = updated; draft.adopted = true
        }, inverseCommit: { updated in
            draft.document = updated; draft.adopted = false
        }))
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(draft.document.plainText, candidate.plainText)
        XCTAssertTrue(draft.adopted)
        XCTAssertTrue(handle.textView === editor)
        XCTAssertTrue(editor.undoManager?.canUndo == true, "原生撤销栈应含采用操作")
        let identity = editor.documentIdentity
        editor.undo(nil)
        XCTAssertEqual(editor.string, original.plainText, "undo 后的原生正文；identityChanged=\(identity != editor.documentIdentity), canUndo=\(editor.undoManager?.canUndo == true), group=\(editor.undoManager?.groupingLevel ?? -1)")
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(draft.document, original)
        XCTAssertFalse(draft.adopted)
        editor.redo(nil)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(draft.document.plainText, candidate.plainText)
        XCTAssertTrue(draft.adopted)
    }
}
