import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorScrollRoutingTests: XCTestCase {
    private final class RecordingScrollView: NSScrollView {
        var wheelEvents: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) { wheelEvents.append(event) }
    }
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
    private final class WheelEvent: NSEvent {
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
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    func testGrowingEditorForwardsUpAndDownWithAdjacentScrollRegion() throws {
        let shell = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let scroll = RecordingScrollView(frame: NSRect(x: 220, y: 0, width: 580, height: 400))
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 580, height: 1800))
        let editor = FlippedView(frame: NSRect(x: 28, y: 60, width: 500, height: 1600))
        document.addSubview(editor)
        scroll.documentView = document
        shell.addSubview(scroll)
        let sidebar = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))
        shell.addSubview(sidebar)
        let window = InspectorPanelTestSupport.ownerWindow(for: shell, width: 800, height: 400)
        defer { window.close() }
        let point = editor.convert(NSPoint(x: 80, y: 100), to: nil)
        let down = try wheel(in: window, point: point, dy: -28)
        let up = try wheel(in: window, point: point, dy: 28)
        XCTAssertTrue(EditorHostScrollRouting.forward(down, over: editor, enabled: true))
        XCTAssertTrue(EditorHostScrollRouting.forward(up, over: editor, enabled: true))
        XCTAssertTrue(scroll.wheelEvents.first === down, "Preserve the native event, rather than synthesizing a delta")
        XCTAssertTrue(scroll.wheelEvents.last === up)
        let neighbor = try wheel(in: window, point: NSPoint(x: 100, y: 200), dy: -28)
        XCTAssertFalse(EditorHostScrollRouting.forward(neighbor, over: editor, enabled: true))
        XCTAssertEqual(scroll.wheelEvents.count, 2, "The editor must not intercept sidebar scrolling")
    }

    func testInnerMenuHorizontalWheelAndFixedViewportKeepTheirEvents() throws {
        let scroll = RecordingScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))
        let editor = FlippedView(frame: NSRect(x: 0, y: 0, width: 560, height: 1400))
        scroll.documentView = editor
        let window = InspectorPanelTestSupport.ownerWindow(for: scroll, width: 560, height: 400)
        defer { window.close() }
        let point = editor.convert(NSPoint(x: 80, y: 100), to: nil)
        let vertical = try wheel(in: window, point: point, dy: -20)
        XCTAssertFalse(EditorHostScrollRouting.forward(vertical, over: editor, enabled: false))
        XCTAssertFalse(EditorHostScrollRouting.forward(vertical, over: editor, enabled: true,
            internalScrollRegions: [NSRect(x: 40, y: 70, width: 224, height: 260)]))
        let horizontal = try wheel(in: window, point: point, dx: -30, dy: -2)
        XCTAssertFalse(EditorHostScrollRouting.forward(horizontal, over: editor, enabled: true))
        XCTAssertTrue(scroll.wheelEvents.isEmpty)
        XCTAssertTrue(EditorHostScrollRouting.forward(vertical, over: editor, enabled: true),
                      "Closing the menu restores outer scrolling")
    }

    func testSwiftUIScrollHostUsesSlimDraggableOverlay() throws {
        let host = NSHostingView(rootView: ScrollView {
            Text(String(repeating: "长正文\n", count: 100))
                .frame(maxWidth: .infinity).compactScrollbars()
        }.frame(width: 420, height: 260))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 260)
        defer { window.close() }
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        let scroller = try XCTUnwrap(scroll.verticalScroller as? CompactOverlayScroller)
        XCTAssertEqual(scroller.controlSize, .small)
        XCTAssertTrue(scroll.autohidesScrollers)
        let thumb = CompactOverlayScroller.thumbRect(in: NSRect(x: 0, y: 20, width: 15, height: 80))
        XCTAssertEqual(thumb.width, 3, "编辑区/任务列表/侧栏统一约 3pt 细条")
        XCTAssertEqual(thumb.midX, 7.5, accuracy: 0.01, "细条在命中轨道内居中")
        XCTAssertNotNil(scroller.target, "Keep the scroll view's native knob target")
        XCTAssertNotNil(scroller.action)
    }

    /// 选项面板的横向滚动同样要细：之前只处理竖向，横条会退回系统粗滚条。
    func testHorizontalScrollHostUsesSlimDraggableOverlay() throws {
        let host = NSHostingView(rootView: ScrollView(.horizontal) {
            Text(String(repeating: "格式选项 ", count: 80)).fixedSize()
                .frame(maxHeight: .infinity)
                .compactScrollbars()
        }.frame(width: 320, height: 120))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 320, height: 120)
        defer { window.close() }
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        let scroller = try XCTUnwrap(scroll.horizontalScroller as? CompactOverlayScroller)
        XCTAssertEqual(scroller.controlSize, .small)
        let thumb = CompactOverlayScroller.thumbRect(in: NSRect(x: 20, y: 0, width: 80, height: 15),
                                                     isHorizontal: true)
        XCTAssertEqual(thumb.height, 3)
        XCTAssertEqual(thumb.midY, 7.5, accuracy: 0.01, "横条在命中轨道内居中")
        XCTAssertNotNil(scroller.target)
        XCTAssertNotNil(scroller.action)
    }

    /// 修饰器直接加在 ScrollView 外层（不再放进内容里）也要生效：
    /// 设置页、筛选弹窗等大量深层页面都是这种写法。
    func testScrollViewLevelModifierStylesTheHost() throws {
        let host = NSHostingView(rootView: ScrollView {
            Text(String(repeating: "深层页面正文\n", count: 100))
                .frame(maxWidth: .infinity)
        }
        .frame(width: 420, height: 260)
        .compactScrollbars())
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 260)
        defer { window.close() }
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        XCTAssertTrue(scroll.verticalScroller is CompactOverlayScroller)
        XCTAssertTrue(scroll.autohidesScrollers)
    }

    /// TextEditor 的滚动视图在宿主 ScrollView 内部，不能先被外层截走。
    func testTextEditorModifierStylesItsOwnScrollView() throws {
        let text = (1...40).map { "第 \($0) 行：长文本用来撑出滚动。" }.joined(separator: "\n")
        let host = NSHostingView(rootView: ScrollView {
            TextEditor(text: .constant(text))
                .frame(height: 120)
                .compactTextEditorScrollbars()
        }
        .frame(width: 420, height: 300)
        .compactScrollbars())
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 300)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let textScroll = try XCTUnwrap(findScroll(in: host, where: { $0.documentView is NSTextView }))
        XCTAssertEqual(textScroll.scrollerStyle, .overlay)
        let scroller = try XCTUnwrap(textScroll.verticalScroller as? CompactOverlayScroller)
        XCTAssertEqual(scroller.controlSize, .small)
        XCTAssertTrue(textScroll.autohidesScrollers)
        XCTAssertNotNil(scroller.target, "Keep the scroll view's native knob target")
        XCTAssertNotNil(scroller.action)
    }

    /// 外层横向滚动 + 每列纵向滚动：修饰器加在列外层时不能被外层截走。
    func testNestedScrollViewModifierStylesInnerScrolls() throws {
        let host = NSHostingView(rootView: ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { column in
                    ScrollView {
                        VStack {
                            ForEach(0..<30, id: \.self) { row in
                                Text("任务 \(column)-\(row)").frame(width: 160)
                            }
                        }
                    }
                    .frame(width: 180, height: 180)
                    .compactScrollbars()
                }
            }
        }
        .frame(width: 420, height: 240)
        .compactScrollbars())
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 240)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let scrolls = allScrolls(in: host)
        let columns = scrolls.filter { $0.hasVerticalScroller }
        XCTAssertEqual(columns.count, 2)
        for column in columns {
            XCTAssertTrue(column.verticalScroller is CompactOverlayScroller)
        }
        let board = try XCTUnwrap(scrolls.first { $0.hasHorizontalScroller })
        XCTAssertTrue(board.horizontalScroller is CompactOverlayScroller)
    }

    /// `/` 菜单（行尾标着「文字格式」的那张选项框）此前没挂紧凑样式。
    func testSlashMenuScrollerIsSlimOverlay() throws {
        let host = NSHostingView(rootView: SlashCommandList(
            commands: DocumentProfile.standardBlockMenuCommands,
            selected: 0, compact: false,
            onSelect: { _ in }, onHover: { _ in })
            .frame(width: 300, height: 200))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 300, height: 200)
        defer { window.close() }
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        let scroller = try XCTUnwrap(scroll.verticalScroller as? CompactOverlayScroller)
        XCTAssertEqual(scroller.controlSize, .small)
        XCTAssertTrue(scroll.autohidesScrollers)
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        findScroll(in: view, where: { _ in true })
    }

    private func allScrolls(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scroll = view as? NSScrollView { result.append(scroll) }
        for subview in view.subviews { result.append(contentsOf: allScrolls(in: subview)) }
        return result
    }

    private func findScroll(in view: NSView, where matches: (NSScrollView) -> Bool) -> NSScrollView? {
        if let scroll = view as? NSScrollView, matches(scroll) { return scroll }
        for subview in view.subviews {
            if let found = findScroll(in: subview, where: matches) { return found }
        }
        return nil
    }

    private func wheel(in window: NSWindow, point: NSPoint, dx: CGFloat = 0, dy: CGFloat) throws -> NSEvent {
        WheelEvent(owner: window, point: point, dx: dx, dy: dy)
    }
}
