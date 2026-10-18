import AppKit
import XCTest
@testable import WorkFollow

/// TI2-21：行首块手柄的点击通道。
///
/// 滴答证据：`TTTaskDetailMarkdownCell.leadingButtonClicked:` / `refreshLeadingIcon`
/// 与 `md_vertical_*` 竖排块类型菜单。本地把"空行 + / 标题 H 角标 / 正文六点手柄"
/// 统一到同一条沟槽命中区：点开都走块类型菜单（Slash 面板的空查询态）；
/// 列表/检查项/引用/代码行不接管（行首标记另有职责）。
@MainActor
final class DocumentBlockMenuTests: XCTestCase {

    func testBlockMenuOpensForPlainBodyLine() throws {
        let (view, window) = try makeView(kind: .paragraph, text: "正文内容")
        defer { view.dismissSlash(); window.close() }
        let point = try menuPoint(view)

        XCTAssertTrue(view.openBlockMenu(at: point))
        XCTAssertNotNil(view.slashSession, "点手柄应打开块类型菜单")
    }

    func testBlockMenuOpensForHeadingLine() throws {
        let (view, window) = try makeView(kind: .heading(2), text: "二级标题")
        defer { view.dismissSlash(); window.close() }
        let point = try menuPoint(view)

        XCTAssertTrue(view.openBlockMenu(at: point))
        XCTAssertNotNil(view.slashSession)
    }

    func testBlockMenuDoesNotStealChecklistMarker() throws {
        let (view, window) = try makeView(kind: .checklist(false), text: "检查项")
        defer { view.dismissSlash(); window.close() }
        let point = try menuPoint(view)

        XCTAssertFalse(view.openBlockMenu(at: point), "检查项行首是完成框，不能变成块菜单")
        XCTAssertNil(view.slashSession)
    }

    func testBlockMenuIgnoresClicksOutsideTheMarkerColumn() throws {
        let (view, window) = try makeView(kind: .paragraph, text: "正文内容")
        defer { view.dismissSlash(); window.close() }
        let line = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
        let point = NSPoint(x: line.maxX, y: line.midY)

        XCTAssertFalse(view.openBlockMenu(at: point))
        XCTAssertNil(view.slashSession)
    }

    // MARK: - Helpers

    private func makeView(kind: DocumentBlockKind, text: String) throws -> (NativeTextView, NSWindow) {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: kind,
                                                             runs: [DocumentRun(text: text)])])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [])
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return (view, window)
    }

    private func menuPoint(_ view: NativeTextView) throws -> NSPoint {
        let line = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
        return NSPoint(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: view.decorationVisibleMinX) + 2,
                       y: line.midY)
    }
}
