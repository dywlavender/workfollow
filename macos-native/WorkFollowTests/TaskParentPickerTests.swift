import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskParentPickerTests: XCTestCase {
    func testInspectorMoreOpensParentPickerAndOutsideClickCancels() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "待关联任务", in: .inbox).taskID)
        _ = workspace.createTask(title: "发布周报", in: .inbox)
        workspace.select(source)
        let before = workspace.task(for: source)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }

        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertEqual(more.frame.width, 208, accuracy: 1)
        try InspectorPanelTestSupport.clickButton(containing: "关联主任务", in: more)
        XCTAssertFalse(more.isVisible)

        let picker = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertEqual(picker.frame.width, 280, accuracy: 1)
        XCTAssertEqual(picker.frame.height, 340, accuracy: 1)
        XCTAssertTrue(picker.parent === window)

        // A real click outside the action panel both cancels its draft and reaches the
        // inspector title field, which is a sibling in the owner window's AX tree.
        try InspectorPanelTestSupport.clickElement(containing: "任务标题", in: window)
        XCTAssertFalse(picker.isVisible)
        XCTAssertEqual(workspace.task(for: source), before)
    }

    func testCandidateSearchExcludesSourceChildrenAndClosedTargets() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        let parent = try XCTUnwrap(workspace.createTask(title: "周报", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(parent, title: "步骤").taskID)
        let closed = try XCTUnwrap(workspace.createTask(title: "完成", in: .inbox).taskID)
        _ = workspace.complete(closed)
        let result = TaskParentPickerProjection.candidates(for: source, tasks: workspace.allTasks, query: "")
        XCTAssertEqual(result.map(\.id), [parent])
        XCTAssertFalse(result.contains { $0.id == child })
        XCTAssertEqual(TaskParentPickerProjection.candidates(for: source, tasks: workspace.allTasks, query: "周报").map(\.id), [parent])
        XCTAssertTrue(TaskParentPickerProjection.candidates(for: source, tasks: workspace.allTasks, query: "不存在").isEmpty)
    }

    func testWorkspaceAssignmentKeepsSelectionAndBulkStateAndCanUndo() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        let parent = try XCTUnwrap(workspace.createTask(title: "主任务", in: .inbox).taskID)
        workspace.select(source)
        workspace.bulkSelection = [parent]
        workspace.toggleExpanded(parent)
        XCTAssertEqual(workspace.assignParent(source, parentID: parent), .success(source))
        XCTAssertEqual(workspace.selectedTaskID, source)
        XCTAssertEqual(workspace.bulkSelection, [parent])
        XCTAssertFalse(workspace.collapsedTaskIDs.contains(parent))
        XCTAssertEqual(workspace.task(for: source)?.parentID, parent)
        workspace.undo()
        XCTAssertNil(workspace.task(for: source)?.parentID)
    }

    func testPickerRenderDoesNotMutateTaskAndEscapeCancels() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        let parent = try XCTUnwrap(workspace.createTask(title: "发布周报", in: .inbox).taskID)
        let original = workspace.task(for: source)
        var closed = false
        var frames: [TaskParentPickerAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: TaskParentPicker(taskID: source, workspace: workspace) { closed = true }
            .background(PopupEscapeRouter(depth: 2) { closed = true })
            .onPreferenceChange(TaskParentPickerFrames.self) { frames = $0 })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 280, height: 340),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(host.fittingSize.width, 280, accuracy: 1)
        XCTAssertEqual(host.fittingSize.height, 340, accuracy: 1)
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_parent_picker.png"))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(closed)
        XCTAssertEqual(workspace.task(for: source), original)
        closed = false
        func click(_ rect: CGRect) throws {
            let point = host.convert(NSPoint(x: rect.midX, y: host.isFlipped ? rect.midY : host.bounds.height - rect.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try click(try XCTUnwrap(frames[.candidate(parent)]))
        XCTAssertEqual(workspace.task(for: source), original, "Selecting is draft-only")
        try click(try XCTUnwrap(frames[.confirm]))
        XCTAssertTrue(closed)
        XCTAssertEqual(workspace.task(for: source)?.parentID, parent)
    }
}
