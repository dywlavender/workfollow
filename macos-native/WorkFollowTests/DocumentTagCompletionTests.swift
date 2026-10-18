import AppKit
import XCTest
@testable import WorkFollow

/// TI2-08：`#` 标签补全。
///
/// 滴答证据：`shouldShowQuickTag` / `existedTagNamesForTagCandidate` /
/// `markdownText:didSelectTag:`。本地：输入 `#` 列出宿主已有标签，回车/点击
/// 落成 `#tag ` 并把标签挂到任务上；Esc 只收面板、不改文本。
@MainActor
final class DocumentTagCompletionTests: XCTestCase {

    func testHashOpensCandidatesAndFiltersByQuery() throws {
        let (view, window) = try makeView(tags: ["工作", "学习", "生活"])
        defer { view.dismissTagCompletion(); window.close() }

        type("正文 #", into: view)
        let session = try XCTUnwrap(view.tagSession, "# 后应出现候选")
        XCTAssertEqual(session.candidates, ["工作", "学习", "生活"])

        type("工", into: view)
        XCTAssertEqual(view.tagSession?.candidates, ["工作"])
        XCTAssertEqual(view.tagSession?.selectedIndex, 0)
    }

    func testReturnCommitsSelectedTagAndNotifiesHost() throws {
        let (view, window) = try makeView(tags: ["工作", "学习"])
        defer { view.dismissTagCompletion(); window.close() }
        var inserted: [String] = []
        view.profile.onTagInserted = { inserted.append($0) }

        type("正文 #", into: view)
        view.moveTagCompletion(1)
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.string, "正文 #学习 ", "落成的标签带 # 前缀与尾随空格")
        XCTAssertEqual(inserted, ["学习"])
        XCTAssertNil(view.tagSession)
    }

    func testEscapeOnlyDismissesThePanel() throws {
        let (view, window) = try makeView(tags: ["工作"])
        defer { view.dismissTagCompletion(); window.close() }

        type("正文 #", into: view)
        XCTAssertNotNil(view.tagSession)
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertNil(view.tagSession)
        XCTAssertEqual(view.string, "正文 #", "Esc 不删已输入的字符（与 Slash 同口径）")
    }

    func testHashInsideTextDoesNotTrigger() throws {
        let (view, window) = try makeView(tags: ["工作"])
        defer { view.dismissTagCompletion(); window.close() }

        type("a#工", into: view)
        XCTAssertNil(view.tagSession, "`a#` 不是标签边界")
    }

    func testHashInsideCodeBlockDoesNotTrigger() throws {
        let (view, window) = try makeView(tags: ["工作"], blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "let a = 1")])
        ])
        defer { view.dismissTagCompletion(); window.close() }

        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        type("#", into: view)
        XCTAssertNil(view.tagSession)
    }

    func testNoCandidatesMeansNoPanel() throws {
        let (view, window) = try makeView(tags: [])
        defer { window.close() }

        type("正文 #", into: view)
        XCTAssertNil(view.tagSession)
    }

    // MARK: - Helpers

    private func makeView(tags: [String],
                          blocks: [DocumentBlock] = [DocumentBlock(kind: .paragraph, runs: [])])
    throws -> (NativeTextView, NSWindow) {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        var profile = DocumentProfile()
        profile.tagCandidates = { tags }
        view.profile = profile
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.close() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: blocks)))
        view.typingAttributes = DocumentTextCodec.attributes(kind: blocks.first?.kind ?? .paragraph, marks: [])
        window.makeFirstResponder(view)
        let end = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (view, window)
    }

    private func type(_ text: String, into view: NativeTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
    }
}
