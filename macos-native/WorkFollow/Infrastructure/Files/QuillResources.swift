import Foundation

/// Quill 运行时的解包与版本化（对齐 DrawioResources）：
/// bundle 里的 `QuillRuntime.zip` 解压到 `Caches/WorkFollow/Quill/<version>/`，
/// bridge.html 每次原子覆盖，按 `runtimeVersion` 失效缓存。
enum QuillResources {
    /// 换包（升级 Quill / 改 bridge）时递增。
    static let runtimeVersion = "1"

    enum Failure: LocalizedError {
        case missingResources
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .missingResources: "缺少 QuillRuntime.zip 或 QuillBridge.html"
            case .extractionFailed: "Quill 运行时解压失败"
            }
        }
    }

    static func prepare(bundle: Bundle = .main,
                        cacheRoot: URL? = nil) async throws -> URL {
        guard let zip = bundle.url(forResource: "QuillRuntime", withExtension: "zip"),
              let bridge = bundle.url(forResource: "QuillBridge", withExtension: "html") else {
            throw Failure.missingResources
        }
        let caches = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let versionDir = caches.appendingPathComponent("WorkFollow/Quill/\(runtimeVersion)")
        let index = versionDir.appendingPathComponent("quill/quill.js")
        if !FileManager.default.fileExists(atPath: index.path) {
            try? FileManager.default.removeItem(at: versionDir)
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            // staging 放在版本目录**外**，避免把中间目录一起搬进去。
            let staging = caches.appendingPathComponent("WorkFollow/Quill/staging-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zip.path, staging.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: staging.appendingPathComponent("quill/quill.js").path) else {
                try? FileManager.default.removeItem(at: staging)
                throw Failure.extractionFailed
            }
            try FileManager.default.moveItem(at: staging.appendingPathComponent("quill"),
                                             to: versionDir.appendingPathComponent("quill"))
            try? FileManager.default.removeItem(at: staging)
        }
        // bridge 每次覆盖：它的更新频率高于运行时。
        let bridgeTarget = versionDir.appendingPathComponent("bridge.html")
        let stagingBridge = versionDir.appendingPathComponent("bridge-\(UUID().uuidString).html")
        try Data(contentsOf: bridge).write(to: stagingBridge)
        _ = try FileManager.default.replaceItemAt(bridgeTarget, withItemAt: stagingBridge)
        return bridgeTarget
    }
}
