import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class FocusDurationOutsideClickTests: XCTestCase {
    func testOverviewClickCancelsDraftAndReturnsOriginalEvent() throws {
        let (window, panel) = makePanel()
        defer { panel.invalidate(); window.close() }
        let session = FocusDurationEditorSession()
        session.present(currentMinutes: 25)
        session.draftText = "60"
        panel.onOutsideClick = { session.cancel() }
        let event = try mouseDown(in: window, at: NSPoint(x: 700, y: 150))

        XCTAssertTrue(panel.routeMouseDown(event) === event,
                      "The Overview control must still receive the original click")
        XCTAssertFalse(session.isPresented)
        XCTAssertEqual(session.draftText, "60", "Dismissal only cancels presentation")
    }

    func testPanelInteriorUsesActualWindowCoordinatesAndDoesNotDismiss() throws {
        let (window, panel) = makePanel()
        defer { panel.invalidate(); window.close() }
        var dismissals = 0
        panel.onOutsideClick = { dismissals += 1 }
        let point = panel.convert(NSPoint(x: 20, y: 20), to: nil)
        let event = try mouseDown(in: window, at: point)

        XCTAssertTrue(panel.routeMouseDown(event) === event)
        XCTAssertEqual(dismissals, 0)
        XCTAssertNil(panel.hitTest(NSPoint(x: 20, y: 20)),
                     "The observation view must not intercept the editor controls")
    }

    func testOtherWindowClickDoesNotDismissOrConsumeEvent() throws {
        let (owner, panel) = makePanel()
        let (other, _) = makePanel()
        defer { panel.invalidate(); owner.close(); other.close() }
        var dismissals = 0
        panel.onOutsideClick = { dismissals += 1 }
        let event = try mouseDown(in: other, at: NSPoint(x: 700, y: 150))

        XCTAssertTrue(panel.window === owner)
        XCTAssertTrue(panel.routeMouseDown(event) === event)
        XCTAssertEqual(dismissals, 0)
    }

    func testSecondaryClicksAlsoDismissWithoutConsumption() throws {
        let (window, panel) = makePanel()
        defer { panel.invalidate(); window.close() }
        var dismissals = 0
        panel.onOutsideClick = { dismissals += 1 }
        for type in [NSEvent.EventType.rightMouseDown, .otherMouseDown] {
            let event = try mouseDown(in: window, at: NSPoint(x: 700, y: 150), type: type)
            XCTAssertTrue(panel.routeMouseDown(event) === event)
        }
        XCTAssertEqual(dismissals, 2)
    }

    func testDetachReattachAndDismantleCleanUpWindowOwnership() throws {
        let (original, panel) = makePanel()
        let (replacement, _) = makePanel()
        defer { panel.invalidate(); original.close(); replacement.close() }
        var dismissals = 0
        panel.onOutsideClick = { dismissals += 1 }
        XCTAssertTrue(panel.isMonitoring)

        panel.removeFromSuperview()
        XCTAssertFalse(panel.isMonitoring)
        let oldEvent = try mouseDown(in: original, at: NSPoint(x: 700, y: 150))
        XCTAssertTrue(panel.routeMouseDown(oldEvent) === oldEvent)
        XCTAssertEqual(dismissals, 0)

        try XCTUnwrap(replacement.contentView).addSubview(panel)
        XCTAssertTrue(panel.isMonitoring)
        _ = panel.routeMouseDown(oldEvent)
        XCTAssertEqual(dismissals, 0)
        let newEvent = try mouseDown(in: replacement, at: NSPoint(x: 700, y: 150))
        _ = panel.routeMouseDown(newEvent)
        XCTAssertEqual(dismissals, 1)

        panel.invalidate()
        XCTAssertFalse(panel.isMonitoring)
        XCTAssertNil(panel.onOutsideClick)
        _ = panel.routeMouseDown(newEvent)
        XCTAssertEqual(dismissals, 1)
    }

    private func makePanel() -> (NSWindow, FocusDurationOutsideClickView) {
        // Unshown windows exercise AppKit ownership without activating the app.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 30, y: 40, width: 320, height: 500))
        let panel = FocusDurationOutsideClickView(
            frame: NSRect(x: 50, y: 70, width: 232, height: 104))
        window.contentView?.addSubview(container)
        container.addSubview(panel)
        return (window, panel)
    }

    private func mouseDown(in window: NSWindow, at point: NSPoint,
                           type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                        timestamp: 0, windowNumber: window.windowNumber,
                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}
