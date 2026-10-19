import Foundation
import XCTest
@testable import WorkFollow

@MainActor
final class SQLitePersistenceTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SQLitePersistenceTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func task(_ title: String) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none, schedule: TaskSchedule(),
             parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
    }
    private func flush(_ coordinator: PersistenceCoordinator) {
        let done = expectation(description: "database committed")
        coordinator.flush { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testLegacyMigrationPreservesDocumentsRelationshipsMetadataAndOriginalFile() throws {
        var parent = task("父任务")
        parent.document = NativeDocument(plainText: "第一行\n第二行")
        var child = task("子任务"); child.parentID = parent.id
        let note = Note(id: UUID(), title: "笔记", document: NativeDocument(plainText: "正文"),
                        folder: "工作", linkedTaskIDs: [parent.id], updatedAt: now,
                        originalContentJson: "{\"rich\":true}")
        let unusedTag = TaskTag(id: UUID(), name: "未使用的标签", colorARGB: 0xFF123456,
                                sortOrder: 3, parentID: nil)
        let original = NativeWorkspaceSnapshot(tasks: [parent, child], notes: [note], taskLists: ["工作"],
                                               taskTags: [unusedTag], noteFolders: ["工作"])
        let bytes = try JSONEncoder().encode(original)
        let legacy = directory.appendingPathComponent("workspace.json")
        try bytes.write(to: legacy)
        let repository = NativePreviewRepository(directory: directory)
        let restored = try XCTUnwrap(try repository.load())
        XCTAssertEqual(restored.tasks, original.tasks)
        XCTAssertEqual(restored.notes, original.notes)
        XCTAssertEqual(restored.taskLists, original.taskLists)
        XCTAssertEqual(restored.taskTags, original.taskTags)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)

        var changed = parent; changed.title = "数据库中的新标题"
        var batch = SQLiteWorkspaceRepository.Batch()
        let changes = TaskChangeSet(updatedFrom: parent, to: changed)
        batch.tasks[parent.id] = try XCTUnwrap(changes.entries.first)
        try repository.apply(batch)
        XCTAssertEqual(try repository.load()?.tasks.first?.title, changed.title)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes, "Migration JSON is never a second writer")
    }

    func testUnsupportedLegacyVersionDoesNotCreateAnInitializedDatabase() throws {
        var snapshot = NativeWorkspaceSnapshot(tasks: [task("保留")], notes: [])
        snapshot.version = 9
        let bytes = try JSONEncoder().encode(snapshot)
        let file = directory.appendingPathComponent("workspace.json")
        try bytes.write(to: file)
        XCTAssertThrowsError(try NativePreviewRepository(directory: directory).load())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.sqlite").path))
    }

    func testPreviewSnapshotWithoutTagCatalogStillDecodes() throws {
        let data = Data(#"{"version":1,"tasks":[],"notes":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: data)
        XCTAssertNil(snapshot.taskTags)
    }

    func testTagCatalogPersistsThroughDeferredLoadMetadataChangesAndBackupRestore() throws {
        let root = TaskTag(id: UUID(), name: "项目", colorARGB: 0xFF123456,
                           sortOrder: 4, parentID: nil)
        let unused = TaskTag(id: UUID(), name: "尚未使用", colorARGB: nil,
                             sortOrder: 8, parentID: root.id)
        var tagged = task("带标签的任务")
        tagged.tags = [root.name]
        tagged.tagReferences = [TaskTagReference(id: root.id, name: root.name)]
        tagged.document = NativeDocument(plainText: "目录变化不改正文")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [tagged], notes: [], taskTags: [root, unused]))
        XCTAssertEqual(try repository.loadDeferred()?.taskTags, [root, unused])

        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("CREATE TABLE tag_body_audit(id TEXT)")
        try db.execute("CREATE TRIGGER tag_body_audit AFTER UPDATE ON task_documents BEGIN INSERT INTO tag_body_audit VALUES (new.id); END")
        var renamed = unused
        renamed.name = "保留的空标签"
        renamed.colorARGB = 0xFF445566
        renamed.sortOrder = 2
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.metadata = NativeWorkspaceSnapshot(tasks: [], notes: [], taskTags: [root, renamed])
        try repository.apply(batch)
        XCTAssertEqual(try repository.load()?.taskTags, [root, renamed])
        XCTAssertEqual(try repository.load()?.tasks, [tagged])
        XCTAssertEqual(try db.rows("SELECT id FROM tag_body_audit").count, 0)

        let backup = try XCTUnwrap(repository.backupNow(now: now))
        XCTAssertEqual(try SQLiteWorkspaceRepository(directory: directory).readBackup(at: backup).taskTags,
                       [root, renamed])
        batch.metadata = NativeWorkspaceSnapshot(tasks: [], notes: [], taskTags: [])
        try repository.apply(batch)
        try repository.restoreBackup(at: backup, now: now.addingTimeInterval(60))
        XCTAssertEqual(try repository.load()?.taskTags, [root, renamed])
        XCTAssertEqual(try repository.load()?.tasks, [tagged])
    }

    func testApplicationPersistsHydratedLegacyTagReferencesBeforeAnyTaskEdit() throws {
        let existingTagID = UUID()
        var legacyTask = task("旧快照中的任务")
        legacyTask.tags = ["已有身份", "仅有名称"]
        legacyTask.tagReferences = [TaskTagReference(id: existingTagID, name: "已有身份")]
        legacyTask.document = NativeDocument(plainText: "启动补目录时保持正文延迟读取")
        let legacy = NativeWorkspaceSnapshot(tasks: [legacyTask], notes: [])
        try JSONEncoder().encode(legacy).write(to: directory.appendingPathComponent("workspace.json"))

        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        let hydrated = try XCTUnwrap(environment.taskWorkspace.task(for: legacyTask.id))
        let newTag = try XCTUnwrap(environment.taskWorkspace.taskTags.first { $0.name == "仅有名称" })
        let references = [TaskTagReference(id: existingTagID, name: "已有身份"),
                          TaskTagReference(id: newTag.id, name: newTag.name)]
        XCTAssertEqual(hydrated.tagReferences, references)
        XCTAssertEqual(environment.documentReadCount, 0)
        let saved = expectation(description: "hydrated tag directory committed")
        environment.flush { error in XCTAssertNil(error); saved.fulfill() }
        wait(for: [saved], timeout: 5)

        let repository = NativePreviewRepository(directory: directory)
        let snapshot = try XCTUnwrap(try repository.load())
        XCTAssertEqual(snapshot.tasks.first?.tagReferences, references)
        XCTAssertEqual(snapshot.taskTags?.first { $0.name == "已有身份" }?.id, existingTagID)
        XCTAssertEqual(snapshot.taskTags?.first { $0.name == newTag.name }?.id, newTag.id)
        XCTAssertEqual(snapshot.tasks.first?.document, legacyTask.document)
        XCTAssertEqual(environment.documentReadCount, 0)
        let restarted = TaskWorkspaceModel(clock: { self.now }, initialTasks: snapshot.tasks,
                                          initialTags: snapshot.taskTags)
        XCTAssertEqual(restarted.task(for: legacyTask.id)?.tagReferences, references)
    }

    func testRepeatedTitleChangesWriteOneTaskAndDoNotRewriteItsDocument() throws {
        var tasks = (0..<1_000).map { task("任务\($0)") }
        tasks[0].document = NativeDocument(plainText: String(repeating: "长正文", count: 1_000))
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: tasks, notes: []))
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("CREATE TABLE audit(kind TEXT)")
        try db.execute("CREATE TRIGGER task_audit AFTER UPDATE ON tasks BEGIN INSERT INTO audit VALUES ('task'); END")
        try db.execute("CREATE TRIGGER document_audit AFTER UPDATE ON task_documents BEGIN INSERT INTO audit VALUES ('document'); END")
        let coordinator = PersistenceCoordinator(repository: repository, delay: 60)
        var current = tasks[0]
        for index in 0..<20 {
            var next = current; next.title = "标题\(index)"
            coordinator.schedule(changes: TaskChangeSet(updatedFrom: current, to: next))
            current = next
        }
        flush(coordinator)
        XCTAssertEqual(try db.rows("SELECT kind FROM audit WHERE kind='task'").count, 1)
        XCTAssertEqual(try db.rows("SELECT kind FROM audit WHERE kind='document'").count, 0)
        XCTAssertEqual(try repository.load()?.tasks[0], current)
        XCTAssertEqual(try repository.load()?.tasks.count, 1_000)
    }

    func testCoalescedInsertDocumentEditDeleteAndUndoOrderSurviveReload() throws {
        let repository = NativePreviewRepository(directory: directory)
        let a = task("A"), b = task("B")
        try repository.save(NativeWorkspaceSnapshot(tasks: [a], notes: []))
        let coordinator = PersistenceCoordinator(repository: repository, delay: 60)
        coordinator.schedule(changes: TaskChangeSet(before: [a], after: [a, b]))
        var edited = b; edited.document = NativeDocument(plainText: "最后正文")
        coordinator.schedule(changes: TaskChangeSet(updatedFrom: b, to: edited))
        coordinator.schedule(changes: TaskChangeSet(before: [a, edited], after: [edited]))
        coordinator.schedule(changes: TaskChangeSet(before: [edited], after: [a, edited]))
        flush(coordinator)
        XCTAssertEqual(try repository.load()?.tasks, [a, edited])
    }

    func testFailedBatchRollsBackTaskAndNoteTogether() throws {
        let repository = NativePreviewRepository(directory: directory)
        let before = task("原标题")
        try repository.save(NativeWorkspaceSnapshot(tasks: [before], notes: []))
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("CREATE TRIGGER reject_note BEFORE INSERT ON notes BEGIN SELECT RAISE(ABORT,'test transaction failure'); END")
        var next = before; next.title = "未提交标题"
        let note = Note(id: UUID(), title: "笔记", document: .empty, folder: "未归档", updatedAt: now)
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[before.id] = TaskChangeSet(updatedFrom: before, to: next).entries.first
        batch.noteUpserts[note.id] = note
        XCTAssertThrowsError(try repository.apply(batch))
        XCTAssertEqual(try repository.load()?.tasks, [before])
        XCTAssertEqual(try repository.load()?.notes, [])
    }

    func testSummaryReadOmitsBodyAndExplicitBodyReadReturnsFullDocument() throws {
        var original = task("摘要")
        original.document = NativeDocument(plainText: "完整正文")
        let repository = SQLiteWorkspaceRepository(directory: directory)
        try repository.replace(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        let summary = try XCTUnwrap(repository.taskSummaries(limit: 1).first)
        XCTAssertEqual(summary.title, original.title)
        XCTAssertEqual(summary.id, original.id)
        XCTAssertEqual(try repository.taskDocument(id: original.id), original.document)
    }

    func testHistoryAppendEncodesOneRecordAndDateQueryIsBounded() throws {
        let taskID = UUID()
        let records = (0..<10_000).map { index in
            TaskActivityEvent(taskID: taskID, occurredAt: now.addingTimeInterval(Double(index)), kind: .created)
        }
        let store = SQLiteRecordStore<TaskActivityEvent, EmptyHistoryMetadata>(filename: "history", directory: directory,
            timestamp: { $0.occurredAt }, taskID: { $0.taskID }, migrate: { _ in .init(records: [], metadata: nil) })
        func flushHistory() {
            let done = expectation(description: "history committed")
            store.flush { error in XCTAssertNil(error); done.fulfill() }
            wait(for: [done], timeout: 10)
        }
        store.schedule(records: records, metadata: nil)
        flushHistory()
        let count = store.encodedRecordCount
        let newest = TaskActivityEvent(taskID: taskID, occurredAt: now.addingTimeInterval(10_000), kind: .focusStarted)
        store.schedule(records: records + [newest], metadata: nil)
        flushHistory()
        XCTAssertEqual(store.encodedRecordCount - count, 1)
        let page = try store.history(taskID: taskID, from: now.addingTimeInterval(9_990), limit: 3)
        XCTAssertEqual(page.count, 3)
        XCTAssertEqual(page.first, newest)
        XCTAssertEqual(try store.history(taskID: UUID(), limit: 3), [])
    }

    func testApplicationNoteEditsPersistAndReplacementCannotBeOverwrittenOnExit() throws {
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.notesWorkspace.create()
        let id = try XCTUnwrap(environment.notesWorkspace.selectedID)
        environment.notesWorkspace.edit(id) { $0.document = NativeDocument(plainText: "笔记最终正文") }
        let prepared = expectation(description: "ready for restore")
        environment.prepareStorageReplacement { error in XCTAssertNil(error); prepared.fulfill() }
        wait(for: [prepared], timeout: 5)
        XCTAssertEqual(try repository.load()?.notes.first?.document.plainText, "笔记最终正文")
        let replacement = task("恢复后的任务")
        try repository.save(NativeWorkspaceSnapshot(tasks: [replacement], notes: []))
        environment.finishStorageReplacement(succeeded: true)
        _ = environment.taskWorkspace.createTask(title: "旧内存中的任务", in: .inbox)
        let done = expectation(description: "termination flush")
        environment.flush { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try repository.load()?.tasks, [replacement])
        XCTAssertEqual(try repository.load()?.notes, [])
    }

    func testLegacyHistoryAndFocusSessionMigrateAndExportLatestDatabaseValues() throws {
        let modules = directory.appendingPathComponent("modules")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        let id = UUID()
        let event = TaskActivityEvent(taskID: id, occurredAt: now, kind: .created)
        let activityJSON = try JSONEncoder().encode([event])
        try activityJSON.write(to: modules.appendingPathComponent("task-activity.json"))
        let record = PomodoroRecord(id: UUID(), taskID: id, startedAt: now, minutes: 25, completed: true)
        var archive = FocusStore.Archive(records: [record])
        archive.preferences.dailyGoal = 12
        let focusJSON = try JSONEncoder().encode(archive)
        try focusJSON.write(to: modules.appendingPathComponent("focus.json"))
        let focus = FocusStore(clock: { self.now }, directory: modules)
        let activity = TaskActivityStore(clock: { self.now }, directory: modules)
        XCTAssertEqual(focus.records, [record])
        XCTAssertEqual(focus.preferences.dailyGoal, 12)
        XCTAssertEqual(activity.events, [event])
        activity.recordFocusStart(taskID: id, stopwatch: true)
        let done = expectation(description: "new activity saved")
        activity.flush { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 5)
        let exported = try SQLiteModuleExport.export(directory: modules)
        XCTAssertEqual(try JSONDecoder().decode([TaskActivityEvent].self, from: exported["task-activity.json"]!).count, 2)
        XCTAssertEqual(try JSONDecoder().decode(FocusStore.Archive.self, from: exported["focus.json"]!).records, [record])
        XCTAssertEqual(try Data(contentsOf: modules.appendingPathComponent("focus.json")), focusJSON)
        XCTAssertEqual(try Data(contentsOf: modules.appendingPathComponent("task-activity.json")), activityJSON)
    }

    func testNoteMetadataEditsDoNotRewriteBodyAndLaterBodyEditIsSaved() throws {
        let original = Note(id: UUID(), title: "笔记", document: NativeDocument(plainText: "原正文"),
                            folder: "未归档", updatedAt: now)
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: [original]))
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("CREATE TABLE body_audit(id TEXT)")
        try db.execute("CREATE TRIGGER note_body_audit AFTER UPDATE ON note_documents BEGIN INSERT INTO body_audit VALUES (new.id); END")
        let store = NoteStore(notes: [original], clock: { self.now })
        let coordinator = PersistenceCoordinator(repository: repository, delay: 60)
        store.onChange = { coordinator.schedule(notes: $0) }
        store.edit(original.id) { $0.title = "新标题" }
        flush(coordinator)
        XCTAssertEqual(try db.rows("SELECT id FROM body_audit").count, 0)
        XCTAssertEqual(try repository.load()?.notes.first?.document, original.document)
        store.edit(original.id) { $0.document = NativeDocument(plainText: "新正文") }
        store.edit(original.id) { $0.title = "最后标题" }
        flush(coordinator)
        XCTAssertEqual(try db.rows("SELECT id FROM body_audit").count, 1)
        XCTAssertEqual(try repository.load()?.notes.first?.document.plainText, "新正文")
    }

    func testDatabaseBackupIncludesCommittedWALAndLegacyJSONRestoreStillWorks() throws {
        let repository = NativePreviewRepository(directory: directory)
        let original = task("WAL 中的任务")
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        // Keep another connection open so backup cannot rely on last-close
        // checkpointing to copy changes out of WAL.
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("PRAGMA wal_autocheckpoint=0")
        var changed = original; changed.title = "已提交的新标题"
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[original.id] = TaskChangeSet(updatedFrom: original, to: changed).entries.first
        try repository.apply(batch)
        let backup = try XCTUnwrap(repository.backupNow(now: now))
        let reader = SQLiteWorkspaceRepository(directory: directory)
        XCTAssertEqual(try reader.readBackup(at: backup).tasks, [changed])
        let json = directory.appendingPathComponent("old-backup.json")
        try JSONEncoder().encode(NativeWorkspaceSnapshot(tasks: [original], notes: [])).write(to: json)
        try repository.restoreBackup(at: json, now: now.addingTimeInterval(60))
        XCTAssertEqual(try repository.load()?.tasks, [original])
    }
}
