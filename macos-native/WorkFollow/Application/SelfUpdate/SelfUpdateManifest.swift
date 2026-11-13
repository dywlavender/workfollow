import CryptoKit
import Foundation

/// 本地目录更新通道的发布清单。与 `local-app.py release` 写出的 manifest.json
/// 字段一一对应；build 号（CFBundleVersion 递增整数）是唯一的版本比较口径。
struct SelfUpdateManifest: Codable, Equatable {
    var version: String
    var build: Int
    var notes: String?
    var releasedAt: String?
    var packages: Packages

    struct Packages: Codable, Equatable {
        var full: Package
        /// 差分包：与 `fromBuild` 这一版做的文件级 diff。客户端当前 build
        /// 不等于 fromBuild 时必须回落 full 包。
        var hot: HotPackage?
    }

    struct Package: Codable, Equatable {
        var file: String
        var bytes: Int
        var sha256: String
    }

    struct HotPackage: Codable, Equatable {
        var file: String
        var bytes: Int
        var sha256: String
        var fromBuild: Int
        /// zip 内的相对路径（`Contents/…`）与逐文件哈希；客户端解压后不再逐个
        /// 校验——zip 本体的 sha256 在暂存阶段已核过。
        var files: [FileEntry]
    }

    struct FileEntry: Codable, Equatable {
        var path: String
        var sha256: String
    }
}

extension SelfUpdateManifest {
    /// 客户端该用哪种包：热更只对 fromBuild 精确生效，其余一律全量。
    /// 无热更包（首次发布/无 diff）也回落全量。
    func preferredMode(currentBuild: Int) -> SelfUpdateMode {
        if let hot = packages.hot, hot.fromBuild == currentBuild { return .hot }
        return .full
    }

    func package(for mode: SelfUpdateMode) -> SelfUpdateManifest.Package {
        mode == .hot ? packages.hot!.asPackage : packages.full
    }
}

enum SelfUpdateMode: String, Equatable {
    case hot, full
}

extension SelfUpdateManifest.HotPackage {
    var asPackage: SelfUpdateManifest.Package {
        .init(file: file, bytes: bytes, sha256: sha256)
    }
}

enum SelfUpdateError: LocalizedError {
    case channelNotSet
    case manifestMissing
    case manifestCorrupted(String)
    case channelIncomplete(String)
    case checksumMismatch(String)
    case stagingFailed(String)
    case helperMissing
    case handOffFailed(String)

    var errorDescription: String? {
        switch self {
        case .channelNotSet: return "尚未设置更新目录。"
        case .manifestMissing: return "更新目录里没有 manifest.json（可能是同步未完成）。"
        case .manifestCorrupted(let detail): return "manifest.json 无法解析：\(detail)"
        case .channelIncomplete(let detail): return "更新目录不完整：\(detail)"
        case .checksumMismatch(let detail): return "更新包校验失败：\(detail)"
        case .stagingFailed(let detail): return "暂存更新包失败：\(detail)"
        case .helperMissing: return "应用内缺少更新执行器（workfollowctl）。"
        case .handOffFailed(let detail): return "更新交接失败：\(detail)"
        }
    }
}

enum SelfUpdateHashing {
    /// 分块计算文件 SHA-256（更新包最大 ~200M，不能整读进内存）。
    static func sha256(ofFileAt url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SelfUpdateError.channelIncomplete("文件不存在：\(url.lastPathComponent)")
        }
        guard let stream = InputStream(url: url) else {
            throw SelfUpdateError.stagingFailed("无法读取：\(url.lastPathComponent)")
        }
        stream.open()
        defer { stream.close() }
        var digest = SHA256()
        let bufferSize = 512 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 { throw SelfUpdateError.stagingFailed("读取失败：\(url.lastPathComponent)") }
            if read == 0 { break }
            digest.update(data: Data(buffer[0..<read]))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
