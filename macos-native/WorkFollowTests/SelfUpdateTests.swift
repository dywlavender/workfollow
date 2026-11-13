import CryptoKit
import XCTest
@testable import WorkFollow

/// 应用内自更新（本地目录通道）：manifest 解析、包选择、哈希校验与暂存。
/// 落位/回滚在 workfollowctl apply-update（进程级行为，不在单测覆盖）。
@MainActor
final class SelfUpdateTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        UserDefaults.standard.removeObject(forKey: SelfUpdateModel.channelPathKey)
        super.tearDown()
    }

    /// 每个测试用独立目录；提前建好，路径在整个用例里保持一致。
    private func newDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selfupdate-test-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    private func makeManifest(build: Int, fromBuild: Int? = nil,
                              sha256: String = String(repeating: "a", count: 64)) -> SelfUpdateManifest {
        SelfUpdateManifest(
            version: "0.2.0", build: build, notes: "测试更新", releasedAt: nil,
            packages: .init(
                full: .init(file: "WorkFollow-0.2.0-\(build)-full.zip", bytes: 100, sha256: sha256),
                hot: fromBuild.map {
                    .init(file: "WorkFollow-0.2.0-\(build)-hot.zip", bytes: 10, sha256: sha256,
                          fromBuild: $0,
                          files: [.init(path: "Contents/MacOS/WorkFollow", sha256: sha256)])
                }))
    }

    // MARK: - 包选择

    func testHotPackageOnlyAppliesToExactFromBuild() {
        let manifest = makeManifest(build: 60, fromBuild: 59)
        XCTAssertEqual(manifest.preferredMode(currentBuild: 59), .hot)
        XCTAssertEqual(manifest.preferredMode(currentBuild: 55), .full,
                       "跳版本的客户端必须回落全量包")
        XCTAssertEqual(manifest.preferredMode(currentBuild: 60), .full,
                       "已是当前版不适用（调用方先用 build>current 过滤）")
    }

    func testMissingHotPackageFallsBackToFull() {
        let manifest = makeManifest(build: 60, fromBuild: nil)
        XCTAssertEqual(manifest.preferredMode(currentBuild: 59), .full)
        XCTAssertNil(manifest.packages.hot)
    }

    func testManifestDecodesPublishedShape() throws {
        // 与 local-app.py release 写出的字段一一对应（camelCase）。
        let json = """
        {"version":"0.2.0","build":60,"notes":"目录栏图标","releasedAt":"2026-11-13T09:00:00+0800",
         "packages":{"full":{"file":"WorkFollow-0.2.0-60-full.zip","bytes":1,"sha256":"\(String(repeating: "b", count: 64))"},
                     "hot":{"file":"WorkFollow-0.2.0-60-hot.zip","bytes":2,"sha256":"\(String(repeating: "c", count: 64))",
                            "fromBuild":59,"files":[{"path":"Contents/Info.plist","sha256":"\(String(repeating: "d", count: 64))"}]}}}
        """
        let manifest = try JSONDecoder().decode(SelfUpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.build, 60)
        XCTAssertEqual(manifest.packages.hot?.fromBuild, 59)
        XCTAssertEqual(manifest.packages.hot?.files.first?.path, "Contents/Info.plist")
        XCTAssertEqual(manifest.preferredMode(currentBuild: 59), .hot)
    }

    // MARK: - 哈希

    func testSha256MatchesKnownDigest() throws {
        let directory = newDirectory()
        let url = directory.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: url)
        // echo -n hello | shasum -a 256
        XCTAssertEqual(try SelfUpdateHashing.sha256(ofFileAt: url),
                       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testSha256RejectsMissingFile() {
        XCTAssertThrowsError(try SelfUpdateHashing.sha256(ofFileAt: newDirectory().appendingPathComponent("nope")))
    }

    // MARK: - 检查与暂存

    /// 在通道目录里打一个真实 zip（ditto），供哈希计算与下载模拟。
    private func publishZip(_ channel: URL, zipName: String, content: String) throws {
        try FileManager.default.createDirectory(at: channel, withIntermediateDirectories: true)
        let zipDirectory = channel.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: zipDirectory, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: zipDirectory.appendingPathComponent("sample.txt"))
        try runTool("/usr/bin/ditto", ["-c", "-k", zipDirectory.path, channel.appendingPathComponent(zipName).path])
    }

    private func writeManifest(_ channel: URL, _ manifest: SelfUpdateManifest) throws {
        try JSONEncoder().encode(manifest).write(to: channel.appendingPathComponent("manifest.json"))
    }

    private func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testCheckRejectsOlderManifestBuild() throws {
        let channel = newDirectory()
        try publishZip(channel, zipName: "full.zip", content: "x")
        try writeManifest(channel, makeManifest(build: 1))
        let model = SelfUpdateModel()
        model.channelDirectory = channel
        XCTAssertNil(try model.check())
        if case .upToDate = model.phase {} else { XCTFail("应当是 upToDate") }
    }

    func testPrepareStagesVerifiedZipRequestAndHelper() throws {
        let channel = newDirectory()
        let dataRoot = newDirectory()
        let backupRoot = newDirectory()
        let statusURL = newDirectory().appendingPathComponent("status.json")

        // 先按 manifest 命名规则打 zip → 算真实哈希 → 发布 manifest。
        let build = SelfUpdateModel.currentBuild + 10
        let zipName = "WorkFollow-0.2.0-\(build)-hot.zip"
        try publishZip(channel, zipName: zipName, content: "热更载荷")
        let realSHA = try SelfUpdateHashing.sha256(ofFileAt: channel.appendingPathComponent(zipName))
        try writeManifest(channel, makeManifest(build: build,
                                                fromBuild: SelfUpdateModel.currentBuild,
                                                sha256: realSHA))

        // 测试宿主是精简 runner，没有内嵌 workfollowctl：造一个假执行器
        // 验证复制与权限位。
        let fakeHelper = newDirectory().appendingPathComponent("workfollowctl")
        try Data("#!/bin/sh\n".utf8).write(to: fakeHelper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHelper.path)
        let model = SelfUpdateModel(dataRoot: dataRoot, backupRoot: backupRoot, statusURL: statusURL,
                                    helperURL: fakeHelper)
        model.channelDirectory = channel

        let discovery = try XCTUnwrap(try model.check())
        XCTAssertEqual(discovery.mode, .hot)
        try model.prepare(discovery)

        let staging = dataRoot.appendingPathComponent("selfupdate", isDirectory: true)
        let stagedZip = staging.appendingPathComponent("update.zip")
        XCTAssertEqual(try SelfUpdateHashing.sha256(ofFileAt: stagedZip), realSHA)
        // 交接请求：模式、目标、哈希过审的 zip 路径
        let request = try JSONSerialization.jsonObject(
            with: Data(contentsOf: staging.appendingPathComponent("update-request.json"))) as! [String: Any]
        XCTAssertEqual(request["mode"] as? String, "hot")
        XCTAssertEqual(request["zip"] as? String, stagedZip.path)
        XCTAssertEqual(request["build"] as? Int, build)
        // helper 已复制进暂存区（App 从暂存区拉起它，避免换身时占用旧 bundle）
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: staging.appendingPathComponent("workfollowctl").path))
    }

    func testPrepareFailsOnChecksumMismatch() throws {
        let channel = newDirectory()
        let dataRoot = newDirectory()
        let wrongSHA = String(repeating: "e", count: 64)
        let manifest = makeManifest(build: SelfUpdateModel.currentBuild + 10, sha256: wrongSHA)
        try publishZip(channel, zipName: manifest.packages.full.file, content: "内容")
        try writeManifest(channel, manifest)
        let model = SelfUpdateModel(dataRoot: dataRoot)
        model.channelDirectory = channel
        let discovery = try XCTUnwrap(try model.check())
        XCTAssertThrowsError(try model.prepare(discovery)) { error in
            guard case SelfUpdateError.checksumMismatch = error else {
                XCTFail("应当是校验失败：\(error)"); return
            }
        }
    }
}
