import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusRenderTests: XCTestCase {
    private enum TimerState: String, CaseIterable {
        case idleWithoutRecords
        case idleWithOneRecord
    }

    private struct RenderCase {
        let size: CGSize
        let colorScheme: ColorScheme
        let colorName: String
        let appearanceName: NSAppearance.Name
        let timerState: TimerState
    }

    func testIdleLibraryOverviewGeometryAcrossReferenceRenderMatrix() throws {
        let sizes = [CGSize(width: 1_440, height: 900), CGSize(width: 1_600, height: 900)]
        let schemes: [(colorScheme: ColorScheme, colorName: String,
                       appearanceName: NSAppearance.Name)] = [
            (colorScheme: .light, colorName: "light", appearanceName: .aqua),
            (colorScheme: .dark, colorName: "dark", appearanceName: .darkAqua)
        ]
        let cases = sizes.flatMap { size in
            schemes.flatMap { scheme in
                TimerState.allCases.map {
                    RenderCase(size: size, colorScheme: scheme.colorScheme,
                               colorName: scheme.colorName,
                               appearanceName: scheme.appearanceName, timerState: $0)
                }
            }
        }

        for renderCase in cases {
            let result = try render(renderCase)
            let frames = result.frames
            let rail = try XCTUnwrap(frames[.rail], "Icon Rail frame missing")
            let selectedHitArea = try XCTUnwrap(frames[.railSelectedHitArea],
                                                "Selected Rail hit area missing")
            let divider = try XCTUnwrap(frames[.divider], "Focus divider frame missing")
            let library = try XCTUnwrap(frames[.presetLibrary], "Idle entry must show the library")
            let compactTimer = try XCTUnwrap(frames[.presetLibraryTimerBar])
            let card = try XCTUnwrap(frames[.overviewFirstCard], "First Overview card frame missing")
            let recordsHeader = try XCTUnwrap(frames[.recordsHeader], "Records header frame missing")

            let shellDividerX = WFMetrics.railWidth + WFMetrics.divider
            let workspaceWidth = renderCase.size.width - shellDividerX
            let expectedFocusWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: workspaceWidth, isCompleted: true)
            let expectedDividerX = shellDividerX + expectedFocusWidth
            let expectedCardWidth = (renderCase.size.width - expectedDividerX - WFMetrics.divider
                - 2 * FocusLayoutMetrics.overviewHorizontalPadding - FocusLayoutMetrics.overviewCardGap) / 2

            XCTAssertEqual(rail.minX, 0, accuracy: 0.5)
            XCTAssertEqual(rail.width, RailMetrics.width, accuracy: 0.5)
            XCTAssertEqual(selectedHitArea.width, RailMetrics.hitSize, accuracy: 0.5)
            XCTAssertEqual(selectedHitArea.height, RailMetrics.hitSize, accuracy: 0.5)
            XCTAssertEqual(divider.minX, expectedDividerX, accuracy: 0.5)
            XCTAssertEqual(divider.width, WFMetrics.divider, accuracy: 0.5)
            XCTAssertEqual(library.maxX, divider.minX, accuracy: 0.5)
            XCTAssertEqual(compactTimer.height, 64, accuracy: 0.5)
            XCTAssertEqual(compactTimer.maxY, renderCase.size.height, accuracy: 0.5)
            XCTAssertNil(frames[.timerRing])
            XCTAssertNil(frames[.activeTimeline])
            XCTAssertEqual(card.minX, divider.maxX + FocusLayoutMetrics.overviewHorizontalPadding,
                           accuracy: 0.5)
            XCTAssertEqual(card.width, expectedCardWidth, accuracy: 0.5)
            XCTAssertEqual(card.height, FocusLayoutMetrics.overviewCardHeight, accuracy: 0.5)
            XCTAssertEqual(card.minY, 61, accuracy: 0.5,
                           "Overview card top edge moved from the rendered reference")
            XCTAssertEqual(recordsHeader.minY, 277.75, accuracy: 0.5,
                           "Records header moved from the rendered reference")
            if renderCase.timerState == .idleWithoutRecords {
                let illustration = try XCTUnwrap(frames[.emptyRecordsIllustration],
                                                 "Empty records illustration missing")
                let emptyContent = try XCTUnwrap(frames[.emptyRecordsContent],
                                                 "Empty records content missing")
                let emptyRegion = try XCTUnwrap(frames[.emptyRecordsRegion],
                                                "Empty records region missing")
                XCTAssertEqual(illustration.width, FocusLayoutMetrics.recordEmptyIllustrationWidth,
                               accuracy: 0.5)
                XCTAssertEqual(illustration.height, FocusLayoutMetrics.recordEmptyIllustrationHeight,
                               accuracy: 0.5)
                XCTAssertEqual(emptyContent.midY, emptyRegion.midY, accuracy: 0.5,
                               "Empty state must center inside the records region")
            } else {
                XCTAssertNil(frames[.emptyRecordsIllustration],
                             "An empty-state illustration must not render with records")
            }
            XCTAssertTrue(result.screenshotExists)
        }
    }

    func testExplicitlyExpandedIdleTimerGeometryAcrossSizesAndAppearances() throws {
        for size in [CGSize(width: 1_440, height: 900), CGSize(width: 1_600, height: 900)] {
            for dark in [false, true] {
                let renderCase = RenderCase(size: size, colorScheme: dark ? .dark : .light,
                    colorName: dark ? "dark" : "light", appearanceName: dark ? .darkAqua : .aqua,
                    timerState: .idleWithoutRecords)
                let result = try render(renderCase, expandsTimer: true)
                let frames = result.frames
                let divider = try XCTUnwrap(frames[.divider])
                let ring = try XCTUnwrap(frames[.timerRing])
                let duration = try XCTUnwrap(frames[.focusDurationTrigger])
                let mode = try XCTUnwrap(frames[.focusModeSegment])
                let start = try XCTUnwrap(frames[.primaryButton])
                let timeline = try XCTUnwrap(frames[.activeTimeline])
                let note = try XCTUnwrap(frames[.activeFocusNote])
                let shellDividerX = WFMetrics.railWidth + WFMetrics.divider
                let leftWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: size.width - shellDividerX)
                XCTAssertEqual(divider.minX, shellDividerX + leftWidth, accuracy: 0.5)
                XCTAssertEqual(ring.midX, shellDividerX + leftWidth / 2, accuracy: 0.5)
                XCTAssertEqual(ring.midY, FocusLayoutMetrics.ringTop + FocusLayoutMetrics.ringSize / 2, accuracy: 0.5)
                XCTAssertEqual(ring.width, 238, accuracy: 0.5)
                XCTAssertTrue(ring.insetBy(dx: -0.5, dy: -0.5).contains(duration))
                XCTAssertEqual(mode.midX, ring.midX, accuracy: 0.5)
                XCTAssertEqual(start.midX, ring.midX, accuracy: 0.5)
                XCTAssertEqual(start.midY, FocusLayoutMetrics.footerTop(paneHeight: size.height) + 24, accuracy: 0.5)
                XCTAssertGreaterThan(timeline.minX, divider.maxX)
                XCTAssertGreaterThan(note.minX, divider.maxX)
                XCTAssertNotNil(frames[.timerBackToLibrary])
                XCTAssertNil(frames[.focusAddTimerButton], "Presets are added in the library")
                XCTAssertNil(frames[.overviewFirstCard])
                XCTAssertNil(frames[.presetLibrary])
                XCTAssertTrue(result.screenshotExists)
            }
        }
    }

    func testFocusWorkspaceMinimumWidthContract() throws {
        let minimumWorkspaceWidth = FocusLayoutMetrics.minimumWorkspaceWidth
        XCTAssertEqual(minimumWorkspaceWidth, 1_051)
        let focusWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: minimumWorkspaceWidth)
        let overviewWidth = minimumWorkspaceWidth - focusWidth - FocusLayoutMetrics.dividerWidth
        XCTAssertEqual(focusWidth, 430)
        XCTAssertEqual(overviewWidth, 620)

        let fixture = makeFixture(state: .idleWithoutRecords)
        let host = NSHostingView(rootView: FocusWorkspaceShellView(
            workspace: fixture.workspace,
            navigation: fixture.navigation,
            store: fixture.store,
            onNavigate: { fixture.navigation.destination = $0 },
            onOpenQuickOpen: {},
            onSelectRecordTask: { _ in }
        ))
        XCTAssertGreaterThanOrEqual(host.fittingSize.width,
                                    minimumWorkspaceWidth + WFMetrics.railWidth + WFMetrics.divider,
                                    "Window content must enforce a minimum instead of squeezing Overview")
        flushAndRemove(fixture.store, directory: fixture.directory)
    }

    private func render(_ renderCase: RenderCase, expandsTimer: Bool = false) throws -> (frames: [FocusRenderAnchor: CGRect], screenshotExists: Bool) {
        let fixture = makeFixture(state: renderCase.timerState)
        if expandsTimer { fixture.store.showTimerWorkspace() }
        var frames: [FocusRenderAnchor: CGRect] = [:]
        let root = FocusWorkspaceShellView(
            workspace: fixture.workspace,
            navigation: fixture.navigation,
            store: fixture.store,
            onNavigate: { fixture.navigation.destination = $0 },
            onOpenQuickOpen: {},
            onSelectRecordTask: { id in
                fixture.workspace.select(id)
                fixture.navigation.destination = .allTasks
            })
            .preferredColorScheme(renderCase.colorScheme)
            .coordinateSpace(name: FocusRenderAnchor.coordinateSpaceName)
            .onPreferenceChange(FocusRenderFramesPreferenceKey.self) { frames = $0 }

        let contentRect = NSRect(origin: .zero, size: renderCase.size)
        let window = NSWindow(contentRect: contentRect, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: renderCase.appearanceName)
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

        let route = expandsTimer ? "timer" : "library"
        let name = "focus-render-\(route)-\(Int(renderCase.size.width))x\(Int(renderCase.size.height))-"
            + "\(renderCase.timerState.rawValue)-\(renderCase.colorName).png"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("focus-render-contract")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshotURL = directory.appendingPathComponent(name)
        let image = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: screenshotURL)

        window.orderOut(nil)
        flushAndRemove(fixture.store, directory: fixture.directory)
        return (frames, FileManager.default.fileExists(atPath: screenshotURL.path))
    }

    private func makeFixture(state: TimerState) -> (workspace: TaskWorkspaceModel,
                                                    navigation: AppNavigation,
                                                    store: FocusStore,
                                                    directory: URL) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false,
                                           initialTasks: [], initialLists: [])
        let navigation = AppNavigation()
        navigation.destination = .focus
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusRenderTests-\(UUID().uuidString)", isDirectory: true)
        let store = FocusStore(clock: { now }, directory: directory)
        if state == .idleWithOneRecord {
            precondition(store.addRecord(taskID: nil,
                                         startedAt: now.addingTimeInterval(-3_600), minutes: 25))
        }
        return (workspace, navigation, store, directory)
    }

    private func flushAndRemove(_ store: FocusStore, directory: URL) {
        let flushed = expectation(description: "flush isolated render fixture")
        store.flush { _ in flushed.fulfill() }
        wait(for: [flushed], timeout: 5)
        try? FileManager.default.removeItem(at: directory)
    }
}
