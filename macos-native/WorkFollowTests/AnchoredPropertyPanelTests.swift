import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AnchoredPropertyPanelTests: XCTestCase {
    private typealias Adapter = AnchoredPropertyPanel<AnyView>

    // Capture native event dispatch after local monitors have returned the event.
    private final class EventWindow: NSWindow {
        var received: NSEvent?
        override func sendEvent(_ event: NSEvent) { received = event }
    }

    private func owner() -> EventWindow {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let window = EventWindow(contentRect: CGRect(x: screen.minX + 80, y: screen.minY + 100,
                                                     width: 260, height: 506),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: 506))
        window.orderFront(nil)
        return window
    }

    private func coordinator(in owner: NSWindow, row: CGRect = CGRect(x: 14, y: 320, width: 232, height: 34),
                             height: CGFloat = 180) -> Adapter.Coordinator {
        let anchor = Adapter.AnchorView(frame: row)
        owner.contentView!.addSubview(anchor)
        let coordinator = Adapter.Coordinator()
        coordinator.anchor = anchor
        coordinator.presented = true
        coordinator.width = ScheduleMetrics.optionPanelWidth
        coordinator.root = AnyView(Color.clear.frame(height: height))
        coordinator.update()
        settle(coordinator.host)
        return coordinator
    }

    private func settle(_ view: NSView? = nil) {
        view?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view?.layoutSubtreeIfNeeded()
    }

    private func mouse(in window: NSWindow, at point: CGPoint, type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                           clickCount: 1, pressure: 1)!
    }

    func testRealChildHostFitsContentAndAnchorsWithoutResizingParent() throws {
        let owner = owner()
        let baseline = owner.frame
        let coordinator = coordinator(in: owner)
        defer { coordinator.close(); owner.close() }
        let panel = try XCTUnwrap(coordinator.panel)
        let host = try XCTUnwrap(coordinator.host)
        let anchor = try XCTUnwrap(coordinator.anchor)
        XCTAssertTrue(panel.contentView === host)
        XCTAssertTrue(panel.parent === owner)
        XCTAssertTrue(owner.childWindows?.contains(where: { $0 === panel }) == true)
        XCTAssertEqual(panel.title, "日期属性")
        XCTAssertTrue(panel.canBecomeKey, "自定义提醒与重复输入框必须能获得键盘焦点")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(host.fittingSize.width, ScheduleMetrics.optionPanelWidth, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.height, 180, accuracy: 0.5)
        let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertEqual(panel.frame.minX, row.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, row.minY, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, host.fittingSize.height, accuracy: 0.5)
        XCTAssertEqual(owner.frame, baseline)

        coordinator.root = AnyView(Color.clear.frame(height: 240))
        coordinator.update()
        settle(host)
        XCTAssertTrue(coordinator.panel === panel)
        XCTAssertTrue(coordinator.host === host)
        XCTAssertEqual(panel.frame.height, 240, accuracy: 0.5)
        XCTAssertEqual(owner.frame, baseline)
    }

    func testSearchPanelKeepsItsInputAndWindowAcrossLayoutRefresh() throws {
        let owner = owner()
        let coordinator = coordinator(in: owner)
        defer { coordinator.close(); owner.close() }
        XCTAssertFalse(try XCTUnwrap(coordinator.panel).isKeyWindow,
                       "Default presentation must preserve the presenter focus")
        coordinator.close()
        coordinator.focusPolicy = .panel
        var query = ""
        coordinator.root = AnyView(TextField("搜索", text: Binding(get: { query }, set: { query = $0 }))
            .textFieldStyle(.plain).frame(height: 32))
        coordinator.update()
        settle(coordinator.host)
        let panel = try XCTUnwrap(coordinator.panel)
        XCTAssertTrue(panel.isKeyWindow)
        let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
        editor.insertText("搜索内容", replacementRange: editor.selectedRange())
        coordinator.update()
        settle(coordinator.host)
        XCTAssertTrue(coordinator.panel === panel)
        XCTAssertTrue(panel.firstResponder === editor)
        XCTAssertEqual(editor.string, "搜索内容")
        XCTAssertEqual(query, "搜索内容")
    }

    func testBottomRowFlipsRealChildAboveAnchor() throws {
        let owner = owner()
        let screen = try XCTUnwrap(owner.screen).visibleFrame
        owner.setFrameOrigin(CGPoint(x: screen.minX + 80, y: screen.minY + 8))
        let baseline = owner.frame
        let coordinator = coordinator(in: owner, row: CGRect(x: 14, y: 10, width: 232, height: 34))
        defer { coordinator.close(); owner.close() }
        let anchor = try XCTUnwrap(coordinator.anchor)
        let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let panel = try XCTUnwrap(coordinator.panel)
        XCTAssertEqual(panel.frame.minY, row.maxY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, screen.minY + 8)
        XCTAssertLessThanOrEqual(panel.frame.maxY, screen.maxY - 8)
        XCTAssertEqual(owner.frame, baseline)
    }

    func testRepeatEndCalendarPrefersAboveWithoutChangingParent() throws {
        let owner = owner()
        let baseline = owner.frame
        let coordinator = coordinator(in: owner, row: CGRect(x: 14, y: 80, width: 232, height: 30), height: 240)
        defer { coordinator.close(); owner.close() }
        coordinator.prefersAbove = true
        coordinator.update()
        settle(coordinator.host)
        let anchor = try XCTUnwrap(coordinator.anchor)
        let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertEqual(try XCTUnwrap(coordinator.panel).frame.minY, row.maxY, accuracy: 0.5)
        XCTAssertEqual(owner.frame, baseline)
    }

    func testChildCanExtendPastParentBottomWhileStayingBelowRow() throws {
        let owner = owner()
        let screen = try XCTUnwrap(owner.screen).visibleFrame
        owner.setFrameOrigin(CGPoint(x: screen.minX + 80, y: screen.minY + 240))
        let baseline = owner.frame
        let coordinator = coordinator(in: owner, row: CGRect(x: 14, y: 80, width: 232, height: 34))
        defer { coordinator.close(); owner.close() }
        let anchor = try XCTUnwrap(coordinator.anchor)
        let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let child = try XCTUnwrap(coordinator.panel)
        XCTAssertEqual(child.frame.maxY, row.minY, accuracy: 0.5)
        XCTAssertLessThan(child.frame.minY, baseline.minY)
        XCTAssertEqual(child.frame.height, 180, accuracy: 0.5)
        XCTAssertTrue(child.parent === owner)
        XCTAssertEqual(owner.frame, baseline)
    }

    func testOutsideClickCancelsAndPassesOriginalEventToParent() throws {
        let owner = owner()
        let coordinator = coordinator(in: owner)
        var cancels = 0
        coordinator.dismiss = { [weak coordinator] in
            cancels += 1
            coordinator?.presented = false
            coordinator?.close()
        }
        defer { coordinator.close(); owner.close() }
        let panel = try XCTUnwrap(coordinator.panel)
        let anchor = try XCTUnwrap(coordinator.anchor)
        let rowPoint = anchor.convert(CGPoint(x: 10, y: 10), to: nil)
        let rowEvent = mouse(in: owner, at: rowPoint)
        NSApp.sendEvent(rowEvent)
        XCTAssertEqual(cancels, 0)
        XCTAssertTrue(owner.received === rowEvent)
        NSApp.sendEvent(mouse(in: panel, at: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(cancels, 0)
        let outside = mouse(in: owner, at: CGPoint(x: 5, y: 5))
        NSApp.sendEvent(outside)
        XCTAssertEqual(cancels, 1)
        XCTAssertTrue(owner.received === outside)
        XCTAssertNil(coordinator.panel)
        XCTAssertNil(coordinator.host)
        XCTAssertNil(coordinator.interactionRegistration)
        XCTAssertNil(panel.parent)
        XCTAssertFalse(panel.isVisible)
    }

    func testEscapeClosesChildBeforeParentForEitherOwnedWindow() throws {
        for targetChild in [false, true] {
            let owner = owner()
            let coordinator = coordinator(in: owner)
            var parentCalls = 0
            var childCalls = 0
            let registration = PopupEscapeRegistry.shared.register(view: owner.contentView!, depth: 2) {
                parentCalls += 1
            }
            coordinator.dismiss = { [weak coordinator] in
                childCalls += 1
                coordinator?.presented = false
                coordinator?.close()
            }
            defer {
                PopupEscapeRegistry.shared.unregister(registration)
                coordinator.close()
                owner.close()
            }
            let child = try XCTUnwrap(coordinator.panel)
            XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: targetChild ? child : owner))
            settle()
            XCTAssertEqual(childCalls, 1)
            XCTAssertEqual(parentCalls, 0)
            XCTAssertNil(coordinator.panel)
            XCTAssertNil(coordinator.interactionRegistration)
            XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: owner))
            XCTAssertEqual(parentCalls, 1)
        }
    }

    func testDismantlingAdapterUnloadsChildAndMonitor() throws {
        let owner = owner()
        let coordinator = coordinator(in: owner)
        let child = try XCTUnwrap(coordinator.panel)
        let anchor = try XCTUnwrap(coordinator.anchor)
        defer { coordinator.close(); owner.close() }
        XCTAssertNotNil(coordinator.interactionRegistration)
        Adapter.dismantleNSView(anchor, coordinator: coordinator)
        settle()
        XCTAssertFalse(coordinator.presented)
        XCTAssertNil(anchor.moved)
        XCTAssertNil(coordinator.panel)
        XCTAssertNil(coordinator.host)
        XCTAssertNil(coordinator.interactionRegistration)
        XCTAssertNil(child.parent)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(owner.childWindows?.isEmpty ?? true)
        XCTAssertFalse(PopupEscapeRegistry.shared.route(eventWindow: owner))
    }

    func testDescendantClickRetainsParentAndParentClickClosesOnlyChild() throws {
        let owner = owner()
        let parent = coordinator(in: owner)
        let parentWindow = try XCTUnwrap(parent.panel)
        let child = coordinator(in: parentWindow)
        var parentDismissals = 0
        var childDismissals = 0
        parent.dismiss = { parentDismissals += 1 }
        child.dismiss = { childDismissals += 1 }
        defer { child.close(); parent.close(); owner.close() }
        let event = mouse(in: try XCTUnwrap(child.panel), at: CGPoint(x: 5, y: 5))
        XCTAssertTrue(PopupInteractionRegistry.shared.routeMouseDown(event) === event)
        XCTAssertEqual(parentDismissals, 0)
        XCTAssertEqual(childDismissals, 0)
        let parentClick = mouse(in: parentWindow, at: CGPoint(x: 5, y: 5))
        XCTAssertTrue(PopupInteractionRegistry.shared.routeMouseDown(parentClick) === parentClick)
        XCTAssertEqual(parentDismissals, 0)
        XCTAssertEqual(childDismissals, 1)
    }

    func testUnrelatedWindowClickClosesPanelAndPreservesEvent() throws {
        let owner = owner()
        let other = self.owner()
        let coordinator = coordinator(in: owner)
        var calls = 0
        coordinator.dismiss = { calls += 1 }
        defer { coordinator.close(); owner.close(); other.close() }
        let event = mouse(in: other, at: CGPoint(x: 5, y: 5))
        XCTAssertTrue(PopupInteractionRegistry.shared.routeMouseDown(event) === event)
        XCTAssertEqual(calls, 1)
    }

    func testKeyTransferWithinFamilyRetainsPanelButOtherWindowDismisses() throws {
        let owner = owner()
        let other = self.owner()
        let coordinator = coordinator(in: owner)
        var calls = 0
        coordinator.dismiss = { calls += 1 }
        defer { coordinator.close(); owner.close(); other.close() }
        let child = try XCTUnwrap(coordinator.panel)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: child)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: owner)
        XCTAssertEqual(calls, 0)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        XCTAssertEqual(calls, 1)
    }

    func testApplicationDeactivationClosesPanelAndUnregisters() throws {
        let owner = owner()
        let coordinator = coordinator(in: owner)
        coordinator.dismiss = { [weak coordinator] in
            coordinator?.presented = false
            coordinator?.close()
        }
        defer { coordinator.close(); owner.close() }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertNil(coordinator.panel)
        XCTAssertNil(coordinator.interactionRegistration)
    }

    func testClosingParentUnloadsChildAndMonitorWithoutAnotherUpdate() throws {
        let owner = owner()
        let coordinator = coordinator(in: owner)
        let child = try XCTUnwrap(coordinator.panel)
        defer { coordinator.close() }
        owner.close()
        settle()
        XCTAssertNil(coordinator.panel, "parent 关闭后应主动卸载 child，无需等待 SwiftUI update")
        XCTAssertNil(coordinator.host)
        XCTAssertNil(coordinator.interactionRegistration)
        XCTAssertNil(child.parent)
        XCTAssertFalse(child.isVisible)
    }
}
