import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusActiveSessionRenderTests: XCTestCase {
    private enum RenderState: String, CaseIterable {
        case running25m
        case paused25m
        case running180mClipped
        case running25mDark
        case breakOverview
    }

    func testActiveSessionTimelineNotesAndControlsRenderContracts() throws {
        for state in RenderState.allCases {
            let rendered = try render(state)
            XCTAssertTrue(rendered.screenshotExists, "Screenshot missing for \(state.rawValue)")

            if state == .breakOverview {
                XCTAssertNotNil(rendered.frames[.overviewFirstCard],
                                "Break phases retain the existing Overview pane")
                XCTAssertNil(rendered.frames[.activeTimeline])
                XCTAssertNil(rendered.frames[.focusDurationTrigger],
                             "Duration editing is unavailable during breaks")
                XCTAssertNotNil(rendered.frames[.focusModeSegment],
                                "Breaks are not active focus sessions")
                XCTAssertNotNil(rendered.frames[.focusAddTimerButton])
                XCTAssertNotNil(rendered.frames[.focusRunningStatus],
                                "Keep the existing break status line")
                continue
            }

            let frames = rendered.frames
            XCTAssertNil(frames[.focusDurationTrigger],
                         "Duration editing is unavailable during an active focus session")
            XCTAssertNil(frames[.focusModeSegment],
                         "The mode switch is hidden while focus is running or paused")
            XCTAssertNil(frames[.focusAddTimerButton],
                         "Add-timer is hidden while focus is running or paused")
            XCTAssertNil(frames[.focusRunningStatus],
                         "Running and paused focus omit the extra status line")
            let tomatoIcon = try XCTUnwrap(frames[.activeSessionTomatoIcon],
                                           "Active header must use the fixed vector tomato icon")
            XCTAssertEqual(tomatoIcon.size, CGSize(width: 20, height: 20))
            let projection = try XCTUnwrap(rendered.projection)
            let timeline = try XCTUnwrap(frames[.activeTimeline])
            let ring = try XCTUnwrap(frames[.timerRing])
            let line = try XCTUnwrap(frames[.activeTimelineCurrentLine])
            let dot = try XCTUnwrap(frames[.activeTimelineCurrentDot])
            let noteHeader = try XCTUnwrap(frames[.activeFocusNoteHeader])
            let note = try XCTUnwrap(frames[.activeFocusNote])

            XCTAssertEqual(timeline.height, FocusLayoutMetrics.timelineHeight, accuracy: 0.5)
            XCTAssertEqual(note.height, FocusLayoutMetrics.focusNoteHeight, accuracy: 0.5)
            XCTAssertEqual(dot.width, FocusLayoutMetrics.timelineCurrentDotSize, accuracy: 0.5)
            XCTAssertEqual(dot.midY, line.midY, accuracy: 0.5)
            XCTAssertGreaterThan(note.minY, noteHeader.maxY)

            for (index, anchor) in tickAnchors.enumerated() {
                let tick = try XCTUnwrap(frames[anchor], "Timeline tick \(index) missing")
                XCTAssertEqual(tick.midY, timeline.minY + CGFloat(index) * timeline.height / 4,
                               accuracy: 0.75)
            }

            let expectedY = projection.currentYRatio * timeline.height
            XCTAssertEqual(dot.midY - timeline.minY, expectedY, accuracy: 0.75)

            if let fill = frames[.activeTimelineFocusFill], let endRatio = projection.endYRatio {
                XCTAssertEqual(fill.minY, timeline.minY + expectedY, accuracy: 0.75)
                XCTAssertEqual(fill.maxY - timeline.minY, endRatio * timeline.height, accuracy: 0.75)
            } else {
                XCTFail("Countdown focus interval should render a blue fill in \(state.rawValue)")
            }

            if state == .running25m || state == .running25mDark || state == .running180mClipped {
                let pause = try XCTUnwrap(frames[.focusPauseButton])
                XCTAssertEqual(pause.midX, ring.midX, accuracy: 0.5,
                               "Pause should be centered under the timer ring")
                XCTAssertEqual(pause.width, FocusLayoutMetrics.primaryButtonWidth, accuracy: 0.5)
                XCTAssertEqual(pause.height, FocusLayoutMetrics.primaryButtonHeight, accuracy: 0.5)
                XCTAssertNil(frames[.focusResumeButton])
                XCTAssertNil(frames[.focusEndButton])
                XCTAssertNil(frames[.focusPausedTimerLabel])
            } else {
                XCTAssertNil(frames[.focusPauseButton])
                let resume = try XCTUnwrap(frames[.focusResumeButton])
                let end = try XCTUnwrap(frames[.focusEndButton])
                XCTAssertEqual(resume.midX, end.midX, accuracy: 0.5)
                XCTAssertLessThan(resume.maxY, end.minY,
                                  "Continue and End should be vertically stacked")
                XCTAssertEqual(resume.width, FocusLayoutMetrics.primaryButtonWidth, accuracy: 0.5)
                XCTAssertEqual(end.width, FocusLayoutMetrics.primaryButtonWidth, accuracy: 0.5)
                XCTAssertEqual(resume.height, FocusLayoutMetrics.primaryButtonHeight, accuracy: 0.5)
                XCTAssertEqual(end.height, FocusLayoutMetrics.primaryButtonHeight, accuracy: 0.5)
                XCTAssertNotNil(frames[.focusPausedTimerLabel],
                                "Paused countdown retains the in-ring 已暂停 label")
            }

            if state == .running180mClipped {
                XCTAssertEqual(try XCTUnwrap(projection.endYRatio), 1, accuracy: 0.0001)
                XCTAssertEqual(projection.visibleProjectedEndAt, projection.visibleEnd)
            }
        }
    }

    private var tickAnchors: [FocusRenderAnchor] {
        [.activeTimelineTick0, .activeTimelineTick1, .activeTimelineTick2,
         .activeTimelineTick3, .activeTimelineTick4]
    }

    private func render(_ state: RenderState) throws -> RenderedState {
        let fixture = makeFixture(state)
        var frames: [FocusRenderAnchor: CGRect] = [:]
        let colorScheme: ColorScheme = state == .running25mDark ? .dark : .light
        let appearance: NSAppearance.Name = state == .running25mDark ? .darkAqua : .aqua
        let size = CGSize(width: 1_600, height: 900)
        let root = FocusWorkspaceView(store: fixture.store, workspace: nil)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(colorScheme)
            .coordinateSpace(name: FocusRenderAnchor.coordinateSpaceName)
            .onPreferenceChange(FocusRenderFramesPreferenceKey.self) { frames = $0 }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.hasShadow = false
        let hostingView = NSHostingView(rootView: root)
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let projection: FocusTimelineProjection? = fixture.store.sessionTiming.map {
            FocusTimelineProjection.make(timing: $0, now: fixture.now(), calendar: .current)
        }
        let screenshotURL = try capture(window, state: state)
        window.orderOut(nil)
        flushAndRemove(fixture.store, directory: fixture.directory)

        return RenderedState(frames: frames, projection: projection,
                             screenshotExists: FileManager.default.fileExists(atPath: screenshotURL.path))
    }

    private func makeFixture(_ state: RenderState) -> (store: FocusStore,
                                                        now: () -> Date,
                                                        directory: URL) {
        let calendar = Calendar.current
        let initialNow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30,
                                                             hour: 13, minute: 37))!
        var clockNow = initialNow
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusActiveRender-\(UUID().uuidString)", isDirectory: true)
        let store = FocusStore(clock: { clockNow }, directory: directory)

        switch state {
        case .running25m, .running25mDark:
            precondition(store.start(minutes: 25))
            store.updateCurrentSessionNote("整理今天的优先事项")
        case .paused25m:
            clockNow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30,
                                                          hour: 13, minute: 12))!
            precondition(store.start(minutes: 50))
            clockNow = initialNow
            store.refresh()
            precondition(store.pause())
            store.updateCurrentSessionNote("先记录评审结论")
            clockNow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30,
                                                          hour: 13, minute: 50))!
            store.refresh()
        case .running180mClipped:
            precondition(store.start(minutes: 180))
            store.updateCurrentSessionNote("长专注记录")
        case .breakOverview:
            precondition(store.start(minutes: 5))
            clockNow = initialNow.addingTimeInterval(5 * 60)
            store.refresh()
            precondition(store.phase == .breaking)
        }
        return (store, { clockNow }, directory)
    }

    private func capture(_ window: NSWindow, state: RenderState) throws -> URL {
        guard let content = window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw NSError(domain: "FocusActiveSessionRender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Window view could not be rendered"])
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-active-session-render", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(state.rawValue).png")
        try png.write(to: url)
        return url
    }

    private func flushAndRemove(_ store: FocusStore, directory: URL) {
        let flushed = expectation(description: "flush Focus render fixture")
        store.flush { _ in flushed.fulfill() }
        wait(for: [flushed], timeout: 5)
        try? FileManager.default.removeItem(at: directory)
    }

    private struct RenderedState {
        let frames: [FocusRenderAnchor: CGRect]
        let projection: FocusTimelineProjection?
        let screenshotExists: Bool
    }
}
