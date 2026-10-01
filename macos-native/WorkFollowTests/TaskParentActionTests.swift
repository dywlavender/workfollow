import XCTest
@testable import WorkFollow

final class TaskParentActionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeTask(_ title: String, parentID: UUID? = nil,
                          list: TaskList = .inbox, childOrder: Int = 0,
                          createdAt: Date? = nil, updatedAt: Date? = nil) -> Task {
        Task(id: UUID(), title: title, list: list, priority: .none, schedule: TaskSchedule(),
             parentID: parentID, childOrder: childOrder,
             createdAt: createdAt ?? now, updatedAt: updatedAt ?? now)
    }

    private func replacingHierarchy(of task: Task, parentID: UUID?, list: TaskList,
                                    childOrder: Int, updatedAt: Date) -> Task {
        Task(id: task.id, title: task.title, document: task.document, tags: task.tags,
             recurrence: task.recurrence, recurrenceRule: task.recurrenceRule,
             reminderAt: task.reminderAt, reminderOffsets: task.reminderOffsets,
             attachments: task.attachments, list: list, priority: task.priority,
             schedule: task.schedule, status: task.status, parentID: parentID,
             childOrder: childOrder, createdAt: task.createdAt, updatedAt: updatedAt,
             completedAt: task.completedAt, deletedAt: task.deletedAt, isPinned: task.isPinned,
             abandonedAt: task.abandonedAt, skippedAt: task.skippedAt,
             convertedNoteID: task.convertedNoteID, sourceNoteID: task.sourceNoteID)
    }

    func testReparentingMovesAcrossListsAppendsAfterDeletedSiblingsPreservesFieldsAndUndoesOnce() throws {
        let oldRoot = makeTask("旧父任务", list: TaskList(name: "旧清单"))
        let newRoot = makeTask("新父任务", list: TaskList(name: "新清单"))
        let activeSibling = makeTask("现有子任务", parentID: newRoot.id,
                                     list: newRoot.list, childOrder: 2)
        var deletedSibling = makeTask("已删除子任务", parentID: newRoot.id,
                                      list: newRoot.list, childOrder: 8)
        deletedSibling.deletedAt = now.addingTimeInterval(-60)
        let original = makeTask("待重挂", parentID: oldRoot.id, list: oldRoot.list,
                                childOrder: 4, createdAt: now.addingTimeInterval(-600),
                                updatedAt: now.addingTimeInterval(-120))
        var source = original
        source.document = NativeDocument(plainText: "保留正文")
        source.tags = ["项目", "重要"]
        source.recurrence = .weekly
        source.recurrenceRule = RecurrenceRule(interval: 2, remainingCount: 4, weekday: 3)
        source.reminderAt = now.addingTimeInterval(3_600)
        source.reminderOffsets = [-15, 0]
        source.attachments = [NativeAttachment(id: UUID(), name: "资料.pdf", storedName: "资料.pdf")]
        source.priority = .high
        source.schedule = TaskSchedule(dueAt: now, hasTime: true,
                                       dueEndAt: now.addingTimeInterval(7_200),
                                       deadlineAt: now.addingTimeInterval(86_400))
        source.isPinned = true
        source.sourceNoteID = UUID()

        let before = [oldRoot, newRoot, activeSibling, deletedSibling, source]
        let store = WorkspaceStore()
        store.commit(before, undoPolicy: .skip)
        store.clearUndo()
        let actions = TaskActions(store: store, clock: { self.now })

        XCTAssertEqual(actions.setParent(source.id, parentID: newRoot.id), .success(source.id))

        let expected = replacingHierarchy(of: source, parentID: newRoot.id, list: newRoot.list,
                                         childOrder: 9, updatedAt: now)
        XCTAssertEqual(store.task(source.id), expected,
                       "重挂只更换父级、跟随清单、追加顺序和更新时间，其余任务字段保留")
        XCTAssertTrue(store.canUndo)

        actions.undo()

        XCTAssertEqual(store.tasks, before, "一次撤销完整恢复重挂前快照")
        XCTAssertFalse(store.canUndo, "重挂只记录一个 undo 步骤")
    }

    func testSettingSameParentIsSuccessfulNoOpWithoutUndoCommit() {
        let parent = makeTask("父任务")
        let child = makeTask("子任务", parentID: parent.id)
        let store = WorkspaceStore()
        store.commit([parent, child], undoPolicy: .skip)
        store.clearUndo()
        let before = store.tasks
        let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.setPriority(child.id, .high)
        let afterEdit = store.tasks

        XCTAssertEqual(actions.setParent(child.id, parentID: parent.id), .success(child.id))

        XCTAssertEqual(store.tasks, afterEdit)
        XCTAssertTrue(store.canUndo)
        actions.undo()
        XCTAssertEqual(store.tasks, before, "同一父级不会在既有 undo 记录前插入步骤")
        XCTAssertFalse(store.canUndo)
    }

    func testSetParentRejectsSelfChildTargetAndSourceWithDeletedChild() {
        let source = makeTask("来源")
        let targetRoot = makeTask("目标根任务")
        let childTargetRoot = makeTask("子目标的父任务")
        let childTarget = makeTask("子目标", parentID: childTargetRoot.id)
        let sourceWithChild = makeTask("已有子任务的来源")
        var deletedChild = makeTask("已删除子任务", parentID: sourceWithChild.id)
        deletedChild.deletedAt = now
        let store = WorkspaceStore()
        store.commit([source, targetRoot, childTargetRoot, childTarget,
                      sourceWithChild, deletedChild], undoPolicy: .skip)
        let actions = TaskActions(store: store, clock: { self.now })

        XCTAssertEqual(actions.setParent(source.id, parentID: source.id),
                       .failure(.cannotParentToSelf))
        XCTAssertEqual(actions.setParent(source.id, parentID: childTarget.id),
                       .failure(.childCannotHaveChildren))
        XCTAssertEqual(actions.setParent(sourceWithChild.id, parentID: targetRoot.id),
                       .failure(.taskHasChildren), "已删除子任务仍阻止来源成为 child")
    }

    func testTaskParentPolicyRequiresEligibleSourceAndTargetAndChildlessSource() {
        let task = makeTask("来源")
        let parent = makeTask("目标")
        let eligibleTasks = [task, parent]
        XCTAssertTrue(TaskParentPolicy.canAssign(task: task, parent: parent, tasks: eligibleTasks))

        var deletedSource = task
        deletedSource.deletedAt = now
        XCTAssertFalse(TaskParentPolicy.canAssign(task: deletedSource, parent: parent,
                                                  tasks: [deletedSource, parent]))

        var convertedSource = task
        convertedSource.convertedNoteID = UUID()
        XCTAssertFalse(TaskParentPolicy.canAssign(task: convertedSource, parent: parent,
                                                  tasks: [convertedSource, parent]))

        var convertedTarget = parent
        convertedTarget.convertedNoteID = UUID()
        XCTAssertFalse(TaskParentPolicy.canAssign(task: task, parent: convertedTarget,
                                                  tasks: [task, convertedTarget]))

        var completedSource = task
        completedSource.status = .completed
        XCTAssertFalse(TaskParentPolicy.canAssign(task: completedSource, parent: parent,
                                                  tasks: [completedSource, parent]))

        var closedTarget = parent
        closedTarget.abandonedAt = now
        XCTAssertFalse(TaskParentPolicy.canAssign(task: task, parent: closedTarget,
                                                  tasks: [task, closedTarget]))

        var skippedSource = task
        skippedSource.skippedAt = now
        XCTAssertFalse(TaskParentPolicy.canAssign(task: skippedSource, parent: parent,
                                                  tasks: [skippedSource, parent]))

        var skippedTarget = parent
        skippedTarget.skippedAt = now
        XCTAssertFalse(TaskParentPolicy.canAssign(task: task, parent: skippedTarget,
                                                  tasks: [task, skippedTarget]))

        var deletedTarget = parent
        deletedTarget.deletedAt = now
        XCTAssertFalse(TaskParentPolicy.canAssign(task: task, parent: deletedTarget,
                                                  tasks: [task, deletedTarget]))

        let child = makeTask("已有的子任务", parentID: task.id)
        XCTAssertFalse(TaskParentPolicy.canAssign(task: task, parent: parent,
                                                  tasks: [task, parent, child]))
    }
}
