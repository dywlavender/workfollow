import Foundation

enum DrawioResources {
    /// Bump when replacing the bundled archive; cached assets are never a network dependency.
    static let runtimeVersion = "1"

    static func prepare(bundle: Bundle = .main, cacheRoot: URL? = nil) async throws -> URL {
        guard let archive = bundle.url(forResource: "DrawioRuntime", withExtension: "zip"),
              let bridge = bundle.url(forResource: "DrawioBridge", withExtension: "html") else {
            throw Failure.missingResources
        }
        let root = (cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollow/Drawio", isDirectory: true))
            .appendingPathComponent(runtimeVersion, isDirectory: true)
        return try await _Concurrency.Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let entry = root.appendingPathComponent("drawio/index.html")
            if !fm.fileExists(atPath: entry.path) {
                try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
                defer { try? fm.removeItem(at: staging) }
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", archive.path, staging.path]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try unzip.run(); unzip.waitUntilExit()
                guard unzip.terminationStatus == 0,
                      fm.fileExists(atPath: staging.appendingPathComponent("drawio/index.html").path) else {
                    throw Failure.extractionFailed
                }
                if !fm.fileExists(atPath: root.path) { try fm.moveItem(at: staging, to: root) }
            }
            let target = root.appendingPathComponent("bridge.html")
            try Data(contentsOf: bridge).write(to: target, options: .atomic)
            return target
        }.value
    }

    enum Failure: LocalizedError {
        case missingResources, extractionFailed
        var errorDescription: String? {
            switch self {
            case .missingResources: "绘图资源缺失，请重新安装 WorkFollow。"
            case .extractionFailed: "绘图资源未能准备完成，请重新打开绘图窗口。"
            }
        }
    }
}
