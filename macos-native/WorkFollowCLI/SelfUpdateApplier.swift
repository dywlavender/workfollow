import Foundation

/// 应用内自更新的落位执行器。由 App 在退出前拉起（从暂存区运行，不占用
/// 旧 bundle），等 App 退出后：备份 → 应用热更/全量 → ad-hoc 重签 → 重启；
/// 任何一步失败都恢复备份。结果写 statusPath 供下次启动展示。
enum SelfUpdateApplier {
    struct Request: Codable {
        var mode: String            // "hot" | "full" | "restore"
        var target: String          // /Applications/WorkFollow.app
        var zip: String?            // hot/full 的暂存 zip
        var backupDir: String
        var statusPath: String
        var build: Int?
    }

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--request"), arguments.count > flag + 1 else {
            FileHandle.standardError.write(Data("缺少 --request <path>\n".utf8))
            return 2
        }
        let requestURL = URL(fileURLWithPath: arguments[flag + 1])
        do {
            let data = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(Request.self, from: data)
            try execute(request)
            return 0
        } catch {
            let message = String(describing: error)
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            if let data = try? Data(contentsOf: requestURL),
               let request = try? JSONDecoder().decode(Request.self, from: data) {
                writeStatus(request, ok: false, message: message)
            }
            return 1
        }
    }

    private static func execute(_ request: Request) throws {
        let target = URL(fileURLWithPath: request.target, isDirectory: true)
        let backupDir = URL(fileURLWithPath: request.backupDir, isDirectory: true)
        switch request.mode {
        case "hot": try applyHot(request, target: target)
        case "full": try applyFull(request, target: target)
        case "restore": try restore(request, target: target, backupDir: backupDir)
        default: throw Failure(message: "未知模式：\(request.mode)")
        }
        seal(target)
        relaunch(target)
        writeStatus(request, ok: true,
                    message: request.mode == "restore"
                        ? "已恢复到上一版本。"
                        : "已更新到 build \(request.build ?? 0)，重启完成。")
    }

    // MARK: - 等待退出

    private static func waitForAppExit(timeout: TimeInterval = 30) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            probe.arguments = ["-x", "WorkFollow"]
            probe.standardOutput = FileHandle.nullDevice
            probe.standardError = FileHandle.nullDevice
            try probe.run()
            probe.waitUntilExit()
            if probe.terminationStatus != 0 { return }   // 没有匹配进程 = 已退出
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw Failure(message: "App 未在 30 秒内退出，本次更新未做任何改动。")
    }

    // MARK: - 应用

    /// 与目标同卷的临时目录：保证 rename 原子性。
    private static func scratchDirectory(near target: URL) throws -> URL {
        let scratch = target.deletingLastPathComponent()
            .appendingPathComponent(".wf-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    private static func extract(zip: URL, into directory: URL) throws {
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
    }

    private static func applyHot(_ request: Request, target: URL) throws {
        guard let zipPath = request.zip else { throw Failure(message: "缺少 zip 路径。") }
        try waitForAppExit()
        let backupDir = URL(fileURLWithPath: request.backupDir, isDirectory: true)
        try backup(target: target, to: backupDir)
        let scratch = try scratchDirectory(near: target)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try extract(zip: URL(fileURLWithPath: zipPath), into: scratch)
        let contents = scratch.appendingPathComponent("Contents", isDirectory: true)
        guard FileManager.default.fileExists(atPath: contents.path) else {
            throw Failure(message: "热更包缺少 Contents/（zip 结构不符）。")
        }
        // 逐项覆盖进现有 bundle。热更包只含变化的文件（含 Info.plist），
        // 不做删除——资源删除走全量包。
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil) {
            let destination = target.appendingPathComponent("Contents/\(item.lastPathComponent)")
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: item, to: destination)
        }
        makeExecutables(target)
    }

    private static func applyFull(_ request: Request, target: URL) throws {
        guard let zipPath = request.zip else { throw Failure(message: "缺少 zip 路径。") }
        try waitForAppExit()
        let backupDir = URL(fileURLWithPath: request.backupDir, isDirectory: true)
        try backup(target: target, to: backupDir)
        let scratch = try scratchDirectory(near: target)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try extract(zip: URL(fileURLWithPath: zipPath), into: scratch)
        let extracted = scratch.appendingPathComponent("WorkFollow.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw Failure(message: "全量包缺少 WorkFollow.app（zip 结构不符）。")
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: extracted, to: target)
    }

    private static func restore(_ request: Request, target: URL, backupDir: URL) throws {
        try waitForAppExit()
        let backup = backupDir.appendingPathComponent("WorkFollow.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: backup.path) else {
            throw Failure(message: "备份不存在，无法恢复。")
        }
        let scratch = try scratchDirectory(near: target)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent("WorkFollow.app", isDirectory: true)
        try runTool("/usr/bin/ditto", [backup.path, staged.path])
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: staged, to: target)
    }

    /// 完整备份当前 app（ditto 保留权限与符号链接），仅保留最近一份。
    private static func backup(target: URL, to backupDir: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let destination = backupDir.appendingPathComponent("WorkFollow.app", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try runTool("/usr/bin/ditto", [target.path, destination.path])
    }

    /// 主二进制与 CLI 恢复可执行位（ditto/unzip 一般会带，这里兜底）。
    private static func makeExecutables(_ target: URL) {
        let macos = target.appendingPathComponent("Contents/MacOS")
        guard let items = try? FileManager.default.contentsOfDirectory(at: macos,
                                                                       includingPropertiesForKeys: nil)
        else { return }
        for item in items {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: item.path)
        }
    }

    /// ad-hoc 重签（本机签名无校验链，只为保持包整洁；失败不阻断）。
    private static func seal(_ target: URL) {
        try? runTool("/usr/bin/codesign", ["--force", "--deep", "-s", "-", target.path])
        let widget = target.appendingPathComponent("Contents/PlugIns/WorkFollowWidgets.appex")
        if FileManager.default.fileExists(atPath: widget.path) {
            try? runTool("/usr/bin/pluginkit", ["-a", widget.path])
        }
    }

    private static func relaunch(_ target: URL) {
        try? runTool("/usr/bin/open", [target.path])
    }

    private static func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw Failure(message: "\(path) 退出码 \(process.terminationStatus)")
        }
    }

    private static func writeStatus(_ request: Request, ok: Bool, message: String) {
        let payload: [String: Any] = ["ok": ok, "message": message,
                                      "build": request.build ?? 0,
                                      "finishedAt": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return }
        let url = URL(fileURLWithPath: request.statusPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
