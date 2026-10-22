import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRowHoverTests: XCTestCase {
    func testNativeHoverIsVisibleBehindTheActualTaskControls() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "悬停绘制验收", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: id))
        let host = NSHostingView(rootView: TaskRowView(task: task, workspace: workspace,
            depth: 0, hasChildren: false, expanded: false, selected: false,
            onSelect: {}, onComplete: {}, onRestore: {}, onToggleExpanded: {})
            .frame(width: 390, height: 60).background(WFColors.content)
            .environmentObject(AppEnvironment()))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 60)
        defer { window.close() }
        func hoverView(_ view: NSView) -> TaskRowHoverView? {
            if let value = view as? TaskRowHoverView { return value }
            return view.subviews.lazy.compactMap { hoverView($0) }.first
        }
        func color() throws -> NSColor {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            return try XCTUnwrap(bitmap.colorAt(x: Int(382 * scale), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        }
        let before = try color()
        let view = try XCTUnwrap(hoverView(host))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseEntered(with: event)
        let after = try color()
        XCTAssertLessThan(after.redComponent, before.redComponent - 0.01)
    }

    func testMovingBetweenRowsUpdatesNativeHighlightWithoutWaitingForLayout() throws {
        let first = TaskRowHoverView(frame: CGRect(x: 0, y: 0, width: 390, height: 50))
        let second = TaskRowHoverView(frame: CGRect(x: 0, y: 50, width: 390, height: 50))
        let pointer = TaskRowPointerState()
        second.onHover = { pointer.update($0) }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        first.mouseEntered(with: event)
        XCTAssertGreaterThan(first.layer?.backgroundColor?.alpha ?? 0, 0)
        first.mouseExited(with: event)
        second.mouseEntered(with: event)
        XCTAssertEqual(first.layer?.backgroundColor?.alpha, 0)
        XCTAssertGreaterThan(second.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertTrue(pointer.inside)
        XCTAssertTrue(second.layer?.animationKeys()?.isEmpty ?? true)
        XCTAssertNil(second.hitTest(CGPoint(x: 20, y: 20)), "灰底不能拦截标题、勾选和拖放")
        second.mouseExited(with: event)
        XCTAssertEqual(second.layer?.backgroundColor?.alpha, 0)
        XCTAssertFalse(pointer.inside)
    }

    func testSelectedRowKeepsItsSelectionColorAfterPointerLeaves() throws {
        let view = TaskRowHoverView(frame: CGRect(x: 0, y: 0, width: 390, height: 50))
        view.setSelected(true)
        let selectedColor = try XCTUnwrap(view.layer?.backgroundColor)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseEntered(with: event)
        view.mouseExited(with: event)
        XCTAssertEqual(view.layer?.backgroundColor, selectedColor)
        view.setSelected(false)
        XCTAssertEqual(view.layer?.backgroundColor?.alpha, 0)
    }
}
