import XCTest
@testable import WorkFollow

final class TaskRelationProjectionTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 0)

    private func makeTask(_ title: String, id: UUID = UUID(), list: String = "收集箱",
                          parentID: UUID? = nil) -> Task {
        Task(id: id, title: title, list: TaskList(name: list), priority: .none,
             schedule: TaskSchedule(), parentID: parentID, childOrder: 0,
             createdAt: timestamp, updatedAt: timestamp)
    }

    private func makeNote(_ title: String, id: UUID = UUID(), folder: String = "",
                          deletedAt: Date? = nil) -> Note {
        Note(id: id, title: title, document: .empty, folder: folder,
             updatedAt: timestamp, deletedAt: deletedAt)
    }

    func testTargetsKeepTaskAndNoteInputOrderAndSearchTitleListAndFolder() {
        let source = makeTask("来源")
        let firstTask = makeTask("Draft", list: "Work")
        let secondTask = makeTask("Quarterly Review", list: "Home")
        let firstNote = makeNote("Clip", folder: "Research")
        let secondNote = makeNote("Meeting", folder: "Archive")
        var bodyOnlyNote = makeNote("Document", folder: "Archive")
        bodyOnlyNote.document = NativeDocument(plainText: "bodyneedle")

        let all = TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, firstTask, secondTask], notes: [firstNote, secondNote, bodyOnlyNote], query: " \n ")

        XCTAssertEqual(all, [.task(firstTask), .task(secondTask), .note(firstNote), .note(secondNote), .note(bodyOnlyNote)])
        XCTAssertEqual(TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, firstTask, secondTask], notes: [firstNote, secondNote], query: "  rEvIeW \n"),
            [.task(secondTask)])
        XCTAssertEqual(TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, firstTask, secondTask], notes: [firstNote, secondNote], query: " wOrK "),
            [.task(firstTask)])
        XCTAssertEqual(TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, firstTask, secondTask], notes: [firstNote, secondNote], query: " RESEARCH "),
            [.note(firstNote)])
        XCTAssertTrue(TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, firstTask, secondTask], notes: [firstNote, secondNote, bodyOnlyNote], query: "bodyneedle").isEmpty)
    }

    func testEmptyTitlesUseDisplayFallbacksAndReferences() {
        let task = makeTask("")
        let note = makeNote("")
        let taskTarget = TaskRelationTarget.task(task)
        let noteTarget = TaskRelationTarget.note(note)

        XCTAssertEqual(taskTarget.title, "无标题任务")
        XCTAssertEqual(taskTarget.subtitle, "任务 · 收集箱")
        XCTAssertEqual(taskTarget.reference.title, "任务：无标题任务")
        XCTAssertEqual(noteTarget.title, "未命名笔记")
        XCTAssertEqual(noteTarget.subtitle, "笔记 · ")
        XCTAssertEqual(noteTarget.reference.title, TaskDocumentProfile.reference(to: note).title)
        XCTAssertEqual(noteTarget.reference.target, TaskDocumentProfile.reference(to: note).target)

        XCTAssertEqual(TaskRelationProjection.targets(sourceTaskID: UUID(), tasks: [task], notes: [],
                                                       query: "无标题任务"), [.task(task)])
        XCTAssertEqual(TaskRelationProjection.targets(sourceTaskID: UUID(), tasks: [], notes: [note],
                                                       query: "未命名笔记"), [.note(note)])
    }

    func testIDsAndReferencesKeepTaskAndNoteNamespacesDistinct() {
        let sharedID = UUID()
        let taskTarget = TaskRelationTarget.task(makeTask("同步", id: sharedID))
        let note = makeNote("同步", id: sharedID)
        let noteTarget = TaskRelationTarget.note(note)

        XCTAssertEqual(taskTarget.id, "task:\(sharedID.uuidString)")
        XCTAssertEqual(noteTarget.id, "note:\(sharedID.uuidString)")
        XCTAssertNotEqual(taskTarget.id, noteTarget.id)
        XCTAssertEqual(taskTarget.reference.title, "任务：同步")
        XCTAssertEqual(taskTarget.reference.target, NativeResourceLink.task(sharedID).url.absoluteString)
        XCTAssertEqual(noteTarget.reference.title, TaskDocumentProfile.reference(to: note).title)
        XCTAssertEqual(noteTarget.reference.target, TaskDocumentProfile.reference(to: note).target)
        XCTAssertEqual(noteTarget.reference.target, NativeResourceLink.note(sharedID).url.absoluteString)
        XCTAssertEqual(taskTarget.symbol, "checkmark.circle")
        XCTAssertEqual(noteTarget.symbol, "doc.text")
    }

    func testExcludesSelfUnavailableTasksAndChildrenWithUnavailableParentsButKeepsClosedTasks() {
        let source = makeTask("来源")
        var deleted = makeTask("已删除")
        deleted.deletedAt = timestamp
        var skipped = makeTask("已跳过")
        skipped.skippedAt = timestamp
        var converted = makeTask("已转换")
        converted.convertedNoteID = UUID()

        var deletedParent = makeTask("删除的父任务")
        deletedParent.deletedAt = timestamp
        let childOfDeleted = makeTask("父任务已删除", parentID: deletedParent.id)
        var skippedParent = makeTask("跳过的父任务")
        skippedParent.skippedAt = timestamp
        let childOfSkipped = makeTask("父任务已跳过", parentID: skippedParent.id)
        var convertedParent = makeTask("转换的父任务")
        convertedParent.convertedNoteID = UUID()
        let childOfConverted = makeTask("父任务已转换", parentID: convertedParent.id)
        let childWithMissingParent = makeTask("父任务不存在", parentID: UUID())

        let validParent = makeTask("有效父任务")
        let validChild = makeTask("有效子任务", parentID: validParent.id)
        var completed = makeTask("已完成")
        completed.status = .completed
        let deletedNote = makeNote("已删除笔记", deletedAt: timestamp)
        let liveNote = makeNote("有效笔记")

        let targets = TaskRelationProjection.targets(sourceTaskID: source.id,
            tasks: [source, deleted, skipped, converted, deletedParent, childOfDeleted,
                    skippedParent, childOfSkipped, convertedParent, childOfConverted,
                    childWithMissingParent, validParent, validChild, completed],
            notes: [deletedNote, liveNote], query: "")

        XCTAssertEqual(targets, [.task(validParent), .task(validChild), .task(completed), .note(liveNote)])
    }
}
