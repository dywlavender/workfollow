import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class PopupEscapeRoutingTests: XCTestCase {
    func testCompositionGetsEscapeBeforeRegisteredPopup() {
        let registry = PopupEscapeRegistry()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NativeTextView(frame: window.contentLayoutRect, textContainer: nil)
        window.contentView = editor
        window.orderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertTrue(window.firstResponder === editor)
        var dismissals = 0
        let id = registry.register(view: editor, depth: 2) { dismissals += 1 }
        defer { registry.unregister(id); window.close() }
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(registry.route(eventWindow: window))
        XCTAssertEqual(dismissals, 0)
        editor.unmarkText()
        XCTAssertTrue(registry.route(eventWindow: window))
        XCTAssertEqual(dismissals, 1)
    }

    func testExplicitPresenterRoutesEscapeWhenPopoverHasNoParentWindow() {
        let registry = PopupEscapeRegistry()
        let presenter = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        let panel = NSWindow(contentRect: presenter.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let unrelated = NSWindow(contentRect: presenter.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [presenter, panel, unrelated] { window.isReleasedWhenClosed = false }
        let view = NSView(frame: panel.contentLayoutRect)
        panel.contentView = view
        panel.orderFront(nil)
        XCTAssertNil(panel.parent)
        var calls = 0
        let id = registry.register(view: view, depth: 2, presentingWindow: { [weak presenter] in presenter }) { calls += 1 }
        defer {
            registry.unregister(id)
            for window in [presenter, panel, unrelated] { window.close() }
        }
        XCTAssertTrue(registry.route(eventWindow: presenter))
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(registry.route(eventWindow: unrelated))
        panel.orderOut(nil)
        XCTAssertFalse(registry.route(eventWindow: presenter))
    }

    func testWindowOwnershipDepthAndCleanup() {
        let registry = PopupEscapeRegistry()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        other.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let child = NSView(frame: .zero)
        root.addSubview(child)
        window.contentView = root
        window.orderFront(nil)
        var parentCalls = 0
        var childCalls = 0
        // Register the parent LAST: depth must win over monitor registration order.
        let childID = registry.register(view: child, depth: 2) { childCalls += 1 }
        let parentID = registry.register(view: root, depth: 1) { parentCalls += 1 }
        defer {
            registry.unregister(childID); registry.unregister(parentID)
            window.contentView = nil; window.close(); other.close()
        }
        XCTAssertFalse(registry.route(eventWindow: nil))
        XCTAssertFalse(registry.route(eventWindow: other))
        XCTAssertTrue(registry.route(eventWindow: window))
        XCTAssertEqual(childCalls, 1)
        XCTAssertEqual(parentCalls, 0)
        registry.unregister(childID)
        XCTAssertTrue(registry.route(eventWindow: window))
        XCTAssertEqual(parentCalls, 1)
        root.isHidden = true
        XCTAssertFalse(registry.route(eventWindow: window))
        root.isHidden = false
        window.orderOut(nil)
        XCTAssertFalse(registry.route(eventWindow: window))
    }

    func testDetachedOwnerDoesNotConsumeEscape() {
        let registry = PopupEscapeRegistry()
        let view = NSView()
        var calls = 0
        let id = registry.register(view: view, depth: 2) { calls += 1 }
        defer { registry.unregister(id) }
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        XCTAssertFalse(registry.route(eventWindow: window))
        XCTAssertEqual(calls, 0)
    }

    func testSystemModalPreventsBackgroundPopupFromConsumingEscape() {
        let registry = PopupEscapeRegistry()
        let owner = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        let modal = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        modal.isReleasedWhenClosed = false
        let view = NSView(frame: owner.contentLayoutRect)
        owner.contentView = view
        owner.orderFront(nil)
        var calls = 0
        let id = registry.register(view: view, depth: 2) { calls += 1 }
        let session = NSApp.beginModalSession(for: modal)
        XCTAssertNotNil(NSApp.modalWindow)
        XCTAssertFalse(registry.route(eventWindow: owner))
        XCTAssertEqual(calls, 0)
        NSApp.endModalSession(session)
        XCTAssertTrue(registry.route(eventWindow: owner))
        registry.unregister(id)
        owner.contentView = nil
        owner.close(); modal.close()
    }
}
