import Foundation

/// Quill 运行时的解包与版本化（对齐 DrawioResources）：
/// bundle 里的 `QuillRuntime.zip`（quill dist + 编辑器 Web 组件）解压到
/// `Caches/WorkFollow/Quill/<version>/`，按 `runtimeVersion` 失效缓存。
/// zip 内容：`quill/quill.js`、`quill/quill.snow.css`、`index.html`、
/// `editor.css`、`bridge.js`、`toolbar.js`、`slash-menu.js`、`markdown.js`、`blots.js`。
enum QuillResources {
    /// 换包（升级 Quill / 改 Web 组件）时递增。
    static let runtimeVersion = "15"

    enum Failure: LocalizedError {
        case missingResources
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .missingResources: "缺少 QuillRuntime.zip"
            case .extractionFailed: "Quill 运行时解压失败"
            }
        }
    }

    /// 返回 index.html 的地址（scheme handler 的挂载目录即其所在目录）。
    static func prepare(bundle: Bundle = .main,
                        cacheRoot: URL? = nil) async throws -> URL {
        guard let zip = bundle.url(forResource: "QuillRuntime", withExtension: "zip") else {
            throw Failure.missingResources
        }
        let caches = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let versionDir = caches.appendingPathComponent("WorkFollow/Quill/\(runtimeVersion)")
        let index = versionDir.appendingPathComponent("index.html")
        guard !FileManager.default.fileExists(atPath: index.path) else { return index }
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
              FileManager.default.fileExists(atPath: staging.appendingPathComponent("index.html").path),
              FileManager.default.fileExists(atPath: staging.appendingPathComponent("quill/quill.js").path) else {
            try? FileManager.default.removeItem(at: staging)
            throw Failure.extractionFailed
        }
        for entry in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            try FileManager.default.moveItem(at: entry, to: versionDir.appendingPathComponent(entry.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: staging)
        return index
    }
}
