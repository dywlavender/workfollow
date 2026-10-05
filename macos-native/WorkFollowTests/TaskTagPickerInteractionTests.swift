import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagPickerInteractionTests: XCTestCase {
    func testInspectorMoreToDateClosesOldPanelWithOneClick() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let taskID = try XCTUnwrap(workspace.createTask(title: "日期入口切换", in: .inbox).taskID)
        workspace.select(taskID)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: AppEnvironment())
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        for _ in 0..<3 {
            try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
            let more = try InspectorPanelTestSupport.actionPanel(in: window)
            try InspectorPanelTestSupport.clickElement(containing: "设置日期", in: window)
            let date = try InspectorPanelTestSupport.panel(title: "日期属性", below: window)
            XCTAssertFalse(more.isVisible, "Date must replace More rather than coexist with it")
            try InspectorPanelTestSupport.sendEscape(to: date)
            XCTAssertFalse(date.isVisible)
            XCTAssertEqual(workspace.selectedTaskID, taskID)
        }
    }

    private func click(_ rect: CGRect, host: NSView, window: NSWindow) throws {
        let point = host.convert(NSPoint(x: rect.midX, y: host.isFlipped ? rect.midY : host.bounds.height - rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    private func window(for host: NSView, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return window
    }

    func testUnsavedQuickAddTagRemainsAvailableAfterDeselectAndApplyOnlyCallsHost() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let before = workspace.allTasks
        var frames: [TaskTagPickerAnchor: CGRect] = [:]
        var applied: [String]?
        let host = NSHostingView(rootView: TaskTagPickerPopover(initialTags: ["尚未保存"], workspace: workspace,
            onCancel: {}, onApply: { applied = $0 })
            .onPreferenceChange(TaskTagPickerFrames.self) { frames = $0 })
        let window = window(for: host, width: 264, height: 320)
        defer { window.close() }
        let row = try XCTUnwrap(frames[.tag("尚未保存")])
        let confirm = try XCTUnwrap(frames[.confirm])
        try click(row, host: host, window: window)
        XCTAssertEqual(frames[.tag("尚未保存")], row)
        XCTAssertEqual(frames[.confirm], confirm, "Selection cannot shift the footer")
        try click(row, host: host, window: window)
        try click(confirm, host: host, window: window)
        XCTAssertEqual(applied, ["尚未保存"])
        XCTAssertEqual(workspace.allTasks, before, "Quick Add picker cannot persist tasks or global tags")
    }

    func testInspectorCancelReopenApplyAndUndoUseSharedPicker() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "标签验收", in: .inbox).taskID)
        let other = try XCTUnwrap(workspace.createTask(title: "已有标签", in: .inbox).taskID)
        workspace.setTags(source, ["原标签"])
        workspace.setTags(other, ["工作"])
        workspace.select(source)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        func open() throws {
            try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
            let more = try InspectorPanelTestSupport.actionPanel(in: window)
            XCTAssertEqual(more.frame.width, 208, accuracy: 1)
            try InspectorPanelTestSupport.clickButton(containing: "标签", in: more)
            XCTAssertFalse(more.isVisible)
            let picker = try InspectorPanelTestSupport.actionPanel(in: window)
            XCTAssertEqual(picker.frame.width, 264, accuracy: 1)
            XCTAssertEqual(picker.frame.height, 320, accuracy: 1)
        }
        func pickerClick(_ label: String) throws {
            try InspectorPanelTestSupport.clickButton(containing: label,
                in: InspectorPanelTestSupport.actionPanel(in: window))
        }
        try open()
        try pickerClick("工作")
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        let cancelledPicker = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.clickElement(containing: "任务标题", in: window)
        XCTAssertFalse(cancelledPicker.isVisible)
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        try open()
        try pickerClick("确定")
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"], "Dismissed draft must not leak on reopen")
        try open()
        try pickerClick("工作")
        try pickerClick("确定")
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签", "工作"])
        XCTAssertFalse(InspectorPanelTestSupport.visibleWindows(below: window)
            .contains { $0.title == InspectorPanelTestSupport.actionPanelTitle })
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        try open()
        try pickerClick("工作")
        let escapePicker = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.sendEscape(to: escapePicker)
        XCTAssertFalse(escapePicker.isVisible)
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
    }
}
