import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AgentAccessGuideTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-guide-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private struct Fixture {
        let app: URL
        let installer: URL
        let cli: URL
        let skill: URL
    }

    private func fixture(in root: URL) throws -> Fixture {
        let app = root.appendingPathComponent("Applications/WorkFollow Example.app")
        let embeddedInstaller = app.appendingPathComponent("Contents/Resources/Automation/install-native-cli.sh")
        let cli = app.appendingPathComponent("Contents/MacOS/workfollowctl")
        let skill = app.appendingPathComponent("Contents/Resources/Skills/workfollow-cli/SKILL.md")
        for parent in [embeddedInstaller.deletingLastPathComponent(), cli.deletingLastPathComponent(), skill.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let resource = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent("Automation/install-native-cli.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resource.path), "安装命令必须随 App 分发")
        try FileManager.default.copyItem(at: resource, to: embeddedInstaller)
        try "#!/bin/sh\nprintf '%s\\n' '{\"ok\":true}'\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        try "---\nname: workfollow-cli\ndescription: fixture\n---\n".write(to: skill, atomically: true, encoding: .utf8)
        return Fixture(app: app, installer: embeddedInstaller, cli: cli, skill: skill)
    }

    private func run(_ command: String, environment: [String: String]) throws -> (Int32, String) {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testSameCopiedCommandWorksWithDifferentMacDirectories() throws {
        let root = try directory(), guide = AgentAccessGuide()
        for agent in AgentAccessGuide.Agent.allCases {
            let command = guide.manualCommand(for: agent)
            for name in ["第一台 Mac", "第二台 Mac"] {
                let machine = root.appendingPathComponent(agent.rawValue + "/" + name)
                let app = try fixture(in: machine)
                let bin = machine.appendingPathComponent("Local User/bin")
                let skills = machine.appendingPathComponent("Local User/skills")
                let (status, text) = try run(command, environment: [
                    "WORKFOLLOW_APP_PATH": app.app.path,
                    "WORKFOLLOW_CLI_BIN_DIR": bin.path,
                    "WORKFOLLOW_CLI_SKILL_DIR": skills.path
                ])
                XCTAssertEqual(status, 0, text)
                XCTAssertTrue(text.contains("\"ok\":true"), text)
                let link = bin.appendingPathComponent("workfollowctl")
                XCTAssertEqual(link.resolvingSymlinksInPath().path, app.cli.resolvingSymlinksInPath().path)
                let installed = skills.appendingPathComponent("workfollow-cli/SKILL.md")
                XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8),
                               try String(contentsOf: app.skill, encoding: .utf8))
            }
        }
    }

    func testEmbeddedInstallerFindsItsOwnAppWithoutAnAppArgument() throws {
        let root = try directory(), app = try fixture(in: root)
        let bin = root.appendingPathComponent("user/bin"), skills = root.appendingPathComponent("user/skills")
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [app.installer.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WORKFOLLOW_CLI_BIN_DIR": bin.path,
            "WORKFOLLOW_CLI_SKILL_DIR": skills.path
        ]) { _, value in value }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        XCTAssertEqual(bin.appendingPathComponent("workfollowctl").resolvingSymlinksInPath().path,
                       app.cli.resolvingSymlinksInPath().path)
    }

    func testMissingAppStopsBeforeWritingAgentConfiguration() throws {
        let root = try directory(), destination = root.appendingPathComponent("configuration")
        let (status, text) = try run(AgentAccessGuide().manualCommand(for: .workbuddy), environment: [
            "WORKFOLLOW_APP_PATH": root.appendingPathComponent("Missing.app").path,
            "WORKFOLLOW_CLI_BIN_DIR": destination.appendingPathComponent("bin").path,
            "WORKFOLLOW_CLI_SKILL_DIR": destination.appendingPathComponent("skills").path
        ])
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(text.contains("没有找到 WorkFollow"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCopiedInstructionsUseTheTargetMacEnvironment() {
        let guide = AgentAccessGuide()
        let texts = [guide.aiInstructions] + AgentAccessGuide.Agent.allCases.map(guide.manualCommand(for:))
        for text in texts {
            XCTAssertFalse(text.contains(FileManager.default.homeDirectoryForCurrentUser.path))
            XCTAssertFalse(text.contains(Bundle.main.bundleURL.path))
            XCTAssertTrue(text.contains("$HOME"))
        }
        XCTAssertTrue(guide.manualCommand(for: .codex).contains("${CODEX_HOME:-$HOME/.codex}/skills"))
    }

    func testCopyButtonsAndAgentChoiceUseTheDisplayedPlan() throws {
        let guide = AgentAccessGuide()
        for width: CGFloat in [600, 340] {
            var frames: [InspectorRenderAnchor: CGRect] = [:]
            var copied: [String] = []
            let view = AgentAccessGuideView(guide: guide, copyText: { copied.append($0) })
                .padding(12).frame(width: width, height: 380, alignment: .topLeading)
                .coordinateSpace(name: "inspector-render")
                .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
            let host = NSHostingView(rootView: AnyView(view))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 380)
            defer { window.contentView = nil; window.close() }
            let ai = try XCTUnwrap(frames[.agentCopyInstructions])
            let command = try XCTUnwrap(frames[.agentCopyCommand])
            XCTAssertTrue(host.bounds.contains(ai))
            XCTAssertTrue(host.bounds.contains(command))
            try InspectorPanelTestSupport.click(ai, in: host, window: window)
            XCTAssertEqual(copied.last, guide.aiInstructions)
            try InspectorPanelTestSupport.click(command, in: host, window: window)
            XCTAssertEqual(copied.last, guide.manualCommand(for: .workbuddy))

            func segmented(in view: NSView) -> NSSegmentedControl? {
                if let control = view as? NSSegmentedControl { return control }
                return view.subviews.lazy.compactMap { segmented(in: $0) }.first
            }
            let picker = try XCTUnwrap(segmented(in: host))
            picker.selectedSegment = try XCTUnwrap((0..<picker.segmentCount).first { picker.label(forSegment: $0) == "Codex" })
            NSApp.sendAction(try XCTUnwrap(picker.action), to: picker.target, from: picker)
            InspectorPanelTestSupport.settle(window)
            try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.agentCopyCommand]), in: host, window: window)
            XCTAssertEqual(copied.last, guide.manualCommand(for: .codex))
            XCTAssertEqual(copied.count, 3)

            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: "/private/tmp/workfollow-agent-guide-\(Int(width)).png"))
        }
    }

    func testGuideEntryOpensTheInstructionsInTheTaskInspector() throws {
        let environment = AppEnvironment(directory: try directory())
        XCTAssertTrue(environment.taskWorkspace.installWelcomeGuide())
        XCTAssertTrue(environment.openGuideAction(.agentAccess))
        let workspace = environment.taskWorkspace
        XCTAssertEqual(workspace.activeList, WelcomeGuide.listName)
        XCTAssertEqual(WelcomeGuide.action(for: try XCTUnwrap(workspace.selectedTask)), .agentAccess)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment,
            onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.contentView = nil; window.close() }
        XCTAssertNotNil(frames[.agentCopyInstructions])
        XCTAssertNotNil(frames[.agentCopyCommand])
    }
}
