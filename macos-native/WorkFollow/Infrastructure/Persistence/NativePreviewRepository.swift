import Foundation

struct NativeWorkspaceSnapshot: Codable {
    var version = 1
    let tasks: [Task]
    let notes: [Note]
    var taskLists: [String]? = nil
    /// 侧栏清单元数据（Round B1 additive）：旧快照没有该键，解码为 nil。
    var taskListMeta: [TaskListMeta]? = nil
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
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativePreview", isDirectory: true)
    }
    static let snapshotFileName = "workspace.json"
    static let backupFolderName = "backups"
    /// 每天保留一份快照，保留最近 7 天（与 Flutter LocalWorkspaceStore 一致）。
    static let backupRetentionDays = 7

    private let directory: URL
    private var file: URL { directory.appendingPathComponent(Self.snapshotFileName) }
    init(directory: URL = NativePreviewRepository.directory) { self.directory = directory }
    func load() throws -> NativeWorkspaceSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.version == 1 else {
            throw NSError(domain: "NativePreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "预览数据版本不兼容，已停止自动保存，原文件未改动。"])
        }
        return snapshot
    }
    func save(_ snapshot: NativeWorkspaceSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: file, options: .atomic)
    }

    // MARK: 快照备份（对齐 Flutter LocalWorkspaceStore：每日备份 + 立即备份 + 恢复）

    var backupsDirectory: URL {
        directory.appendingPathComponent(Self.backupFolderName, isDirectory: true)
    }

    private static let backupStampFormatter: DateFormatter = posixFormatter("yyyy-MM-dd")
    private static let backupTimeFormatter: DateFormatter = posixFormatter("HHmmss")
    /// 匹配 `workspace-YYYY-MM-DD.json` 与 `workspace-YYYY-MM-DD-HHmmss.json`。
    private static let backupStampRegex = try! NSRegularExpression(pattern: #"^workspace-(\d{4}-\d{2}-\d{2})(?:-\d{6})?\.json$"#)

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

    /// 立即备份：workspace.json 复制为 backups/workspace-<日期>-<时刻>.json。
    @discardableResult
    func backupNow(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let target = backupsDirectory.appendingPathComponent(
            "workspace-\(Self.dayStamp(for: now))-\(Self.backupTimeFormatter.string(from: now)).json")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }

    /// backups/ 下所有符合命名规则的快照备份，按文件名（即时间）升序。
    func listBackups() -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path) else { return [] }
        return names
            .filter { $0.lowercased().hasSuffix(".json") && backupDateStamp(of: backupsDirectory.appendingPathComponent($0)) != nil }
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

    /// 每天首次成功写入后把 workspace.json 复制为 backups/workspace-<日期>.json，
    /// 并只保留最近 7 份。备份簿记失败绝不影响保存本身。
    func maintainDailyBackup(now: Date = Date(), retentionLimit: Int? = nil) {
        let retentionDays = retentionLimit ?? Self.backupRetentionDays
        do {
            let stamp = Self.dayStamp(for: now)
            if FileManager.default.fileExists(atPath: file.path),
               !listBackups().contains(where: { backupDateStamp(of: $0) == stamp }) {
                try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(
                    at: file,
                    to: backupsDirectory.appendingPathComponent("workspace-\(stamp).json"))
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

    /// 恢复备份：先校验目标文件能解码为快照，再备份当前内容，最后原子写入。
    func restoreBackup(at url: URL, now: Date = Date()) throws {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: data)
        guard snapshot.version == 1 else {
            throw NSError(domain: "NativePreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "备份版本不兼容，无法恢复。"])
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try backupNow(now: now)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
