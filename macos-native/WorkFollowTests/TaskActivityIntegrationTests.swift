import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskActivityIntegrationTests: XCTestCase {
    func testWorkspaceCommandsRecordRealChangesWithoutBackfilling() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-integration-\(UUID())")
        let activity = TaskActivityStore(directory: directory)
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let oldID = try XCTUnwrap(workspace.createTask(title: "旧任务", in: .inbox).taskID)
        workspace.attachActivityStore(activity)
        XCTAssertTrue(activity.events.isEmpty)
        _ = workspace.setTitle(oldID, "新标题")
        let count = activity.events.count
        _ = workspace.setTitle(oldID, "新标题")
        XCTAssertEqual(activity.events.count, count)
        _ = workspace.setPriority(oldID, .high)
        workspace.setTags(oldID, ["测试"])
        _ = workspace.complete(oldID)
        _ = workspace.restore(oldID)
        _ = workspace.createChild(oldID, title: "子任务")
        let kinds = Set(activity.events(for: oldID).map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.titleChanged, .priorityChanged, .tagsChanged, .completed, .restored, .childCreated]))
        XCTAssertFalse(kinds.contains(.created))
        let newID = try XCTUnwrap(workspace.createTask(title: "新任务", in: .inbox).taskID)
        XCTAssertEqual(activity.events(for: newID).map(\.kind), [.created])
    }

    func testOuterTransactionReportsFinalSnapshotAndUndoReportsRestore() {
        let store = WorkspaceStore()
        var snapshots: [([Task], [Task])] = []
        store.onTasksChanged = { snapshots.append(($0, $1)) }
        store.transaction {
            var task = Task(id: UUID(), title: "初始", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: Date(), updatedAt: Date())
            store.commit([task])
            task.title = "最终"
            store.commit([task])
        }
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].1.first?.title, "最终")
        store.undo()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots[1].1.isEmpty)
    }

    func testOnlySuccessfulFocusStartNotifiesActivity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-focus-\(UUID())")
        let activity = TaskActivityStore(directory: directory)
        let focus = FocusStore(directory: directory)
        focus.onTaskFocusStarted = { activity.recordFocusStart(taskID: $0, stopwatch: $1) }
        let id = UUID()
        XCTAssertTrue(focus.start(taskID: id, stopwatch: true))
        XCTAssertFalse(focus.start(taskID: id, stopwatch: false))
        XCTAssertEqual(activity.events(for: id).count, 1)
        XCTAssertEqual(activity.events(for: id).first?.kind, .focusStarted)
        _ = focus.giveUp()
    }

    func testActivityPanelClosesMoreAndUsesArrowlessChildWithEscape() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "动态浮层验收", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: TaskInspectorShell(workspace: workspace, showBack: false)
            .environmentObject(environment)
            .frame(width: 760, height: 700)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        func click(_ rect: CGRect) throws {
            let point = host.convert(NSPoint(x: rect.midX, y: host.isFlipped ? rect.midY : host.bounds.height - rect.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            settle()
        }
        settle()
        try click(try XCTUnwrap(frames[.footerMore]))
        try click(try XCTUnwrap(frames[.activityMenuRow]))
        let panel = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertNil(frames[.moreMenu])
        XCTAssertEqual(panel.frame.width, 320, accuracy: 1)
        XCTAssertTrue(window.frame.insetBy(dx: 8, dy: 8).contains(panel.frame),
                      "Footer activity must stay inside the owner even on a larger screen")
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: panel))
        settle()
        XCTAssertFalse(panel.isVisible)
    }
}
