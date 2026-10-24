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

    // MARK: - 清单补全（TI2-08 剩余项）

    func testTildeOpensListCandidatesAndCommitsMove() throws {
        let (view, window) = try makeView(tags: [], lists: ["收集箱", "工作", "学习"])
        defer { view.dismissTagCompletion(); window.close() }
        var moved: [String] = []
        view.profile.onListInserted = { moved.append($0) }

        type("正文 ~", into: view)
        let session = try XCTUnwrap(view.tagSession, "~ 后应出现清单候选")
        XCTAssertEqual(session.kind, .list)
        XCTAssertEqual(session.candidates, ["收集箱", "工作", "学习"])

        type("学", into: view)
        XCTAssertEqual(view.tagSession?.candidates, ["学习"])
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.string, "正文 ~学习 ", "落成的清单带 ~ 前缀与尾随空格")
        XCTAssertEqual(moved, ["学习"], "选中清单要回写宿主，把任务移过去")
        XCTAssertNil(view.tagSession)
    }

    func testHashAndTildeSessionsDoNotCollide() throws {
        let (view, window) = try makeView(tags: ["工作"], lists: ["学习"])
        defer { view.dismissTagCompletion(); window.close() }

        type("#", into: view)
        XCTAssertEqual(view.tagSession?.kind, .tag)
        view.dismissTagCompletion()
        // 清掉面板，在行首重新输入 `~`。
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertText("\n", replacementRange: view.selectedRange())
        type("~", into: view)
        XCTAssertEqual(view.tagSession?.kind, .list, "两种前缀各自成会话")
        XCTAssertEqual(view.tagSession?.candidates, ["学习"])
    }

    func testTildeWithoutCandidatesDoesNotTrigger() throws {
        let (view, window) = try makeView(tags: ["工作"], lists: [])
        defer { window.close() }

        type("正文 ~", into: view)
        XCTAssertNil(view.tagSession, "没有清单候选就不出面板")
    }

    func testTildeInsideTextDoesNotTrigger() throws {
        let (view, window) = try makeView(tags: [], lists: ["学习"])
        defer { window.close() }

        type("a~学", into: view)
        XCTAssertNil(view.tagSession, "`a~` 不是清单边界")
    }

    func testListCompletionFiltersCaseInsensitively() throws {
        let (view, window) = try makeView(tags: [], lists: ["Work", "Personal"])
        defer { view.dismissTagCompletion(); window.close() }

        type("~w", into: view)
        XCTAssertEqual(view.tagSession?.candidates, ["Work"])
    }

    // MARK: - Helpers

    private func makeView(tags: [String], lists: [String] = [],
                          blocks: [DocumentBlock] = [DocumentBlock(kind: .paragraph, runs: [])])
    throws -> (NativeTextView, NSWindow) {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        var profile = DocumentProfile()
        profile.tagCandidates = { tags }
        profile.listCandidates = { lists }
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
