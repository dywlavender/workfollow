import AppKit
import XCTest
@testable import WorkFollow

/// TI2-08 下半项：链接悬停菜单（复制 / 编辑 / 移除）。
///
/// 滴答证据：`hideLinkHoverMenu`、`TTMarkdownLinkViewController`、
/// `md_link_copy` / `md_link_edit`。
@MainActor
final class DocumentLinkHoverTests: XCTestCase {

    func testLinkLookupFindsRangeAndTarget() throws {
        let (view, window) = try makeView()
        defer { window.close() }
        let linkStart = ("前" as NSString).length

        let range = try XCTUnwrap(view.linkRange(at: try pointInLink(view, window: window)),
                                  "鼠标落在链接字形上应命中链接范围")
        XCTAssertEqual(range.location, linkStart)
        XCTAssertEqual(range.length, ("链接" as NSString).length)
        XCTAssertEqual(view.linkTarget(in: range), "https://example.com")
    }

    func testPlainTextHasNoLinkAtPoint() throws {
        let (view, window) = try makeView()
        defer { window.close() }
        let plain = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
        XCTAssertNil(view.linkRange(at: NSPoint(x: plain.minX + 1, y: plain.midY)),
                     "普通文字不弹链接菜单")
    }

    func testCopyWritesTheTargetToPasteboard() throws {
        let (view, window) = try makeView()
        defer { window.close() }
        let range = try XCTUnwrap(view.linkRange(at: try pointInLink(view, window: window)))

        XCTAssertTrue(view.copyLink(in: range))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://example.com")
    }

    func testRemoveClearsTheLinkMark() throws {
        let (view, window) = try makeView()
        defer { window.close() }
        let range = try XCTUnwrap(view.linkRange(at: try pointInLink(view, window: window)))

        view.removeLink(in: range)

        let document = DocumentTextCodec.decode(view.attributedString(),
                                                preserving: NativeDocument(plainText: view.string),
                                                trailing: view.pendingTrailingBlock)
        let marks = document.blocks.flatMap { $0.runs.flatMap(\.marks) }
        XCTAssertFalse(marks.contains { if case .link = $0 { return true }; return false },
                       "移除后不再有链接标记")
        XCTAssertTrue(view.string.contains("链接"))
    }

    func testHoverPanelShowsAndHides() throws {
        let (view, window) = try makeView()
        defer { window.close() }
        let range = try XCTUnwrap(view.linkRange(at: try pointInLink(view, window: window)))

        view.showLinkHoverMenu(for: range)
        XCTAssertNotNil(view.linkHoverPanel)
        XCTAssertEqual(view.linkHoverPanel?.isVisible, true)

        view.hideLinkHoverMenu()
        XCTAssertNil(view.linkHoverPanel)
    }

    // MARK: - Helpers

    private func makeView() throws -> (NativeTextView, NSWindow) {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.isEditable = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "前"),
            DocumentRun(text: "链接", marks: [.link("https://example.com")]),
            DocumentRun(text: "后")
        ])])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        window.makeFirstResponder(view)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        return (view, window)
    }

    private func pointInLink(_ view: NativeTextView, window: NSWindow) throws -> NSPoint {
        let linkStart = ("前" as NSString).length
        let screen = view.firstRect(forCharacterRange: NSRange(location: linkStart, length: 1),
                                    actualRange: nil)
        let windowPoint = window.convertFromScreen(
            NSRect(origin: NSPoint(x: screen.midX, y: screen.midY), size: .zero)).origin
        return view.convert(windowPoint, from: nil)
    }
}
