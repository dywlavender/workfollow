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

    func testTaskNotesRoundTripRestoresListContextButClosesDetails() throws {
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
        XCTAssertNotNil(environment.notesWorkspace.selectedID)
        XCTAssertNil(workspace.selectedTaskID, "切到笔记后任务详情关闭")
        environment.navigate(to: .today)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNil(workspace.selectedTaskID, "切回清单不再恢复任务详情")
        environment.navigate(to: .notes)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNil(environment.notesWorkspace.selectedID, "切回笔记不再恢复笔记详情")
        environment.openTask(id)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.selectedTaskID, id, "显式链接仍直接打开任务")
        _ = workspace.moveToList(id, TaskList(name: "工作"))
        workspace.activeList = "工作"
        environment.navigate(to: .notes); InspectorPanelTestSupport.settle(window)
        environment.navigate(to: .allTasks); InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.activeList, "工作", "清单上下文仍然逐页恢复")
        XCTAssertNil(workspace.selectedTaskID, "清单上下文不包含选中任务")
    }

    func testSwitchingScopesClosesTaskAndNoteDetails() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let notes = NotesWorkspaceModel()
        let navigation = AppNavigation(destination: .today)
        let memory = WorkspaceSelectionMemory()
        memory.connect(workspace: workspace, notes: notes, navigation: navigation)
        let id = try XCTUnwrap(workspace.createTask(title: "关闭详情", in: .today).taskID)
        workspace.activeList = "工作"
        workspace.select(id)
        navigation.destination = .inbox
        XCTAssertNil(workspace.selectedTaskID)
        navigation.destination = .today
        XCTAssertNil(workspace.selectedTaskID, "返回清单只恢复筛选上下文，不恢复详情")
        XCTAssertEqual(workspace.activeList, "工作")

        navigation.destination = .notes
        notes.create()
        XCTAssertNotNil(notes.selectedID)
        navigation.destination = .notesTrash
        XCTAssertNil(notes.selectedID)
        navigation.destination = .notes
        XCTAssertNil(notes.selectedID, "笔记与垃圾桶之间切换同样不恢复详情")
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
