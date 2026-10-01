import XCTest
@testable import WorkFollow

final class TaskDuplicateActionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeTask(_ title: String, parentID: UUID? = nil,
                          childOrder: Int = 0) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(), parentID: parentID, childOrder: childOrder,
             createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-300))
    }

    private func expectedDuplicate(of source: Task, id: UUID, parentID: UUID?,
                                   childOrder: Int) -> Task {
        Task(id: id, title: source.title, document: source.document, tags: source.tags,
             recurrence: source.recurrence, recurrenceRule: source.recurrenceRule,
             reminderAt: source.reminderAt, reminderOffsets: source.reminderOffsets,
             attachments: source.attachments, list: source.list, priority: source.priority,
             schedule: source.schedule, status: .active, parentID: parentID,
             childOrder: childOrder, createdAt: now, updatedAt: now,
             completedAt: nil, deletedAt: nil, isPinned: false, abandonedAt: nil,
             skippedAt: nil, convertedNoteID: nil, sourceNoteID: source.sourceNoteID)
    }

    func testRootDuplicatePreservesValuesCopiesOnlyLiveChildrenAndUndoesOnce() throws {
        var root = makeTask("根任务")
        root.document = NativeDocument(plainText: "保留的正文")
        root.tags = ["项目", "重要"]
        root.recurrence = .monthly
        root.recurrenceRule = RecurrenceRule(interval: 2, endDate: now.addingTimeInterval(86_400),
                                             remainingCount: 4, monthDay: 12, weekday: 3, month: 5)
        root.reminderAt = now.addingTimeInterval(3_600)
        root.reminderOffsets = [-30, 0, 15]
        root.attachments = [NativeAttachment(id: UUID(), name: "资料.pdf", storedName: "资料.pdf")]
        root.list = TaskList(name: "学习")
        root.priority = .high
        root.schedule = TaskSchedule(dueAt: now, hasTime: true,
                                     dueEndAt: now.addingTimeInterval(7_200),
                                     deadlineAt: now.addingTimeInterval(86_400))
        root.isPinned = true
        root.sourceNoteID = UUID()

        var liveChild = makeTask("现存子任务", parentID: root.id, childOrder: 2)
        liveChild.document = NativeDocument(plainText: "子任务正文")
        liveChild.tags = ["子标签"]
        liveChild.recurrence = .weekly
        liveChild.recurrenceRule = RecurrenceRule(interval: 3, remainingCount: 5, weekday: 4)
        liveChild.reminderAt = now.addingTimeInterval(7_200)
        liveChild.reminderOffsets = [-10, 0]
        liveChild.attachments = [NativeAttachment(id: UUID(), name: "子资料.txt", storedName: "child.txt")]
        liveChild.priority = .medium
        liveChild.schedule = TaskSchedule(dueAt: now.addingTimeInterval(86_400), hasTime: true,
                                          dueEndAt: now.addingTimeInterval(172_800),
                                          deadlineAt: now.addingTimeInterval(259_200))
        liveChild.isPinned = true
        liveChild.sourceNoteID = UUID()

        var completedChild = makeTask("已完成但仍保留的子任务", parentID: root.id, childOrder: 6)
        completedChild.status = .completed
        completedChild.completedAt = now.addingTimeInterval(-60)
        var convertedChild = makeTask("已转为笔记的子任务", parentID: root.id, childOrder: 10)
        convertedChild.convertedNoteID = UUID()
        convertedChild.sourceNoteID = UUID()
        var deletedChild = makeTask("已删除子任务", parentID: root.id, childOrder: 8)
        deletedChild.deletedAt = now.addingTimeInterval(-120)
        var skippedChild = makeTask("已跳过子任务", parentID: root.id, childOrder: 12)
        skippedChild.skippedAt = now.addingTimeInterval(-180)

        let before = [root, liveChild, completedChild, convertedChild, deletedChild, skippedChild]
        let store = WorkspaceStore()
        store.commit(before, undoPolicy: .skip)
        store.clearUndo()
        let actions = TaskActions(store: store, clock: { self.now })

        let duplicateID = try XCTUnwrap(actions.duplicate(root.id).taskID)
        let duplicate = try XCTUnwrap(store.task(duplicateID))
        XCTAssertNotEqual(duplicate.id, root.id)
        XCTAssertEqual(duplicate, expectedDuplicate(of: root, id: duplicateID,
                                                    parentID: nil, childOrder: root.childOrder))

        let copiedChildren = store.children(of: duplicateID)
        XCTAssertEqual(copiedChildren.map(\.title), [liveChild.title, completedChild.title])
        XCTAssertEqual(copiedChildren.map(\.childOrder), [liveChild.childOrder, completedChild.childOrder])
        XCTAssertEqual(copiedChildren[0], expectedDuplicate(of: liveChild, id: copiedChildren[0].id,
                                                            parentID: duplicateID,
                                                            childOrder: liveChild.childOrder))
        XCTAssertEqual(copiedChildren[1], expectedDuplicate(of: completedChild, id: copiedChildren[1].id,
                                                            parentID: duplicateID,
                                                            childOrder: completedChild.childOrder))
        XCTAssertTrue(([duplicate] + copiedChildren).allSatisfy { $0.createdAt == now && $0.updatedAt == now })
        XCTAssertEqual(Set(([duplicate] + copiedChildren).map(\.id)).count, 3)
        XCTAssertTrue(Set(([duplicate] + copiedChildren).map(\.id))
            .isDisjoint(with: Set(before.map(\.id))))
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertFalse(copiedChildren[1].isClosed)
        XCTAssertNil(copiedChildren[1].completedAt)

        XCTAssertTrue(store.canUndo)
        actions.undo()
        XCTAssertEqual(store.tasks, before)
        XCTAssertFalse(store.canUndo, "整组复制由一步撤销恢复")
    }

    func testChildDuplicateAppendsAfterActiveDeletedAndSkippedSiblings() throws {
        let parent = makeTask("父任务")
        var source = makeTask("要复制的子任务", parentID: parent.id, childOrder: 2)
        source.reminderOffsets = []
        source.isPinned = true
        let activeSibling = makeTask("现存同级", parentID: parent.id, childOrder: 15)
        var deletedSibling = makeTask("已删除同级", parentID: parent.id, childOrder: 17)
        deletedSibling.deletedAt = now
        var skippedSibling = makeTask("已跳过同级", parentID: parent.id, childOrder: 23)
        skippedSibling.skippedAt = now

        let store = WorkspaceStore()
        store.commit([parent, source, activeSibling, deletedSibling, skippedSibling], undoPolicy: .skip)
        let actions = TaskActions(store: store, clock: { self.now })

        let duplicateID = try XCTUnwrap(actions.duplicate(source.id).taskID)
        let duplicate = try XCTUnwrap(store.task(duplicateID))
        XCTAssertEqual(duplicate.parentID, parent.id)
        XCTAssertEqual(duplicate.childOrder, 24, "已删除与已跳过的同级仍占据既有顺序号")
        XCTAssertEqual(duplicate.reminderOffsets, [])
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertEqual(duplicate, expectedDuplicate(of: source, id: duplicateID,
                                                    parentID: parent.id, childOrder: 24))
    }

    func testDuplicateOfClosedSourceBecomesActiveAndClearsLifecycleState() throws {
        var completed = makeTask("已完成")
        completed.status = .completed
        completed.completedAt = now.addingTimeInterval(-60)
        var abandoned = makeTask("已放弃")
        abandoned.abandonedAt = now.addingTimeInterval(-120)
        var skipped = makeTask("已跳过")
        skipped.skippedAt = now.addingTimeInterval(-180)

        let store = WorkspaceStore()
        store.commit([completed, abandoned, skipped], undoPolicy: .skip)
        let actions = TaskActions(store: store, clock: { self.now })

        for source in [completed, abandoned, skipped] {
            let duplicateID = try XCTUnwrap(actions.duplicate(source.id).taskID)
            let duplicate = try XCTUnwrap(store.task(duplicateID))
            XCTAssertEqual(duplicate, expectedDuplicate(of: source, id: duplicateID,
                                                        parentID: nil, childOrder: source.childOrder))
            XCTAssertEqual(duplicate.status, .active)
            XCTAssertNil(duplicate.completedAt)
            XCTAssertNil(duplicate.deletedAt)
            XCTAssertNil(duplicate.abandonedAt)
            XCTAssertNil(duplicate.skippedAt)
            XCTAssertNil(duplicate.convertedNoteID)
        }
    }

    func testDuplicateRejectsConvertedSourceAndChildOfDeletedOrConvertedParent() {
        var convertedSource = makeTask("已转为笔记")
        convertedSource.convertedNoteID = UUID()
        var deletedParent = makeTask("已删除父任务")
        deletedParent.deletedAt = now
        let childOfDeletedParent = makeTask("父任务已删除的子任务", parentID: deletedParent.id)
        var convertedParent = makeTask("已转为笔记的父任务")
        convertedParent.convertedNoteID = UUID()
        let childOfConvertedParent = makeTask("父任务已转为笔记的子任务", parentID: convertedParent.id)
        let before = [convertedSource, deletedParent, childOfDeletedParent,
                      convertedParent, childOfConvertedParent]
        let store = WorkspaceStore()
        store.commit(before, undoPolicy: .skip)
        store.clearUndo()
        let actions = TaskActions(store: store, clock: { self.now })

        XCTAssertEqual(actions.duplicate(convertedSource.id), .failure(.alreadyConverted))
        XCTAssertEqual(actions.duplicate(childOfDeletedParent.id), .failure(.deletedTask))
        XCTAssertEqual(actions.duplicate(childOfConvertedParent.id), .failure(.alreadyConverted))
        XCTAssertEqual(store.tasks, before)
        XCTAssertFalse(store.canUndo)
    }
}
