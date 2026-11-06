import Foundation

enum MilkdownResources {
    private static let runtime = Runtime()
    static func prepare(bundle: Bundle = .main, cacheRoot: URL? = nil) async throws -> URL {
        guard let zip = bundle.url(forResource: "MilkdownRuntime", withExtension: "zip") else { throw Failure.missing }
        let root = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return try await runtime.prepare(zip: zip, root: root)
    }
    private actor Runtime {
        var tasks: [URL: _Concurrency.Task<URL, Error>] = [:]
        func prepare(zip: URL, root: URL) async throws -> URL {
            if let task = tasks[zip] { return try await task.value }
            let task = _Concurrency.Task.detached(priority: .userInitiated) {
                let info = try zip.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let version = "1-\(info.fileSize ?? 0)-\(Int(info.contentModificationDate?.timeIntervalSince1970 ?? 0))"
                let parent = root.appendingPathComponent("WorkFollow/Milkdown", isDirectory: true)
                let target = parent.appendingPathComponent(version, isDirectory: true)
                let index = target.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: index.path) { return index }
                let staging = parent.appendingPathComponent("staging-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-x", "-k", zip.path, staging.path]
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: staging.appendingPathComponent("milkdown.js").path) else { throw Failure.extraction }
                try FileManager.default.moveItem(at: staging, to: target)
                return index
            }
            tasks[zip] = task
            do { return try await task.value } catch { tasks[zip] = nil; throw error }
        }
    }
    enum Failure: LocalizedError {
        case missing, extraction
        var errorDescription: String? { "正文编辑器资源缺失或无法读取，请重新安装完整应用。" }
    }
}
