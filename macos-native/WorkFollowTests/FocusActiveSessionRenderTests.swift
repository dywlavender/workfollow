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
        case naturalCompletion
        case stopwatchIdle
        case stopwatchRunning
        case stopwatchPaused
        case stopwatchCompleted
        case presetLibraryDetail
        case expandedIdle

        var isStopwatch: Bool {
            self == .stopwatchIdle || self == .stopwatchRunning || self == .stopwatchPaused || self == .stopwatchCompleted
        }
        var isCompleted: Bool { self == .breakOverview || self == .naturalCompletion || self == .stopwatchCompleted }
        var isNavigationFixture: Bool { self == .presetLibraryDetail || self == .expandedIdle }
    }

    func testActiveSessionTimelineNotesAndControlsRenderContracts() throws {
        for state in RenderState.allCases where !state.isStopwatch && !state.isNavigationFixture {
            let rendered = try render(state)
            XCTAssertTrue(rendered.screenshotExists, "Screenshot missing for \(state.rawValue)")

            if state.isCompleted {
                let divider = try XCTUnwrap(rendered.frames[.divider])
                let summary = try XCTUnwrap(rendered.frames[.completionSummary])
                let figure = try XCTUnwrap(rendered.frames[.completionFigure])
                let timeline = try XCTUnwrap(rendered.frames[.activeTimeline])
                let note = try XCTUnwrap(rendered.frames[.activeFocusNote])
                XCTAssertLessThanOrEqual(summary.maxX, divider.minX + 0.5)
                XCTAssertGreaterThan(timeline.minX, divider.maxX)
                XCTAssertGreaterThan(note.minX, divider.maxX)
                XCTAssertEqual(divider.minX, 567, accuracy: 0.75)
                XCTAssertEqual(figure.size, CGSize(width: 180, height: 180))
                XCTAssertEqual(figure.midX, 283.5, accuracy: 0.75)
                XCTAssertEqual(figure.midY, 280, accuracy: 0.75)
                XCTAssertEqual(timeline.height, 410, accuracy: 0.75)
                XCTAssertEqual(note.height, 106, accuracy: 0.75)
                XCTAssertNil(rendered.frames[.focusDurationTrigger],
                             "The completed record has its own duration editor")
                XCTAssertNotNil(rendered.frames[.editCompletedDuration])
                XCTAssertNil(rendered.frames[.focusModeSegment])
                XCTAssertNil(rendered.frames[.focusAddTimerButton])
                XCTAssertNil(rendered.frames[.focusRunningStatus])
                if state == .naturalCompletion {
                    let start = try XCTUnwrap(rendered.frames[.completionStartBreak])
                    let skip = try XCTUnwrap(rendered.frames[.completionSkipBreak])
                    let exit = try XCTUnwrap(rendered.frames[.completionExit])
                    XCTAssertEqual(start.size, CGSize(width: 123, height: 48))
                    XCTAssertEqual(start.minY, 525, accuracy: 0.75)
                    XCTAssertEqual(skip.minY - start.maxY, 16, accuracy: 0.75)
                    XCTAssertEqual(exit.minY - skip.maxY, 16, accuracy: 0.75)
                }
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

    func testStopwatchIdleRunningAndPausedRenderContracts() throws {
        for state in [RenderState.stopwatchIdle, .stopwatchRunning, .stopwatchPaused] {
            let rendered = try render(state)
            let frames = rendered.frames
            XCTAssertTrue(rendered.screenshotExists, "Screenshot missing for \(state.rawValue)")

            let ring = try XCTUnwrap(frames[.timerRing])
            let dial = try XCTUnwrap(frames[.focusStopwatchDial],
                                     "Stopwatch mode must render radial ticks")
            let digits = try XCTUnwrap(frames[.focusTimerDigits])
            XCTAssertEqual(dial.size, CGSize(width: FocusLayoutMetrics.ringSize,
                                              height: FocusLayoutMetrics.ringSize))
            XCTAssertEqual(digits.midX, ring.midX, accuracy: 0.5)
            XCTAssertNil(frames[.focusDurationTrigger],
                         "Stopwatch digits are not a duration-edit trigger")

            if state == .stopwatchIdle {
                XCTAssertEqual(FocusViewLogic.clockText(rendered.elapsedSeconds), "00:00")
                XCTAssertNotNil(frames[.focusModeSegment])
                XCTAssertNil(frames[.focusAddTimerButton])
                XCTAssertNotNil(frames[.activeTimeline],
                                "Expanded idle stopwatch keeps the same timeline workspace")
                XCTAssertNotNil(frames[.activeFocusNote])
                XCTAssertNil(frames[.overviewFirstCard])
                continue
            }

            XCTAssertNotNil(frames[.activeTimeline])
            XCTAssertNotNil(frames[.activeFocusNoteHeader])
            XCTAssertNotNil(frames[.activeFocusNote])
            XCTAssertNil(frames[.focusModeSegment])
            XCTAssertNil(frames[.focusAddTimerButton])
            XCTAssertNil(frames[.activeTimelineFocusFill],
                         "An elapsed stopwatch session has no projected end block")
            XCTAssertNil(rendered.projection?.endYRatio)
            XCTAssertEqual(FocusViewLogic.clockText(rendered.elapsedSeconds), "00:42")

            if state == .stopwatchRunning {
                XCTAssertNotNil(frames[.focusPauseButton])
                XCTAssertNil(frames[.focusResumeButton])
                XCTAssertNil(frames[.focusEndButton])
                XCTAssertNil(frames[.focusPausedTimerLabel])
            } else {
                XCTAssertNil(frames[.focusPauseButton])
                let resume = try XCTUnwrap(frames[.focusResumeButton])
                let end = try XCTUnwrap(frames[.focusEndButton])
                XCTAssertEqual(resume.midX, end.midX, accuracy: 0.5)
                XCTAssertLessThan(resume.maxY, end.minY)
                XCTAssertNotNil(frames[.focusPausedTimerLabel])
            }
        }
    }

    func testStopwatchCompletionUsesCompletedRecordOnLeftAndEditableNotesOnRight() throws {
        let rendered = try render(.stopwatchCompleted)
        let summary = try XCTUnwrap(rendered.frames[.completionSummary])
        let divider = try XCTUnwrap(rendered.frames[.divider])
        let timeline = try XCTUnwrap(rendered.frames[.activeTimeline])
        let note = try XCTUnwrap(rendered.frames[.activeFocusNote])
        XCTAssertLessThanOrEqual(summary.maxX, divider.minX + 0.5)
        XCTAssertGreaterThan(timeline.minX, divider.maxX)
        XCTAssertGreaterThan(note.minX, divider.maxX)
        XCTAssertNotNil(rendered.frames[.editCompletedDuration])
        XCTAssertNil(rendered.frames[.completionStartBreak])
        XCTAssertNil(rendered.frames[.activeTimelineFocusFill])
        XCTAssertNil(rendered.frames[.timerRing])
    }

    func testPresetLibraryDetailAndCompactTimerUseSeparatePanelsAtReferenceSize() throws {
        let rendered = try render(.presetLibraryDetail)
        let divider = try XCTUnwrap(rendered.frames[.divider])
        let library = try XCTUnwrap(rendered.frames[.presetLibrary])
        let row = try XCTUnwrap(rendered.frames[.presetLibraryFirstRow])
        let compactTimer = try XCTUnwrap(rendered.frames[.presetLibraryTimerBar])
        let detail = try XCTUnwrap(rendered.frames[.presetDetail])
        let cards = try XCTUnwrap(rendered.frames[.presetDetailCards])
        XCTAssertEqual(divider.minX, 567, accuracy: 0.75)
        XCTAssertLessThanOrEqual(library.maxX, divider.minX + 0.5)
        XCTAssertGreaterThanOrEqual(detail.minX, divider.maxX - 0.5)
        XCTAssertEqual(row.height, 54, accuracy: 0.75)
        XCTAssertEqual(compactTimer.height, 64, accuracy: 0.75)
        XCTAssertEqual(compactTimer.maxY, 859, accuracy: 0.75)
        XCTAssertEqual(cards.height, 72, accuracy: 0.75)
        XCTAssertNotNil(rendered.frames[.presetDetailChart])
        XCTAssertNil(rendered.frames[.timerRing])
    }

    func testExplicitlyExpandedIdleTimerHasTimelineAndNotesInsteadOfOverview() throws {
        let rendered = try render(.expandedIdle)
        XCTAssertNotNil(rendered.frames[.timerRing])
        XCTAssertNotNil(rendered.frames[.timerBackToLibrary])
        XCTAssertNotNil(rendered.frames[.focusModeSegment])
        XCTAssertNotNil(rendered.frames[.activeTimeline])
        XCTAssertNotNil(rendered.frames[.activeFocusNote])
        XCTAssertNil(rendered.frames[.overviewFirstCard])
        XCTAssertNil(rendered.frames[.activeTimelineFocusFill])
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
        let size = state.isCompleted || state == .presetLibraryDetail
            ? CGSize(width: 1_450, height: 859) : CGSize(width: 1_600, height: 900)
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

        let projection: FocusTimelineProjection? = fixture.store.displayedSessionTiming.map {
            FocusTimelineProjection.make(timing: $0, now: fixture.now(), calendar: .current)
        }
        let elapsedSeconds = fixture.store.elapsedSeconds
        let screenshotURL = try capture(window, state: state)
        window.orderOut(nil)
        flushAndRemove(fixture.store, directory: fixture.directory)

        return RenderedState(frames: frames, projection: projection,
                             elapsedSeconds: elapsedSeconds,
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
        case .stopwatchIdle:
            precondition(store.setStopwatchMode(true))
            store.showTimerWorkspace()
        case .stopwatchRunning:
            precondition(store.setStopwatchMode(true))
            precondition(store.start())
            clockNow = initialNow.addingTimeInterval(42)
            store.refresh()
            store.updateCurrentSessionNote("正计时进行中")
        case .stopwatchPaused:
            precondition(store.setStopwatchMode(true))
            precondition(store.start())
            clockNow = initialNow.addingTimeInterval(42)
            store.refresh()
            precondition(store.pause())
            clockNow = initialNow.addingTimeInterval(142)
            store.refresh()
            store.updateCurrentSessionNote("正计时暂停中")
        case .stopwatchCompleted:
            precondition(store.start(stopwatch: true))
            store.updateCurrentSessionNote("正计时完成笔记")
            clockNow = initialNow.addingTimeInterval(90)
            precondition(store.finishEarly() != nil)
        case .presetLibraryDetail:
            precondition(store.setFocusMinutes(180))
            precondition(store.addTimer(name: "阅读", emoji: "📚", stopwatch: false, minutes: 10))
            precondition(store.addTimer(name: "五分钟", emoji: "🍅", stopwatch: false, minutes: 5))
            let preset = store.timers[0]
            var draft = FocusRecordDraft(now: clockNow, presetID: preset.id)
            draft.startedAt = clockNow.addingTimeInterval(-600); draft.creditedPomodoros = 1
            precondition(store.saveRecordDraft(draft))
            store.selectPresetForDetails(preset.id)
        case .expandedIdle:
            store.showPresetLibrary(); store.showTimerWorkspace()
            store.updateCurrentSessionNote("开始前的笔记")
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
        case .naturalCompletion:
            precondition(store.setAutoStartBreak(false))
            precondition(store.start(minutes: 5))
            store.updateCurrentSessionNote("五分钟完成笔记")
            clockNow = initialNow.addingTimeInterval(300)
            store.refresh()
            precondition(store.pendingBreak)
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
        let elapsedSeconds: Int
        let screenshotExists: Bool
    }
}
