import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskBatchInteractionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ title: String, parentID: UUID? = nil) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(), parentID: parentID, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func environment(tasks: [Task]) throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-batch-flow-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try NativePreviewRepository(directory: directory)
            .save(NativeWorkspaceSnapshot(tasks: tasks, notes: []))
        return AppEnvironment(clock: { self.now }, directory: directory)
    }

    private func panelWindow(environment: AppEnvironment,
                             actionFrames: @escaping ([String: CGRect]) -> Void,
                             parentFrames: @escaping ([TaskParentPickerAnchor: CGRect]) -> Void = { _ in }) -> NSWindow {
        let root = TaskBatchPanelView(workspace: environment.taskWorkspace)
            .environmentObject(environment)
            .onPreferenceChange(TaskBatchPanelActionFrames.self, perform: actionFrames)
            .environment(\.popupContentObservation, { content in
                AnyView(content.onPreferenceChange(TaskParentPickerFrames.self, perform: parentFrames))
            })
        return InspectorPanelTestSupport.ownerWindow(
            for: NSHostingView(rootView: root), width: 400, height: 850)
    }

    func testBatchPanelParentPickerAssignsEverySourceAndUndoesTogether() throws {
        let first = task("整理提纲"), second = task("补齐附件"), parent = task("提交周报")
        let environment = try environment(tasks: [first, second, parent])
        let workspace = environment.taskWorkspace
        workspace.setBulkSelection(in: [first.id, second.id])
        let before = workspace.allTasks
        var actions: [String: CGRect] = [:]
        var candidates: [TaskParentPickerAnchor: CGRect] = [:]
        let window = panelWindow(environment: environment, actionFrames: { actions = $0 },
                                 parentFrames: { candidates = $0 })
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        try InspectorPanelTestSupport.click(try XCTUnwrap(actions["关联主任务"]), in: host, window: window)
        let picker = try InspectorPanelTestSupport.panel(title: "批量关联主任务", below: window)
        let pickerHost = try XCTUnwrap(picker.contentView)
        XCTAssertNil(candidates[.candidate(first.id)], "整个批选集合均不可成为自己的目标")
        XCTAssertNil(candidates[.candidate(second.id)])
        try InspectorPanelTestSupport.click(try XCTUnwrap(candidates[.candidate(parent.id)]),
                                             in: pickerHost, window: picker)
        XCTAssertEqual(workspace.allTasks, before, "浏览与选择只改草稿")
        try InspectorPanelTestSupport.click(try XCTUnwrap(candidates[.confirm]), in: pickerHost, window: picker)

        XCTAssertEqual(workspace.task(for: first.id)?.parentID, parent.id)
        XCTAssertEqual(workspace.task(for: second.id)?.parentID, parent.id)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        let after = workspace.allTasks
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before, "一次撤销恢复所有来源")
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, after)
    }

    func testSingleSelectionMergeTileDoesNotClearSelectionOrCreateParent() throws {
        let source = task("整理周报")
        let environment = try environment(tasks: [source])
        let workspace = environment.taskWorkspace
        workspace.setBulkSelection(in: [source.id])
        let before = workspace.allTasks
        var actions: [String: CGRect] = [:]
        let window = panelWindow(environment: environment, actionFrames: { actions = $0 })
        defer { window.close() }
        try InspectorPanelTestSupport.click(try XCTUnwrap(actions["合并"]),
                                             in: try XCTUnwrap(window.contentView), window: window)

        XCTAssertEqual(workspace.bulkSelection, [source.id], "禁用瓦片不执行失败动作")
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testBatchPanelConversionPreservesTaskIdentityAndUndoesTogether() throws {
        var first = task("交付复盘")
        first.document = NativeDocument(plainText: "保留复盘正文")
        let child = task("记录验收结果", parentID: first.id)
        var second = task("下周计划")
        second.tags = ["工作"]
        let environment = try environment(tasks: [first, child, second])
        let workspace = environment.taskWorkspace
        let destination = environment.navigation.destination
        workspace.setBulkSelection(in: [first.id, child.id, second.id])
        let before = workspace.allTasks
        var actions: [String: CGRect] = [:]
        let window = panelWindow(environment: environment, actionFrames: { actions = $0 })
        defer { window.close() }
        try InspectorPanelTestSupport.click(try XCTUnwrap(actions["转换为笔记"]),
                                             in: try XCTUnwrap(window.contentView), window: window)

        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        XCTAssertEqual(environment.navigation.destination, destination)
        XCTAssertTrue(environment.notesWorkspace.notes.isEmpty)
        for original in before {
            let changed = try XCTUnwrap(workspace.task(for: original.id))
            XCTAssertEqual(changed.kind, .note)
            XCTAssertEqual(changed.parentID, original.parentID)
            XCTAssertEqual(changed.document, original.document)
            XCTAssertEqual(changed.tags, original.tags)
            XCTAssertNil(changed.deletedAt)
            XCTAssertNil(changed.convertedNoteID)
        }
        let after = workspace.allTasks

        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo, "转换没有留下隐藏的逐项历史")
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, after)
        workspace.setBulkSelection(in: [first.id, child.id, second.id])
        InspectorPanelTestSupport.settle(window)
        try InspectorPanelTestSupport.click(try XCTUnwrap(actions["转换为任务"]),
                                             in: try XCTUnwrap(window.contentView), window: window)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        XCTAssertTrue(workspace.allTasks.allSatisfy { $0.kind == .text })
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, after)
    }
}
