import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskContextPanelTests: XCTestCase {
    private typealias Adapter = AnchoredPropertyPanel<AnyView>

    private func owner() -> NSWindow {
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: CGRect(x: screen.minX + 40, y: screen.minY + 40,
                                                  width: min(1000, screen.width - 80), height: min(700, screen.height - 80)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: window.contentLayoutRect)
        window.orderFront(nil)
        return window
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    func testCursorCardUsesBorderlessWindowAndCleansAnchor() throws {
        let owner = owner()
        let view = try XCTUnwrap(owner.contentView)
        let originalCount = view.subviews.count
        let session = TaskContextMenuPresenter.Session(in: view, at: CGPoint(x: 350, y: 500))
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "无箭头菜单验收", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.allTasks.first { $0.id == id })
        session.coordinator.root = AnyView(TaskContextMenuPopover(
            workspace: workspace,
            isPresented: Binding(get: { [weak session] in session?.coordinator.presented == true },
                                 set: { [weak session] value in if !value { session?.close() } }),
            task: task, onCustomDate: {}))
        session.coordinator.update()
        settle()
        defer { session.close(); owner.close() }
        let panel = try XCTUnwrap(session.coordinator.panel)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.parent === owner)
        XCTAssertEqual(panel.frame.width, 264, accuracy: 0.5)
        let anchor = owner.convertToScreen(session.anchor.convert(session.anchor.bounds, to: nil))
        XCTAssertEqual(panel.frame.minX, anchor.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, anchor.minY, accuracy: 0.5)
        session.close()
        XCTAssertNil(session.coordinator.panel)
        XCTAssertEqual(view.subviews.count, originalCount)
        XCTAssertFalse(panel.isVisible)
    }

    func testSubmenuUsesRootBoundsNotSmallMenuBoundsAndEscapeIsHierarchical() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 350, y: 500))
        let presenter = PopupPresentingWindow()
        presenter.window = owner
        session.coordinator.presentingWindow = presenter
        session.coordinator.root = AnyView(Color.clear.frame(height: 350))
        session.coordinator.update()
        settle()
        let main = try XCTUnwrap(session.coordinator.panel)
        let frame = main.frame
        let child = Adapter.Coordinator()
        let anchor = Adapter.AnchorView(frame: CGRect(x: 0, y: 250, width: 264, height: 30))
        let host = try XCTUnwrap(main.contentView)
        let container = NSView(frame: host.frame)
        main.contentView = container
        container.addSubview(host)
        container.addSubview(anchor)
        child.anchor = anchor
        child.width = 196
        child.placement = .submenu
        child.presentingWindow = presenter
        child.presented = true
        child.root = AnyView(Color.clear.frame(height: 300))
        child.dismiss = { child.presented = false; child.close() }
        child.update()
        settle()
        defer { child.close(); session.close(); owner.close() }
        let panel = try XCTUnwrap(child.panel)
        XCTAssertEqual(panel.frame.width, 196, accuracy: 0.5)
        XCTAssertTrue(panel.frame.minX >= main.frame.maxX || panel.frame.maxX <= main.frame.minX)
        XCTAssertEqual(main.frame, frame)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: owner))
        XCTAssertNil(child.panel)
        XCTAssertNotNil(session.coordinator.panel)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: owner))
        XCTAssertNil(session.coordinator.panel)
    }

    func testMainCardFollowsOwnerMovementAndOwnerClose() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 300, y: 400))
        session.coordinator.root = AnyView(Color.clear.frame(height: 200))
        session.coordinator.update()
        settle()
        defer { session.close(); owner.close() }
        let panel = try XCTUnwrap(session.coordinator.panel)
        let original = panel.frame
        owner.setFrameOrigin(CGPoint(x: owner.frame.minX + 10, y: owner.frame.minY + 10))
        settle()
        XCTAssertEqual(panel.frame.minX, original.minX + 10, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, original.minY + 10, accuracy: 0.5)
        owner.close()
        settle()
        XCTAssertNil(session.coordinator.panel)
        XCTAssertNil(session.anchor.superview)
    }

    func testOutsideClickDismissesButChildClickKeepsMainCard() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 350, y: 500))
        session.coordinator.root = AnyView(Color.clear.frame(height: 350))
        session.coordinator.update()
        session.observeOutsideApplicationClicks()
        settle()
        let main = try XCTUnwrap(session.coordinator.panel)
        let child = NSPanel(contentRect: CGRect(x: main.frame.maxX + 6, y: main.frame.minY, width: 196, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        main.addChildWindow(child, ordered: .above)
        child.orderFront(nil)
        defer { child.close(); session.close(); owner.close() }
        func click(_ window: NSWindow) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: CGPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)))
        }
        try click(child)
        XCTAssertNotNil(session.coordinator.panel)
        try click(owner)
        XCTAssertNil(session.coordinator.panel)
        XCTAssertNil(session.anchor.superview)
    }
}
