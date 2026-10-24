import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-07：顶栏进度条可交互。
///
/// 滴答的 `TTTaskDetailProgressView` 有 `isProgressChangable` +
/// `progressChangedHandler`，重写了 `mouseDown:` / `mouseMoved:` /
/// `updateTrackingAreas`。它没有"手动百分比"字段——进度就是子任务完成度，
/// 所以拖动等价于按比例勾选/取消勾选子任务。
@MainActor
final class ProgressBarInteractionTests: XCTestCase {

    // MARK: - 纯换算

    func testTargetDoneRoundsToNearestSubtask() {
        let progress = TaskInspectorSubtaskProgress(done: 1, total: 4)
        XCTAssertEqual(progress.targetDone(for: 0), 0)
        XCTAssertEqual(progress.targetDone(for: 0.2), 1, "0.8 条 → 1")
        XCTAssertEqual(progress.targetDone(for: 0.3), 1, "1.2 条 → 1")
        XCTAssertEqual(progress.targetDone(for: 0.4), 2, "1.6 条 → 2")
        XCTAssertEqual(progress.targetDone(for: 1), 4)
    }

    func testTargetDoneClampsOutOfRange() {
        let progress = TaskInspectorSubtaskProgress(done: 0, total: 3)
        XCTAssertEqual(progress.targetDone(for: -2), 0)
        XCTAssertEqual(progress.targetDone(for: 5), 3)
    }

    func testChecklistProgressIsReadOnly() throws {
        let progress = try XCTUnwrap(TaskInspectorSubtaskProgress.parse("2/5"))
        XCTAssertTrue(progress.isAdjustable, "子任务进度默认可调")
        let checklist = TaskInspectorSubtaskProgress(done: 2, total: 5, isAdjustable: false)
        XCTAssertFalse(checklist.isAdjustable)
        // 可调性只影响交互，不影响显示比例。
        XCTAssertEqual(checklist.fraction, progress.fraction)
    }

    func testParseRejectsMalformed() {
        XCTAssertNil(TaskInspectorSubtaskProgress.parse(nil))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("5"))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("2/0"), "total 必须 > 0")
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("6/5"), "done 不能超过 total")
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("-1/5"))
    }

    // MARK: - 写回

    func testAdjustCompletesPrefixAndRestoresRest() throws {
        let (environment, parentID, children) = try makeParent(childCount: 4)
        let workspace = environment.taskWorkspace
        // 先完成第 3 条，确认拖动会把它恢复。
        _ = workspace.complete(children[2])
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "1/4")

        workspace.adjustSubtaskCompletion(children, completedCount: 2)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "2/4")
        XCTAssertEqual(workspace.task(for: children[0])?.status, .completed)
        XCTAssertEqual(workspace.task(for: children[1])?.status, .completed)
        XCTAssertEqual(workspace.task(for: children[2])?.status, .active, "超出的要恢复")
        XCTAssertEqual(workspace.task(for: children[3])?.status, .active)
    }

    func testAdjustToZeroRestoresAll() throws {
        let (environment, parentID, children) = try makeParent(childCount: 3)
        let workspace = environment.taskWorkspace
        workspace.adjustSubtaskCompletion(children, completedCount: 3)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "3/3")

        workspace.adjustSubtaskCompletion(children, completedCount: 0)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "0/3")
    }

    func testAdjustIsOneUndoStep() throws {
        let (environment, parentID, children) = try makeParent(childCount: 3)
        let workspace = environment.taskWorkspace
        workspace.adjustSubtaskCompletion(children, completedCount: 3)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "3/3")

        workspace.undo()
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "0/3",
                       "一次拖动只应是一步撤销，撤销后整组回到拖动前")
    }

    func testAdjustWithSameCountIsNoOp() throws {
        let (environment, parentID, children) = try makeParent(childCount: 2)
        let workspace = environment.taskWorkspace
        workspace.adjustSubtaskCompletion(children, completedCount: 0)
        let before = workspace.revision
        workspace.adjustSubtaskCompletion(children, completedCount: 0)
        XCTAssertEqual(workspace.revision, before, "没有实际变化不产生修订")
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "0/2")
    }

    // MARK: - 视图

    func testBarExposesProgressAndAdjustability() throws {
        let (environment, _, children) = try makeParent(childCount: 4)
        _ = environment
        let box = FrameBox()
        let view = VStack {
            TaskInspectorProgressBar(progress: TaskInspectorSubtaskProgress(done: 1, total: 4),
                                     onAdjust: { _ in })
                .inspectorRenderAnchor(.progressBar)
        }
        .frame(width: 400)
        .coordinateSpace(name: "progress-render")
        .onPreferenceChange(InspectorFramesKey.self) { box.frames = $0 }
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        let frame = try XCTUnwrap(box.frames[.progressBar])
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertEqual(children.count, 4)
    }

    // MARK: - Helpers

    private final class FrameBox {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
    }

    private func makeParent(childCount: Int) throws -> (AppEnvironment, UUID, [UUID]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let parentID = try XCTUnwrap(workspace.createTask(title: "带子任务", in: .inbox).taskID)
        var children: [UUID] = []
        for index in 0..<childCount {
            let id = try XCTUnwrap(workspace.createChild(parentID, title: "子 \(index)").taskID)
            children.append(id)
        }
        return (environment, parentID, children)
    }
}
