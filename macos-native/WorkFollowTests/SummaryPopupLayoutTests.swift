import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SummaryPopupLayoutTests: XCTestCase {
    private typealias Adapter = AnchoredPropertyPanel<AnyView>
    private final class ContentProbe: ObservableObject { @Published var expanded = false }
    private struct ChangingContent: View {
        @ObservedObject var probe: ContentProbe
        var body: some View { Text("自定义日期内容").frame(height: probe.expanded ? 220 : 100) }
    }
    private func settle(_ view: NSView? = nil) {
        view?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view?.layoutSubtreeIfNeeded()
    }
    private func owner() -> NSWindow {
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: CGRect(x: screen.minX + 80, y: screen.minY + 80, width: 500, height: 650),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 650))
        window.orderFront(nil)
        return window
    }

    func testDropdownAlignsToValueButtonAndFallsBackAboveNearScreenBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 1160, y: 650, width: 160, height: 28)
        let size = CGSize(width: SummaryPopoverMetrics.dateWidth, height: 326)
        let below = AnchoredPropertyPanelGeometry.dropdownFrame(anchor: anchor, size: size, bounds: screen)
        XCTAssertEqual(below.maxX, anchor.maxX)
        XCTAssertEqual(below.maxY, anchor.minY - 4)
        let lower = CGRect(x: 1290, y: 20, width: 150, height: 28)
        let above = AnchoredPropertyPanelGeometry.dropdownFrame(anchor: lower, size: size, bounds: screen)
        XCTAssertEqual(above.minY, lower.maxY + 4)
        XCTAssertLessThanOrEqual(above.maxX, screen.maxX - 8)
        XCTAssertGreaterThanOrEqual(above.minX, screen.minX + 8)
    }

    func testRealSummaryControlAnchorsItsPanelToTheValueButton() throws {
        let screen = NSScreen.main!.visibleFrame
        let control = SummarySettingControl(title: "日期", value: "本周（10月19日-10月25日）",
            isPresented: .constant(true), width: SummaryPopoverMetrics.dateWidth) {
            Text("日期选项").frame(height: 100)
        }
        let host = NSHostingView(rootView: control)
        let owner = NSWindow(contentRect: CGRect(x: screen.minX + 200, y: screen.minY + 400, width: 360, height: 38),
            styleMask: [.borderless], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false; owner.contentView = host; owner.orderFront(nil)
        settle(host)
        defer { owner.close() }
        let panel = try XCTUnwrap(owner.childWindows?.first { $0.title == "摘要：日期" })
        XCTAssertEqual(panel.frame.width, SummaryPopoverMetrics.dateWidth, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxX, owner.frame.maxX - 16, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, owner.frame.minY + 5 - 4, accuracy: 0.5)
    }

    func testFullWeekLabelFitsWithoutWrappingInTheNarrowDateMenu() {
        let label = "本周（10月19日-10月25日）" as NSString
        let textWidth = ceil(label.size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width)
        // Outer card padding, row padding, checkmark and its single gap.
        XCTAssertLessThanOrEqual(textWidth + 12 + 24 + 16 + 10, SummaryPopoverMetrics.dateWidth)
    }

    func testChildContentResizesTheSameDropdownWithoutMovingOwnerOrLosingAnchor() throws {
        let owner = owner(), probe = ContentProbe()
        let originalFrame = owner.frame
        let anchor = Adapter.AnchorView(frame: CGRect(x: 360, y: 480, width: 90, height: 28))
        owner.contentView!.addSubview(anchor)
        let coordinator = Adapter.Coordinator()
        coordinator.anchor = anchor; coordinator.width = SummaryPopoverMetrics.dateWidth
        coordinator.placement = .dropdown; coordinator.presented = true
        coordinator.root = AnyView(ChangingContent(probe: probe))
        coordinator.update(); settle(coordinator.host)
        defer { coordinator.close(); owner.close() }
        let panel = try XCTUnwrap(coordinator.panel)
        let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertEqual(panel.frame.maxX, row.maxX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, row.minY - 4, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, 100, accuracy: 0.5)
        probe.expanded = true; settle(coordinator.host)
        XCTAssertTrue(coordinator.panel === panel)
        XCTAssertEqual(panel.frame.height, 220, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxX, row.maxX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, row.minY - 4, accuracy: 0.5)
        probe.expanded = false; settle(coordinator.host)
        XCTAssertEqual(panel.frame.height, 100, accuracy: 0.5)
        XCTAssertEqual(owner.frame, originalFrame)
    }

    func testSmallListUsesContentHeightAndLongListKeepsAScrollLimit() throws {
        let owner = owner()
        let anchor = Adapter.AnchorView(frame: CGRect(x: 360, y: 500, width: 90, height: 28))
        owner.contentView!.addSubview(anchor)
        let coordinator = Adapter.Coordinator()
        coordinator.anchor = anchor; coordinator.width = SummaryPopoverMetrics.listWidth
        coordinator.placement = .dropdown; coordinator.presented = true
        func content(_ lists: [String]) -> AnyView {
            AnyView(SummaryListPopover(selected: [], lists: lists, metas: [], folders: [], onApply: { _ in }, onCancel: {}))
        }
        coordinator.root = content(["收集箱", "工作", "学习"])
        coordinator.update(); settle(coordinator.host)
        defer { coordinator.close(); owner.close() }
        let small = try XCTUnwrap(coordinator.panel).frame.size
        XCTAssertEqual(small.width, SummaryPopoverMetrics.listWidth, accuracy: 0.5)
        XCTAssertLessThan(small.height, 270, "少量清单不能仍占一个大滚动面板")
        coordinator.close(); coordinator.presented = true
        coordinator.root = content(["收集箱"] + (1...20).map { "项目清单 \($0)" })
        coordinator.update(); settle(coordinator.host)
        let large = try XCTUnwrap(coordinator.panel).frame.size
        XCTAssertGreaterThan(large.height, small.height)
        XCTAssertLessThan(large.height, 430, "更多清单应在固定上限内滚动")
    }
}
