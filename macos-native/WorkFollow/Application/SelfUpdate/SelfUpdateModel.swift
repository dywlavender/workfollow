import AppKit
import CryptoKit
import Foundation

/// 应用内自更新（本地目录通道）。职责链：读 manifest → 比 build → 暂存并
/// 校验 zip → 复制 workfollowctl 到暂存区 → 写交接请求 → 拉起暂存区里的
/// helper 并优雅退出。真正的备份/落位/回滚/重启都在 helper（workfollowctl
/// apply-update）里做——「自己替换自己」必须由独立进程执行。
@MainActor
final class SelfUpdateModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case upToDate
        case available(SelfUpdateMode)
        case preparing(Double)   // 0…1，本地目录通道只有拷贝，几乎瞬完
        case handingOff
        case failed(String)
    }

    struct Discovery: Equatable {
        var manifest: SelfUpdateManifest
        var mode: SelfUpdateMode
        var package: SelfUpdateManifest.Package

        var title: String { "\(manifest.version) (\(manifest.build))" }
        /// 热更包大小展示（full 包不标，196M 是已知全量）。
        var sizeHint: String? {
            mode == .hot ? ByteCountFormatter.string(fromByteCount: Int64(package.bytes),
                                                     countStyle: .file) : nil
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// helper 上次执行结果（本次会话读到的落盘状态），设置页展示。
    @Published private(set) var lastResult: String?

    // 通道路径与上次结果直接落 UserDefaults.standard。模型不是 View，
    // 不用 @AppStorage——它只在 SwiftUI 视图里发布变更。
    static let channelPathKey = "selfupdate.channelPath"
    static let lastStatusKey = "selfupdate.lastStatus"

    private let fileManager = FileManager.default
    private var defaults: UserDefaults { .standard }
    /// 测试注入点：三个根路径都可覆盖，默认指向真实数据目录。
    private let dataRootOverride: URL?
    private let backupRootOverride: URL?
    private let statusURLOverride: URL?
    /// 测试注入点：helper 可执行文件（正式路径取 Bundle 内的 workfollowctl）。
    private let helperURLOverride: URL?

    init(dataRoot: URL? = nil, backupRoot: URL? = nil, statusURL: URL? = nil,
         helperURL: URL? = nil) {
        self.dataRootOverride = dataRoot
        self.backupRootOverride = backupRoot
        self.statusURLOverride = statusURL
        self.helperURLOverride = helperURL
    }

    var channelDirectory: URL? {
        get {
            let path = defaults.string(forKey: Self.channelPathKey) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
        }
        set { defaults.set(newValue?.path ?? "", forKey: Self.channelPathKey) }
    }
    private var storedStatus: String {
        get { defaults.string(forKey: Self.lastStatusKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.lastStatusKey) }
    }

    /// 与 workfollowctl 的 workspaceDirectory、脚本回滚目录同一片根。
    private var dataRoot: URL {
        dataRootOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativePreview", isDirectory: true)
    }
    private var stagingRoot: URL { dataRoot.appendingPathComponent("selfupdate", isDirectory: true) }
    private var helperStatusURL: URL {
        statusURLOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativeUpdates/selfupdate-status.json")
    }
    var hasBackup: Bool {
        fileManager.fileExists(atPath: backupDirectory.appendingPathComponent("WorkFollow.app").path)
    }
    /// 备份存在即可恢复上一版本。
    var previousRollbackAvailable: Bool { hasBackup }
    private var backupDirectory: URL {
        backupRootOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativeUpdates/selfupdate-backup", isDirectory: true)
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    static var versionLabel: String { "\(currentVersion) (\(currentBuild))" }

    // MARK: - 检查

    /// 读取通道目录的 manifest 并与当前 build 比较。抛错原因进 failed 态。
    func check() throws -> Discovery? {
        phase = .idle
        lastResult = storedStatus.isEmpty ? nil : storedStatus
        guard let directory = channelDirectory else { throw SelfUpdateError.channelNotSet }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SelfUpdateError.manifestMissing
        }
        let manifest: SelfUpdateManifest
        do {
            manifest = try JSONDecoder().decode(SelfUpdateManifest.self,
                                                from: Data(contentsOf: manifestURL))
        } catch {
            throw SelfUpdateError.manifestCorrupted(String(describing: error))
        }
        let current = Self.currentBuild
        guard manifest.build > current else {
            phase = .upToDate
            return nil
        }
        let mode = manifest.preferredMode(currentBuild: current)
        let discovery = Discovery(manifest: manifest, mode: mode,
                                  package: manifest.package(for: mode))
        phase = .available(mode)
        return discovery
    }

    /// 静默检查（启动时调用）：异常吞掉，只留设置页可见的状态。
    func checkSilently() {
        do {
            _ = try check()
            if case .available = phase {
                lastResult = "发现新版，可在设置里安装。"
            }
        } catch {
            // 静默失败不打扰：目录没设/同步未完成都是日常态。
            phase = .idle
        }
    }

    // MARK: - 暂存与交接

    /// 校验并把 zip 复制进暂存区；成功后即可 handOff。
    func prepare(_ discovery: Discovery) throws {
        phase = .preparing(0)
        let directory = try requireChannel()
        let source = directory.appendingPathComponent(discovery.package.file)
        guard fileManager.fileExists(atPath: source.path) else {
            throw SelfUpdateError.channelIncomplete("缺少 \(discovery.package.file)")
        }
        let staging = try makeStaging()
        let stagedZip = staging.appendingPathComponent("update.zip")
        try? fileManager.removeItem(at: stagedZip)
        try fileManager.copyItem(at: source, to: stagedZip)
        phase = .preparing(0.5)
        let digest = try SelfUpdateHashing.sha256(ofFileAt: stagedZip)
        guard digest == discovery.package.sha256.lowercased() else {
            throw SelfUpdateError.checksumMismatch(
                "哈希不符（发布目录可能仍在同步），稍后重试。")
        }
        phase = .preparing(0.9)
        try writeRequest(discovery: discovery, staging: staging)
        try copyHelper(to: staging)
        phase = .preparing(1)
    }

    /// 拉起暂存区里的 helper（独立进程，活得比本进程久），然后优雅退出。
    /// helper 等 App 退出后执行备份/落位/回滚/重启。
    func handOff() throws {
        let staging = try requireStaging()
        let helper = staging.appendingPathComponent("workfollowctl")
        guard fileManager.fileExists(atPath: helper.path) else {
            throw SelfUpdateError.helperMissing
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["apply-update", "--request",
                             staging.appendingPathComponent("update-request.json").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw SelfUpdateError.handOffFailed(String(describing: error))
        }
        phase = .handingOff
        // applicationShouldTerminate 会 flush 各 store（terminateLater + reply）。
        NSApp.terminate(nil)
    }

    /// 设置页「恢复上一版本」：让 helper 把备份换回 /Applications。
    func restorePrevious() throws {
        guard hasBackup else { throw SelfUpdateError.handOffFailed("没有可用的备份。") }
        let staging = try makeStaging()
        let request: [String: Any] = [
            "mode": "restore",
            "target": targetAppURL.path,
            "backupDir": backupDirectory.path,
            "statusPath": helperStatusURL.path,
        ]
        try writeJSON(request, to: staging.appendingPathComponent("update-request.json"))
        try copyHelper(to: staging)
        let helper = staging.appendingPathComponent("workfollowctl")
        let process = Process()
        process.executableURL = helper
        process.arguments = ["apply-update", "--request",
                             staging.appendingPathComponent("update-request.json").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        phase = .handingOff
        NSApp.terminate(nil)
    }

    /// 下次启动读取 helper 落盘的结果。
    func consumeHelperStatus() {
        guard let data = try? Data(contentsOf: helperStatusURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let message = payload["message"] as? String, !message.isEmpty {
            storedStatus = message
            lastResult = message
        }
        try? fileManager.removeItem(at: helperStatusURL)
    }

    // MARK: - 内部

    private var targetAppURL: URL {
        URL(fileURLWithPath: "/Applications/WorkFollow.app", isDirectory: true)
    }

    private func requireChannel() throws -> URL {
        guard let directory = channelDirectory else { throw SelfUpdateError.channelNotSet }
        return directory
    }

    private func requireStaging() throws -> URL {
        let staging = stagingRoot
        guard fileManager.fileExists(atPath: staging.path) else {
            throw SelfUpdateError.stagingFailed("请先完成暂存。")
        }
        return staging
    }

    private func makeStaging() throws -> URL {
        let staging = stagingRoot
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    private func writeRequest(discovery: Discovery, staging: URL) throws {
        let request: [String: Any] = [
            "mode": discovery.mode.rawValue,
            "target": targetAppURL.path,
            "zip": staging.appendingPathComponent("update.zip").path,
            "backupDir": backupDirectory.path,
            "statusPath": helperStatusURL.path,
            "build": discovery.manifest.build,
        ]
        try writeJSON(request, to: staging.appendingPathComponent("update-request.json"))
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// helper 从暂存区跑，避免它所在的旧 bundle 被自己替换。
    private func copyHelper(to staging: URL) throws {
        let embedded = helperURLOverride
            ?? Bundle.main.url(forResource: "workfollowctl", withExtension: nil)
        guard let embedded else { throw SelfUpdateError.helperMissing }
        let destination = staging.appendingPathComponent("workfollowctl")
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: embedded, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }
}
