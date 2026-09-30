import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusDurationPopoverRenderTests: XCTestCase {
    func testIdleDurationLayerIsArrowlessAndBelowClockWithoutMovingRing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-duration-popover-\(UUID().uuidString)",
                                   isDirectory: true)
        let store = FocusStore(clock: Date.init, directory: directory)
        let session = FocusDurationEditorSession()
        var frames: [FocusRenderAnchor: CGRect] = [:]
        let root = FocusTimerRing(
            store: store,
            durationEditor: session,
            theme: FocusTheme(.light),
            taskTitle: nil,
            onEditDuration: {
                session.present(currentMinutes: store.preferences.focusMinutes)
            }
        )
        .focusRenderAnchor(.timerRing)
        .frame(width: 260, height: 260)
        .frame(width: 320, height: 320)
        .preferredColorScheme(.light)
        .coordinateSpace(name: FocusRenderAnchor.coordinateSpaceName)
        .focusDurationPopover(session: session,
                              onConfirm: { store.setFocusMinutes($0) })
        .background(Color.white)
        .onPreferenceChange(FocusRenderFramesPreferenceKey.self) { frames = $0 }

        let hostWindow = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 320, height: 320),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.appearance = NSAppearance(named: .aqua)
        hostWindow.backgroundColor = .white
        hostWindow.hasShadow = false
        hostWindow.contentView = NSHostingView(rootView: root)
        hostWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hostWindow.contentView?.layoutSubtreeIfNeeded()
        hostWindow.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let initialRingFrame = try XCTUnwrap(frames[.timerRing])
        let clockFrame = try XCTUnwrap(frames[.focusDurationTrigger],
                                       "Popover anchor must be the clock button, not the whole ring")

        session.present(currentMinutes: store.preferences.focusMinutes)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostWindow.contentView?.layoutSubtreeIfNeeded()

        let fieldEditor = try XCTUnwrap(hostWindow.firstResponder as? NSTextView,
                                        "Opening the editor should focus the minutes field")
        XCTAssertEqual(fieldEditor.string, "25")
        XCTAssertEqual(fieldEditor.selectedRange(), NSRange(location: 0, length: 2),
                       "The existing duration should be selected so typing replaces it")

        let panel = try XCTUnwrap(frames[.focusDurationPopover],
                                  "Arrowless duration layer should render in the same window")
        XCTAssertEqual(panel.size, CGSize(width: 232, height: 104))
        XCTAssertEqual(panel.midX, clockFrame.midX, accuracy: 0.5,
                       "Duration layer should align with the timer digits")
        XCTAssertEqual(panel.minY, clockFrame.maxY + 12, accuracy: 0.5,
                       "Duration layer should sit 12 points below the clock anchor")
        XCTAssertNil(NSApp.windows.first { $0 !== hostWindow && $0.isVisible && $0.parent === hostWindow },
                     "Arrowless layer should not create a system popover window")

        let screenshotURL = try capture(hostWindow)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))

        session.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hostWindow.contentView?.layoutSubtreeIfNeeded()
        XCTAssertNil(frames[.focusDurationPopover], "Cancel should dismiss the duration editor")
        XCTAssertEqual(try XCTUnwrap(frames[.timerRing]), initialRingFrame,
                       "Showing and closing the popover must not move the timer ring")
        XCTAssertEqual(try XCTUnwrap(frames[.focusDurationTrigger]), clockFrame,
                       "Showing and closing the popover must not move the clock anchor")

        hostWindow.orderOut(nil)
        flush(store)
        try? FileManager.default.removeItem(at: directory)
    }

    private func capture(_ window: NSWindow) throws -> URL {
        let image = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]),
            "Could not capture the actual system popover window")
        let bitmap = NSBitmapImageRep(cgImage: image)
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
}
