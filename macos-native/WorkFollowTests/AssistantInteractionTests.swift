import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AssistantInteractionTests: XCTestCase {
    private func environment() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppEnvironment(directory: root)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func capture(_ window: NSWindow, _ name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/private/tmp/workfollow-assistant-\(name)-20261103.png"))
    }

    func testSettingsCanRememberEditAndForgetThroughActualControls() throws {
        let environment = try environment(); environment.settingsSection = .assistant
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: SettingsShellView().environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 }))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 580)
        defer { window.contentView = nil; window.close() }
        func enter(_ text: String) throws {
            let field = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }
                .first { $0.placeholderString == "输入一条长期偏好…" })
            window.makeFirstResponder(field)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.selectAll(nil); editor.insertText(text)
            window.makeFirstResponder(nil)
            InspectorPanelTestSupport.settle(window)
        }
        func click(_ id: String) throws {
            try InspectorPanelTestSupport.waitUntil { anchors[id]?.window === window }
            let button = try XCTUnwrap(anchors[id])
            try InspectorPanelTestSupport.click(button.bounds, in: button, window: window)
        }
        try enter("虚构偏好：会议提前十分钟提醒")
        try click("assistant.memory.save")
        let saved = try XCTUnwrap(environment.assistantMemories.entries.first)
        XCTAssertEqual(saved.content, "虚构偏好：会议提前十分钟提醒")
        try click("assistant.memory.edit.\(saved.id)")
        try enter("虚构偏好：会议提前二十分钟提醒")
        try click("assistant.memory.save")
        XCTAssertEqual(environment.assistantMemories.entries.first?.content, "虚构偏好：会议提前二十分钟提醒")
        try capture(window, "memory-settings")
        try click("assistant.memory.forget.\(saved.id)")
        XCTAssertTrue(environment.assistantMemories.entries.isEmpty)
    }

    func testDailyBriefingAndMemoryEntryAppearInTheFullChatShell() async throws {
        let environment = try environment()
        let facts = AssistantBriefingFacts.make(tasks: [], now: Date(), calendar: .current)
        environment.assistantBriefing.refresh(force: true) { updates in
            updates(AITextUpdate(kind: "text", text: "虚构简报正在输出"))
            return (facts, "### 今日重点\n处理虚构项目的评审意见。\n\n### 截止事项\n虚构周报明天截止，建议下午先完成草稿。")
        }
        for _ in 0..<100 where environment.assistantBriefing.isRunning {
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        try InspectorPanelTestSupport.waitUntil { anchors["assistant.briefing.refresh"] != nil && anchors["ai.chat.memory"] != nil }
        XCTAssertNotNil(anchors["ai.chat.new"])
        XCTAssertNotNil(anchors["ai.chat.settings"])
        try capture(window, "daily-chat")
        window.appearance = NSAppearance(named: .darkAqua)
        InspectorPanelTestSupport.settle(window)
        try capture(window, "daily-chat-dark")
    }
}
