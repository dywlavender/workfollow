import XCTest
@testable import WorkFollow

@MainActor
final class DeferredDocumentTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeferredDocumentTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func task(_ title: String, body: String) -> Task {
        Task(id: UUID(), title: title, document: NativeDocument(plainText: body), list: .inbox,
             priority: .none, schedule: TaskSchedule(), parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
    }
    private func flush(_ environment: AppEnvironment) {
        let done = expectation(description: "saved")
        environment.flush { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testThousandTaskPreviewsAndAllSearchEntrypointsDoNotHydrateDocuments() throws {
        let padding = String(repeating: "长正文 ", count: 500)
        let originals = (0..<1_000).map { index in
            task("任务\(index)", body: "首行\n" + padding + (index == 999 ? "HiddenNeedle" : "普通文字") + padding)
        }
        let note = Note(id: UUID(), title: "笔记", document: NativeDocument(plainText: padding + "HiddenNeedle" + padding),
                        folder: "工作", updatedAt: now, originalContentJson: String(repeating: "富文本源", count: 1_000))
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: originals, notes: [note]))
        let snapshot = try XCTUnwrap(repository.loadDeferred())
        XCTAssertEqual(repository.documentReadCount, 0)
        XCTAssertEqual(repository.originalContentReadCount, 0)
        for task in snapshot.tasks {
            XCTAssertFalse(task.document.isLoaded)
            XCTAssertEqual(TaskListViewDefaults.bodyPreview(of: task.document), "首行")
            XCTAssertFalse(task.document.isEmpty)
        }
        let matches = snapshot.tasks.filter { TaskListQuery(search: "hiddenneedle").matches($0) }
        XCTAssertEqual(matches.map(\.id), [originals[999].id])
        let notes = NotesWorkspaceModel(initialNotes: snapshot.notes)
        XCTAssertEqual(notes.rows(trash: false, query: "hiddenneedle", folder: nil, favorites: false).map(\.id), [note.id])
        let entries = CommandPaletteProjection.entries(query: "hiddenneedle", tasks: snapshot.tasks, notes: snapshot.notes,
                                                       creationList: "收集箱", schedulesForToday: false, now: now)
        XCTAssertTrue(entries.contains { $0.action == .openTask(originals[999].id) })
        XCTAssertTrue(entries.contains { $0.action == .openNote(note.id) })
        XCTAssertEqual(repository.documentReadCount, 0)
        XCTAssertEqual(repository.originalContentReadCount, 0)
    }

    func testMetadataEditsLeaveBodiesAndPreservedRichSourceUnloaded() throws {
        let original = task("原标题", body: String(repeating: "正文", count: 1_000))
        let note = Note(id: UUID(), title: "原笔记", document: NativeDocument(plainText: "完整正文"),
                        folder: "工作", updatedAt: now, originalContentJson: "{\"rich\":true}")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: [note]))
        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        XCTAssertEqual(environment.documentReadCount, 0)
        _ = environment.taskWorkspace.setTitle(original.id, "新标题")
        environment.notesWorkspace.edit(note.id) { $0.title = "新笔记标题" }
        environment.notesWorkspace.moveNoteToFolder(note.id, named: "另一文件夹")
        flush(environment)
        XCTAssertEqual(environment.documentReadCount, 0)
        XCTAssertEqual(environment.originalContentReadCount, 0)
        let restored = try XCTUnwrap(repository.load())
        XCTAssertEqual(restored.tasks.first?.document, original.document)
        XCTAssertEqual(restored.notes.first?.document, note.document)
        XCTAssertEqual(restored.notes.first?.originalContentJson, note.originalContentJson)
        XCTAssertEqual(restored.notes.first?.folder, "另一文件夹")
    }

    func testFirstReadCachesRichBlocksAndValueEditsKeepOriginalDocument() throws {
        var original = task("富文本", body: "原正文")
        original.document.blocks[0].kind = .heading(2)
        original.document.blocks[0].runs[0].marks = [.bold, .link("https://example.com")]
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        XCTAssertEqual(lazy.document.blocks, original.document.blocks)
        XCTAssertEqual(lazy.document.blocks, original.document.blocks)
        XCTAssertEqual(repository.documentReadCount, 1)
        var edited = lazy
        edited.document.blocks[0].runs[0].text = "修改正文"
        XCTAssertEqual(lazy.document.blocks, original.document.blocks)
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[lazy.id] = TaskChangeSet(updatedFrom: lazy, to: edited).entries.first!
        try repository.apply(batch)
        XCTAssertEqual(try repository.load()?.tasks.first?.document, edited.document)
        XCTAssertEqual(lazy.document.blocks, original.document.blocks)
        XCTAssertEqual(repository.documentReadCount, 1)
    }

    func testRemovedTaskUndoReferenceSurvivesDatabaseCascadeDeletion() throws {
        let original = task("可撤销", body: "需要恢复的正文")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        let store = WorkspaceStore()
        store.commit([lazy]); store.clearUndo()
        store.commit([])
        XCTAssertEqual(repository.documentReadCount, 1)
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[original.id] = TaskChangeSet(before: [lazy], after: []).entries.first!
        try repository.apply(batch)
        XCTAssertEqual(try repository.load()?.tasks.count, 0)
        store.undo()
        XCTAssertEqual(store.tasks.first?.document, original.document)
        batch.tasks[original.id] = TaskChangeSet(before: [], after: store.tasks).entries.first!
        try repository.apply(batch)
        XCTAssertEqual(try repository.load()?.tasks.first?.document, original.document)
    }

    func testConversionAndRichNoteCopyReadCompleteBodiesAndPreserveOriginalSource() throws {
        let original = task("转换任务", body: String(repeating: "完整任务正文", count: 100))
        let note = Note(id: UUID(), title: "受保护笔记", document: NativeDocument(plainText: "完整受保护内容"),
                        folder: "工作", updatedAt: now, originalContentJson: "{\"rich\":true}")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: [note]))
        let environment = AppEnvironment(clock: { self.now }, directory: directory)
        let lazyNote = try XCTUnwrap(environment.notesWorkspace.notes.first)
        XCTAssertTrue(lazyNote.hasPreservedRichContent)
        XCTAssertEqual(environment.originalContentReadCount, 0)
        let convertedID = try XCTUnwrap(environment.moveTaskToNoteLibrary(original.id))
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == convertedID }?.document, original.document)
        let copyID = try XCTUnwrap(environment.notesWorkspace.createPlainTextCopy(note.id))
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == copyID }?.document.plainText, note.document.plainText)
        XCTAssertEqual(environment.documentReadCount, 2)
        XCTAssertEqual(environment.originalContentReadCount, 0)
        flush(environment)
        XCTAssertEqual(try repository.load()?.notes.first { $0.id == note.id }?.originalContentJson, note.originalContentJson)
        environment.taskWorkspace.undo()
        flush(environment)
        XCTAssertFalse(environment.notesWorkspace.notes.contains { $0.id == convertedID })
        XCTAssertEqual(try repository.load()?.tasks.first?.document, original.document)
    }

    func testBodySearchCacheRefreshesAfterDocumentChange() throws {
        let padding = String(repeating: "上下文 ", count: 200)
        let original = task("索引更新", body: padding + "OldNeedle" + padding)
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        XCTAssertTrue(lazy.document.matches("oldneedle"))
        XCTAssertEqual(repository.documentReadCount, 0)
        var edited = lazy
        edited.document = NativeDocument(plainText: padding + "NewNeedle" + padding)
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[lazy.id] = TaskChangeSet(updatedFrom: lazy, to: edited).entries.first!
        try repository.apply(batch)
        let refreshed = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        XCTAssertFalse(refreshed.document.matches("oldneedle"))
        XCTAssertTrue(refreshed.document.matches("newneedle"))
        XCTAssertFalse(refreshed.document.isLoaded)
    }

    func testExistingVersionOneDatabaseBackfillsPreviewsWithoutChangingRichBodies() throws {
        let original = task("旧 SQLite", body: "首行\n完整旧正文")
        let note = Note(id: UUID(), title: "旧富文本", document: original.document, folder: "工作",
                        updatedAt: now, originalContentJson: "{\"rich\":true}")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: [note]))
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        let payload = try db.rows("SELECT document FROM task_documents").first?[0]
        for (table, column) in [("tasks", "document_summary"), ("notes", "document_summary"),
                                ("task_documents", "plain_text"), ("note_documents", "plain_text")] {
            try db.execute("ALTER TABLE \(table) DROP COLUMN \(column)")
        }
        try db.execute("PRAGMA user_version=1")
        let snapshot = try XCTUnwrap(repository.loadDeferred())
        XCTAssertEqual(repository.documentReadCount, 0)
        XCTAssertEqual(TaskListViewDefaults.bodyPreview(of: snapshot.tasks[0].document), "首行")
        XCTAssertTrue(snapshot.notes[0].hasPreservedRichContent)
        XCTAssertEqual(repository.originalContentReadCount, 0)
        XCTAssertEqual(try db.rows("SELECT document FROM task_documents").first?[0], payload)
        XCTAssertEqual(try db.rows("PRAGMA user_version").first?[0], Data("3".utf8))
        XCTAssertEqual(snapshot.tasks[0].document, original.document)
        XCTAssertEqual(snapshot.notes[0].originalContentJson, note.originalContentJson)
    }

    func testDeferredReadFailureCannotEncodeOrOverwriteExistingWorkspace() throws {
        let original = task("保留", body: "正文")
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))
        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        let db = try SQLiteDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        try db.execute("UPDATE task_documents SET document=? WHERE id=?", [.blob(Data("invalid document".utf8)), .text(original.id.uuidString)])
        XCTAssertThrowsError(try lazy.document.materialized())
        XCTAssertNotNil(lazy.document.loadError)
        XCTAssertThrowsError(try JSONEncoder().encode(lazy.document))
        var edited = lazy; edited.title = "不应提交"
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[original.id] = TaskChangeSet(updatedFrom: lazy, to: edited).entries.first!
        XCTAssertThrowsError(try repository.apply(batch))
        XCTAssertEqual(try db.rows("SELECT title FROM tasks").first?[0], Data("保留".utf8))
    }
}
