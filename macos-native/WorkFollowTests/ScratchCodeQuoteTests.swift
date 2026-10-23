import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class ScratchCodeQuoteTests: XCTestCase {
    func testQuotesInCodeBlock() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "")])
        ])))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .code, marks: [])
        view.insertText("let s = \"hi\"", replacementRange: view.selectedRange())
        print("PROBE code=\(view.string.debugDescription)")
        view.insertText(" -- x", replacementRange: view.selectedRange())
        print("PROBE code2=\(view.string.debugDescription)")
    }
}
