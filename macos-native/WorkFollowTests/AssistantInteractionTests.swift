import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AssistantInteractionTests: XCTestCase {
    private func environment(clock: @escaping () -> Date = Date.init) throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppEnvironment(clock: clock, directory: root)
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

    /// 用户反馈今日简报卡「一直在、关不掉」：卡片必须能整卡关闭并跨启动保留，
    /// 页头同时给出再打开的入口。
    func testBriefingCardCanBeClosedAndReopenedFromPageHeader() async throws {
        let environment = try environment()
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        func wait(_ message: @autoclosure () -> String, _ ready: () -> Bool) async throws {
            for _ in 0..<250 {
                if ready() { return }
                try await _Concurrency.Task.sleep(for: .milliseconds(12))
            }
            XCTFail(message())
        }
        func click(_ id: String) async throws {
            try await wait("visible \(id)") { anchors[id]?.window === window }
            let button = try XCTUnwrap(anchors[id])
            try InspectorPanelTestSupport.click(button.bounds, in: button, window: window)
        }
        try await wait("简报卡应先出现") { anchors["assistant.briefing.close"]?.window === window }
        XCTAssertFalse(environment.assistantBriefing.cardHidden)

        try await click("assistant.briefing.close")
        try await wait("收起后页头应出现再打开入口") {
            anchors["assistant.briefing.reopen"]?.window === window
                && anchors["assistant.briefing.close"]?.window !== window
        }
        XCTAssertTrue(environment.assistantBriefing.cardHidden)

        try await click("assistant.briefing.reopen")
        try await wait("再打开后卡片应回来") {
            anchors["assistant.briefing.close"]?.window === window
                && anchors["assistant.briefing.reopen"]?.window !== window
        }
        XCTAssertFalse(environment.assistantBriefing.cardHidden)
    }

    func testMeetingCandidateCreatesLinkedTaskAndCompletionRemovesItFromToday() async throws {
        var now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-10T09:00:00+08:00"))
        let environment = try environment(clock: { now })
        try environment.assistantBriefing.setAutomaticEnabled(false)
        try environment.meetingFollowUps.setEnabled(true)
        environment.meetingStore.create()
        environment.meetingStore.appendTranscriptForTesting("请周三 16:00 前发虚构验收清单", speaker: "刘工")
        let meeting = try XCTUnwrap(environment.meetingStore.selected)
        environment.meetingStore.onFinalizedForFollowUp = { [weak environment] finalized in
            guard let environment else { return }
            environment.meetingFollowUps.generate(for: finalized, request: environment.aiTaskRequest(for: finalized), isCurrent: { true }) { _ in
                #"{"tasks":[{"title":"发虚构验收清单","due":"2026-11-11T16:00:00+08:00","quote":"请周三 16:00 前发虚构验收清单"}]}"#
            }
        }
        environment.startPersonalAssistant()
        environment.navigation.destination = .meetings
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1150, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1150, height: 800)
        defer { window.contentView = nil; window.close() }
        func wait(_ message: @autoclosure () -> String, _ ready: () -> Bool) async throws {
            for _ in 0..<250 {
                if ready() { return }
                try await _Concurrency.Task.sleep(for: .milliseconds(12))
            }
            XCTFail(message())
        }
        func click(_ id: String) async throws {
            try await wait("Missing visible action \(id)") {
                guard let anchor = anchors[id], let owner = anchor.window else { return false }
                return owner.isVisible && owner.alphaValue >= 0.99 && !anchor.bounds.isEmpty
            }
            let anchor = try XCTUnwrap(anchors[id])
            try InspectorPanelTestSupport.click(anchor.bounds, in: anchor, window: try XCTUnwrap(anchor.window))
        }
        try await click("assistant.meeting.finish.\(meeting.id)")
        try await wait("Finishing the meeting should deliver one batch of candidates") { environment.meetingFollowUps.pending.count == 1 }
        environment.navigate(to: .aiChat)
        try await click("assistant.meeting.review.\(meeting.id)")
        try await click("ai-task-composer.apply")
        try await wait("Pending follow-ups: \(environment.meetingFollowUps.pending.count), sheet visible: \(window.attachedSheet != nil)") {
            environment.meetingFollowUps.pending.isEmpty && window.attachedSheet == nil
        }
        let task = try XCTUnwrap(environment.taskWorkspace.allTasks.first { $0.sourceMeetingID == meeting.id })
        XCTAssertTrue(task.document.blocks.first?.runs.last?.marks.contains(where: {
            if case let .link(url) = $0 { return url.contains("line=") }
            return false
        }) == true)
        now = now.addingTimeInterval(86400)
        environment.refreshAssistantBriefingAutomatically()
        try await click("assistant.task.actions.\(task.id)")
        try await click("assistant.task.complete.\(task.id)")
        try await wait("Completed task should disappear from the briefing") {
            !environment.assistantBriefing.today.contains(where: { $0.id == task.id })
        }
        XCTAssertEqual(environment.taskWorkspace.task(for: task.id)?.status, .completed)
    }
}
