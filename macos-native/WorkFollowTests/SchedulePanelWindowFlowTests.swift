import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SchedulePanelWindowFlowTests: XCTestCase {
    private final class LayoutState {
        weak var triggerView: NSView?
        var frames: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        var childFrames: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
    }

    private struct TriggerReader: NSViewRepresentable {
        let layout: LayoutState
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            layout.triggerView = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    private struct Harness: View {
        let task: Task
        @ObservedObject var workspace: TaskWorkspaceModel
        let layout: LayoutState
        @State private var presented = false

        var body: some View {
            HStack(spacing: 10) {
                Text(task.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("日期") { presented = true }
                    .scheduleTrigger()
                    .background(TriggerReader(layout: layout).allowsHitTesting(false))
            }
            .padding(.horizontal, 12)
            .frame(width: 400, height: 50)
            .contentShape(Rectangle())
            .schedulePopover(isPresented: $presented) {
                TaskDatePopoverV2(task: task, workspace: workspace) { presented = false }
            }
            .frame(width: 560, height: 520)
        }
    }

    private struct Fixture {
        let owner: NSWindow
        let host: NSHostingView<AnyView>
        let workspace: TaskWorkspaceModel
        let task: Task
        let otherTaskID: UUID
        let layout: LayoutState
        let directory: URL
    }

    func testTimePanelEscapeRoutesChildThenParentForParentWindow() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let (parent, timePanel) = try openTimePanel(in: fixture)
        XCTAssertTrue(parent.parent === fixture.owner)
        XCTAssertTrue(timePanel.parent === parent)
        XCTAssertTrue(parent.isVisible)
        XCTAssertTrue(timePanel.isVisible)

        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: parent))
        settle(fixture)
        XCTAssertFalse(timePanel.isVisible, "The first parent-window Escape must close only the time child")
        XCTAssertNil(timePanel.parent)
        XCTAssertTrue(parent.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)

        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: parent))
        settle(fixture)
        XCTAssertFalse(parent.isVisible, "The second parent-window Escape closes the schedule panel")
        XCTAssertNil(parent.parent)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)
    }

    func testEscapeKeyEventInPanelClosesTimeChildFirst() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let (parent, timePanel) = try openTimePanel(in: fixture)
        XCTAssertTrue(parent.firstResponder is NSTextView,
                      "Opening time must focus its editable clock without another click")
        let firstTarget = parent

        try sendEscape(to: firstTarget)
        settle(fixture)
        XCTAssertFalse(timePanel.isVisible, "Escape dispatched through AppKit must close the time child first")
        XCTAssertNil(timePanel.parent)
        XCTAssertTrue(parent.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)

        let secondTarget = parent
        try sendEscape(to: secondTarget)
        settle(fixture)
        XCTAssertFalse(parent.isVisible, "A second Escape closes the schedule panel")
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)
    }

    func testNativeCancelCommandClosesChildBeforeParent() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }
        let (parent, child) = try openTimePanel(in: fixture)
        parent.cancelOperation(nil)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        parent.cancelOperation(nil)
        settle(fixture)
        XCTAssertFalse(parent.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)
    }

    func testOpeningEachPropertyChildPreservesParentAndAnchorFrames() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let parent = try openSchedulePanel(in: fixture)
        let initialWindowFrame = parent.frame
        let initialFrames = fixture.layout.frames
        let properties: [TaskDatePopoverV2.InlineSheet] = [.time, .reminder, .repeat]

        for property in properties {
            try clickMain(.icon(property), in: parent, fixture: fixture)
            let child = try XCTUnwrap(childPanel(in: parent), "Missing child panel for \(property)")
            XCTAssertEqual(parent.frame, initialWindowFrame,
                           "Opening \(property) must not resize or move the main panel")
            for anchor in [ScheduleRenderAnchor.row(property), .icon(property), .trailing(property)] {
                XCTAssertEqual(fixture.layout.frames[anchor]?.frame, initialFrames[anchor]?.frame,
                               "Opening \(property) moved its trigger geometry")
            }
            XCTAssertEqual(fixture.layout.frames[.mainFooter]?.frame, initialFrames[.mainFooter]?.frame)
            XCTAssertEqual(fixture.layout.frames[.calendarSection]?.frame,
                           initialFrames[.calendarSection]?.frame)

            XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: parent))
            settle(fixture)
            XCTAssertFalse(child.isVisible)
            XCTAssertNil(child.parent)
            XCTAssertTrue(parent.isVisible)
            XCTAssertEqual(parent.frame, initialWindowFrame)
        }
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)
    }

    func testCancelAndOutsideDismissDiscardReminderDraftAndReopenClean() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let parent = try openSchedulePanel(in: fixture)
        try clickMain(.icon(.reminder), in: parent, fixture: fixture)
        var child = try XCTUnwrap(childPanel(in: parent))
        captureChildFrames(in: child, fixture: fixture)
        let reminderOption = ScheduleRenderAnchor.option("提前1天 (09:00)")
        try clickChild(reminderOption, in: child, fixture: fixture)
        captureChildFrames(in: child, fixture: fixture)
        XCTAssertTrue(fixture.layout.childFrames[reminderOption]?.active == true)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)

        let cancelFooter = try XCTUnwrap(fixture.layout.childFrames[.editorFooter(.reminder)]?.frame)
        try sendClick(in: try XCTUnwrap(child.contentView),
                      frame: CGRect(x: cancelFooter.minX + 30, y: cancelFooter.midY - 10,
                                    width: 48, height: 20), window: child)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        XCTAssertEqual(fixture.layout.frames[.row(.reminder)]?.label, "提醒")
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)

        try clickMain(.icon(.reminder), in: parent, fixture: fixture)
        child = try XCTUnwrap(childPanel(in: parent))
        captureChildFrames(in: child, fixture: fixture)
        XCTAssertFalse(try XCTUnwrap(fixture.layout.childFrames[reminderOption]).active,
                       "Cancel must discard the reminder editor's local selection")
        try clickChild(reminderOption, in: child, fixture: fixture)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)

        try sendClick(in: fixture.host,
                      frame: CGRect(x: 12, y: 12, width: 24, height: 24), window: fixture.owner)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertFalse(parent.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: fixture.task.id), fixture.task)
        XCTAssertEqual(fixture.workspace.bulkSelection, [fixture.otherTaskID])

        let reopened = try openSchedulePanel(in: fixture)
        XCTAssertEqual(fixture.layout.frames[.row(.reminder)]?.label, "提醒")
        XCTAssertEqual(fixture.layout.frames[.row(.repeat)]?.label, "重复")
        try clickMain(.icon(.reminder), in: reopened, fixture: fixture)
        let reopenedChild = try XCTUnwrap(childPanel(in: reopened))
        captureChildFrames(in: reopenedChild, fixture: fixture)
        XCTAssertFalse(try XCTUnwrap(fixture.layout.childFrames[reminderOption]).active,
                       "Outside dismissal must not leave reminder draft state on reopening")
    }

    func testConfirmCommitsScheduleReminderAndRepeatTogetherAndGrowsPanel() throws {
        let fixture = try makeFixture()
        defer { close(fixture) }

        let originalTask = fixture.task
        let originalRevision = fixture.workspace.revision
        let originalSelection = fixture.workspace.bulkSelection
        let parent = try openSchedulePanel(in: fixture)
        let baseWindowFrame = parent.frame
        let baseHeight = parent.frame.height

        try clickMain(.icon(.time), in: parent, fixture: fixture)
        var child = try XCTUnwrap(childPanel(in: parent))
        captureChildFrames(in: child, fixture: fixture)
        try clickChild(.option("12:30"), in: child, fixture: fixture)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: originalTask.id), originalTask)
        XCTAssertEqual(fixture.workspace.bulkSelection, originalSelection)

        try clickMain(.icon(.reminder), in: parent, fixture: fixture)
        child = try XCTUnwrap(childPanel(in: parent))
        captureChildFrames(in: child, fixture: fixture)
        try clickChild(.option("当天 (12:30)"), in: child, fixture: fixture)
        let reminderFooter = try XCTUnwrap(fixture.layout.childFrames[.editorFooter(.reminder)]?.frame)
        try sendClick(in: try XCTUnwrap(child.contentView),
                      frame: CGRect(x: reminderFooter.maxX - 38, y: reminderFooter.midY - 10,
                                    width: 48, height: 20), window: child)
        settle(fixture)
        XCTAssertFalse(child.isVisible)
        XCTAssertEqual(fixture.workspace.task(for: originalTask.id), originalTask,
                       "Confirming a child editor changes only the outer draft")

        try clickMain(.icon(.repeat), in: parent, fixture: fixture)
        child = try XCTUnwrap(childPanel(in: parent))
        captureChildFrames(in: child, fixture: fixture)
        try clickChild(.option("每天"), in: child, fixture: fixture)
        settle(fixture)
        XCTAssertFalse(child.isVisible)

        XCTAssertEqual(parent.frame.height, baseHeight + ScheduleMetrics.rowHeight, accuracy: 0.5)
        XCTAssertEqual(parent.frame.maxY, baseWindowFrame.maxY, accuracy: 0.5,
                       "The top edge must remain anchored while the repeat-end row is added")
        let panelContent = try XCTUnwrap(fixture.layout.frames[.panel]?.frame)
        let footer = try XCTUnwrap(fixture.layout.frames[.mainFooter]?.frame)
        XCTAssertEqual(panelContent.height, baseHeight + ScheduleMetrics.rowHeight, accuracy: 0.5)
        XCTAssertLessThanOrEqual(footer.maxY,
                                 panelContent.maxY - ScheduleMetrics.horizontalPadding + 0.5,
                                 "The main Confirm footer must remain visible after the height increase")
        XCTAssertEqual(fixture.workspace.task(for: originalTask.id), originalTask)
        XCTAssertEqual(fixture.workspace.bulkSelection, originalSelection)

        let confirmFooter = try XCTUnwrap(fixture.layout.frames[.mainFooter]?.frame)
        try sendClick(in: try XCTUnwrap(parent.contentView),
                      frame: CGRect(x: confirmFooter.maxX - 38, y: confirmFooter.midY - 10,
                                    width: 48, height: 20), window: parent)
        settle(fixture)

        let committed = try XCTUnwrap(fixture.workspace.task(for: originalTask.id))
        let expectedDue = fixture.workspace.calendar.date(bySettingHour: 12, minute: 30,
                                                           second: 0, of: originalTask.schedule.dueAt!)!
        XCTAssertEqual(committed.schedule.dueAt, expectedDue)
        XCTAssertTrue(committed.schedule.hasTime)
        XCTAssertEqual(committed.reminderOffsets, [0])
        XCTAssertEqual(committed.reminderAt, expectedDue)
        XCTAssertEqual(committed.recurrence, .daily)
        XCTAssertEqual(fixture.workspace.revision, originalRevision + 1,
                       "The three schedule fields should produce one workspace change")
        XCTAssertEqual(fixture.workspace.bulkSelection, originalSelection)

        fixture.workspace.undo()
        XCTAssertEqual(fixture.workspace.task(for: originalTask.id), originalTask,
                       "A single undo should restore the complete schedule edit")
        XCTAssertEqual(fixture.workspace.bulkSelection, originalSelection)
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2,
                                                     hour: 12))!
        let due = calendar.startOfDay(for: now)
        let task = Task(id: UUID(), title: "日程窗口 Esc 验收", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: due), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        let otherTask = Task(id: UUID(), title: "保留批量选择", list: .inbox, priority: .none,
                             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                             createdAt: now, updatedAt: now)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchedulePanelWindowFlowTests-\(UUID().uuidString)",
                                    isDirectory: true)
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [task, otherTask], notes: [],
                                                    taskLists: [TaskList.inbox.name]))
        let snapshot = try XCTUnwrap(repository.load())
        let isolatedTask = try XCTUnwrap(snapshot.tasks.first)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                                           seedDemoData: false, initialTasks: snapshot.tasks,
                                           initialLists: snapshot.taskLists ?? [])
        workspace.bulkSelection = [otherTask.id]
        let layout = LayoutState()
        let root = Harness(task: isolatedTask, workspace: workspace, layout: layout)
            .frame(width: 560, height: 520)
        let host = NSHostingView(rootView: AnyView(root))
        let owner = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 560, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.appearance = NSAppearance(named: .aqua)
        owner.contentView = host
        owner.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let fixture = Fixture(owner: owner, host: host, workspace: workspace,
                              task: isolatedTask, otherTaskID: otherTask.id,
                              layout: layout, directory: directory)
        settle(fixture)
        return fixture
    }

    private func openTimePanel(in fixture: Fixture) throws -> (NSPanel, NSPanel) {
        let parent = try openSchedulePanel(in: fixture)
        try clickMain(.icon(.time), in: parent, fixture: fixture)
        let child = try XCTUnwrap(childPanel(in: parent),
                                  "Opening the time row did not create its anchored child panel")
        return (parent, child)
    }

    private func openSchedulePanel(in fixture: Fixture) throws -> NSPanel {
        let button = try XCTUnwrap(fixture.layout.triggerView)
        try sendClick(in: button, frame: button.bounds, window: fixture.owner)
        settle(fixture)

        let parent = try XCTUnwrap(parentPanel(in: fixture.owner),
                                   "The task-row schedulePopover did not present its main panel")
        XCTAssertTrue(parent.styleMask.contains(.borderless))
        XCTAssertFalse(parent.styleMask.contains(.titled))
        XCTAssertEqual(parent.frame.width, ScheduleMetrics.panelWidth, accuracy: 0.5)
        XCTAssertTrue(parent.parent === fixture.owner)
        let trigger = fixture.owner.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = fixture.owner.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let expected = AnchoredPropertyPanelGeometry.scheduleFrame(anchor: trigger,
                            size: parent.frame.size, bounds: screen)
        XCTAssertEqual(parent.frame.minX, expected.minX, accuracy: 1,
                       "Panel must anchor to the trailing date button, not the whole row")
        XCTAssertEqual(parent.frame.minY, expected.minY, accuracy: 1,
                       "Panel must stay adjacent to the trigger, except for boundary avoidance")
        let host = try XCTUnwrap(parent.contentView as? NSHostingView<AnyView>)
        let layout = fixture.layout
        host.rootView = AnyView(host.rootView
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { layout.frames = $0 })
        settle(fixture)

        return parent
    }

    private func clickMain(_ anchor: ScheduleRenderAnchor, in panel: NSPanel,
                           fixture: Fixture) throws {
        let frame = try XCTUnwrap(fixture.layout.frames[anchor]?.frame,
                                  "Missing schedule anchor: \(anchor)")
        try sendClick(in: try XCTUnwrap(panel.contentView), frame: frame, window: panel)
        settle(fixture)
    }

    private func captureChildFrames(in child: NSPanel, fixture: Fixture) {
        guard let host = child.contentView as? NSHostingView<AnyView> else { return }
        let layout = fixture.layout
        // The presenter replaces the child hosting root when its draft changes.
        // Reinstall measurement on that current root to observe the latest value.
        host.rootView = AnyView(host.rootView
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { layout.childFrames = $0 })
        settle(fixture)
    }

    private func clickChild(_ anchor: ScheduleRenderAnchor, in child: NSPanel,
                            fixture: Fixture) throws {
        let frame = try XCTUnwrap(fixture.layout.childFrames[anchor]?.frame,
                                  "Missing child schedule anchor: \(anchor)")
        try sendClick(in: try XCTUnwrap(child.contentView), frame: frame, window: child)
        settle(fixture)
    }

    private func close(_ fixture: Fixture) {
        fixture.owner.contentView = nil
        fixture.owner.close()
        settle(fixture)
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    private func settle(_ fixture: Fixture) {
        fixture.host.layoutSubtreeIfNeeded()
        if let parent = parentPanel(in: fixture.owner) {
            parent.contentView?.layoutSubtreeIfNeeded()
            childPanel(in: parent)?.contentView?.layoutSubtreeIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        fixture.host.layoutSubtreeIfNeeded()
        if let parent = parentPanel(in: fixture.owner) {
            parent.contentView?.layoutSubtreeIfNeeded()
            childPanel(in: parent)?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func parentPanel(in owner: NSWindow) -> NSPanel? {
        owner.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
    }

    private func childPanel(in parent: NSWindow) -> NSPanel? {
        parent.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible)
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

    private func sendEscape(to window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(event)
    }
}
