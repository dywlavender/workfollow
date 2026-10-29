import XCTest
@testable import WorkFollow

@MainActor
final class AIConfigurationGuideTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-guide-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testExistingPiModelsAreOpenedWithoutReplacingTheirContents() throws {
        let root = try directory()
        let url = AIConfigurationGuide.piModelsURL(environment: [:], home: root)
        XCTAssertEqual(url, root.appendingPathComponent(".pi/agent/models.json"))
        _ = try AIConfigurationGuide.preparePiModels(at: url)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        let existing = #"{"providers":{"custom":{"apiKey":"fixture-key"}}}"#
        try existing.write(to: url, atomically: true, encoding: .utf8)
        _ = try AIConfigurationGuide.preparePiModels(at: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), existing)
        let custom = root.appendingPathComponent("Custom Pi")
        XCTAssertEqual(AIConfigurationGuide.piModelsURL(environment: ["PI_CODING_AGENT_DIR": custom.path], home: root), custom.appendingPathComponent("models.json"))
    }

    func testPiInstallCommandWorksAcrossMacDirectoriesWithoutInstallingSystemFiles() throws {
        let root = try directory()
        let tools = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let brew = tools.appendingPathComponent("brew"), npm = tools.appendingPathComponent("npm")
        try "#!/bin/sh\nprintf '%s\\n' \"$WORKFOLLOW_TEST_NODE_PREFIX\"\n".write(to: brew, atomically: true, encoding: .utf8)
        try #"""
        #!/bin/sh
        [ "$1" = install ] && [ "$2" = --global ] && [ "$3" = --prefix ] && [ "$4" = "$HOME/.local" ] || exit 1
        [ "$5" = @earendil-works/pi-coding-agent@0.86.1 ] || exit 1
        mkdir -p "$4/bin"
        printf '#!/bin/sh\nnode --version\nprintf "0.86.1\\n"\n' > "$4/bin/pi"
        chmod +x "$4/bin/pi"
        """#.write(to: npm, atomically: true, encoding: .utf8)
        for executable in [brew, npm] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path) }
        for name in ["Mac One", "另一台 Mac"] {
            let machine = root.appendingPathComponent(name)
            let prefix = machine.appendingPathComponent("Node Installation")
            let node = prefix.appendingPathComponent("bin/node")
            try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nprintf 'v24.22.1\\n'\n".write(to: node, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", AIConfigurationGuide.piInstallCommand]
            process.environment = ["HOME": machine.path, "PATH": tools.path + ":/usr/bin:/bin", "WORKFOLLOW_TEST_NODE_PREFIX": prefix.path]
            process.standardOutput = output; process.standardError = output
            try process.run()
            let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, result)
            XCTAssertTrue(result.contains("0.86.1"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: machine.appendingPathComponent(".local/bin/pi").path))
        }
    }

    func testCopiedInstallCommandUsesTheTargetMacHomebrewPrefix() throws {
        let root = try directory()
        let tools = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let brew = tools.appendingPathComponent("brew")
        try #"""
        #!/bin/sh
        if [ "$1" = install ] && [ "$2" = node@24 ]; then
          exit 0
        fi
        if [ "$1" = --prefix ] && [ "$2" = node@24 ]; then
          printf '%s\n' "$WORKFOLLOW_TEST_NODE_PREFIX"
          exit 0
        fi
        exit 1
        """#.write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        for name in ["Mac One", "另一台 Mac"] {
            let prefix = root.appendingPathComponent(name)
            let node = prefix.appendingPathComponent("bin/node")
            try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nprintf 'v24.22.1\\n'\n".write(to: node, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", AIConfigurationGuide.nodeInstallCommand]
            process.environment = ["PATH": tools.path + ":/usr/bin:/bin", "WORKFOLLOW_TEST_NODE_PREFIX": prefix.path]
            process.standardOutput = output; process.standardError = output
            try process.run()
            let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, result)
            XCTAssertTrue(result.contains("v24.22.1"))
        }
    }
}
