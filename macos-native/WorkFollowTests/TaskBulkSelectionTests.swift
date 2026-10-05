import Combine
import XCTest
@testable import WorkFollow

/// 阶段2：批量选中的模型层不变量（状态机 A 的锚点规则）与批量执行语义
/// （状态机 B：单事务、HUD 撤销、空集合幂等、complete/delete 子任务结转）。
@MainActor
final class TaskBulkSelectionTests: XCTestCase {
    func testPlainSelectionPublishesOnlyVisibleChanges() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "第一项", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "第二项", in: .inbox).taskID)
        workspace.select(first)
        var publications = 0
        let subscription = workspace.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        workspace.select(second)
        XCTAssertEqual(publications, 1, "One visible selection change needs one publication")
        XCTAssertEqual(workspace.bulkAnchorTaskID, second)
        publications = 0
        workspace.select(second)
        workspace.clearBulkSelection()
        XCTAssertEqual(publications, 0, "Same selection and already-empty bulk state are not UI changes")
        workspace.selectFromKeyboard(first)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(workspace.bulkAnchorTaskID, first)
        workspace.setBulkSelection(in: [first, second])
        publications = 0
        workspace.clearBulkSelection()
        XCTAssertEqual(publications, 1, "Clearing a real bulk selection still refreshes the UI")
        XCTAssertNil(workspace.bulkAnchorTaskID)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!
    }

    private func makeTask(_ title: String, dueAt: Date? = nil,
                          deadlineAt: Date? = nil, list: TaskList = .inbox) -> Task {
        let created = now
        return Task(id: UUID(), title: title, list: list, priority: .none,
                    schedule: TaskSchedule(dueAt: dueAt, deadlineAt: deadlineAt),
                    parentID: nil, childOrder: 0, createdAt: created, updatedAt: created)
    }

    private func makeWorkspace(_ tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                           seedDemoData: false, initialTasks: tasks)
    }

    // MARK: - 状态机 A：锚点与集合规则

    func testToggleFromSingleSelectCarriesCurrentSelectionWithClickedAnchor() {
        let a = makeTask("a"), b = makeTask("b")
        let workspace = makeWorkspace([a, b])
        workspace.select(a.id)   // S1：选中 a

        workspace.toggleBulkSelection(b.id, carryingSelection: true)

        XCTAssertEqual(workspace.bulkSelection, [a.id, b.id])
        XCTAssertEqual(workspace.bulkAnchorTaskID, b.id, "锚点停在点击行，Shift 范围从最后点击处延伸")
    }

    func testToggleCarryingSelectionIsPlainToggleWhenBulkAlreadyActive() {
        let a = makeTask("a"), b = makeTask("b"), c = makeTask("c")
        let workspace = makeWorkspace([a, b, c])
        workspace.select(a.id)
        workspace.toggleBulkSelection(b.id, carryingSelection: true)

        workspace.toggleBulkSelection(c.id, carryingSelection: true)

        XCTAssertEqual(workspace.bulkSelection, [a.id, b.id, c.id],
                       "批量已激活时 carryingSelection 不再夹带单选行（S2 内点击一律切换）")
        XCTAssertEqual(workspace.bulkAnchorTaskID, c.id, "锚点跟随最新点击行")
    }

    func testToggleRemovalKeepsAnchorUntilSetEmpties() {
        let a = makeTask("a"), b = makeTask("b"), c = makeTask("c")
        let workspace = makeWorkspace([a, b, c])
        workspace.toggleBulkSelection(a.id)
        workspace.toggleBulkSelection(b.id)
        workspace.toggleBulkSelection(c.id)

        workspace.toggleBulkSelection(c.id)
        XCTAssertEqual(workspace.bulkSelection, [a.id, b.id])
        XCTAssertNotNil(workspace.bulkAnchorTaskID, "移除后集合非空，锚点不动")

        workspace.toggleBulkSelection(a.id)
        workspace.toggleBulkSelection(b.id)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        XCTAssertNil(workspace.bulkAnchorTaskID, "集合清空即落回 S0，锚点一并复位")
    }

    func testExtendBulkSelectionCoversInclusiveRangeRegardlessOfDirection() {
        let tasks = (0..<5).map { makeTask("t\($0)") }
        let order = tasks.map(\.id)
        let workspace = makeWorkspace(tasks)
        workspace.setBulkSelection(in: [order[1]])

        workspace.extendBulkSelection(to: order[3], in: order)
        XCTAssertEqual(workspace.bulkSelection, Set(order[1...3]))

        workspace.setBulkSelection(in: [order[3]])
        workspace.extendBulkSelection(to: order[0], in: order)
        XCTAssertEqual(workspace.bulkSelection, Set(order[0...3]), "反向延伸同样闭合")
    }

    // MARK: - 状态机 B：批量执行语义

    func testApplyBulkCompleteFinishesActiveTasksAndClearsSelection() {
        let active1 = makeTask("a1"), active2 = makeTask("a2")
        let closed = makeTask("done")
        var closedTask = closed
        closedTask.status = .completed
        closedTask.completedAt = now
        let workspace = makeWorkspace([active1, active2, closedTask])
        workspace.setBulkSelection(in: [active1.id, active2.id, closedTask.id])

        workspace.applyBulk(.complete)

        XCTAssertTrue(workspace.bulkSelection.isEmpty, "执行后落回 S0")
        XCTAssertTrue(workspace.task(for: active1.id)?.status == .completed)
        XCTAssertTrue(workspace.task(for: active2.id)?.status == .completed)
        XCTAssertEqual(workspace.task(for: closedTask.id)?.completedAt, now,
                       "已完成的任务不再重复盖章")
        workspace.undo()
        XCTAssertTrue(workspace.task(for: active1.id)?.status == .active, "批量是一次事务，一步撤销整批生效")
    }

    func testApplyBulkMoveOnlyTouchesRootsAndCarriesChildren() throws {
        let parent = makeTask("parent")
        let workspace = makeWorkspace([parent])
        let childID = try XCTUnwrap(workspace.createChild(parent.id, title: "child").taskID)
        workspace.setBulkSelection(in: [parent.id, childID])

        workspace.applyBulk(.move("学习"))

        XCTAssertEqual(workspace.task(for: parent.id)?.list.name, "学习")
        XCTAssertEqual(workspace.task(for: childID)?.list.name, "学习",
                       "父任务移动自带子任务；批量子任务不再单独移动（避免重复结转）")
    }

    func testApplyBulkSchedulePreservesEachTaskDeadline() {
        let deadline = calendar.date(byAdding: .day, value: 5, to: now)!
        let withDeadline = makeTask("with deadline", dueAt: now, deadlineAt: deadline)
        let plain = makeTask("plain")
        let workspace = makeWorkspace([withDeadline, plain])
        workspace.setBulkSelection(in: [withDeadline.id, plain.id])
        let target = calendar.date(byAdding: .day, value: 2, to: now)!

        workspace.applyBulk(.schedule(TaskSchedule(dueAt: target)))

        XCTAssertEqual(workspace.task(for: withDeadline.id)?.schedule.dueAt, target)
        XCTAssertEqual(workspace.task(for: withDeadline.id)?.schedule.deadlineAt, deadline,
                       "批量改期不得抹掉各自的截止日期")
        XCTAssertEqual(workspace.task(for: plain.id)?.schedule.dueAt, target)
        XCTAssertNil(workspace.task(for: plain.id)?.schedule.deadlineAt)
    }

    func testApplyBulkOnEmptySelectionChangesNothing() {
        let task = makeTask("a")
        let workspace = makeWorkspace([task])
        let before = workspace.allTasks

        workspace.applyBulk(.complete)

        XCTAssertEqual(workspace.allTasks, before, "空集合幂等跳过")
        XCTAssertFalse(workspace.task(for: task.id)?.status == .completed)
    }

    func testDeleteViaBulkClearsInspectorSelectionForDeletedTask() {
        let a = makeTask("a")
        let workspace = makeWorkspace([a])
        workspace.select(a.id)
        workspace.setBulkSelection(in: [a.id])

        workspace.applyBulk(.delete)

        XCTAssertNil(workspace.selectedTaskID, "被删任务正是详情任务时，详情随之关闭")
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        XCTAssertNotNil(workspace.task(for: a.id)?.deletedAt)
    }

    // MARK: - 阶段4：置顶 / 复制 / 放弃

    func testApplyBulkPinMarksAllSelectedAndIsUndoable() {
        let a = makeTask("a"), b = makeTask("b")
        let workspace = makeWorkspace([a, b])
        workspace.setBulkSelection(in: [a.id, b.id])

        workspace.applyBulk(.pin(true))

        XCTAssertTrue(workspace.task(for: a.id)?.isPinned == true)
        XCTAssertTrue(workspace.task(for: b.id)?.isPinned == true)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)

        workspace.undo()
        XCTAssertFalse(workspace.task(for: a.id)?.isPinned ?? true, "批量置顶一步撤销整批")
    }

    func testApplyBulkDuplicateCarriesChildrenOnce() throws {
        let parent = makeTask("parent")
        let workspace = makeWorkspace([parent])
        let childID = try XCTUnwrap(workspace.createChild(parent.id, title: "child").taskID)
        workspace.setBulkSelection(in: [parent.id, childID])

        workspace.applyBulk(.duplicate)

        XCTAssertEqual(workspace.allTasks.count, 4,
                       "父任务复制自带子任务；批内子任务不再单独复制（避免双份）")
        XCTAssertEqual(workspace.allTasks.filter { $0.title == "parent" }.count, 2)
        XCTAssertEqual(workspace.allTasks.filter { $0.title == "child" }.count, 2)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
    }

    func testApplyBulkAbandonSkipsClosedTasks() {
        let open = makeTask("open")
        let done = makeTask("done")
        var closed = done
        closed.status = .completed
        closed.completedAt = now
        let workspace = makeWorkspace([open, closed])
        workspace.setBulkSelection(in: [open.id, closed.id])

        workspace.applyBulk(.abandon)

        XCTAssertTrue(workspace.task(for: open.id)?.isAbandoned == true)
        XCTAssertFalse(workspace.task(for: closed.id)?.isAbandoned ?? true,
                       "已完成任务不追加放弃态")
        XCTAssertEqual(workspace.task(for: closed.id)?.status, .completed)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
    }

    // MARK: - 补齐轮：批量标签 / 批量关联主任务

    func testApplyBulkTagsMergesWithoutDuplicates() {
        var tagged = makeTask("tagged")
        tagged.tags = ["工作"]
        let plain = makeTask("plain")
        let workspace = makeWorkspace([tagged, plain])
        workspace.setBulkSelection(in: [tagged.id, plain.id])

        workspace.applyBulk(.tags(["紧急", "工作"]))

        XCTAssertEqual(workspace.task(for: tagged.id)?.tags, ["工作", "紧急"],
                       "已有标签保留,新标签追加去重")
        XCTAssertEqual(workspace.task(for: plain.id)?.tags, ["紧急", "工作"])
        XCTAssertTrue(workspace.bulkSelection.isEmpty)

        workspace.undo()
        XCTAssertEqual(workspace.task(for: tagged.id)?.tags, ["工作"], "批量标签一步撤销整批")
        XCTAssertEqual(workspace.task(for: plain.id)?.tags, [])
    }

    func testApplyBulkLinkParentAssignsAllToSameParent() throws {
        let parent = makeTask("parent")
        let a = makeTask("a"), b = makeTask("b")
        let workspace = makeWorkspace([parent, a, b])
        workspace.setBulkSelection(in: [a.id, b.id])

        workspace.applyBulk(.linkParent(parent.id))

        XCTAssertEqual(workspace.task(for: a.id)?.parentID, parent.id)
        XCTAssertEqual(workspace.task(for: b.id)?.parentID, parent.id)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)

        workspace.undo()
        XCTAssertNil(workspace.task(for: a.id)?.parentID, "批量关联一步撤销整批")
    }

    func testApplyBulkLinkParentSkipsPolicyViolations() {
        let parent = makeTask("parent")
        let child = makeTask("child")
        let free = makeTask("free")
        let workspace = makeWorkspace([parent, child, free])
        _ = workspace.assignParent(child.id, parentID: parent.id) // 已是子任务:不能再挂
        workspace.setBulkSelection(in: [child.id, free.id])

        workspace.applyBulk(.linkParent(parent.id))

        XCTAssertEqual(workspace.task(for: child.id)?.parentID, parent.id,
                       "已有父的任务策略拒绝,保持原父不动")
        XCTAssertEqual(workspace.task(for: free.id)?.parentID, parent.id, "合法目标正常挂载")
    }

// MARK: - 补齐轮:批量合并(滴答实测语义:所选任务全部变成子任务,父任务新建)

func testApplyBulkMergeCreatesParentWithAllSelectedAsChildren() {
    let a = makeTask("a"), b = makeTask("b"), c = makeTask("c")
    let workspace = makeWorkspace([a, b, c])
    workspace.setBulkSelection(in: [a.id, b.id, c.id])

    workspace.mergeBulkTasks()

    let parent = workspace.allTasks.first { $0.title == "合并任务" }
    let parentID = parent?.id
    XCTAssertNotNil(parent, "新建父任务")
    XCTAssertEqual(workspace.task(for: a.id)?.parentID, parentID)
    XCTAssertEqual(workspace.task(for: b.id)?.parentID, parentID)
    XCTAssertEqual(workspace.task(for: c.id)?.parentID, parentID)
    XCTAssertEqual(workspace.allTasks.filter { $0.parentID == parentID }.count, 3)
    XCTAssertTrue(workspace.bulkSelection.isEmpty)

    workspace.undo()
    XCTAssertNil(workspace.task(for: a.id)?.parentID, "合并一步撤销")
    XCTAssertNil(workspace.allTasks.first { $0.title == "合并任务" }, "撤销后父任务消失")
}

func testMergeBulkTasksBelowTwoReturnsNil() {
    let a = makeTask("a")
    let workspace = makeWorkspace([a])
    workspace.setBulkSelection(in: [a.id])

    let parentID = workspace.mergeBulkTasks()

    XCTAssertNil(parentID, "少于 2 条不合并(滴答置灰语义)")
    XCTAssertTrue(workspace.bulkSelection.isEmpty, "操作后集合清空")
}
}
