import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusDurationPopoverRenderTests: XCTestCase {
    func testIdleDurationPopoverOpensAtCompactSizeInARealWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-duration-popover-\(UUID().uuidString)",
                                   isDirectory: true)
        let store = FocusStore(clock: Date.init, directory: directory)
        let session = FocusDurationEditorSession()
        let root = DurationPopoverHost(session: session, store: store)
            .frame(width: 220, height: 80)
            .preferredColorScheme(.light)
        let hostWindow = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 280, height: 140),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.appearance = NSAppearance(named: .aqua)
        hostWindow.backgroundColor = .clear
        hostWindow.hasShadow = false
        let hostingView = NSHostingView(rootView: root)
        hostWindow.contentView = hostingView
        hostWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hostingView.layoutSubtreeIfNeeded()
        hostWindow.displayIfNeeded()

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hostingView.layoutSubtreeIfNeeded()

        let popoverWindow = try XCTUnwrap(
            NSApp.windows.first(where: { $0 !== hostWindow && $0.isVisible && $0.parent === hostWindow }),
            "SwiftUI duration popover did not create a visible AppKit child window; windows: \(NSApp.windows.map { (String(describing: type(of: $0)), $0.frame, $0.isVisible) })"
        )
        let popoverContentSize = try XCTUnwrap(popoverWindow.contentView).bounds.size

        XCTAssertGreaterThanOrEqual(popoverContentSize.width, 232)
        XCTAssertLessThanOrEqual(popoverContentSize.width, 280,
                                 "Duration editor should remain compact, not span a large dialog")
        XCTAssertGreaterThanOrEqual(popoverContentSize.height, 104)
        XCTAssertLessThanOrEqual(popoverContentSize.height, 160,
                                 "Duration editor should fit its controls without excess height")

        let screenshotURL = try capture(popoverWindow)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))

        popoverWindow.orderOut(nil)
        hostWindow.orderOut(nil)
        flush(store)
        try? FileManager.default.removeItem(at: directory)
    }

    private func capture(_ window: NSWindow) throws -> URL {
        guard let content = window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw NSError(domain: "FocusDurationPopoverRender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Popover content could not be rendered"])
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-duration-popover-render", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("idle-duration-popover.png")
        try png.write(to: url)
        return url
    }

    private func flush(_ store: FocusStore) {
        let flushed = expectation(description: "flush isolated duration popover fixture")
        store.flush { _ in flushed.fulfill() }
        wait(for: [flushed], timeout: 5)
    }

    private struct DurationPopoverHost: View {
        @ObservedObject var session: FocusDurationEditorSession
        @ObservedObject var store: FocusStore

        var body: some View {
            Text("25:00")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .popover(isPresented: session.presentationBinding, arrowEdge: .bottom) {
                    FocusDurationPopover(session: session,
                                         onConfirm: { store.setFocusMinutes($0) })
                }
                .onAppear {
                    session.present(currentMinutes: store.preferences.focusMinutes)
                }
        }
    }
}
