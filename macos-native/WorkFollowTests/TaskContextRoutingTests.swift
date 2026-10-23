import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskContextRoutingTests: XCTestCase {
    func testTaskRightClickWithSidebarInTheProductionShell() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-context-routing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(seed.createTask(title: "完整窗口右键路由", in: .inbox).taskID)
        _ = seed.setDueDate(id, Date())
        try NativePreviewRepository(directory: directory)
            .save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        let workspace = environment.taskWorkspace
        environment.navigation.destination = .inbox
        var menuRows: [BusinessMenuRowFrame] = []
        let root = RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "business-menu")
                    .onPreferenceChange(BusinessMenuRowFrames.self) { menuRows = $0 })
            })
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer {
            TaskContextMenuPresenter.activeSession?.close()
            window.close()
        }
        InspectorPanelTestSupport.settle(window, duration: 0.4)
        for destination: NativeDestination in [.inbox, .today, .inbox] {
            environment.navigate(to: destination)
            InspectorPanelTestSupport.settle(window)
            let row = try XCTUnwrap(descendants(host)
                .compactMap { $0 as? SecondaryClickCapture.SecondaryClickView }
                .first { !$0.bounds.intersection($0.visibleRect).isEmpty })
            let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
            try rightClick(point, in: window)
            let session = try XCTUnwrap(TaskContextMenuPresenter.activeSession,
                                        "任务区域不能弹出侧栏智能清单的显示设置")
            XCTAssertEqual(session.coordinator.panel?.title, "任务右键菜单")
            XCTAssertFalse(InspectorPanelTestSupport.visibleWindows(below: window)
                .contains { $0.title == "操作菜单" })
            session.close()
        }

        // The sidebar must retain its own visibility menu after task navigation.
        let sidebarPoint = host.convert(NSPoint(x: WFMetrics.railWidth + WFMetrics.navigationWidth / 2,
            y: WFSpace.md + NavigationMetrics.rowHeight / 2), to: nil)
        try rightClick(sidebarPoint, in: window)
        let sidebarMenu = try InspectorPanelTestSupport.panel(title: "操作菜单", below: window)
        XCTAssertEqual(menuRows.count, SmartListVisibility.allCases.count)
        XCTAssertNil(TaskContextMenuPresenter.activeSession)
        try InspectorPanelTestSupport.sendEscape(to: window)
        XCTAssertFalse(sidebarMenu.isVisible)

        // Empty task-area space must not open any sidebar menu either.
        try rightClick(host.convert(NSPoint(x: 600, y: 650), to: nil), in: window)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: window).isEmpty)
        XCTAssertEqual(workspace.task(for: id)?.title, "完整窗口右键路由")
    }

    func testUnclippedSiblingContextTargetsOnlyClaimTheirOwnRows() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let first = NSView(frame: NSRect(x: 20, y: 20, width: 196, height: 38))
        let second = NSView(frame: NSRect(x: 20, y: 80, width: 196, height: 38))
        for row in [first, second] { row.clipsToBounds = false; root.addSubview(row) }
        let window = InspectorPanelTestSupport.ownerWindow(for: root, width: 600, height: 400)
        let registry = PopupInteractionRegistry()
        var firstCalls = 0, secondCalls = 0
        let firstID = registry.registerContext(view: first) { _ in firstCalls += 1 }
        let secondID = registry.registerContext(view: second) { _ in secondCalls += 1 }
        defer {
            registry.unregisterContext(firstID); registry.unregisterContext(secondID)
            window.close()
        }
        XCTAssertFalse(registry.showContextMenu(for: try mouseEvent(at: NSPoint(x: 400, y: 100), in: window)))
        XCTAssertEqual(firstCalls + secondCalls, 0)
        XCTAssertTrue(registry.showContextMenu(for: try mouseEvent(at: NSPoint(x: 100, y: 35), in: window)))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 0)
        XCTAssertTrue(registry.showContextMenu(for: try mouseEvent(at: NSPoint(x: 100, y: 95), in: window)))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)
    }

    func testNestedContextTargetStillWinsOverItsContainer() throws {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let child = NSView(frame: NSRect(x: 20, y: 20, width: 196, height: 38))
        parent.addSubview(child)
        let window = InspectorPanelTestSupport.ownerWindow(for: parent, width: 600, height: 400)
        let registry = PopupInteractionRegistry()
        var calls: [String] = []
        let childID = registry.registerContext(view: child) { _ in calls.append("child") }
        let parentID = registry.registerContext(view: parent) { _ in calls.append("parent") }
        defer {
            registry.unregisterContext(childID); registry.unregisterContext(parentID)
            window.close()
        }
        XCTAssertTrue(registry.showContextMenu(for: try mouseEvent(at: NSPoint(x: 100, y: 35), in: window)))
        XCTAssertEqual(calls, ["child"])
        XCTAssertTrue(registry.showContextMenu(for: try mouseEvent(at: NSPoint(x: 400, y: 100), in: window)))
        XCTAssertEqual(calls, ["child", "parent"])
    }

    private func mouseEvent(at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func rightClick(_ point: NSPoint, in window: NSWindow) throws {
        let event = try mouseEvent(at: point, in: window)
        NSApp.postEvent(event, atStart: true)
        let down = try XCTUnwrap(NSApp.nextEvent(matching: .rightMouseDown, until: Date(),
                                                inMode: .default, dequeue: true))
        NSApp.sendEvent(down)
        InspectorPanelTestSupport.settle(window)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
