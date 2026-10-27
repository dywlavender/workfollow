import XCTest
@testable import WorkFollow

/// Option A acceptance: legacy `Note` rows become `Task(kind: .note)` once,
/// keep their identity and metadata, stay lazy at launch, and live in the
/// Notes projection while remaining absent from the task page.
@MainActor
final class NoteTaskMigrationTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTaskMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sourceTask() -> Task {
        Task(id: UUID(), title: "原任务", document: NativeDocument(plainText: "任务正文"), list: .inbox,
             priority: .none, schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func legacyNotes(linkedTaskID: UUID) -> [Note] {
        [
            Note(id: UUID(), title: "迁移笔记", document: NativeDocument(plainText: "完整迁移正文"),
                 folder: "工作", folderID: "folder-work", favorite: true,
                 linkedTaskIDs: [linkedTaskID], updatedAt: now,
                 originalContentJson: "{\"rich\":true}"),
            Note(id: UUID(), title: "回收站笔记", document: NativeDocument(plainText: "待删除"),
                 folder: "未归档", updatedAt: now.addingTimeInterval(-60),
                 deletedAt: now.addingTimeInterval(-30))
        ]
    }

    private func seed(_ notes: [Note], tasks: [Task]) throws {
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(
            tasks: tasks, notes: notes,
            noteFolders: ["工作"],
            noteFolderMetadata: [NoteFolderMeta(id: "folder-work", parentID: nil, name: "工作",
                                                sortOrder: 0, createdAt: nil, updatedAt: nil)]))
    }

    private func flush(_ environment: AppEnvironment) {
        let done = expectation(description: "saved")
        environment.flush { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func sqlite() throws -> SQLiteDatabase {
        try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
    }

    func testLegacyNotesBecomeSameIdentityTasksWithoutHydratingBodies() throws {
        let task = sourceTask()
        let notes = legacyNotes(linkedTaskID: task.id)
        try seed(notes, tasks: [task])

        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        XCTAssertEqual(environment.documentReadCount, 0)
        XCTAssertEqual(environment.originalContentReadCount, 0)

        let migrated = try XCTUnwrap(environment.taskWorkspace.task(for: notes[0].id))
        XCTAssertEqual(migrated.kind, .note)
        XCTAssertEqual(migrated.title, notes[0].title)
        XCTAssertEqual(migrated.list, .notes)
        XCTAssertFalse(migrated.document.isLoaded)
        XCTAssertEqual(migrated.note?.folder, "工作")
        XCTAssertEqual(migrated.note?.folderID, "folder-work")
        XCTAssertTrue(migrated.note?.isFavorite == true)
        XCTAssertEqual(migrated.note?.linkedTaskIDs, [task.id])
        XCTAssertTrue(migrated.note?.hasPreservedRichContent == true)
        XCTAssertEqual(environment.originalContentReadCount, 0)

        // Notes projection keeps the same ids and note-only fields.
        XCTAssertEqual(Set(environment.notesWorkspace.notes.map(\.id)), Set(notes.map(\.id)))
        let projected = try XCTUnwrap(environment.notesWorkspace.notes.first { $0.id == notes[0].id })
        XCTAssertEqual(projected.folder, "工作")
        XCTAssertTrue(projected.favorite)
        XCTAssertEqual(projected.linkedTaskIDs, [task.id])
        XCTAssertEqual(environment.notesWorkspace.rows(trash: true, query: "", folder: nil,
                                                       favorites: false).map(\.id), [notes[1].id])
        XCTAssertEqual(environment.notesWorkspace.folders, ["工作"])
        XCTAssertEqual(environment.originalContentReadCount, 0)

        // Task page and its trash exclude note rows.
        XCTAssertEqual(environment.taskWorkspace.tasksInActiveLists.map(\.id), [task.id])
        XCTAssertTrue(environment.taskWorkspace.deletedTasks.isEmpty)
        XCTAssertEqual(TaskListProjection.matches(in: .allTasks, tasks: environment.taskWorkspace.allTasks,
                                                  now: now, calendar: .current).map(\.id), [task.id])
        XCTAssertFalse(environment.taskWorkspace.listNames.contains(TaskList.notes.name))

        // Legacy rows stay for rollback; only the metadata flag changes.
        let db = try sqlite()
        XCTAssertEqual(try db.rows("SELECT id FROM notes").count, 2)
        XCTAssertEqual(try db.rows("SELECT title FROM notes WHERE id=?",
                                   [.text(notes[0].id.uuidString)]).first?[0],
                       Data("迁移笔记".utf8))
        let snapshot = try XCTUnwrap(NativePreviewRepository(directory: directory).loadDeferred())
        XCTAssertEqual(snapshot.notesMergedIntoTasks, true)
        XCTAssertEqual(snapshot.tasks.count, 3)
        XCTAssertEqual(snapshot.tasks.filter(\.isNoteTask).count, 2)

        // No body was materialized by migration or projection.
        XCTAssertEqual(NativePreviewRepository(directory: directory).documentReadCount, 0)
        XCTAssertEqual(NativePreviewRepository(directory: directory).originalContentReadCount, 0)
    }

    func testSecondLaunchDoesNotReimportNotesOrDuplicateRows() throws {
        let task = sourceTask()
        let notes = legacyNotes(linkedTaskID: task.id)
        try seed(notes, tasks: [task])

        _ = AppEnvironment(clock: { self.now }, directory: directory)
        let second = AppEnvironment(clock: { self.now }, directory: directory)

        XCTAssertEqual(second.documentReadCount, 0)
        XCTAssertEqual(second.originalContentReadCount, 0)
        XCTAssertEqual(Set(second.notesWorkspace.notes.map(\.id)), Set(notes.map(\.id)))
        XCTAssertEqual(second.taskWorkspace.noteTasks.count, 2)
        XCTAssertEqual(second.taskWorkspace.allTasks.count, 3)
        XCTAssertEqual(try sqlite().rows("SELECT id FROM tasks").count, 3)
        XCTAssertEqual(try sqlite().rows("SELECT id FROM notes").count, 2)
    }

    func testMigratedNoteEditsPersistOnTaskRowsAndUndoRestoresMetadata() throws {
        let task = sourceTask()
        let notes = legacyNotes(linkedTaskID: task.id)
        try seed(notes, tasks: [task])
        let environment = AppEnvironment(clock: { self.now }, directory: directory)

        environment.notesWorkspace.edit(notes[0].id) {
            $0.title = "改名后的笔记"
            $0.folder = "生活"
            $0.favorite = false
        }
        flush(environment)

        let restored = try XCTUnwrap(NativePreviewRepository(directory: directory)
            .loadDeferred()?.tasks.first { $0.id == notes[0].id })
        XCTAssertEqual(restored.kind, .note)
        XCTAssertEqual(restored.title, "改名后的笔记")
        XCTAssertEqual(restored.note?.folder, "生活")
        XCTAssertFalse(restored.note?.isFavorite == true)
        XCTAssertTrue(restored.note?.hasPreservedRichContent == true)
        // The retained legacy row is a rollback copy, not a second writer.
        XCTAssertEqual(try sqlite().rows("SELECT title FROM notes WHERE id=?",
                                         [.text(notes[0].id.uuidString)]).first?[0],
                       Data("迁移笔记".utf8))

        environment.taskWorkspace.undo()
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == notes[0].id }?.title, "迁移笔记")
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == notes[0].id }?.folder, "工作")

        environment.taskWorkspace.redo()
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == notes[0].id }?.title, "改名后的笔记")
    }

    func testInPlaceConversionMovesSameTaskBetweenPagesAndUndoes() throws {
        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "转成笔记", in: .inbox).taskID)

        XCTAssertEqual(environment.convertTaskToNote(id), id)
        XCTAssertEqual(workspace.task(for: id)?.kind, .note)
        XCTAssertEqual(environment.notesWorkspace.notes.map(\.id), [id])
        XCTAssertTrue(workspace.tasksInActiveLists.isEmpty)
        XCTAssertTrue(workspace.deletedTasks.isEmpty)
        XCTAssertNil(workspace.task(for: id)?.convertedNoteID)

        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.kind, .text)
        XCTAssertTrue(environment.notesWorkspace.notes.isEmpty)
        XCTAssertEqual(workspace.tasksInActiveLists.map(\.id), [id])

        workspace.redo()
        XCTAssertEqual(environment.notesWorkspace.notes.map(\.id), [id])

        workspace.setKind(id, .text)
        XCTAssertTrue(environment.notesWorkspace.notes.isEmpty)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox)
        XCTAssertEqual(workspace.tasksInActiveLists.map(\.id), [id])
    }

    func testNotesPageConvertToTaskClearsSelectionAndReturnsToTaskPage() throws {
        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        let notes = environment.notesWorkspace
        let id = notes.create()
        notes.selectedID = id

        XCTAssertEqual(notes.convertToTask(id).taskID, id)
        XCTAssertNil(notes.selectedID)
        XCTAssertTrue(notes.notes.isEmpty)
        XCTAssertEqual(environment.taskWorkspace.task(for: id)?.kind, .text)
        XCTAssertEqual(environment.taskWorkspace.task(for: id)?.list, .inbox)
        XCTAssertEqual(environment.taskWorkspace.tasksInActiveLists.map(\.id), [id])

        environment.taskWorkspace.undo()
        XCTAssertEqual(notes.notes.map(\.id), [id])
        XCTAssertTrue(environment.taskWorkspace.tasksInActiveLists.isEmpty)
    }
}
