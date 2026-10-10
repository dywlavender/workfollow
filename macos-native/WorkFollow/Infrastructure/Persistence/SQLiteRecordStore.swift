import Foundation

/// History rows are encoded individually. A small session/preferences record
/// is independent from the growing history collection.
final class SQLiteRecordStore<Record: Codable & Equatable & Identifiable, Metadata: Codable> where Record.ID == UUID {
    struct Totals { var value = 0; var count = 0; var records = 0 }
    struct Snapshot { var records: [Record]; var metadata: Metadata? }
    private let queue = DispatchQueue(label: "WorkFollow.history.persistence", qos: .utility)
    private let url: URL
    private let legacyURL: URL
    private let migrate: (Data) throws -> Snapshot
    private let newestFirst: Bool
    private let timestamp: (Record) -> Date
    private let taskID: (Record) -> UUID?
    private let metrics: ((Record) -> (value: Int, count: Int))?
    private var deltaMetadata: Metadata?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var saved: [UUID: Record] = [:]
    private var pending: Snapshot?
    private var deltaUpserts: [UUID: Record] = [:]
    private var deltaOrder: [UUID] = []
    private var deltaDeleted = Set<UUID>()
    private var decodedRecords = 0
    private var aggregateQueries = 0
    var aggregateQueryCount: Int { queue.sync { aggregateQueries } }
    var decodedRecordCount: Int { queue.sync { decodedRecords } }
    private var work: DispatchWorkItem?
    private var loadError: Error?
    private(set) var encodedRecordCount = 0

    init(filename: String, directory: URL, newestFirst: Bool = false, timestamp: @escaping (Record) -> Date,
         taskID: @escaping (Record) -> UUID?, metrics: ((Record) -> (value: Int, count: Int))? = nil, migrate: @escaping (Data) throws -> Snapshot) {
        url = directory.appendingPathComponent(filename + ".sqlite")
        legacyURL = directory.appendingPathComponent(filename + ".json")
        self.timestamp = timestamp; self.taskID = taskID; self.migrate = migrate
        self.newestFirst = newestFirst; self.metrics = metrics
        encoder.outputFormatting = [.sortedKeys]
    }

    private func database() throws -> SQLiteDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteDatabase(url: url)
        let version = try db.rows("PRAGMA user_version").first?[0]
            .flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
        guard version <= 3 else { throw NSError(domain: "WorkFollow.Storage", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "历史数据版本不兼容。"]) }
        if version == 0 {
            try db.transaction {
                try db.execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, position INTEGER NOT NULL, occurred_at REAL NOT NULL, task_id TEXT, payload BLOB NOT NULL)")
                try db.execute("CREATE INDEX IF NOT EXISTS records_date ON records(occurred_at DESC)")
                try db.execute("CREATE INDEX IF NOT EXISTS records_task_date ON records(task_id, occurred_at DESC)")
                try db.execute("CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
                try db.execute("PRAGMA user_version=1")
            }
        }
        if version < 2 {
            try db.transaction {
                try db.execute("CREATE INDEX IF NOT EXISTS records_position ON records(position)")
                try db.execute("DROP INDEX IF EXISTS records_date")
                try db.execute("DROP INDEX IF EXISTS records_task_date")
                try db.execute("CREATE INDEX records_date ON records(occurred_at DESC, position DESC)")
                try db.execute("CREATE INDEX records_task_date ON records(task_id, occurred_at DESC, position DESC)")
                try db.execute("PRAGMA user_version=2")
            }
        }
        if version < 3 {
            try db.transaction {
                try db.execute("ALTER TABLE records ADD COLUMN metric_value INTEGER")
                try db.execute("ALTER TABLE records ADD COLUMN metric_count INTEGER")
                try db.execute("PRAGMA user_version=3")
            }
        }
        if let metrics, try db.rows("SELECT value FROM state WHERE key='metrics_initialized'").isEmpty {
            try db.transaction {
                for row in try db.rows("SELECT id,payload FROM records WHERE metric_value IS NULL") {
                    let record = try decoder.decode(Record.self, from: row[1]!)
                    let totals = metrics(record)
                    try db.execute("UPDATE records SET metric_value=?,metric_count=? WHERE id=?",
                                   [.integer(Int64(totals.value)), .integer(Int64(totals.count)), .text(record.id.uuidString)])
                }
                try db.execute("CREATE INDEX IF NOT EXISTS records_metrics ON records(metric_value,metric_count)")
                try db.execute("INSERT INTO state(key,value) VALUES ('metrics_initialized',X'01')")
            }
        }
        return db
    }

    /// Called once during store hydration, before writes are submitted.
    func load(recentLimit: Int? = nil) -> Snapshot? {
        do {
            let exists = FileManager.default.fileExists(atPath: url.path)
            let legacyExists = FileManager.default.fileExists(atPath: legacyURL.path)
            guard exists || legacyExists else { return nil }
            let db = try database()
            if try db.rows("SELECT value FROM state WHERE key='initialized'").isEmpty {
                guard legacyExists else { return nil }
                let snapshot = try migrate(Data(contentsOf: legacyURL))
                try write(snapshot, db: db)
            }
            let order = newestFirst ? "occurred_at DESC, position DESC" : (recentLimit != nil ? "position DESC" : "position")
            let bound = recentLimit.map { " LIMIT \(max(0, $0))" } ?? ""
            let records = try db.rows("SELECT payload FROM records ORDER BY \(order)\(bound)").map { try decoder.decode(Record.self, from: $0[0]!) }
            decodedRecords += records.count
            let metadata = try db.rows("SELECT value FROM state WHERE key='metadata'").first?[0]
                .map { try decoder.decode(Metadata.self, from: $0) }
            saved = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return Snapshot(records: records, metadata: metadata)
        } catch { loadError = error; return nil }
    }

    var readError: Error? { loadError }

    func schedule(records: [Record], metadata: Metadata?) {
        queue.async { [self] in
            guard loadError == nil else { return }
            pending = Snapshot(records: records, metadata: metadata)
            work?.cancel()
            let next = DispatchWorkItem { [weak self] in _ = self?.writePending() }
            work = next
            queue.asyncAfter(deadline: .now() + 0.4, execute: next)
        }
    }

    /// Exact mutations for owners that only hydrate a bounded history window.
    func schedule(upserts: [Record] = [], deleted: [UUID] = [], metadata: Metadata? = nil) {
        queue.async { [self] in
            guard loadError == nil else { return }
            if let metadata { deltaMetadata = metadata }
            for id in deleted {
                deltaUpserts.removeValue(forKey: id)
                deltaOrder.removeAll { $0 == id }
                deltaDeleted.insert(id)
            }
            for record in upserts {
                deltaDeleted.remove(record.id)
                if deltaUpserts[record.id] == nil { deltaOrder.append(record.id) }
                deltaUpserts[record.id] = record
            }
            work?.cancel()
            let next = DispatchWorkItem { [weak self] in _ = self?.writePending() }
            work = next
            queue.asyncAfter(deadline: .now() + 0.4, execute: next)
        }
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        queue.async { [self] in
            work?.cancel()
            completion(writePending())
        }
    }

    private func writePending() -> Error? {
        if let loadError { return loadError }
        guard pending != nil || deltaMetadata != nil || !deltaOrder.isEmpty || !deltaDeleted.isEmpty else { return nil }
        do {
            let db = try database()
            if let snapshot = pending { try write(snapshot, db: db); pending = nil }
            if deltaMetadata != nil || !deltaOrder.isEmpty || !deltaDeleted.isEmpty {
                try db.transaction {
                    for id in deltaDeleted { try db.execute("DELETE FROM records WHERE id=?", [.text(id.uuidString)]) }
                    for id in deltaOrder {
                        if let record = deltaUpserts[id] { try upsert(record, db: db) }
                    }
                    if let metadata = deltaMetadata {
                        try db.execute("INSERT INTO state(key,value) VALUES ('metadata',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value WHERE value!=excluded.value", [.blob(try encoder.encode(metadata))])
                    }
                    try db.execute("INSERT OR IGNORE INTO state(key,value) VALUES ('initialized',X'01')")
                }
            }
            deltaUpserts.removeAll(); deltaOrder.removeAll(); deltaDeleted.removeAll(); deltaMetadata = nil
            return nil
        }
        catch { return error }
    }

    private func write(_ snapshot: Snapshot, db: SQLiteDatabase) throws {
        let next = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        try db.transaction {
            for id in saved.keys where next[id] == nil {
                try db.execute("DELETE FROM records WHERE id=?", [.text(id.uuidString)])
            }
            for record in (newestFirst ? snapshot.records.reversed().map { $0 } : snapshot.records) {
                if saved[record.id] != record {
                    try upsert(record, db: db)
                }
            }
            if let metadata = snapshot.metadata {
                try db.execute("INSERT INTO state(key,value) VALUES ('metadata',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value WHERE value!=excluded.value", [.blob(try encoder.encode(metadata))])
            }
            try db.execute("INSERT OR IGNORE INTO state(key,value) VALUES ('initialized',X'01')")
        }
        saved = next
    }

    private func upsert(_ record: Record, db: SQLiteDatabase) throws {
        let data = try encoder.encode(record)
        let totals = metrics?(record)
        encodedRecordCount += 1
        try db.execute("INSERT INTO records(id,position,occurred_at,task_id,payload,metric_value,metric_count) VALUES (?,COALESCE((SELECT position FROM records WHERE id=?),(SELECT COALESCE(MAX(position)+1,0) FROM records)),?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET occurred_at=excluded.occurred_at,task_id=excluded.task_id,payload=excluded.payload,metric_value=excluded.metric_value,metric_count=excluded.metric_count",
            [.text(record.id.uuidString), .text(record.id.uuidString), .real(timestamp(record).timeIntervalSince1970),
             taskID(record).map { .text($0.uuidString) } ?? .null, .blob(data), totals.map { .integer(Int64($0.value)) } ?? .null, totals.map { .integer(Int64($0.count)) } ?? .null])
    }

    /// Serialize the pending commit and query on the utility queue. Open panels
    /// immediately see edits; callers never need a separate flush/retry dance.
    func historyAsync(taskIDs: [UUID]? = nil, limit: Int = 100, offset: Int = 0) async throws -> [Record] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if let error = writePending() { throw error }
                    continuation.resume(returning: try readHistory(taskIDs: taskIDs, limit: limit, offset: offset))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Synchronous compatibility queries for exports and existing callers.
    func history(taskID: UUID? = nil, from: Date? = nil, to: Date? = nil,
                 limit: Int = 100, offset: Int = 0, insertionOrder: Bool = false) throws -> [Record] {
        try queue.sync {
            if let error = writePending() { throw error }
            return try readHistory(taskIDs: taskID.map { [$0] }, from: from, to: to,
                                   limit: limit, offset: offset, insertionOrder: insertionOrder)
        }
    }

    func record(id: UUID) throws -> Record? {
        try query { db -> Record? in
            let data = try db.rows("SELECT payload FROM records WHERE id=?", [.text(id.uuidString)]).first?[0]
            guard let data else { return nil }
            decodedRecords += 1
            return try decoder.decode(Record.self, from: data)
        } ?? nil
    }

    func totals(from: Date? = nil, to: Date? = nil) throws -> Totals {
        try query { db in
            aggregateQueries += 1
            var filters: [String] = []; var values: [SQLiteDatabase.Value] = []
            if let from { filters.append("occurred_at>=?"); values.append(.real(from.timeIntervalSince1970)) }
            if let to { filters.append("occurred_at<?"); values.append(.real(to.timeIntervalSince1970)) }
            let clause = filters.isEmpty ? "" : " WHERE " + filters.joined(separator: " AND ")
            let row = try db.rows("SELECT COALESCE(SUM(metric_value),0),COALESCE(SUM(metric_count),0),COUNT(*) FROM records\(clause)", values)[0]
            return Totals(value: number(row[0]), count: number(row[1]), records: number(row[2]))
        } ?? Totals()
    }

    func taskTotals(from: Date, limit: Int) throws -> [(UUID?, Int)] {
        try query { db in
            aggregateQueries += 1
            return try db.rows("SELECT task_id,SUM(metric_value) FROM records WHERE occurred_at>=? GROUP BY task_id ORDER BY SUM(metric_value) DESC LIMIT ?",
                        [.real(from.timeIntervalSince1970), .integer(Int64(max(0, limit)))])
                .map { row in (row[0].flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:)), number(row[1])) }
        } ?? []
    }

    private func number(_ data: Data?) -> Int {
        data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
    }

    private func query<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T? {
        try queue.sync {
            if let error = writePending() { throw error }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try body(SQLiteDatabase(url: url, readOnly: true))
        }
    }

    private func readHistory(taskIDs: [UUID]? = nil, from: Date? = nil, to: Date? = nil,
                             limit: Int, offset: Int, insertionOrder: Bool = false) throws -> [Record] {
        if let loadError { throw loadError }
        if taskIDs?.isEmpty == true { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let db = try SQLiteDatabase(url: url, readOnly: true)
        var filters: [String] = []; var values: [SQLiteDatabase.Value] = []
        if let taskIDs {
            filters.append("task_id IN (" + taskIDs.map { _ in "?" }.joined(separator: ",") + ")")
            values += taskIDs.map { .text($0.uuidString) }
        }
        if let from { filters.append("occurred_at>=?"); values.append(.real(from.timeIntervalSince1970)) }
        if let to { filters.append("occurred_at<?"); values.append(.real(to.timeIntervalSince1970)) }
        values += [.integer(Int64(max(0, limit))), .integer(Int64(max(0, offset)))]
        let whereSQL = filters.isEmpty ? "" : " WHERE " + filters.joined(separator: " AND ")
        let order = insertionOrder ? "position" : "occurred_at DESC, position DESC"
        let records = try db.rows("SELECT payload FROM records\(whereSQL) ORDER BY \(order) LIMIT ? OFFSET ?", values)
            .map { try decoder.decode(Record.self, from: $0[0]!) }
        decodedRecords += records.count
        return records
    }
}

struct EmptyHistoryMetadata: Codable {}
