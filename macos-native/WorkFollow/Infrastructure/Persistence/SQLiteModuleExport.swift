import Foundation

enum SQLiteModuleExport {
    static func export(directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("focus.sqlite").path) {
            let store = SQLiteRecordStore<PomodoroRecord, FocusStore.Archive>(filename: "focus", directory: directory,
                newestFirst: true, timestamp: { $0.startedAt }, taskID: { $0.taskID }, migrate: { _ in
                    throw NSError(domain: "WorkFollow.Export", code: 1)
                })
            let snapshot = store.load()
            if let error = store.readError { throw error }
            guard var archive = snapshot?.metadata else { throw NSError(domain: "WorkFollow.Export", code: 2) }
            archive.records = snapshot?.records ?? []
            result["focus.json"] = try JSONEncoder().encode(archive)
        }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("task-activity.sqlite").path) {
            let store = SQLiteRecordStore<TaskActivityEvent, EmptyHistoryMetadata>(filename: "task-activity", directory: directory,
                timestamp: { $0.occurredAt }, taskID: { $0.taskID }, migrate: { _ in
                    throw NSError(domain: "WorkFollow.Export", code: 1)
                })
            let snapshot = store.load()
            if let error = store.readError { throw error }
            result["task-activity.json"] = try JSONEncoder().encode(snapshot?.records ?? [])
        }
        return result
    }
}
