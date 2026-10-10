import Foundation

struct NativeWorkspaceSnapshot: Codable {
    var version = 1
    let tasks: [Task]
    let notes: [Note]
    var taskLists: [String]? = nil
    /// 侧栏清单元数据（Round B1 additive）：旧快照没有该键，解码为 nil。
    var taskListMeta: [TaskListMeta]? = nil
    /// 清单文件夹（滴答层级第一级）。独立存储：允许空文件夹。
    var taskListFolders: [TaskListFolder]? = nil
    /// 清单内自定义分组（滴答第三级：清单 → 分组 → 任务）。
    var taskListSections: [TaskListSection]? = nil
    var noteFolders: [String]? = nil
    /// Full stable folder records; additive so older preview snapshots still decode.
    var noteFolderMetadata: [NoteFolderMeta]? = nil
}

/// Snapshot backup overview for the settings page.
struct SnapshotBackupInfo: Equatable {
    let count: Int
    let latestName: String?
    /// `workspace-YYYY-MM-DD` 的日期段，如 "2026-09-26"。
    let latestDateStamp: String?
}

/// Native-only storage; never reads or writes the Flutter WorkFollow directory.
final class NativePreviewRepository {
    static var directory: URL {
        #if DEBUG
        // Dedicated acceptance builds can use a separate bundle identity and
        // scratch data without replacing a user's active Focus session.
        if let path = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceStorageRoot") as? String,
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativePreview", isDirectory: true)
    }
    static let snapshotFileName = "workspace.json"
    static let backupFolderName = "backups"
    /// 每天保留一份快照，保留最近 7 天（与 Flutter LocalWorkspaceStore 一致）。
    static let backupRetentionDays = 7

    private let directory: URL
    init(directory: URL = NativePreviewRepository.directory) {
        self.directory = directory; database = SQLiteWorkspaceRepository(directory: directory)
    }
    private let database: SQLiteWorkspaceRepository
    var documentReadCount: Int { database.documentReadCount }
    var originalContentReadCount: Int { database.originalContentReadCount }
    var onDocumentFailure: ((Error) -> Void)? {
        get { database.onDocumentFailure }
        set { database.onDocumentFailure = newValue }
    }
    func loadDeferred() throws -> NativeWorkspaceSnapshot? { try database.load(deferred: true) }
    func load() throws -> NativeWorkspaceSnapshot? { try database.load() }
    func save(_ snapshot: NativeWorkspaceSnapshot) throws { try database.replace(snapshot) }
    func apply(_ batch: SQLiteWorkspaceRepository.Batch) throws { try database.apply(batch) }

    // MARK: 快照备份（对齐 Flutter LocalWorkspaceStore：每日备份 + 立即备份 + 恢复）

    var backupsDirectory: URL {
        directory.appendingPathComponent(Self.backupFolderName, isDirectory: true)
    }

    private static let backupStampFormatter: DateFormatter = posixFormatter("yyyy-MM-dd")
    private static let backupTimeFormatter: DateFormatter = posixFormatter("HHmmss")
    /// 匹配 `workspace-YYYY-MM-DD.json` 与 `workspace-YYYY-MM-DD-HHmmss.json`。
    private static let backupStampRegex = try! NSRegularExpression(pattern: #"^workspace-(\d{4}-\d{2}-\d{2})(?:-\d{6})?\.(?:json|sqlite)$"#)

    static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static func dayStamp(for date: Date) -> String {
        backupStampFormatter.string(from: date)
    }

    /// 备份文件名里的日期段（workspace-2026-09-26.json / workspace-2026-09-26-143025.json 都返回 2026-09-26）。
    func backupDateStamp(of url: URL) -> String? {
        let name = url.lastPathComponent
        let range = NSRange(name.startIndex..., in: name)
        guard let match = Self.backupStampRegex.firstMatch(in: name, range: range),
              let stampRange = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[stampRange])
    }

    /// 立即备份：用 SQLite backup API 生成包含已提交 WAL 的独立数据库。
    @discardableResult
    func backupNow(now: Date = Date()) throws -> URL? {
        guard try database.hasWorkspace() else { return nil }
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let target = backupsDirectory.appendingPathComponent(
            "workspace-\(Self.dayStamp(for: now))-\(Self.backupTimeFormatter.string(from: now)).sqlite")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try database.backup(to: target)
        return target
    }

    /// backups/ 下所有符合命名规则的快照备份，按文件名（即时间）升序。
    func listBackups() -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path) else { return [] }
        return names
            .filter { ($0.lowercased().hasSuffix(".json") || $0.lowercased().hasSuffix(".sqlite")) && backupDateStamp(of: backupsDirectory.appendingPathComponent($0)) != nil }
            .sorted()
            .map { backupsDirectory.appendingPathComponent($0) }
    }

    func backupInfo() -> SnapshotBackupInfo {
        let backups = listBackups()
        guard let latest = backups.last else { return SnapshotBackupInfo(count: 0, latestName: nil, latestDateStamp: nil) }
        return SnapshotBackupInfo(count: backups.count,
                                  latestName: latest.lastPathComponent,
                                  latestDateStamp: backupDateStamp(of: latest))
    }

    /// 每天首次成功写入后生成 backups/workspace-<日期>.sqlite，
    /// 并只保留最近 7 份。备份簿记失败绝不影响保存本身。
    func maintainDailyBackup(now: Date = Date(), retentionLimit: Int? = nil) {
        let retentionDays = retentionLimit ?? Self.backupRetentionDays
        do {
            let stamp = Self.dayStamp(for: now)
            if try database.hasWorkspace(),
               !listBackups().contains(where: { backupDateStamp(of: $0) == stamp }) {
                try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                try database.backup(to: backupsDirectory.appendingPathComponent("workspace-\(stamp).sqlite"))
            }
            let all = listBackups()
            if all.count > retentionDays {
                for stale in all.prefix(all.count - retentionDays) {
                    try? FileManager.default.removeItem(at: stale)
                }
            }
        } catch {
            // 备份失败不打断保存流程。
        }
    }

    /// 恢复备份：先校验目标文件能解码为快照，再备份当前内容，最后用事务替换工作区。
    func restoreBackup(at url: URL, now: Date = Date()) throws {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let sqlite = url.appendingPathComponent(SQLiteWorkspaceRepository.filename)
            try restoreBackup(at: FileManager.default.fileExists(atPath: sqlite.path)
                ? sqlite : url.appendingPathComponent(Self.snapshotFileName), now: now)
            return
        }
        let snapshot: NativeWorkspaceSnapshot
        if url.pathExtension == "sqlite" {
            // Read the backup directly; do not mutate it or create sidecar files.
            let source = SQLiteWorkspaceRepository(directory: url.deletingLastPathComponent())
            snapshot = try source.readBackup(at: url)
        } else {
            snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: Data(contentsOf: url))
        }
        guard snapshot.version == 1 else {
            throw NSError(domain: "NativePreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "备份版本不兼容，无法恢复。"])
        }
        if try database.hasWorkspace() { try backupNow(now: now) }
        try database.replace(snapshot)
    }
}
