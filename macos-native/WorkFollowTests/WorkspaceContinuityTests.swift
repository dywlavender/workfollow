import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class WorkspaceContinuityTests: XCTestCase {
    func testCaptureDraftRestartsWithPropertiesAndSuccessfulSubmitClearsIt() throws {
        let suite = "WorkFollow.Continuity.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        var controller: GlobalQuickAddController? = GlobalQuickAddController(workspace: workspace, defaults: defaults)
        controller?.draft.text = "准备评审"
        controller?.draft.description = "结论与资料"
        controller?.draft.schedule = .init(dueAt: Date(timeIntervalSince1970: 1800000000), reminderOffsets: [-10])
        controller?.draft.tags = ["工作"]
        controller?.draft.priority = .high
        controller = nil
        let reopened = GlobalQuickAddController(workspace: workspace, defaults: defaults)
        XCTAssertEqual(reopened.draft.text, "准备评审")
        XCTAssertEqual(reopened.draft.schedule?.reminderOffsets, [-10])
        XCTAssertEqual(reopened.draft.tags, ["工作"])
        reopened.submit(QuickCaptureSession(text: reopened.draft.text, description: reopened.draft.description,
            scheduleOverride: reopened.draft.schedule, priorityOverride: reopened.draft.priority,
            tagsOverride: reopened.draft.tags))
        XCTAssertEqual(workspace.allTasks.first?.priority, .high)
        XCTAssertEqual(workspace.allTasks.first?.document.plainText, "结论与资料")
        XCTAssertFalse(GlobalQuickAddDraft(defaults: defaults).hasContent)
        XCTAssertNil(defaults.data(forKey: GlobalQuickAddDraft.storageKey))
    }

    func testTaskNotesRoundTripRestoresSelectionsAndListContextInFullShell() throws {
        let environment = AppEnvironment()
        let workspace = environment.taskWorkspace
        let navigation = environment.navigation
        navigation.destination = .today
        let id = try XCTUnwrap(workspace.createTask(title: "上下文恢复验收", in: .today).taskID)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        workspace.select(id)
        environment.navigate(to: .notes)
        InspectorPanelTestSupport.settle(window)
        environment.notesWorkspace.create()
        let noteID = try XCTUnwrap(environment.notesWorkspace.selectedID)
        environment.navigate(to: .today)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.selectedTaskID, id)
        environment.navigate(to: .notes)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(environment.notesWorkspace.selectedID, noteID)
        environment.openTask(id)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.selectedTaskID, id, "显式链接优先于页面记忆")
        _ = workspace.moveToList(id, TaskList(name: "工作"))
        workspace.activeList = "工作"
        environment.navigate(to: .notes); InspectorPanelTestSupport.settle(window)
        environment.navigate(to: .allTasks); InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.activeList, "工作")
        XCTAssertEqual(workspace.selectedTaskID, id)
    }

    func testReturnMemoryDoesNotReopenDeletedTask() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let notes = NotesWorkspaceModel()
        let navigation = AppNavigation(destination: .today)
        let memory = WorkspaceSelectionMemory()
        memory.connect(workspace: workspace, notes: notes, navigation: navigation)
        let id = try XCTUnwrap(workspace.createTask(title: "删除后不恢复", in: .today).taskID)
        workspace.select(id)
        navigation.destination = .notes
        _ = workspace.delete(id)
        navigation.destination = .today
        XCTAssertNil(workspace.selectedTaskID)
    }
}
