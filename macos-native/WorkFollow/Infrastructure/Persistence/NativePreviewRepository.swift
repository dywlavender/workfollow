import Foundation

struct NativeWorkspaceSnapshot: Codable {
    var version = 1
    let tasks: [Task]
    let notes: [Note]
}

/// Native-only storage; never reads or writes the Flutter WorkFollow directory.
final class NativePreviewRepository {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativePreview", isDirectory: true)
    }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("workspace.json") }
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
}
