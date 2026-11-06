import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class FirstMouseActionTests: XCTestCase {
    func testInactiveWindowCatcherOwnsOnlyItsVisibleControl() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let neighbor = NSView(frame: NSRect(x: 10, y: 20, width: 80, height: 40))
        let catcher = FirstMouseAction.Catcher(frame: NSRect(x: 150, y: 20, width: 80, height: 40))
        root.addSubview(neighbor); root.addSubview(catcher)
        let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(root.hitTest(NSPoint(x: 170, y: 40)) === catcher)
        XCTAssertTrue(root.hitTest(NSPoint(x: 40, y: 40)) === neighbor,
            "透明首击控件不能抢走旁边控件的点击")
        catcher.isHidden = true
        XCTAssertFalse(root.hitTest(NSPoint(x: 170, y: 40)) === catcher)
    }
}
