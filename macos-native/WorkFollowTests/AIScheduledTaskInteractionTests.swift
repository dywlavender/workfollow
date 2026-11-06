import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIScheduledTaskInteractionTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func wait(_ label: String = "", _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(15))
        }
        XCTFail("Scheduled task controls did not settle: \(label)")
    }
    private func fixture() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-schedule-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pi = root.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json,pathlib,sys
        if '--session' not in sys.argv:
            for line in sys.stdin:
                request=json.loads(line)
                print(json.dumps({'type':'response','id':request.get('id'),'command':'get_available_models','success':True,'data':{'models':[]}}),flush=True)
            sys.exit(0)
        file=pathlib.Path(sys.argv[sys.argv.index('--session')+1])
        for line in sys.stdin:
            request=json.loads(line);file.write_text(json.dumps([request['message']]))
            text='虚构定时任务已回复'
            print(json.dumps({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':text}}),flush=True)
            print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: pi, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pi.path)
        let environment = AppEnvironment(directory: root)
        environment.meetingStore.configuration.executable = pi.path
        environment.navigation.destination = .aiChat
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return environment
    }
    func testChatPageCreatesRunsPausesEditsAndDeletesScheduledTasks() async throws {
        let environment = try fixture(), original = environment.aiChat.current.record.id
        environment.aiChat.current.input = "保留这份未发送的草稿"
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1150, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1150, height: 800)
        defer { environment.stopAIScheduler(); window.contentView = nil; window.close() }
        func click(_ id: String) async throws {
            try await wait(id) { anchors[id]?.window?.isVisible == true && anchors[id]?.bounds.isEmpty == false }
            let view = try XCTUnwrap(anchors[id]), owner = try XCTUnwrap(view.window)
            try InspectorPanelTestSupport.click(view.bounds, in: view, window: owner)
        }
        try await click("ai.chat.schedules")
        try await wait { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        try await click("ai.schedule.new")
        try await wait {
            descendants(sheet.contentView!).contains { ($0 as? NSTextView)?.isEditable == true }
        }
        func enter(_ value: String) async throws {
            try await wait("instruction editor") {
                descendants(sheet.contentView!).contains { ($0 as? NSTextView)?.isEditable == true }
            }
            let editor = try XCTUnwrap(descendants(try XCTUnwrap(sheet.contentView)).compactMap { $0 as? NSTextView }.first { $0.isEditable })
            sheet.makeFirstResponder(editor); editor.selectAll(nil)
            editor.insertText(value, replacementRange: editor.selectedRange())
            InspectorPanelTestSupport.settle(sheet)
        }
        try await enter("汇总虚构松竹项目的未完成事项")
        try await click("ai.schedule.save")
        try await wait { environment.aiScheduledJobs.jobs.count == 1 }
        let job = try XCTUnwrap(environment.aiScheduledJobs.jobs.first)
        XCTAssertEqual(job.schedule.frequency, .daily)
        XCTAssertEqual(job.instruction, "汇总虚构松竹项目的未完成事项")
        try await click("ai.schedule.run.\(job.id)")
        try await wait { environment.aiScheduledJobs.job(job.id)?.lastRun?.state == .complete }
        XCTAssertEqual(environment.aiChat.current.record.id, original)
        XCTAssertEqual(environment.aiChat.current.input, "保留这份未发送的草稿")
        XCTAssertEqual(environment.aiChat.records.first?.messages.last?.text, "虚构定时任务已回复")
        try await click("ai.schedule.enabled.\(job.id)")
        XCTAssertFalse(try XCTUnwrap(environment.aiScheduledJobs.job(job.id)).isEnabled)
        try await click("ai.schedule.menu.\(job.id)")
        try await click("ai.schedule.edit.\(job.id)")
        try await enter("整理虚构松竹项目的会议结论")
        try await click("ai.schedule.save")
        XCTAssertEqual(environment.aiScheduledJobs.job(job.id)?.instruction, "整理虚构松竹项目的会议结论")
        try await click("ai.schedule.menu.\(job.id)")
        try await click("ai.schedule.delete.\(job.id)")
        try await click("dialog.button.删除")
        try await wait { environment.aiScheduledJobs.jobs.isEmpty }
        XCTAssertEqual(environment.aiChat.records.count, 1, "删除计划应保留历史结果")
    }

    func testNarrowChatHistoryCanOpenTheSameScheduledTaskManager() async throws {
        let environment = try fixture()
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 720, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 740)
        defer { environment.stopAIScheduler(); window.contentView = nil; window.close() }
        try await wait("narrow history trigger") { anchors["ai.chat.history.toggle"]?.window === window }
        let toggle = try XCTUnwrap(anchors["ai.chat.history.toggle"])
        try InspectorPanelTestSupport.click(toggle.bounds, in: toggle, window: window)
        try await wait("narrow history controls") { anchors["ai.chat.schedules"]?.window?.isVisible == true }
        let view = try XCTUnwrap(anchors["ai.chat.schedules"]), owner = try XCTUnwrap(view.window)
        try InspectorPanelTestSupport.click(view.bounds, in: view, window: owner)
        try await wait("narrow schedule manager") { window.attachedSheet != nil && anchors["ai.schedule.new"]?.window === window.attachedSheet }
    }
}
