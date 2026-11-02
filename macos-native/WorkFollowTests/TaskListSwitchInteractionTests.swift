import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListSwitchInteractionTests: XCTestCase {
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    func testSidebarSwitchKeepsCaptureControlDraftAndCreationTarget() throws {
        let names = ["虚构清单甲", "虚构清单乙"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date()
        let tasks = names.map { name in
            Task(id: UUID(), title: name + "原任务", list: TaskList(name: name), priority: .none,
                 schedule: TaskSchedule(dueAt: now), childOrder: 0, createdAt: now, updatedAt: now)
        }
        try NativePreviewRepository(directory: directory).save(.init(tasks: tasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.sidebarVisible = true
        environment.viewPreferences.setSidebarSectionCollapsed(.collections, false)
        environment.viewPreferences.setVisibility(.visible, for: SidebarSectionID.collections)
        let workspace = environment.taskWorkspace
        let navigation = environment.navigation
        navigation.destination = .inbox
        let keys = names.map { "listQuickAddDraft.v2." + TaskViewScopeKey.key(destination: .allTasks, activeList: $0, activeTag: nil) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        defer { for key in keys { UserDefaults.standard.removeObject(forKey: key) } }
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { anchors.removeAll(); window.close(); window.contentView = nil }
        func clickList(_ name: String) throws {
            let anchor = try XCTUnwrap(anchors["sidebar.list." + name])
            try InspectorPanelTestSupport.click(anchor.bounds, in: anchor, window: window)
        }
        let original = try XCTUnwrap(find(QuickAddFocusReportingField.self, in: host))
        try clickList(names[0])
        XCTAssertTrue(find(QuickAddFocusReportingField.self, in: host) === original)
        XCTAssertEqual(original.placeholderAttributedString?.string, "添加任务至“" + names[0] + "”")
        original.stringValue = "甲的草稿"
        original.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: original))
        InspectorPanelTestSupport.settle(window)
        try clickList(names[1])
        XCTAssertTrue(find(QuickAddFocusReportingField.self, in: host) === original)
        XCTAssertEqual(original.placeholderAttributedString?.string, "添加任务至“" + names[1] + "”")
        XCTAssertEqual(original.stringValue, "")
        original.onMouseDown?()
        window.makeFirstResponder(original)
        original.stringValue = "明天下午3点虚构讨论"
        original.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: original))
        InspectorPanelTestSupport.settle(window)
        window.makeFirstResponder(original)
        try InspectorPanelTestSupport.sendReturn(to: window)
        let created = try XCTUnwrap(workspace.allTasks.first { $0.title == "虚构讨论" })
        XCTAssertEqual(created.list.name, names[1])
        XCTAssertNotNil(created.schedule.dueAt)
        XCTAssertTrue(created.schedule.hasTime)
        try clickList(names[0])
        XCTAssertEqual(original.stringValue, "甲的草稿")
        XCTAssertEqual(original.placeholderAttributedString?.string, "添加任务至“" + names[0] + "”")
    }

    func testCommonTaskKeepsItsTitleControlAcrossInboxAndToday() throws {
        let environment = AppEnvironment(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let workspace = environment.taskWorkspace
        _ = workspace.createTask(title: "虚构共同任务", in: .today)
        workspace.select(nil)
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close(); window.contentView = nil }
        let original = try XCTUnwrap(find(TaskRowTitleField.Field.self, in: host))
        environment.navigate(to: .today)
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(find(TaskRowTitleField.Field.self, in: host) === original)
        environment.navigate(to: .inbox)
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(find(TaskRowTitleField.Field.self, in: host) === original)
        XCTAssertEqual(original.stringValue, "虚构共同任务")
    }
}
