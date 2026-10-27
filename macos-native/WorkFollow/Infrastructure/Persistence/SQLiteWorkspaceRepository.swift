import Foundation

/// SQLite is authoritative after the initialized marker commits. Legacy JSON
/// remains untouched for migration recovery and is never used as a second writer.
final class SQLiteWorkspaceRepository {
    static let filename = "workspace.sqlite"
    let directory: URL
    var url: URL { directory.appendingPathComponent(Self.filename) }
    var onDocumentFailure: ((Error) -> Void)?
    private let readsLock = NSLock()
    private var documentReads = 0
    private var originalReads = 0
    private var documentFailure: Error?
    var originalContentReadCount: Int { readsLock.lock(); defer { readsLock.unlock() }; return originalReads }
    var documentReadCount: Int { readsLock.lock(); defer { readsLock.unlock() }; return documentReads }
    private let searchLock = NSLock()
    private var searchCache: [String: Set<String>] = [:]
    private var searchOrder: [String] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        self.directory = directory
        encoder.outputFormatting = [.sortedKeys]
    }

    private func database() throws -> SQLiteDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(url: url)
        let version = try db.rows("PRAGMA user_version").first?.first.flatMap { $0 }
            .flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
        guard version <= 3 else { throw incompatible() }
        if version == 0 {
            try db.transaction {
                try db.execute("CREATE TABLE IF NOT EXISTS workspace_state (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
                try db.execute("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, position INTEGER NOT NULL, title TEXT NOT NULL, list TEXT NOT NULL, parent_id TEXT, status INTEGER NOT NULL, due_at REAL, deleted_at REAL, metadata BLOB NOT NULL)")
                try db.execute("CREATE TABLE IF NOT EXISTS task_documents (id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE, document BLOB NOT NULL)")
                try db.execute("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, position INTEGER NOT NULL, title TEXT NOT NULL, folder TEXT NOT NULL, deleted_at REAL, metadata BLOB NOT NULL)")
                try db.execute("CREATE TABLE IF NOT EXISTS note_documents (id TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE, document BLOB NOT NULL, original_content TEXT)")
                try db.execute("CREATE INDEX IF NOT EXISTS tasks_list_status ON tasks(list, status, deleted_at)")
                try db.execute("CREATE INDEX IF NOT EXISTS tasks_parent ON tasks(parent_id)")
                try db.execute("CREATE INDEX IF NOT EXISTS tasks_due ON tasks(due_at)")
                try db.execute("CREATE INDEX IF NOT EXISTS notes_folder ON notes(folder, deleted_at)")
                try db.execute("PRAGMA user_version=1")
            }
        }
        if version < 2 {
            try db.transaction {
                try db.execute("ALTER TABLE tasks ADD COLUMN document_summary BLOB")
                try db.execute("ALTER TABLE notes ADD COLUMN document_summary BLOB")
                try db.execute("ALTER TABLE task_documents ADD COLUMN plain_text TEXT")
                try db.execute("ALTER TABLE note_documents ADD COLUMN plain_text TEXT")
                try rebuildDocumentSummaries(db)
                try db.execute("PRAGMA user_version=2")
            }
        }
        if version < 3 {
            // 清单摘要（total/done/reminders）是 v3 新增字段；旧摘要解码为 nil，
            // 所以升级时按正文重算一次，之后随每次文档保存增量更新。
            try db.transaction {
                try rebuildDocumentSummaries(db)
                try db.execute("PRAGMA user_version=3")
            }
        }
        return db
    }

    private func rebuildDocumentSummaries(_ db: SQLiteDatabase) throws {
        for (table, documents) in [("tasks", "task_documents"), ("notes", "note_documents")] {
            for row in try db.rows("SELECT id,document,\(documents == "note_documents" ? "original_content" : "NULL") FROM \(documents)") {
                let document = try decoder.decode(NativeDocument.self, from: row[1]!)
                let id = String(data: row[0]!, encoding: .utf8)!
                try db.execute("UPDATE \(table) SET document_summary=? WHERE id=?", [.blob(try encoder.encode(DocumentSummary(document, hasOriginalContent: table == "notes" ? row[2] != nil : nil))), .text(id)])
                try db.execute("UPDATE \(documents) SET plain_text=? WHERE id=?", [.text(document.plainText), .text(id)])
            }
        }
    }

    private func incompatible() -> NSError {
        NSError(domain: "WorkFollow.Storage", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "数据版本不兼容，已停止自动保存。"])
    }

    private func state(_ db: SQLiteDatabase) throws -> NativeWorkspaceSnapshot? {
        guard let data = try db.rows("SELECT value FROM workspace_state WHERE key='metadata'").first?[0] else { return nil }
        let snapshot = try decoder.decode(NativeWorkspaceSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw incompatible() }
        return snapshot
    }

    func load(deferred: Bool = false) throws -> NativeWorkspaceSnapshot? {
        let legacyURL = directory.appendingPathComponent(NativePreviewRepository.snapshotFileName)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let legacyExists = FileManager.default.fileExists(atPath: legacyURL.path)
        guard exists || legacyExists else { return nil }
        // Decode before creating a database: a failed legacy import never marks
        // an empty workspace as initialized or hides the original read error.
        if !exists {
            let legacy = try decoder.decode(NativeWorkspaceSnapshot.self, from: Data(contentsOf: legacyURL))
            guard legacy.version == 1 else { throw incompatible() }
            try replace(legacy, verifyImport: true)
        }
        let db = try database()
        if try state(db) == nil, legacyExists {
            let legacy = try decoder.decode(NativeWorkspaceSnapshot.self, from: Data(contentsOf: legacyURL))
            guard legacy.version == 1 else { throw incompatible() }
            try replace(legacy, verifyImport: true)
        }
        return try load(from: db, deferred: deferred)
    }

    private func load(from db: SQLiteDatabase, deferred: Bool = false) throws -> NativeWorkspaceSnapshot? {
        guard let metadata = try state(db) else { return nil }
        if deferred {
            let tasks = try db.rows("SELECT id,metadata,document_summary FROM tasks ORDER BY position").map { row -> Task in
                var task = try decoder.decode(Task.self, from: row[1]!)
                task.document = try deferredDocument(id: task.id, summary: row[2]!, notes: false)
                attachLegacyOriginal(to: &task)
                return task
            }
            let notes = try db.rows("SELECT id,metadata,document_summary FROM notes ORDER BY position").map { row -> Note in
                var note = try decoder.decode(Note.self, from: row[1]!)
                note.document = try deferredDocument(id: note.id, summary: row[2]!, notes: true)
                let id = note.id
                let summary = try decoder.decode(DocumentSummary.self, from: row[2]!)
                note.deferOriginalContent(DeferredOriginalContent(isPresent: summary.hasOriginalContent) { [self] in
                    do {
                        let db = try SQLiteDatabase(url: url, readOnly: true)
                        let row = try db.rows("SELECT original_content FROM note_documents WHERE id=?", [.text(id.uuidString)]).first
                        guard let row else { throw missingDocument() }
                        readsLock.lock(); originalReads += 1; readsLock.unlock()
                        return row[0].flatMap { String(data: $0, encoding: .utf8) }
                    } catch { reportDocumentFailure(error); throw error }
                })
                return note
            }
            return Self.snapshot(metadata: metadata, tasks: tasks, notes: notes)
        }
        let tasks = try db.rows("SELECT t.metadata, d.document FROM tasks t JOIN task_documents d ON d.id=t.id ORDER BY t.position").map { row -> Task in
            var task = try decoder.decode(Task.self, from: row[0]!)
            task.document = try decoder.decode(NativeDocument.self, from: row[1]!)
            attachLegacyOriginal(to: &task)
            return task
        }
        let notes = try db.rows("SELECT n.metadata, d.document, d.original_content FROM notes n JOIN note_documents d ON d.id=n.id ORDER BY n.position").map { row -> Note in
            var note = try decoder.decode(Note.self, from: row[0]!)
            note.document = try decoder.decode(NativeDocument.self, from: row[1]!)
            note.originalContentJson = row[2].flatMap { String(data: $0, encoding: .utf8) }
            return note
        }
        return Self.snapshot(metadata: metadata, tasks: tasks, notes: notes)
    }

    static func snapshot(metadata: NativeWorkspaceSnapshot, tasks: [Task], notes: [Note]) -> NativeWorkspaceSnapshot {
        NativeWorkspaceSnapshot(version: metadata.version, tasks: tasks, notes: notes,
            taskLists: metadata.taskLists, taskListMeta: metadata.taskListMeta,
            taskListFolders: metadata.taskListFolders, taskListSections: metadata.taskListSections,
            taskTags: metadata.taskTags,
            noteFolders: metadata.noteFolders, noteFolderMetadata: metadata.noteFolderMetadata,
            notesMergedIntoTasks: metadata.notesMergedIntoTasks)
    }

    /// Bulk replacement is reserved for migration, explicit import and restore.
    func replace(_ snapshot: NativeWorkspaceSnapshot, verifyImport: Bool = false) throws {
        guard snapshot.version == 1 else { throw incompatible() }
        invalidateSearch()
        defer { invalidateSearch() }
        let db = try database()
        try db.transaction {
            try db.execute("DELETE FROM tasks")
            try db.execute("DELETE FROM notes")
            for (index, task) in snapshot.tasks.enumerated() { try write(task, position: index, document: true, db: db) }
            for (index, note) in snapshot.notes.enumerated() { try write(note, position: index, db: db) }
            try writeMetadata(snapshot, db: db)
            if verifyImport {
                let restored = try load(from: db)
                guard restored?.tasks == snapshot.tasks, restored?.notes == snapshot.notes,
                      try encoder.encode(restored.map { Self.snapshot(metadata: $0, tasks: [], notes: []) }) ==
                          encoder.encode(Optional(Self.snapshot(metadata: snapshot, tasks: [], notes: []))) else {
                    throw NSError(domain: "WorkFollow.Storage", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "旧数据导入校验失败，未切换存储。"])
                }
            }
        }
    }

    /// One-time upgrade of legacy notes into task rows. Documents are copied as
    /// BLOBs so no note body is materialized during launch. The legacy notes
    /// table is deliberately left untouched for rollback; the metadata flag
    /// prevents a second import.
    func mergeNotesAsTasks(_ tasks: [Task]) throws {
        guard !tasks.isEmpty else { return }
        let db = try database()
        try db.transaction {
            for task in tasks {
                let id = SQLiteDatabase.Value.text(task.id.uuidString)
                let exists = try db.rows("SELECT 1 FROM tasks WHERE id=?", [id]).first != nil
                if exists { continue }
                guard try db.rows("SELECT 1 FROM note_documents WHERE id=?", [id]).first != nil else {
                    throw NSError(domain: "WorkFollow.Storage", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "笔记正文缺失，已取消笔记合并。"])
                }
                var metadata = task
                metadata.document = .empty
                try db.execute("""
                    INSERT INTO tasks(id,position,title,list,parent_id,status,due_at,deleted_at,metadata)
                    VALUES (?,(SELECT COALESCE(MAX(position)+1,0) FROM tasks),?,?,?,?,?,?,?)
                    """, [id, .text(task.title), .text(task.list.name),
                          task.parentID.map { .text($0.uuidString) } ?? .null,
                          .integer(task.status == .completed ? 1 : 0),
                          task.schedule.dueAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                          task.deletedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                          .blob(try encoder.encode(metadata))])
                try db.execute("""
                    INSERT OR REPLACE INTO task_documents(id,document,plain_text)
                    SELECT id,document,plain_text FROM note_documents WHERE id=?
                    """, [id])
                try db.execute("""
                    UPDATE tasks SET document_summary=(SELECT document_summary FROM notes WHERE id=?)
                    WHERE id=?
                    """, [id, id])
            }
            let merged: NativeWorkspaceSnapshot
            if let metadata = try state(db) {
                merged = NativeWorkspaceSnapshot(version: metadata.version,
                    tasks: metadata.tasks, notes: metadata.notes,
                    taskLists: metadata.taskLists, taskListMeta: metadata.taskListMeta,
                    taskListFolders: metadata.taskListFolders,
                    taskListSections: metadata.taskListSections,
                    taskTags: metadata.taskTags,
                    noteFolders: metadata.noteFolders,
                    noteFolderMetadata: metadata.noteFolderMetadata,
                    notesMergedIntoTasks: true)
            } else {
                merged = NativeWorkspaceSnapshot(tasks: [], notes: [], notesMergedIntoTasks: true)
            }
            try writeMetadata(merged, db: db)
        }
    }

    struct Batch {
        var tasks: [UUID: TaskChangeSet.Entry] = [:]
        var taskOrder: [UUID]?
        var noteUpserts: [UUID: Note] = [:]
        var noteDeleted = Set<UUID>()
        var noteDocuments = Set<UUID>()
        var noteOrder: [UUID]?
        var metadata: NativeWorkspaceSnapshot?
        var isEmpty: Bool { tasks.isEmpty && taskOrder == nil && metadata == nil && noteUpserts.isEmpty && noteDeleted.isEmpty && noteOrder == nil }
    }

    func apply(_ batch: Batch) throws {
        readsLock.lock(); let failure = documentFailure; readsLock.unlock()
        if let failure { throw failure }
        let changesBody = batch.tasks.values.contains { $0.operation != .update || $0.changedFields.contains(.document) }
            || !batch.noteUpserts.isEmpty || !batch.noteDeleted.isEmpty
        if changesBody { invalidateSearch() }
        defer { if changesBody { invalidateSearch() } }
        let db = try database()
        try db.transaction {
            for entry in batch.tasks.values {
                if let task = entry.after {
                    try write(task, position: nil,
                              document: entry.operation == .insert || entry.changedFields.contains(.document), db: db)
                } else { try db.execute("DELETE FROM tasks WHERE id=?", [.text(entry.taskID.uuidString)]) }
            }
            if let order = batch.taskOrder {
                for (index, id) in order.enumerated() {
                    try db.execute("UPDATE tasks SET position=? WHERE id=? AND position!=?",
                        [.integer(Int64(index)), .text(id.uuidString), .integer(Int64(index))])
                }
            }
            for id in batch.noteDeleted { try db.execute("DELETE FROM notes WHERE id=?", [.text(id.uuidString)]) }
            for note in batch.noteUpserts.values {
                let position = try db.rows("SELECT position FROM notes WHERE id=?", [.text(note.id.uuidString)])
                    .first?[0].flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init)
                try write(note, position: position ?? 0,
                          document: position == nil || batch.noteDocuments.contains(note.id), db: db)
            }
            if let order = batch.noteOrder {
                for (index, id) in order.enumerated() {
                    try db.execute("UPDATE notes SET position=? WHERE id=? AND position!=?", [.integer(Int64(index)), .text(id.uuidString), .integer(Int64(index))])
                }
            }
            if let metadata = batch.metadata { try writeMetadata(metadata, db: db) }
            else if try state(db) == nil { try writeMetadata(NativeWorkspaceSnapshot(tasks: [], notes: []), db: db) }
        }
    }

    private func writeMetadata(_ snapshot: NativeWorkspaceSnapshot, db: SQLiteDatabase) throws {
        let data = try encoder.encode(Self.snapshot(metadata: snapshot, tasks: [], notes: []))
        try db.execute("INSERT INTO workspace_state(key,value) VALUES ('metadata',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value WHERE value!=excluded.value", [.blob(data)])
    }

    private func write(_ task: Task, position: Int?, document: Bool, db: SQLiteDatabase) throws {
        var metadata = task; metadata.document = .empty
        let id = SQLiteDatabase.Value.text(task.id.uuidString)
        try db.execute("""
            INSERT INTO tasks(id,position,title,list,parent_id,status,due_at,deleted_at,metadata)
            VALUES (?,COALESCE(?,(SELECT position FROM tasks WHERE id=?),(SELECT COALESCE(MAX(position)+1,0) FROM tasks)),?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET position=excluded.position,title=excluded.title,list=excluded.list,
            parent_id=excluded.parent_id,status=excluded.status,due_at=excluded.due_at,deleted_at=excluded.deleted_at,metadata=excluded.metadata
            """, [id, position.map { .integer(Int64($0)) } ?? .null, id, .text(task.title), .text(task.list.name),
                task.parentID.map { .text($0.uuidString) } ?? .null, .integer(task.status == .completed ? 1 : 0),
                task.schedule.dueAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                task.deletedAt.map { .real($0.timeIntervalSince1970) } ?? .null, .blob(try encoder.encode(metadata))])
        if document {
            try db.execute("INSERT INTO task_documents(id,document,plain_text) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET document=excluded.document,plain_text=excluded.plain_text",
                [id, .blob(try encoder.encode(task.document)), .text(task.document.plainText)])
            let summary = DocumentSummary(task.document,
                hasOriginalContent: task.isNoteTask ? task.note?.hasPreservedRichContent : nil)
            try db.execute("UPDATE tasks SET document_summary=? WHERE id=?", [.blob(try encoder.encode(summary)), id])
        }
    }

    private func write(_ note: Note, position: Int, document: Bool = true, db: SQLiteDatabase) throws {
        var metadata = note; metadata.document = .empty; metadata.originalContentJson = nil
        let id = SQLiteDatabase.Value.text(note.id.uuidString)
        try db.execute("INSERT INTO notes(id,position,title,folder,deleted_at,metadata) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET position=excluded.position,title=excluded.title,folder=excluded.folder,deleted_at=excluded.deleted_at,metadata=excluded.metadata",
            [id, .integer(Int64(position)), .text(note.title), .text(note.folder), note.deletedAt.map { .real($0.timeIntervalSince1970) } ?? .null, .blob(try encoder.encode(metadata))])
        if document {
            try db.execute("INSERT INTO note_documents(id,document,original_content,plain_text) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET document=excluded.document,original_content=excluded.original_content,plain_text=excluded.plain_text",
                [id, .blob(try encoder.encode(note.document)), note.originalContentJson.map { .text($0) } ?? .null, .text(note.document.plainText)])
            try db.execute("UPDATE notes SET document_summary=? WHERE id=?", [.blob(try encoder.encode(DocumentSummary(note.document, hasOriginalContent: note.hasPreservedRichContent))), id])
        }
    }

    private func missingDocument() -> NSError {
        NSError(domain: "WorkFollow.Storage", code: 4, userInfo: [NSLocalizedDescriptionKey: "找不到正文，已停止自动保存。"])
    }
    private func deferredDocument(id: UUID, summary: Data, notes: Bool) throws -> NativeDocument {
        let value = try decoder.decode(DocumentSummary.self, from: summary)
        return NativeDocument(deferred: DeferredDocument(summary: value, loader: { [self] in
            let db = try SQLiteDatabase(url: url, readOnly: true)
            let table = notes ? "note_documents" : "task_documents"
            guard let data = try db.rows("SELECT document FROM \(table) WHERE id=?", [.text(id.uuidString)]).first?[0] else { throw missingDocument() }
            let document = try JSONDecoder().decode(NativeDocument.self, from: data)
            readsLock.lock(); documentReads += 1; readsLock.unlock()
            return document
        }, search: { [self] query, lowercase in
            try searchMatches(query, notes: notes, lowercase: lowercase).contains(id.uuidString)
        }, report: { [self] error in reportDocumentFailure(error) }))
    }

    /// Migrated notes keep their protected source in the legacy note document
    /// table. Attach it lazily so loading the workspace does not read bodies.
    private func attachLegacyOriginal(to task: inout Task) {
        guard task.isNoteTask, var note = task.note, note.needsDeferredOriginal else { return }
        let id = task.id
        note.deferOriginalContent(DeferredOriginalContent(isPresent: true) { [self] in
            do {
                let db = try SQLiteDatabase(url: url, readOnly: true)
                guard let row = try db.rows("SELECT original_content FROM note_documents WHERE id=?",
                                            [.text(id.uuidString)]).first else { return nil }
                readsLock.lock(); originalReads += 1; readsLock.unlock()
                return row[0].flatMap { String(data: $0, encoding: .utf8) }
            } catch {
                reportDocumentFailure(error)
                throw error
            }
        })
        task.note = note
    }
    private func reportDocumentFailure(_ error: Error) {
        readsLock.lock(); documentFailure = error; readsLock.unlock()
        onDocumentFailure?(error)
    }
    private func invalidateSearch() {
        searchLock.lock(); searchCache.removeAll(); searchOrder.removeAll(); searchLock.unlock()
    }
    private func searchMatches(_ query: String, notes: Bool, lowercase: Bool) throws -> Set<String> {
        searchLock.lock(); defer { searchLock.unlock() }
        let key = "\(notes)-\(lowercase)-\(query)"
        if let cached = searchCache[key] {
            searchOrder.removeAll { $0 == key }; searchOrder.append(key)
            return cached
        }
        let db = try SQLiteDatabase(url: url, readOnly: true)
        let table = notes ? "note_documents" : "task_documents"
        var matches = Set<String>()
        for row in try db.rows("SELECT id,plain_text FROM \(table)") {
            let text = row[1].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if lowercase ? text.localizedLowercase.contains(query) : text.localizedCaseInsensitiveContains(query) {
                matches.insert(String(data: row[0]!, encoding: .utf8)!)
            }
        }
        if searchOrder.count >= 64 { searchCache.removeValue(forKey: searchOrder.removeFirst()) }
        searchOrder.append(key)
        searchCache[key] = matches
        return matches
    }

    /// A summary cannot be saved as a complete Task with a missing body.
    struct TaskSummary: Identifiable {
        let id: UUID
        let title: String
        let list: TaskList
        let priority: TaskPriority
        let schedule: TaskSchedule
        let parentID: UUID?
        let childOrder: Int
        let status: TaskStatus
        init(_ task: Task) {
            id = task.id; title = task.title; list = task.list; priority = task.priority
            schedule = task.schedule; parentID = task.parentID; childOrder = task.childOrder; status = task.status
        }
    }

    /// Lightweight reads do not join/decode document storage.
    func taskSummaries(list: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [TaskSummary] {
        let db = try database()
        let filter = list == nil ? "" : " AND list=?"
        let values: [SQLiteDatabase.Value] = (list.map { [.text($0)] } ?? []) + [.integer(Int64(max(0, limit))), .integer(Int64(max(0, offset)))]
        return try db.rows("SELECT metadata FROM tasks WHERE deleted_at IS NULL\(filter) ORDER BY position LIMIT ? OFFSET ?", values)
            .map { TaskSummary(try decoder.decode(Task.self, from: $0[0]!)) }
    }
    func taskDocument(id: UUID) throws -> NativeDocument? {
        let db = try database()
        return try db.rows("SELECT document FROM task_documents WHERE id=?", [.text(id.uuidString)]).first?[0]
            .map { try decoder.decode(NativeDocument.self, from: $0) }
    }
    func backup(to target: URL) throws { try database().backup(to: target) }
    func hasWorkspace() throws -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) { return try load() != nil }
        return try state(database()) != nil
    }
    func readBackup(at url: URL) throws -> NativeWorkspaceSnapshot {
        let db = try SQLiteDatabase(url: url, readOnly: true, immutable: true)
        guard let snapshot = try load(from: db) else {
            throw NSError(domain: "WorkFollow.Storage", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "备份中没有工作区数据。"])
        }
        return snapshot
    }
}
