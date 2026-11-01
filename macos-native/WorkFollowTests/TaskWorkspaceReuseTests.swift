import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskWorkspaceReuseTests: XCTestCase {
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let value = view as? T { return value }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    func testSelectionDoesNotInvalidateDataObservers() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "虚构任务", in: .inbox).taskID)
        var updates = 0
        let observation = workspace.dataObservation
        let subscription = observation.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }
        workspace.select(id)
        workspace.select(nil)
        XCTAssertEqual(updates, 0)
        workspace.setTitle(id, "新标题")
        XCTAssertEqual(updates, 1)
        workspace.setTitle(id, "新标题")
        workspace.setDocument(id, try XCTUnwrap(workspace.task(for: id)).document)
        XCTAssertEqual(updates, 1)
    }

    func testSharedOutlineRestoresScopeDraftsAndScrollPositions() throws {
        let now = Date()
        let tasks = (0..<100).map { index in
            Task(id: UUID(), title: "虚构任务 \(index)", list: .inbox, priority: .none,
                 schedule: TaskSchedule(dueAt: now), childOrder: index, createdAt: now, updatedAt: now)
        }
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: tasks)
        let environment = AppEnvironment()
        let navigation = AppNavigation(destination: .inbox)
        let keys = [NativeDestination.inbox, .today].map {
            "listQuickAddDraft.v2." + TaskViewScopeKey.key(destination: $0, activeList: nil, activeTag: nil, activeFilterID: nil)
        }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        defer { for key in keys { UserDefaults.standard.removeObject(forKey: key) } }
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close(); window.contentView = nil }
        let outline = try XCTUnwrap(find(NativeTaskOutline.OutlineView.self, in: host))
        let scroll = try XCTUnwrap(outline.enclosingScrollView)
        func enter(_ value: String) throws {
            let field = try XCTUnwrap(find(QuickAddFocusReportingField.self, in: host))
            field.stringValue = value
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            InspectorPanelTestSupport.settle(window)
        }
        try enter("收集箱草稿")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 420))
        scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        let inboxY = scroll.contentView.bounds.minY
        navigation.destination = .today
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(find(NativeTaskOutline.OutlineView.self, in: host) === outline)
        XCTAssertEqual(find(QuickAddFocusReportingField.self, in: host)?.stringValue, "")
        try enter("今天草稿")
        navigation.destination = .inbox
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(find(QuickAddFocusReportingField.self, in: host)?.stringValue, "收集箱草稿")
        XCTAssertEqual(scroll.contentView.bounds.minY, inboxY, accuracy: 2)
        navigation.destination = .today
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(find(QuickAddFocusReportingField.self, in: host)?.stringValue, "今天草稿")
    }

    func testSelectionOnlyRefreshesVisibleAffectedRows() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let ids = try (0..<40).map { try XCTUnwrap(workspace.createTask(title: "虚构任务 \($0)", in: .inbox).taskID) }
        let environment = AppEnvironment()
        let navigation = AppNavigation(destination: .inbox)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close(); window.contentView = nil }
        workspace.select(ids[0])
        InspectorPanelTestSupport.settle(window)
        NativeTaskOutline.Diagnostics.reset()
        let builds = workspace.projectionBuildCount
        for id in [ids[1], ids[0], ids[1]] {
            workspace.select(id)
            InspectorPanelTestSupport.settle(window)
        }
        XCTAssertEqual(workspace.projectionBuildCount, builds)
        XCTAssertEqual(NativeTaskOutline.Diagnostics.createdCells, 0)
        XCTAssertEqual(NativeTaskOutline.Diagnostics.configurations, 6)
        XCTAssertEqual(NativeTaskOutline.Diagnostics.updateTime, 0, "选择不应重新构建整个列表的行描述")
    }
}
