import XCTest
@testable import WorkFollow

final class TaskManagementFlowTests: XCTestCase {
    func testListRenameDeleteAndUndoKeepTasksAndChildren() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store)
        actions.renameList(nil, to: "Empty")
        XCTAssertEqual(store.lists, ["Empty"])
        let parent = actions.create(title: "parent", list: TaskList(name: "Empty")).taskID!
        let child = actions.createChild(parent).taskID!
        actions.renameList("Empty", to: "Renamed")
        XCTAssertEqual(store.task(child)?.list.name, "Renamed")
        actions.removeList("Renamed")
        XCTAssertEqual(store.task(parent)?.list, .inbox)
        XCTAssertEqual(store.task(child)?.list, .inbox)
        XCTAssertNil(store.task(parent)?.deletedAt)
        actions.undo()
        XCTAssertEqual(store.task(parent)?.list.name, "Renamed")
        XCTAssertEqual(store.lists, ["Renamed"])
    }

    func testBulkCompletionSpawnsOnceAndUndoesInOneStep() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store)
        let parent = actions.create(title: "parent").taskID!
        let child = actions.createChild(parent).taskID!
        actions.setRepeat(parent, .daily); actions.setRepeat(child, .weekly)
        let before = store.tasks
        actions.batch([parent, child], operation: .complete)
        XCTAssertEqual(store.tasks.count, 4)
        actions.undo()
        XCTAssertEqual(store.tasks, before)
    }

    func testSkipIsHiddenWithoutCompletingAndUndoRestoresOriginal() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store)
        let id = actions.create(title: "repeat").taskID!
        actions.setRepeat(id, .daily)
        let before = store.tasks
        XCTAssertNotNil(actions.skip(id).taskID)
        XCTAssertNotNil(store.task(id)?.skippedAt)
        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertEqual(TaskListProjection.rows(in: .allTasks, store: store, now: Date(), calendar: .current).count, 1)
        actions.undo()
        XCTAssertEqual(store.tasks, before)
    }

    func testDraftAndTimingEachUndoAsOneOperation() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store)
        let result = actions.createDraft(title: "new", list: "Work", schedule: TaskSchedule(), priority: .high,
                                         tags: ["tag"], reminder: nil, frequency: .daily)
        XCTAssertNotNil(result.taskID)
        XCTAssertEqual(store.tasks[0].tags, ["tag"])
        actions.undo(); XCTAssertTrue(store.tasks.isEmpty)
        let id = actions.create(title: "date").taskID!
        actions.saveTiming(id, schedule: TaskSchedule(dueAt: Date()), reminder: Date(), frequency: .weekly)
        actions.undo()
        XCTAssertNil(store.task(id)?.schedule.dueAt)
        XCTAssertNil(store.task(id)?.reminderAt)
        XCTAssertEqual(store.task(id)?.recurrence, TaskRepeat.never)
    }

    func testTaskConversionMovesParentAndChildrenToNoteAndUndoesAcrossBothStores() async {
        await MainActor.run {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let workspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false)
            let notes = NotesWorkspaceModel(clock: { now })
            let parent = workspace.createTask(title: "Parent", in: .inbox).taskID!
            let child = workspace.createChild(parent, title: "Action item").taskID!
            _ = workspace.setDocument(parent, NativeDocument(plainText: "Description"))
            let source = workspace.task(for: parent)!
            let noteID = notes.createFromTask(source, children: [workspace.task(for: child)!], clock: { now })

            XCTAssertEqual(workspace.convertToNote(parent, noteID: noteID) {
                notes.discardCreatedNoteForUndo(noteID)
            }, .success(parent))
            XCTAssertEqual(workspace.task(for: parent)?.convertedNoteID, noteID)
            XCTAssertNotNil(workspace.task(for: child)?.deletedAt)
            XCTAssertEqual(notes.notes.first?.document.blocks.map(\.kind), [.paragraph, .checklist(false)])
            XCTAssertEqual(notes.notes.first?.document.plainText, "Description\nAction item")
            XCTAssertTrue(workspace.visibleNodes(for: .inbox).isEmpty)

            workspace.undo()

            XCTAssertNil(workspace.task(for: parent)?.convertedNoteID)
            XCTAssertNil(workspace.task(for: child)?.deletedAt)
            XCTAssertTrue(notes.notes.isEmpty)
            XCTAssertEqual(workspace.visibleNodes(for: .inbox).map(\.task.id), [parent, child])
        }
    }

    func testQuickAddDraftPersistsParsedPropertiesAndUndoIsOneStep() async {
        await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))!
            let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
            XCTAssertTrue(workspace.saveList("个人"))
            let parsed = QuickAddParser.parse("每天 明早9点 #工作 @个人 !!!准备评审", now: now,
                                             calendar: calendar, availableLists: workspace.allListNames)

            let result = workspace.createDraft(title: parsed.title, list: parsed.listName ?? "收集箱",
                                                schedule: TaskSchedule(dueAt: parsed.dueAt, hasTime: parsed.hasTime),
                                                priority: parsed.priority, tags: parsed.tags,
                                                reminder: parsed.reminderAt, repeatFrequency: parsed.recurrence,
                                                recurrenceRule: parsed.recurrenceRule)
            let task = workspace.task(for: result.taskID!)!
            XCTAssertEqual(task.title, "准备评审")
            XCTAssertEqual(task.list.name, "个人")
            XCTAssertEqual(task.tags, ["工作"])
            XCTAssertEqual(task.priority, .high)
            XCTAssertEqual(task.recurrence, .daily)
            XCTAssertEqual(task.schedule.dueAt, parsed.dueAt)
            XCTAssertEqual(task.reminderAt, parsed.dueAt)

            workspace.undo()
            XCTAssertTrue(workspace.allTasks.isEmpty)
        }
    }
}
