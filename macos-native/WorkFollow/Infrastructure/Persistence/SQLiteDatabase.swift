import Foundation
import SQLite3

/// Connections belong to the caller's serial persistence queue. Readers use
/// their own connections; no SQLite handle crosses queues.
final class SQLiteDatabase {
    enum Value {
        case text(String), blob(Data), integer(Int64), real(Double), null
    }
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, readOnly: Bool = false, immutable: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let path = immutable ? url.absoluteString + "?immutable=1" : url.path
        let result = sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX | (immutable ? SQLITE_OPEN_URI : 0), nil)
        guard result == SQLITE_OK else {
            let error = failure(result)
            sqlite3_close(handle); handle = nil
            throw error
        }
        sqlite3_busy_timeout(handle, 5_000)
        if !readOnly {
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
        }
    }
    deinit { sqlite3_close(handle) }

    private func failure(_ code: Int32) -> NSError {
        NSError(domain: "WorkFollow.SQLite", code: Int(code), userInfo:
            [NSLocalizedDescriptionKey: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"])
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw failure(code) }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, transient)
                case .blob(let data):
                    result = data.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
                    }
                case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
                case .real(let number): result = sqlite3_bind_double(statement, index, number)
                case .null: result = sqlite3_bind_null(statement, index)
                }
                guard result == SQLITE_OK else { throw failure(result) }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }

    @discardableResult
    func execute(_ sql: String, _ values: [Value] = []) throws -> Int {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw failure(code) }
        return Int(sqlite3_changes(handle))
    }

    func rows(_ sql: String, _ values: [Value] = []) throws -> [[Data?]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [[Data?]] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { index in
                guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
                let count = Int(sqlite3_column_bytes(statement, index))
                guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
                return Data(bytes: bytes, count: count)
            })
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure(code) }
        return result
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func backup(to url: URL) throws {
        let target = try SQLiteDatabase(url: url)
        guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else {
            throw target.failure(sqlite3_errcode(target.handle))
        }
        let code = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard code == SQLITE_DONE, finish == SQLITE_OK else { throw target.failure(finish == SQLITE_OK ? code : finish) }
        try target.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
}
