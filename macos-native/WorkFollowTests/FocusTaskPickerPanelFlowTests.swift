import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusTaskPickerPanelFlowTests: XCTestCase {
    private final class LayoutState {
        var frames: [String: CGRect] = [:]
    }

    private struct Harness: View {
        let workspace: TaskWorkspaceModel
        @ObservedObject var store: FocusStore
        @ObservedObject var session: FocusTaskPickerSession

        var body: some View {
            FocusTimerPane(store: store, workspace: workspace, taskPicker: session,
                           showGiveUpConfirmation: .constant(false), onAddTimer: {})
                .frame(width: 560, height: 640)
        }
    }

    private struct Fixture {
        let owner: NSWindow
        let host: NSHostingView<AnyView>
        let workspace: TaskWorkspaceModel
        let store: FocusStore
        let session: FocusTaskPickerSession
        let layout: LayoutState
        let directory: URL
    }

    func testSearchReceivesInitialFocusAndPickerKeepsDefaultSize() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let picker = try openPicker(in: fixture)
        XCTAssertEqual(picker.frame.width, FocusTaskPickerMetrics.width, accuracy: 0.5)
        XCTAssertEqual(picker.frame.height, FocusTaskPickerMetrics.height, accuracy: 0.5)
        XCTAssertTrue(picker.firstResponder is NSTextView,
                      "Opening the picker must place keyboard focus in the search input")
    }

    func testScopeSelectionKeepsPickerOpenAndDoesNotResizeParent() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let picker = try openPicker(in: fixture)
        capturePickerFrames(in: picker, fixture: fixture)
        let parentFrame = picker.frame
        try clickPickerAnchor("scope", in: picker, fixture: fixture)
        settle(fixture)

        let scopePanel = try XCTUnwrap(childPanel(in: picker))
        XCTAssertEqual(scopePanel.frame.width, FocusTaskPickerMetrics.scopeWidth, accuracy: 0.5)
        XCTAssertEqual(picker.frame, parentFrame)
        try clickScopeRow(index: 1, in: scopePanel)
        settle(fixture)

        XCTAssertEqual(fixture.session.scope, .tomorrow)
        XCTAssertFalse(fixture.session.isScopePickerPresented)
        XCTAssertTrue(fixture.session.isPresented)
        XCTAssertTrue(picker.isVisible)
        XCTAssertFalse(scopePanel.isVisible)
        XCTAssertEqual(picker.frame, parentFrame)
    }

    func testEscapeClosesScopeThenPickerAcrossRealPanelWindows() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let picker = try openPicker(in: fixture)
        capturePickerFrames(in: picker, fixture: fixture)
        try clickPickerAnchor("scope", in: picker, fixture: fixture)
        settle(fixture)
        let scopePanel = try XCTUnwrap(childPanel(in: picker))
        XCTAssertTrue(picker.parent === fixture.owner)
        XCTAssertTrue(scopePanel.parent === picker)

        sendEscape(to: picker)
        settle(fixture)
        XCTAssertFalse(scopePanel.isVisible)
        XCTAssertTrue(picker.isVisible)
        XCTAssertTrue(fixture.session.isPresented)
        XCTAssertFalse(fixture.session.isScopePickerPresented)

        sendEscape(to: picker)
        settle(fixture)
        XCTAssertFalse(picker.isVisible)
        XCTAssertFalse(fixture.session.isPresented)
        XCTAssertFalse(fixture.session.isScopePickerPresented)
        XCTAssertNil(scopePanel.parent)
    }

    func testDismissingPickerClearsOpenScopePanel() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let picker = try openPicker(in: fixture)
        capturePickerFrames(in: picker, fixture: fixture)
        try clickPickerAnchor("scope", in: picker, fixture: fixture)
        settle(fixture)
        let scopePanel = try XCTUnwrap(childPanel(in: picker))

        fixture.session.presentationBinding.wrappedValue = false
        settle(fixture)

        XCTAssertFalse(fixture.session.isPresented)
        XCTAssertFalse(fixture.session.isScopePickerPresented)
        XCTAssertEqual(fixture.session.query, "")
        XCTAssertFalse(picker.isVisible)
        XCTAssertFalse(scopePanel.isVisible)
        XCTAssertNil(scopePanel.parent)
    }

    func testOpeningWithoutSelectingTaskDoesNotStartFocus() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        XCTAssertEqual(fixture.store.phase, .idle)
        XCTAssertNil(fixture.session.linkedTaskID)
        let picker = try openPicker(in: fixture)

        XCTAssertTrue(picker.isVisible)
        XCTAssertEqual(fixture.store.phase, .idle)
        XCTAssertNil(fixture.store.currentTaskID)
        XCTAssertNil(fixture.session.linkedTaskID)
    }

    private func makeFixture() throws -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        let task = Task(id: UUID(), title: "今日待办", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: now), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [task],
                                           initialLists: ["工作", "学习"])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusTaskPickerPanelFlowTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FocusStore(clock: { now }, directory: directory)
        let session = FocusTaskPickerSession()
        let layout = LayoutState()
        let root = Harness(workspace: workspace, store: store, session: session)
        let host = NSHostingView(rootView: AnyView(root))
        let owner = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 760, height: 680),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.appearance = NSAppearance(named: .aqua)
        owner.contentView = host
        owner.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let fixture = Fixture(owner: owner, host: host, workspace: workspace, store: store,
                              session: session, layout: layout, directory: directory)
        settle(fixture)
        return fixture
    }

    private func openPicker(in fixture: Fixture) throws -> NSPanel {
        fixture.session.present()
        settle(fixture)
        return try XCTUnwrap(parentPanel(in: fixture.owner),
                             "The task picker panel did not appear")
    }

    private func close(_ fixture: Fixture) {
        fixture.session.dismiss()
        settle(fixture)
        fixture.owner.contentView = nil
        fixture.owner.close()
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    private func settle(_ fixture: Fixture) {
        fixture.host.layoutSubtreeIfNeeded()
        if let picker = parentPanel(in: fixture.owner) {
            picker.contentView?.layoutSubtreeIfNeeded()
            childPanel(in: picker)?.contentView?.layoutSubtreeIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        fixture.host.layoutSubtreeIfNeeded()
        if let picker = parentPanel(in: fixture.owner) {
            picker.contentView?.layoutSubtreeIfNeeded()
            childPanel(in: picker)?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func parentPanel(in owner: NSWindow) -> NSPanel? {
        owner.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
    }

    private func childPanel(in parent: NSWindow) -> NSPanel? {
        parent.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
    }

    private func capturePickerFrames(in picker: NSPanel, fixture: Fixture) {
        guard let host = picker.contentView as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(host.rootView.onPreferenceChange(FocusTaskPickerLayoutPreferenceKey.self) {
            fixture.layout.frames = $0
        })
        settle(fixture)
    }

    private func clickPickerAnchor(_ key: String, in picker: NSPanel,
                                   fixture: Fixture) throws {
        let frame = try XCTUnwrap(fixture.layout.frames[key], "Missing picker anchor: \(key)")
        let host = try XCTUnwrap(picker.contentView as? NSHostingView<AnyView>)
        try sendClick(in: host, frame: frame, window: picker)
    }

    private func clickScopeRow(index: Int, in scopePanel: NSPanel) throws {
        let host = try XCTUnwrap(scopePanel.contentView)
        let row = CGRect(x: 8, y: 8 + CGFloat(index) * FocusTaskPickerMetrics.scopeRowHeightCompact,
                         width: FocusTaskPickerMetrics.scopeWidth - 16,
                         height: FocusTaskPickerMetrics.scopeRowHeightCompact)
        try sendClick(in: host, frame: row, window: scopePanel)
    }

    private func sendClick(in view: NSView, frame: CGRect, window: NSWindow) throws {
        let point = view.convert(NSPoint(x: frame.midX,
                                         y: view.isFlipped ? frame.midY : view.bounds.height - frame.midY),
                                 to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
    }

    private func sendEscape(to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(event)
    }
}
