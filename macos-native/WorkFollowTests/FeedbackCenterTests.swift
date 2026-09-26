import XCTest
@testable import WorkFollow

/// FeedbackCenter 纯逻辑测试：优先级仲裁、同键合并、undo 确认、时长档位、提示音节流，
/// 以及 workspace 埋点到 HUD 的端到端行为。声音经注入闭包记录，不真的出声。
final class FeedbackCenterTests: XCTestCase {
    // MARK: 工具

    /// 与 TaskWorkspaceModel.complete 的埋点同构：单条完成、可撤销、可合并。
    private func makeCompletion(_ title: String) -> FeedbackEvent {
        FeedbackEvent(kind: .completion, message: "已完成「\(title)」",
                      actionTitle: "撤销", action: {},
                      sound: .completion,
                      coalesceKey: "task-completed",
                      coalescedMessage: { "已完成 \($0) 个任务" })
    }

    @MainActor
    private func makeWorkspace() -> (TaskWorkspaceModel, FeedbackCenter) {
        let workspace = TaskWorkspaceModel(clock: { Date(timeIntervalSince1970: 1_800_000_000) },
                                           seedDemoData: false)
        let center = FeedbackCenter()
        workspace.feedbackSink = center
        return (workspace, center)
    }

    // MARK: 优先级仲裁

    func testHigherPriorityPreemptsAndLowerPriorityYields() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.show(FeedbackEvent(kind: .undoable, message: "已删除「A」",
                                      actionTitle: "撤销", action: {}))
            XCTAssertEqual(center.presentation?.event.kind, .undoable)

            // completion(60) < undoable(80)：撤销不被后续完成挤下屏。
            center.show(makeCompletion("B"))
            XCTAssertEqual(center.presentation?.event.kind, .undoable)
            XCTAssertEqual(center.presentation?.event.message, "已删除「A」")

            // error(100) 抢占一切。
            center.show(FeedbackEvent(kind: .error, message: "保存失败"))
            XCTAssertEqual(center.presentation?.event.kind, .error)

            // info(20) 在 error 面前让路。
            center.show(FeedbackEvent(kind: .info, message: "已添加到「收集箱」"))
            XCTAssertEqual(center.presentation?.event.message, "保存失败")

            // 空场时谁都可以上。
            center.dismiss()
            center.show(FeedbackEvent(kind: .info, message: "已添加到「收集箱」"))
            XCTAssertEqual(center.presentation?.event.message, "已添加到「收集箱」")
        }
    }

    func testEqualPriorityNewerReplacesOlder() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.show(FeedbackEvent(kind: .success, message: "已置顶"))
            center.show(FeedbackEvent(kind: .success, message: "已取消置顶"))
            XCTAssertEqual(center.presentation?.event.message, "已取消置顶")
        }
    }

    // MARK: 同键合并

    func testSameCoalesceKeyFoldsCountAndKeepsPresentationStable() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.show(makeCompletion("写周报"))
            let firstID = center.presentation?.id
            XCTAssertEqual(center.presentation?.event.message, "已完成「写周报」")

            center.show(makeCompletion("交周报"))
            XCTAssertEqual(center.presentation?.coalescedCount, 2)
            XCTAssertEqual(center.presentation?.event.message, "已完成 2 个任务")
            XCTAssertEqual(center.presentation?.id, firstID, "合并只换文案，不重放入场")

            center.show(makeCompletion("审周报"))
            XCTAssertEqual(center.presentation?.coalescedCount, 3)
            XCTAssertEqual(center.presentation?.event.message, "已完成 3 个任务")
        }
    }

    func testDifferentCoalesceKeysDoNotFold() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.show(makeCompletion("A"))
            center.show(FeedbackEvent(kind: .undoable, message: "已删除「A」",
                                      actionTitle: "撤销", action: {}))
            XCTAssertEqual(center.presentation?.event.kind, .undoable)
            XCTAssertEqual(center.presentation?.coalescedCount, 1)
        }
    }

    // MARK: undo

    func testUndoRunsClosureAndConfirmsWith已撤销() async {
        await MainActor.run {
            let center = FeedbackCenter()
            var undone = false
            center.show(FeedbackEvent(kind: .undoable, message: "已删除「A」",
                                      actionTitle: "撤销", action: { undone = true }))
            center.undo()
            XCTAssertTrue(undone)
            XCTAssertEqual(center.presentation?.event.kind, .success)
            XCTAssertEqual(center.presentation?.event.message, "已撤销")
        }
    }

    func testUndoWithoutActionIsNoOp() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.show(FeedbackEvent(kind: .info, message: "已添加到「收集箱」"))
            center.undo()
            XCTAssertEqual(center.presentation?.event.message, "已添加到「收集箱」")
        }
    }

    func testDismissClearsCurrentAndIsSafeWhenEmpty() async {
        await MainActor.run {
            let center = FeedbackCenter()
            center.dismiss()
            XCTAssertNil(center.presentation)
            center.show(makeCompletion("A"))
            center.dismiss()
            XCTAssertNil(center.presentation)
        }
    }

    // MARK: 时长档位

    func testHoldDurationsFollowTierTable() {
        // 对齐 Flutter：undo 4s / error 5s / completion 2.6s / 默认 2.6s。
        XCTAssertEqual(FeedbackTiming.undoHold, 4.0)
        XCTAssertEqual(FeedbackTiming.errorHold, 5.0)
        XCTAssertEqual(FeedbackTiming.completionHold, 2.6)
        XCTAssertEqual(FeedbackTiming.defaultHold, 2.6)
        XCTAssertEqual(FeedbackTiming.soundThrottle, 1.0)

        XCTAssertEqual(FeedbackEvent(kind: .completion, message: "x").hold, 2.6)
        XCTAssertEqual(FeedbackEvent(kind: .success, message: "x").hold, 2.6)
        XCTAssertEqual(FeedbackEvent(kind: .info, message: "x").hold, 2.6)
        XCTAssertEqual(FeedbackEvent(kind: .error, message: "x").hold, 5.0)
        // 可撤销（有动作）停留更久，跨 kind 一致。
        XCTAssertEqual(FeedbackEvent(kind: .undoable, message: "x",
                                     actionTitle: "撤销", action: {}).hold, 4.0)
        XCTAssertEqual(FeedbackEvent(kind: .completion, message: "x",
                                     actionTitle: "撤销", action: {}).hold, 4.0)
        // 显式 duration 覆盖档位。
        XCTAssertEqual(FeedbackEvent(kind: .info, message: "x", duration: 9).hold, 9)
    }

    // MARK: 提示音节流

    func testCompletionSoundThrottledWithinOneSecondWindow() async {
        await MainActor.run {
            // 盒子替代被逃逸闭包捕获的局部 var，时钟推进对中心即时可见。
            final class Box {
                var now = Date(timeIntervalSince1970: 0)
                var played: [FeedbackSound] = []
            }
            let box = Box()
            let center = FeedbackCenter(now: { box.now }, playSound: { box.played.append($0) })

            center.show(makeCompletion("A"))
            XCTAssertEqual(box.played, [.completion])

            // 半秒后的合并完成：音效并入第一次。
            box.now = box.now.addingTimeInterval(0.5)
            center.show(makeCompletion("B"))
            XCTAssertEqual(box.played, [.completion])

            // 窗口过后仍只有 completion 音会上报；success/info 静音。
            box.now = box.now.addingTimeInterval(1.1)
            center.show(FeedbackEvent(kind: .success, message: "已撤销"))
            XCTAssertEqual(box.played, [.completion])

            center.dismiss()
            center.show(makeCompletion("C"))
            XCTAssertEqual(box.played, [.completion, .completion])
        }
    }

    func testSoundDisabledSuppressesPlayback() async {
        await MainActor.run {
            var played: [FeedbackSound] = []
            let center = FeedbackCenter(playSound: { played.append($0) })
            center.completionSoundEnabled = false
            center.show(makeCompletion("A"))
            XCTAssertTrue(played.isEmpty)
        }
    }

    // MARK: workspace 埋点 → HUD 端到端

    func testWorkspaceCompletionReportsFeedbackAndUndoRestores() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let id = workspace.createTask(title: "写周报", in: .inbox).taskID!
            XCTAssertEqual(center.presentation?.event.message, "已添加到「收集箱」")

            _ = workspace.complete(id)
            XCTAssertEqual(center.presentation?.event.kind, .completion)
            XCTAssertEqual(center.presentation?.event.message, "已完成「写周报」")

            center.undo()
            XCTAssertEqual(center.presentation?.event.message, "已撤销")
            XCTAssertEqual(workspace.task(for: id)?.status, .active, "单步撤销回到未完成")
        }
    }

    func testWorkspaceRestoreReportsCompletionKind() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let id = workspace.createTask(title: "写周报", in: .inbox).taskID!
            _ = workspace.complete(id)
            _ = workspace.restore(id)
            XCTAssertEqual(center.presentation?.event.message, "已恢复「写周报」")
            XCTAssertEqual(workspace.task(for: id)?.status, .active)
        }
    }

    func testWorkspaceDeleteReportsUndoableAndUndoRestores() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let id = workspace.createTask(title: "写周报", in: .inbox).taskID!
            center.dismiss()
            _ = workspace.delete(id)
            XCTAssertEqual(center.presentation?.event.kind, .undoable)
            XCTAssertEqual(center.presentation?.event.message, "已删除「写周报」")

            center.undo()
            XCTAssertNil(workspace.task(for: id)?.deletedAt)
        }
    }

    func testWorkspaceSequentialCompletionsFoldIntoCountedMessage() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let first = workspace.createTask(title: "一", in: .inbox).taskID!
            let second = workspace.createTask(title: "二", in: .inbox).taskID!
            center.dismiss()

            _ = workspace.complete(first)
            let id = center.presentation?.id
            XCTAssertEqual(center.presentation?.event.message, "已完成「一」")
            _ = workspace.complete(second)
            XCTAssertEqual(center.presentation?.event.message, "已完成 2 个任务")
            XCTAssertEqual(center.presentation?.id, id)
        }
    }

    func testWorkspaceBulkCompleteReportsCountAndUndoRevertsBatch() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let first = workspace.createTask(title: "一", in: .inbox).taskID!
            let second = workspace.createTask(title: "二", in: .inbox).taskID!
            center.dismiss()

            workspace.setBulkSelection(in: [first, second])
            workspace.applyBulk(.complete)
            XCTAssertEqual(center.presentation?.event.kind, .completion)
            XCTAssertEqual(center.presentation?.event.message, "已完成 2 个任务")

            center.undo()
            XCTAssertEqual(workspace.task(for: first)?.status, .active)
            XCTAssertEqual(workspace.task(for: second)?.status, .active)
        }
    }

    func testWorkspaceNoopMutationsStaySilent() async {
        await MainActor.run {
            let (workspace, center) = makeWorkspace()
            let id = workspace.createTask(title: "写周报", in: .inbox).taskID!
            center.dismiss()

            // 无变化的成功结果不弹 HUD（置顶到相同状态、移动到当前所在清单）。
            _ = workspace.setPinned(id, false)
            _ = workspace.moveToList(id, .inbox)
            XCTAssertNil(center.presentation)
        }
    }
}
