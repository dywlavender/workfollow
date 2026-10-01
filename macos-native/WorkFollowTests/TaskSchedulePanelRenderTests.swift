import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskSchedulePanelRenderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        value.firstWeekday = 2
        return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))! }

    private func fixture(timed: Bool, repeating: Bool = false, allDayReminder: Bool = false) -> (TaskWorkspaceModel, Task) {
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "日期面板验收", in: .inbox).taskID!
        if timed || allDayReminder {
            let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 20, minute: 30))!
            workspace.saveTiming(id, schedule: TaskSchedule(dueAt: due, hasTime: timed),
                reminder: timed ? due : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due),
                frequency: repeating ? .monthly : .never,
                recurrenceRule: repeating ? RecurrenceRule(remainingCount: 2, monthDay: 22) : nil,
                reminderOffsets: [0])
        }
        return (workspace, workspace.task(for: id)!)
    }

    func testThreeMainPanelScenesMatchDisplayedLabelsAndGeometry() throws {
        for (name, timed, repeating) in [("empty", false, false), ("timed", true, false), ("monthly-timed", true, true)] {
            let (workspace, task) = fixture(timed: timed, repeating: repeating)
            let values = try render(task, workspace: workspace, name: name)
            XCTAssertEqual(values[.panel]?.frame.width, 260)
            let panel = try XCTUnwrap(values[.panel]).frame
            let footer = try XCTUnwrap(values[.mainFooter]).frame
            XCTAssertLessThanOrEqual(footer.maxY, panel.maxY - ScheduleMetrics.horizontalPadding + 0.5,
                "重复结束行不能把确认按钮裁掉")
            XCTAssertEqual(panel.height, SchedulePopoverLayoutV2.height(
                availableHeight: NSScreen.main?.visibleFrame.height ?? 900, repeating: repeating), accuracy: 0.5)
            let shortcuts = values.keys.filter { if case .shortcut = $0 { return true }; return false }
            XCTAssertEqual(shortcuts.count, 4)
            XCTAssertNotNil(values[.shortcut("今天")])
            XCTAssertNotNil(values[.shortcut("明天")])
            XCTAssertNotNil(values[.shortcut("下周")])
            XCTAssertNotNil(values[.shortcut("周末")])
            XCTAssertEqual(values[.row(.time)]?.label, timed ? "20:30" : "时间")
            XCTAssertEqual(values[.row(.reminder)]?.label, timed ? "准时" : "提醒")
            XCTAssertEqual(values[.row(.repeat)]?.label, repeating ? "每月 (22日)" : "重复")
            XCTAssertEqual(values[.row(.repeatEnd)] != nil, repeating)
            if repeating {
                XCTAssertEqual(values[.row(.repeatEnd)]?.label, "重复 2 次后结束")
                XCTAssertEqual(values[.row(.repeatEnd)]?.active, true)
            }
            var iconX: CGFloat?
            var trailingX: CGFloat?
            for sheet in [TaskDatePopoverV2.InlineSheet.time, .reminder, .repeat] + (repeating ? [.repeatEnd] : []) {
                let row = try XCTUnwrap(values[.row(sheet)])
                let icon = try XCTUnwrap(values[.icon(sheet)])
                let trailing = try XCTUnwrap(values[.trailing(sheet)])
                XCTAssertEqual(row.frame.height, 30, accuracy: 0.5)
                if let iconX { XCTAssertEqual(icon.frame.minX, iconX, accuracy: 0.5) }
                if let trailingX { XCTAssertEqual(trailing.frame.maxX, trailingX, accuracy: 0.5) }
                iconX = icon.frame.minX
                trailingX = trailing.frame.maxX
                if timed && (sheet == .time || sheet == .reminder || repeating) {
                    XCTAssertTrue(row.active)
                }
            }
        }
    }

    func testAllDayZeroOffsetRemainsSameDayAndDraftEditsDoNotMutateTask() throws {
        let (workspace, task) = fixture(timed: false, allDayReminder: true)
        let values = try render(task, workspace: workspace, name: "all-day")
        XCTAssertEqual(values[.row(.reminder)]?.label, "当天")
        let revision = workspace.revision
        let draft = TaskDateDraftModel(task: task, calendar: calendar, now: { self.now }, deadline: false)
        draft.quick(1)
        draft.chooseFrequency(.monthly)
        draft.setReminderOffsets([0, -30])
        // Closing/discarding the draft (Escape or outside click) cannot write the workspace.
        XCTAssertEqual(workspace.task(for: task.id), task)
        XCTAssertEqual(workspace.revision, revision)
    }

    private func render(_ task: Task, workspace: TaskWorkspaceModel, name: String) throws -> [ScheduleRenderAnchor: ScheduleRenderValue] {
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let root = TaskDatePopoverV2(task: task, workspace: workspace) {}
            .background(WFColors.content)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let size = NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: 260, height: 900))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/workfollow-schedule-panel-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        return values
    }
}
