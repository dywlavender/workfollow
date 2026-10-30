import AppKit
import Combine
import XCTest
@testable import WorkFollow

final class DocumentEditorStateTests: XCTestCase {
    @MainActor
    func testViewRebindCoalescesStyleAndReadsLatestEditorAfterUpdate() {
        let handle = DocumentEditorHandle()
        let outgoing = NativeTextView(frame: .zero, textContainer: nil)
        let incoming = NativeTextView(frame: .zero, textContainer: nil)
        handle.textView = outgoing
        var styles: [DocumentSelectionStyle] = []
        let observation = handle.$style.dropFirst().sink { styles.append($0) }
        defer { observation.cancel() }

        handle.beginViewUpdate()
        outgoing.typingAttributes = DocumentTextCodec.attributes(kind: .heading(1), marks: [])
        handle.refreshStyle()
        handle.textView = incoming
        incoming.typingAttributes = DocumentTextCodec.attributes(kind: .quote, marks: [.bold])
        handle.refreshStyle()
        XCTAssertTrue(styles.isEmpty, "View updates must not publish transient toolbar state")
        handle.endViewUpdate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(styles.count, 1)
        XCTAssertTrue(handle.style.isBlock(.quote))
        XCTAssertTrue(handle.style.has(.bold))

        // User-driven formatting/selection outside the rebind remains synchronous.
        incoming.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        handle.refreshStyle()
        XCTAssertEqual(styles.count, 2)
        XCTAssertTrue(handle.style.isBlock(.paragraph))
    }

    @MainActor
    func testRevealSearchMatchSelectsFirstCaseInsensitiveHitAndGatesOnDocument() {
        let handle = DocumentEditorHandle()
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200),
                                      textContainer: nil)
        textView.string = "第一段\n会议记录：预算 REVIEW\n结尾"
        let documentID = UUID()
        textView.documentIdentity = documentID
        handle.textView = textView

        XCTAssertNil(handle.revealSearchMatch("预算", documentID: UUID()),
                     "目标文档还没换上时不能把光标落进旧正文")
        XCTAssertEqual(handle.revealSearchMatch("review", documentID: documentID), true)
        XCTAssertEqual((textView.string as NSString).substring(with: textView.selectedRange()), "REVIEW")
        XCTAssertEqual(handle.revealSearchMatch("不存在的词", documentID: documentID), false)
    }

    func testEscapeRoutesFromInputMethodThroughEditorLayersToHost() {
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: true, slash: false, selectionToolbar: false, findBar: false), .inputMethod)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: true, selectionToolbar: false, findBar: true), .slash)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: true, findBar: true), .selectionToolbar)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: false, findBar: true), .findBar)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: false, findBar: false), .host)
    }

    func testSelectionIsRetainedForSameTaskAndResetWhenTaskChanges() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        var state = DocumentEditorState(documentID: firstTaskID)
        state.updateSelection(NSRange(location: 8, length: 3))

        state.bind(to: firstTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 8, length: 3))

        state.bind(to: secondTaskID)
        XCTAssertEqual(state.documentID, secondTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 0, length: 0))
    }
}
