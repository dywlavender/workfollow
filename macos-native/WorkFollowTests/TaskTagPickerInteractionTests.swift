import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagPickerInteractionTests: XCTestCase {
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
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "标签验收", in: .inbox).taskID)
        let other = try XCTUnwrap(workspace.createTask(title: "已有标签", in: .inbox).taskID)
        workspace.setTags(source, ["原标签"])
        workspace.setTags(other, ["工作"])
        workspace.select(source)
        var inspector: [InspectorRenderAnchor: CGRect] = [:]
        var picker: [TaskTagPickerAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 760, height: 700).coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { inspector = $0 }
            .onPreferenceChange(TaskTagPickerFrames.self) { picker = $0 })
        let window = window(for: host, width: 760, height: 700)
        defer { window.close() }
        func open() throws {
            try click(try XCTUnwrap(inspector[.footerMore]), host: host, window: window)
            try click(try XCTUnwrap(inspector[.tagsMenuRow]), host: host, window: window)
            XCTAssertNil(inspector[.moreMenu])
        }
        func pickerClick(_ anchor: TaskTagPickerAnchor) throws {
            let panel = try XCTUnwrap(inspector[.tagPicker])
            let rect = try XCTUnwrap(picker[anchor]).offsetBy(dx: panel.minX, dy: panel.minY)
            try click(rect, host: host, window: window)
        }
        try open()
        let panel = try XCTUnwrap(inspector[.tagPicker])
        XCTAssertEqual(panel.width, 264, accuracy: 1)
        XCTAssertEqual(panel.height, 320, accuracy: 1)
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_tag_picker.png"))
        try pickerClick(.tag("工作"))
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        try click(CGRect(x: 40, y: 350, width: 20, height: 20), host: host, window: window)
        XCTAssertNil(inspector[.tagPicker])
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        try open()
        try pickerClick(.confirm)
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"], "Dismissed draft must not leak on reopen")
        try open()
        try pickerClick(.tag("工作"))
        try pickerClick(.confirm)
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签", "工作"])
        XCTAssertNil(inspector[.tagPicker])
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
        try open()
        try pickerClick(.tag("工作"))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertNil(inspector[.tagPicker])
        XCTAssertEqual(workspace.task(for: source)?.tags, ["原标签"])
    }
}
