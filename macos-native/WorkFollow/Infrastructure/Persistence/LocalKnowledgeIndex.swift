import Foundation
import NaturalLanguage

struct LocalKnowledgeHit: Sendable {
    let resourceID: UUID
    let title: String
    let location: String
    let heading: String
    let body: String
    let blockID: UUID?
    let position: Int
    let rank: Double

    func excerpt(matching terms: [String]) -> (text: String, reveal: String)? {
        let range = terms.lazy.compactMap { body.range(of: $0, options: [.caseInsensitive, .widthInsensitive]) }.first
        guard let range else { return nil }
        let start = body.index(range.lowerBound, offsetBy: -24, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: 66, limitedBy: body.endIndex) ?? body.endIndex
        let snippet = String(body[start..<end]).replacingOccurrences(of: "\n", with: " ")
        return ((start == body.startIndex ? "" : "…") + snippet + (end == body.endIndex ? "" : "…"), String(body[range]))
    }
}

/// The index is derived from committed task and note rows. Changes waiting in
/// the workspace save queue are overlaid on both search paths by record ID.
final class LocalKnowledgeIndex: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var pending: [UUID: TaskChangeSet.Entry] = [:]
    private var needsBuild = true

    init(url: URL) { self.url = url }

    var needsBuilding: Bool {
        lock.lock(); defer { lock.unlock() }
        return needsBuild
    }

    func track(_ changes: TaskChangeSet) {
        lock.lock(); defer { lock.unlock() }
        for entry in changes.entries { pending[entry.taskID] = entry }
    }

    func committed(_ entries: Dictionary<UUID, TaskChangeSet.Entry>.Values) {
        lock.lock(); defer { lock.unlock() }
        for entry in entries where pending[entry.taskID]?.after == entry.after {
            pending.removeValue(forKey: entry.taskID)
        }
    }

    // Called on the existing serial persistence queue.
    func buildStep(in db: SQLiteDatabase) throws -> Bool {
        let ready = try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS knowledge_index_state (id INTEGER PRIMARY KEY, cursor TEXT, ready INTEGER NOT NULL)")
            try db.execute("""
                CREATE TABLE IF NOT EXISTS knowledge_passages (
                    id INTEGER PRIMARY KEY, owner TEXT NOT NULL, title TEXT NOT NULL, location TEXT NOT NULL,
                    heading TEXT NOT NULL, body TEXT NOT NULL, block_id TEXT, position INTEGER NOT NULL, folded TEXT NOT NULL)
                """)
            try db.execute("CREATE INDEX IF NOT EXISTS knowledge_owner ON knowledge_passages(owner)")
            try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_words USING fts5(title, location, body, prefix='2 3')")
            let state = try db.rows("SELECT cursor, ready FROM knowledge_index_state WHERE id=1").first
            if state.flatMap({ Self.string($0[1]) }) == "1" { return true }
            if state == nil {
                try db.execute("DELETE FROM knowledge_words")
                try db.execute("DELETE FROM knowledge_passages")
                try db.execute("INSERT INTO knowledge_index_state(id,cursor,ready) VALUES (1,'',0)")
            }
            let cursor = state.flatMap { Self.string($0[0]) } ?? ""
            let rows = try db.rows("""
                SELECT t.id, t.metadata, d.document FROM tasks t
                JOIN task_documents d ON d.id=t.id
                WHERE t.id > ? ORDER BY t.id LIMIT 48
                """, [.text(cursor)])
            let decoder = JSONDecoder()
            for row in rows {
                guard let metadata = row[1], let document = row[2] else { continue }
                var task = try decoder.decode(Task.self, from: metadata)
                task.document = try decoder.decode(NativeDocument.self, from: document)
                try replace(task.id, with: task, rebuildBody: true, in: db)
            }
            let ready = rows.count < 48
            try db.execute("UPDATE knowledge_index_state SET cursor=?, ready=? WHERE id=1",
                [.text(rows.last.flatMap { Self.string($0[0]) } ?? cursor), .integer(ready ? 1 : 0)])
            return ready
        }
        lock.lock(); needsBuild = !ready; lock.unlock()
        return ready
    }

    func invalidate(in db: SQLiteDatabase) throws {
        if try hasState(in: db) { try db.execute("DELETE FROM knowledge_index_state") }
        lock.lock(); needsBuild = true; lock.unlock()
    }

    func apply(_ entries: Dictionary<UUID, TaskChangeSet.Entry>.Values, in db: SQLiteDatabase) throws {
        guard !entries.isEmpty, try hasState(in: db),
              !(try db.rows("SELECT 1 FROM knowledge_index_state WHERE id=1")).isEmpty else { return }
        let indexedFields: Set<TaskChangeSet.Field> = [
            .title, .document, .kind, .list, .tags, .note, .deletedAt, .skippedAt, .convertedNoteID, .isAbandoned
        ]
        try db.execute("SAVEPOINT knowledge_update")
        do {
            for entry in entries where entry.operation != .update || !entry.changedFields.isDisjoint(with: indexedFields) {
                try replace(entry.taskID, with: entry.after,
                    rebuildBody: entry.operation == .insert || entry.changedFields.contains(.document), in: db)
            }
            try db.execute("RELEASE knowledge_update")
        } catch {
            // Business data can commit while an unusable derived index is rebuilt.
            try db.execute("ROLLBACK TO knowledge_update")
            try db.execute("RELEASE knowledge_update")
            try invalidate(in: db)
        }
    }

    /// A nil result requests the existing search path while the index is building.
    func search(_ terms: [String], literal: String? = nil) -> [LocalKnowledgeHit]? {
        guard !terms.isEmpty || literal?.isEmpty == false else { return nil }
        lock.lock(); let overlay = pending; lock.unlock()
        do {
            let db = try SQLiteDatabase(url: url, readOnly: true)
            guard try db.rows("SELECT ready FROM knowledge_index_state WHERE id=1").first.flatMap({ Self.string($0[0]) }) == "1" else { return nil }
            let tokens = terms.flatMap(Self.tokens).filter { !$0.isEmpty }
            let phrases = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
            let columns = "p.owner, p.title, p.location, p.heading, p.body, p.block_id, p.position"
            var hits: [LocalKnowledgeHit] = []
            if !phrases.isEmpty {
                let match = phrases.joined(separator: literal == nil ? " OR " : " AND ")
                hits = try db.rows("""
                    SELECT \(columns), bm25(knowledge_words, 8.0, 3.0, 1.0)
                    FROM knowledge_words JOIN knowledge_passages p ON p.id=knowledge_words.rowid
                    WHERE knowledge_words MATCH ?
                    """, [.text(match)]).compactMap(Self.hit)
            }
            let exactTerms: [String]
            if let literal {
                exactTerms = hits.isEmpty || tokens.count != 1 || literal.count <= 2 ? [literal] : []
            } else {
                exactTerms = terms.filter { $0.count <= 2 }
            }
            if !exactTerms.isEmpty {
                let conditions = exactTerms.map { _ in "instr(p.folded, ?) > 0" }.joined(separator: " OR ")
                let existing = Set(hits.map { "\($0.resourceID)-\($0.position)" })
                let fallback = try db.rows("SELECT \(columns), 0 FROM knowledge_passages p WHERE \(conditions)",
                    exactTerms.map { .text(Self.fold($0)) }).compactMap(Self.hit)
                hits.append(contentsOf: fallback.filter { !existing.contains("\($0.resourceID)-\($0.position)") })
            }
            hits.removeAll { overlay[$0.resourceID] != nil }
            for entry in overlay.values {
                guard let task = entry.after, Self.eligible(task) else { continue }
                for segment in try Self.segments(task.document) {
                    let searchable = Self.fold(task.title + " " + Self.location(task) + " " + segment.heading + " " + segment.body)
                    let matches = literal.map { searchable.contains(Self.fold($0)) || terms.allSatisfy { searchable.contains(Self.fold($0)) } }
                        ?? terms.contains { searchable.contains(Self.fold($0)) }
                    if matches {
                        hits.append(.init(resourceID: task.id, title: task.title, location: Self.location(task),
                            heading: segment.heading, body: segment.body, blockID: segment.blockID, position: segment.position, rank: 0))
                    }
                }
            }
            return hits.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.resourceID == $1.resourceID { return $0.position < $1.position }
                return $0.resourceID.uuidString < $1.resourceID.uuidString
            }
        } catch { return nil }
    }

    static func tokens(_ text: String) -> [String] {
        let text = fold(text)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func hasState(in db: SQLiteDatabase) throws -> Bool {
        try !db.rows("SELECT 1 FROM sqlite_master WHERE type='table' AND name='knowledge_index_state'").isEmpty
    }

    private static func eligible(_ task: Task) -> Bool {
        task.deletedAt == nil && (task.isNoteTask || (!task.isAbandoned && !task.isConverted && task.skippedAt == nil))
    }

    private static func location(_ task: Task) -> String {
        (task.isNoteTask ? task.note?.folder ?? "" : task.list.name) + " " + task.tags.joined(separator: " ")
    }

    private struct Segment {
        let heading: String
        let body: String
        let blockID: UUID?
        let position: Int
    }

    private static func segments(_ document: NativeDocument) throws -> [Segment] {
        let document = try document.materialized()
        let text = document.plainText
        if text.count <= 450 {
            return [.init(heading: "", body: text, blockID: document.blocks.count == 1 ? document.blocks.first?.id : nil, position: 0)]
        }
        var heading = ""
        var segments: [Segment] = []
        for block in document.blocks where !block.plainText.isEmpty {
            if case .heading = block.kind { heading = block.plainText }
            for chunk in KnowledgeCorpus.chunks(block.plainText) {
                segments.append(.init(heading: heading, body: chunk, blockID: block.id, position: segments.count))
            }
        }
        return segments
    }

    private func replace(_ id: UUID, with task: Task?, rebuildBody: Bool, in db: SQLiteDatabase) throws {
        let key = SQLiteDatabase.Value.text(id.uuidString)
        let liveTask = task.flatMap { Self.eligible($0) ? $0 : nil }
        if !rebuildBody, let liveTask {
            let saved = try db.rows("SELECT id, heading, body FROM knowledge_passages WHERE owner=?", [key])
            if !saved.isEmpty {
                let location = Self.location(liveTask)
                let title = Self.tokens(liveTask.title).joined(separator: " ")
                for row in saved {
                    guard let rowID = Self.string(row[0]).flatMap(Int64.init) else { continue }
                    let context = location + " " + (Self.string(row[1]) ?? "")
                    let folded = Self.fold(liveTask.title + " " + context + " " + (Self.string(row[2]) ?? ""))
                    try db.execute("UPDATE knowledge_passages SET title=?, location=?, folded=? WHERE id=?",
                        [.text(liveTask.title), .text(location), .text(folded), .integer(rowID)])
                    try db.execute("UPDATE knowledge_words SET title=?, location=? WHERE rowid=?",
                        [.text(title), .text(Self.tokens(context).joined(separator: " ")), .integer(rowID)])
                }
                return
            }
        }
        try db.execute("DELETE FROM knowledge_words WHERE rowid IN (SELECT id FROM knowledge_passages WHERE owner=?)", [key])
        try db.execute("DELETE FROM knowledge_passages WHERE owner=?", [key])
        guard let task = liveTask else { return }
        let location = Self.location(task)
        let titleTerms = Self.tokens(task.title).joined(separator: " ")
        for segment in try Self.segments(task.document) {
            let context = location + " " + segment.heading
            try db.execute("""
                INSERT INTO knowledge_passages(owner,title,location,heading,body,block_id,position,folded) VALUES (?,?,?,?,?,?,?,?)
                """, [key, .text(task.title), .text(location), .text(segment.heading), .text(segment.body),
                       segment.blockID.map { .text($0.uuidString) } ?? .null, .integer(Int64(segment.position)),
                       .text(Self.fold(task.title + " " + context + " " + segment.body))])
            try db.execute("INSERT INTO knowledge_words(rowid,title,location,body) VALUES (last_insert_rowid(),?,?,?)",
                [.text(titleTerms), .text(Self.tokens(context).joined(separator: " ")), .text(Self.tokens(segment.body).joined(separator: " "))])
        }
    }

    private static func hit(_ row: [Data?]) -> LocalKnowledgeHit? {
        guard let id = string(row[0]).flatMap(UUID.init(uuidString:)),
              let position = string(row[6]).flatMap(Int.init) else { return nil }
        return .init(resourceID: id, title: string(row[1]) ?? "", location: string(row[2]) ?? "",
            heading: string(row[3]) ?? "", body: string(row[4]) ?? "",
            blockID: string(row[5]).flatMap(UUID.init(uuidString:)), position: position,
            rank: string(row[7]).flatMap(Double.init) ?? 0)
    }

    private static func string(_ data: Data?) -> String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
