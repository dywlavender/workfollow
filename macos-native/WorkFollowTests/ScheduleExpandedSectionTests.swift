import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class ScheduleExpandedSectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private var anchor: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 20, minute: 30))!
    }
    private func fixture(timed: Bool = false) -> (TaskWorkspaceModel, Task) {
        let workspace = TaskWorkspaceModel(clock: { self.anchor }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "日期展开验收", in: .inbox).taskID!
        workspace.saveTiming(id, schedule: TaskSchedule(dueAt: anchor, hasTime: timed),
                             reminder: nil, frequency: .never, reminderOffsets: [])
        return (workspace, workspace.task(for: id)!)
    }

    func testRowsTruncateAtExpandedSectionAndRestoreWhenClosed() {
        typealias Section = ScheduleExpandedSection
        XCTAssertEqual(Section.visibleRows(expanded: nil, period: false, repeating: true),
                       [.time, .reminder, .repeat, .repeatEnd])
        XCTAssertEqual(Section.visibleRows(expanded: .reminder, period: false, repeating: true), [.time, .reminder])
        XCTAssertEqual(Section.visibleRows(expanded: .repeat, period: false, repeating: true), [.time, .reminder, .repeat])
        XCTAssertEqual(Section.visibleRows(expanded: .endTime, period: true, repeating: true), [.time, .endTime])
        XCTAssertEqual(Section.visibleRows(expanded: nil, period: true, repeating: false), [.time, .endTime, .reminder, .repeat])
    }

    func testEscapeRouterConsumesOnlyItsPanelWindowEvents() {
        var calls = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScheduleEscapeRouter { calls += 1 })
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        let other = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close(); other.close() }
        func escape(in target: NSWindow) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: target.windowNumber, context: nil, characters: "\u{1b}",
                            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        }
        NSApp.sendEvent(escape(in: other))
        XCTAssertEqual(calls, 0)
        NSApp.sendEvent(escape(in: window))
        XCTAssertEqual(calls, 1)
    }

    func testReminderCancelConfirmAndOuterCommitAreSeparate() throws {
        let (workspace, task) = fixture()
        let model = TaskDateDraftModel(task: task, calendar: calendar, now: { self.anchor }, deadline: false)
        var discarded = ScheduleReminderDraft(offsets: model.reminderOffsets)
        discarded.toggle(-1440)
        XCTAssertEqual(model.reminderOffsets, [])
        XCTAssertEqual(workspace.task(for: task.id), task)
        // Cancel discards this value. Reopening snapshots the unchanged schedule draft.
        var reopened = ScheduleReminderDraft(offsets: model.reminderOffsets)
        XCTAssertEqual(reopened.offsets, [])
        reopened.toggle(-1440)
        XCTAssertTrue(reopened.confirm(into: model))
        XCTAssertEqual(model.reminderOffsets, [-1440])
        XCTAssertEqual(workspace.task(for: task.id), task)
        let plan = model.commitPlan(for: task)
        workspace.saveTiming(task.id, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule,
                             reminderOffsets: plan.reminderOffsets)
        XCTAssertEqual(workspace.task(for: task.id)?.reminderOffsets, [-1440])
    }

    func testCustomReminderQuantityIsIncludedOnlyOnConfirm() {
        let (workspace, task) = fixture(timed: true)
        let model = TaskDateDraftModel(task: task, calendar: calendar, now: { self.anchor }, deadline: false)
        let draft = ScheduleReminderDraft(offsets: [0])
        XCTAssertFalse(draft.confirm(into: model, customAmount: "", unit: 60))
        XCTAssertEqual(model.reminderOffsets, [])
        XCTAssertTrue(draft.confirm(into: model, customAmount: "2", unit: 60))
        XCTAssertEqual(model.reminderOffsets, [0, -120])
        XCTAssertEqual(workspace.task(for: task.id), task)
    }

    func testExpandedPanelRenderingAndFooters() throws {
        let (workspace, task) = fixture()
        for page in [TaskDatePopoverV2.Page.main, .reminder, .recurrence] {
            let values = try render(task, workspace: workspace, page: page, name: "\(page)")
            XCTAssertEqual(values[.panel]?.frame.width, 260)
            XCTAssertNotNil(values[.row(.time)])
            XCTAssertNotNil(values[.row(.reminder)])
            XCTAssertNil(values[.row(.repeatEnd)])
            if page == .main {
                XCTAssertNotNil(values[.row(.repeat)])
                XCTAssertNotNil(values[.mainFooter])
                XCTAssertNil(values[.expandedContent(.reminder)])
            } else {
                let section: ScheduleExpandedSection = page == .reminder ? .reminder : .repeat
                XCTAssertEqual(values[.expandedRow(section)]?.active, true)
                let row = try XCTUnwrap(values[.row(section)])
                let content = try XCTUnwrap(values[.expandedContent(section)])
                XCTAssertEqual(content.frame.minY, row.frame.maxY, accuracy: 0.5)
                XCTAssertNil(values[.mainFooter])
                if page == .reminder {
                    XCTAssertNil(values[.row(.repeat)])
                    XCTAssertNotNil(values[.editorFooter(.reminder)])
                    for title in ["当天 (09:00)", "提前1天 (09:00)", "提前2天 (09:00)", "提前3天 (09:00)", "提前1周 (09:00)"] {
                        XCTAssertEqual(values[.option(title)]?.frame.height, 34)
                    }
                } else {
                    XCTAssertNotNil(values[.row(.repeat)])
                    XCTAssertNil(values[.editorFooter(.repeat)])
                    for title in ["每天", "每周 (周二)", "每月 (22日)", "每年 (9月22日)", "工作日", "节假日", "自定义"] {
                        XCTAssertNotNil(values[.option(title)], title)
                    }
                    XCTAssertNil(values[.option("农历重复")])
                    XCTAssertNil(values[.option("艾宾浩斯记忆法")])
                }
            }
        }
        XCTAssertEqual(workspace.task(for: task.id), task)
    }

    func testTimedReminderOptionsUseScheduledClock() throws {
        let (workspace, task) = fixture(timed: true)
        let values = try render(task, workspace: workspace, page: .reminder, name: "reminder-timed")
        XCTAssertNotNil(values[.option("当天 (20:30)")])
        XCTAssertNotNil(values[.option("提前1天 (20:30)")])
    }

    func testEscapeCollapsesExpandedEditorBeforeClosingPanel() {
        let (workspace, task) = fixture()
        var closed = false
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let popover = NSPopover()
        let root = TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .recurrence) {
            closed = true
            popover.close()
        }
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
        let controller = NSHostingController(rootView: root)
        let host = controller.view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 1000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        window.contentView = anchor
        window.makeKeyAndOrderFront(nil)
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: NSRect(x: 300, y: 900, width: 20, height: 20), of: anchor, preferredEdge: .minY)
        defer { popover.close(); window.contentView = nil; window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        func escape() {
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
            settle()
        }
        settle()
        XCTAssertNotNil(values[.expandedContent(.repeat)])
        escape()
        XCTAssertFalse(closed)
        XCTAssertTrue(popover.isShown)
        XCTAssertNil(values[.expandedContent(.repeat)])
        XCTAssertNotNil(values[.mainFooter])
        escape()
        XCTAssertTrue(closed)
        XCTAssertEqual(workspace.task(for: task.id), task)
    }

    private func render(_ task: Task, workspace: TaskWorkspaceModel, page: TaskDatePopoverV2.Page,
                        name: String) throws -> [ScheduleRenderAnchor: ScheduleRenderValue] {
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let root = TaskDatePopoverV2(task: task, workspace: workspace, initialPage: page) {}
            .background(WFColors.content)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
        let size = NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: 260, height: 1100))
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/workfollow-schedule-expanded-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        return values
    }
}
