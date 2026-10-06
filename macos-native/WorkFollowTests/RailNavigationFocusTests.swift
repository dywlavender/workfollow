import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class RailNavigationFocusTests: XCTestCase {
    private final class KeyboardButton: NSButton {
        override var acceptsFirstResponder: Bool { true }
    }

    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testPointerNavigationEndsEditingBeforeRemovingOldPage() throws {
        let window = window()
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 220, height: 25))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        editor.string = "Committed title"
        var cleared = 0, navigated = false
        RailNavigationFocus.activate(eventType: .leftMouseUp, window: window,
                                    clearRailFocus: { cleared += 1 }) {
            XCTAssertNil(field.currentEditor())
            XCTAssertEqual(field.stringValue, "Committed title")
            navigated = true
        }
        XCTAssertTrue(navigated)
        XCTAssertEqual(cleared, 2)
        XCTAssertNil(field.currentEditor())
    }

    func testKeyboardNavigationKeepsResponderAndDoesNotClearRailFocus() {
        let window = window()
        defer { window.close() }
        let button = KeyboardButton(frame: NSRect(x: 20, y: 20, width: 40, height: 40))
        window.contentView?.addSubview(button)
        XCTAssertTrue(window.makeFirstResponder(button))
        var cleared = false, navigated = false
        RailNavigationFocus.activate(eventType: .keyDown, window: window,
                                    clearRailFocus: { cleared = true }, navigate: { navigated = true })
        XCTAssertTrue(navigated)
        XCTAssertFalse(cleared)
        XCTAssertTrue(window.firstResponder === button)
    }
}
