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

    func testPackagedInstallerCanRunBothCopiedCommandsWithoutARepository() throws {
        let root = try directory()
        let app = root.appendingPathComponent("WorkFollow Example.app")
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
        let user = root.appendingPathComponent("Local User")
        let guide = AgentAccessGuide(appURL: app, userDirectory: user,
                                     codexDirectory: user.appendingPathComponent(".codex"))

        for agent in AgentAccessGuide.Agent.allCases {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-e", "-c", guide.manualCommand(for: agent)]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, text)
            XCTAssertTrue(text.contains("\"ok\":true"), text)
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: guide.cliURL.path)
            XCTAssertEqual(URL(fileURLWithPath: destination).resolvingSymlinksInPath().path,
                           cli.resolvingSymlinksInPath().path)
            let installed = guide.skillDirectory(for: agent).appendingPathComponent("workfollow-cli/SKILL.md")
            XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8),
                           try String(contentsOf: skill, encoding: .utf8))
        }
    }

    func testCopyButtonsAndAgentChoiceUseTheDisplayedPlan() throws {
        let root = try directory()
        let user = root.appendingPathComponent("Local User")
        let guide = AgentAccessGuide(appURL: root.appendingPathComponent("WorkFollow.app"), userDirectory: user,
                                     codexDirectory: user.appendingPathComponent(".codex"))
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
            XCTAssertFalse(FileManager.default.fileExists(atPath: user.path), "查看和复制说明不应执行安装")

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
