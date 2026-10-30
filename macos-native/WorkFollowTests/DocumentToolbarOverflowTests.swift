import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 正文格式工具条的「插入」浮条：固定在最右，只放入插入类动作。
/// （文件名沿用旧“溢出”测试，避免工程文件引用变动。）
@MainActor
final class DocumentToolbarInsertTests: XCTestCase {

    func testInsertCatalogCoversAllExistingInsertActions() {
        let items = DocumentInsertCatalog.items
        XCTAssertEqual(items.map(\.id),
                       ["insert.image", "insert.table", "insert.formula", "insert.link",
                        "insert.codeBlock", "insert.divider", "insert.quote",
                        "insert.attachment", "insert.diagram"])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "插入项 id 不得重复")
        for item in items {
            XCTAssertFalse(item.title.isEmpty, "插入项缺标题：\(item.id)")
            XCTAssertFalse(item.symbol.isEmpty, "插入项缺图标：\(item.id)")
        }
        // 代码块 / 引用复用既有格式命令。
        XCTAssertEqual(EditorCommandCatalog.format("format.codeBlock")?.title, "代码块")
        XCTAssertEqual(EditorCommandCatalog.format("format.quote")?.title, "引用")
    }

    func testToolbarStillLaysOutAtTheContractSize() {
        let host = NSHostingView(rootView: DocumentFormatToolbarView(handle: DocumentEditorHandle()))
        host.frame = NSRect(x: 0, y: 0, width: 444, height: 38)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 445, "工具条宽度仍受 444 契约约束")
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testNarrowToolbarKeepsOneRowAndHidesFormatsInAHorizontalScroller() throws {
        let host = NSHostingView(rootView:
            DocumentFormatToolbarView(handle: DocumentEditorHandle()).frame(width: 340, height: 38))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 38)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 340, height: 38)
        defer { window.close() }
        let scroll = try XCTUnwrap(horizontalScroller(in: host), "窄工具条必须有横向滚动视口")
        let documentWidth = try XCTUnwrap(scroll.documentView?.frame.width)
        XCTAssertGreaterThan(documentWidth, scroll.contentView.bounds.width + 1,
                             "单行工具条在 340pt 下应溢出，而不是折行或压缩")
        XCTAssertGreaterThan(documentWidth, 550,
                             "横向内容必须按理想宽度排版，末尾的时间/代码才滚得到")
        XCTAssertFalse(scroll.hasHorizontalScroller, "横向滚动不显示滚动条")
    }

    func testEveryRegisteredFormatLiesInsideTheScrollableContent() throws {
        var frames: [String: CGRect] = [:]
        let host = NSHostingView(rootView:
            DocumentFormatToolbarView(handle: DocumentEditorHandle(), maxWidth: .infinity)
                .frame(width: 340, height: 38)
                .onPreferenceChange(EditorToolbarCommandFramesKey.self) { frames = $0 })
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 38)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 340, height: 38)
        defer { window.close() }
        for _ in 0..<20 where frames.count < 17 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(frames.count, 17, "所有可滚动格式都应登记落点")
        let scroll = try XCTUnwrap(horizontalScroller(in: host))
        let documentWidth = try XCTUnwrap(scroll.documentView?.frame.width)
        for (id, frame) in frames {
            XCTAssertGreaterThanOrEqual(frame.minX, -0.5, "\(id) 在内容左缘之外")
            XCTAssertLessThanOrEqual(frame.maxX, documentWidth + 0.5,
                                     "\(id) 超出可滚动内容，滚到最右也点不到")
        }
    }

    func testVerticalWheelScrollsTheToolbarHorizontally() throws {
        let host = NSHostingView(rootView:
            DocumentFormatToolbarView(handle: DocumentEditorHandle()).frame(width: 340, height: 38))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 38)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 340, height: 38)
        defer { window.close() }
        let scroll = try XCTUnwrap(horizontalScroller(in: host))
        let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        let down = try wheel(in: window, point: point, dy: -12)
        XCTAssertNil(HorizontalWheelScroll.handle(down, over: scroll),
                     "溢出时纵向滚轮应由横条消费")
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 1,
                             "向下滚轮应把工具条滚向右侧，露出后面的格式")
        let up = try wheel(in: window, point: point, dy: 12)
        XCTAssertNil(HorizontalWheelScroll.handle(up, over: scroll))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.5)
    }

    func testHorizontalGestureAndWideLayoutKeepNativeScrolling() throws {
        let host = NSHostingView(rootView:
            DocumentFormatToolbarView(handle: DocumentEditorHandle(), maxWidth: .infinity)
                .frame(width: 700, height: 38))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 38)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 700, height: 38)
        defer { window.close() }
        let scroll = try XCTUnwrap(horizontalScroller(in: host))
        let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        let wide = try wheel(in: window, point: point, dy: -12)
        XCTAssertTrue(HorizontalWheelScroll.handle(wide, over: scroll) === wide,
                      "宽窗口没有溢出时滚轮应继续交给页面")
    }

    private final class Wheel: NSEvent {
        let owner: NSWindow
        let point: NSPoint
        let dx: CGFloat
        let dy: CGFloat
        init(owner: NSWindow, point: NSPoint, dx: CGFloat, dy: CGFloat) {
            self.owner = owner; self.point = point; self.dx = dx; self.dy = dy
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("not intended") }
        override var type: NSEvent.EventType { .scrollWheel }
        override var window: NSWindow? { owner }
        override var locationInWindow: NSPoint { point }
        override var scrollingDeltaX: CGFloat { dx }
        override var scrollingDeltaY: CGFloat { dy }
        override var hasPreciseScrollingDeltas: Bool { true }
        override var phase: NSEvent.Phase { .changed }
        override var momentumPhase: NSEvent.Phase { [] }
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    private func wheel(in window: NSWindow, point: NSPoint, dx: CGFloat = 0,
                       dy: CGFloat) throws -> NSEvent {
        Wheel(owner: window, point: point, dx: dx, dy: dy)
    }

    private func horizontalScroller(in root: NSView) -> NSScrollView? {
        if let scroll = root as? NSScrollView { return scroll }
        return root.subviews.lazy.compactMap(horizontalScroller(in:)).first
    }
}
