import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class QuickAddScheduleWindowTests: XCTestCase {
    func testReopeningListCaptureSchedulePreservesBothRemindersThroughCreation() throws {
        _ = NSApplication.shared
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let navigation = AppNavigation(destination: .allTasks)
        var quickAddFrames: [QuickAddRenderAnchor: CGRect] = [:]
        let root = TaskListView(workspace: workspace, navigation: navigation, navigationVisible: false)
            .environmentObject(AppEnvironment())
            .frame(width: 760, height: 640)
            .coordinateSpace(name: "quick-add-render")
            .onPreferenceChange(QuickAddFramesKey.self) { quickAddFrames = $0 }
        let host = NSHostingView(rootView: AnyView(root))
        let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 640)
        defer { owner.contentView = nil; owner.close() }

        func input(in view: NSView) -> QuickAddFocusReportingField? {
            if let field = view as? QuickAddFocusReportingField { return field }
            return view.subviews.lazy.compactMap { input(in: $0) }.first
        }
        let field = try XCTUnwrap(input(in: host))
        owner.makeFirstResponder(field)
        field.stringValue = "明天9点复盘"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification,
                                                           object: field))
        InspectorPanelTestSupport.settle(owner)

        func schedulePanel() throws -> NSPanel {
            try InspectorPanelTestSupport.click(try XCTUnwrap(quickAddFrames[.schedule]),
                                                in: host, window: owner)
            return try XCTUnwrap(owner.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible))
        }
        func childPanel(in panel: NSPanel) throws -> NSPanel {
            try XCTUnwrap(panel.childWindows?.compactMap { $0 as? NSPanel }.first(where: \.isVisible))
        }
        var scheduleFrames: [ObjectIdentifier: [ScheduleRenderAnchor: ScheduleRenderValue]] = [:]
        func frames(in panel: NSPanel) throws -> [ScheduleRenderAnchor: ScheduleRenderValue] {
            let panelHost = try XCTUnwrap(panel.contentView as? NSHostingView<AnyView>)
            let identity = ObjectIdentifier(panel)
            panelHost.rootView = AnyView(panelHost.rootView.coordinateSpace(name: "schedule-render")
                .onPreferenceChange(ScheduleFramesKey.self) { scheduleFrames[identity] = $0 })
            InspectorPanelTestSupport.settle(panel)
            return scheduleFrames[identity] ?? [:]
        }
        func click(_ anchor: ScheduleRenderAnchor, in panel: NSPanel) throws {
            let frame = try XCTUnwrap(frames(in: panel)[anchor]?.frame)
            try InspectorPanelTestSupport.click(frame, in: try XCTUnwrap(panel.contentView), window: panel)
        }
        func confirmReminder(in child: NSPanel) throws {
            let footer = try XCTUnwrap(frames(in: child)[.editorFooter(.reminder)]?.frame)
            try InspectorPanelTestSupport.click(
                CGRect(x: footer.maxX - 38, y: footer.midY - 10, width: 48, height: 20),
                in: try XCTUnwrap(child.contentView), window: child)
        }

        let parent = try schedulePanel()
        try click(.icon(.reminder), in: parent)
        let reminder = try childPanel(in: parent)
        let onTime = ScheduleRenderAnchor.option("当天 (09:00)")
        let dayBefore = ScheduleRenderAnchor.option("提前1天 (09:00)")
        try click(onTime, in: reminder)
        try click(dayBefore, in: reminder)
        try confirmReminder(in: reminder)
        try InspectorPanelTestSupport.sendReturn(to: parent)
        XCTAssertFalse(parent.isVisible)
        XCTAssertTrue(workspace.allTasks.isEmpty, "确认日期草稿还不能创建任务")

        let reopened = try schedulePanel()
        try click(.icon(.reminder), in: reopened)
        let reopenedReminder = try childPanel(in: reopened)
        let selection = try frames(in: reopenedReminder)
        XCTAssertTrue(try XCTUnwrap(selection[onTime]).active, "再次打开必须保留准时提醒")
        XCTAssertTrue(try XCTUnwrap(selection[dayBefore]).active, "再次打开必须保留提前提醒")
        try confirmReminder(in: reopenedReminder)
        try InspectorPanelTestSupport.sendReturn(to: reopened)
        owner.makeKeyAndOrderFront(nil)
        owner.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(field.delegate?.control?(field, textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
        InspectorPanelTestSupport.settle(owner)

        let task = try XCTUnwrap(workspace.allTasks.first)
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(task.title, "复盘")
        XCTAssertEqual(task.reminderOffsets, [-1440, 0])
        let due = try XCTUnwrap(task.schedule.dueAt)
        XCTAssertEqual(ReminderSchedule.fireDates(for: task, calendar: calendar),
                       [due.addingTimeInterval(-86400), due])
        workspace.undo()
        XCTAssertTrue(workspace.allTasks.isEmpty, "创建仍然只需一次撤销")
    }
}
