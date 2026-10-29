import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIWorkflowInteractionTests: XCTestCase {
    private func environment() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-workflow-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try NativePreviewRepository(directory: root).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let script = root.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        for line in sys.stdin:
            request = json.loads(line)
            if request.get("type") != "prompt": continue
            prompt = request["message"]
            pathlib.Path(__file__).with_suffix(".prompt").write_text(prompt)
            data = json.loads(prompt.split("输入 JSON：", 1)[1])
            if "existingTasks" in data:
                text = json.dumps({"tasks":[
                    {"title":"核对成本","date":"2026-10-30","due":None,"priority":"high","quote":"核对成本。"},
                    {"title":"发送报价","date":None,"due":"2026-11-02","priority":"none","quote":"发送报价。"}
                ]},ensure_ascii=False)
            elif "sources" in data:
                source = data["sources"][0]
                quote = source["content"].split("\n")[-1]
                text = json.dumps({"paragraphs":[{"text":quote,"citations":[{"source":source["id"],"quote":quote}]}],"insufficient":False},ensure_ascii=False)
            else:
                text = "# 要点\n- 核对成本。\n- 发送报价。"
            print(json.dumps({"type":"message_end","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let environment = AppEnvironment(directory: root)
        environment.focusStore.notifier = nil
        environment.meetingStore.configuration.executable = script.path
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return environment
    }

    private func wait(_ label: String = "", _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(15))
        }
        XCTFail("AI interface did not settle: \(label)")
    }
    private func screenshot(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to:
            URL(fileURLWithPath: "/private/tmp/workfollow-ai-workflow-\(name).png"))
    }

    func testQuestionFromFullShellAndClickingCitationOpensItsNote() async throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案"; $0.document = NativeDocument(plainText: "周五验收。") }
        var anchors: [String: NSView] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        environment.searchSession.query = "海鸥方案何时验收"
        environment.commandPalettePresented = true
        try await wait { window.attachedSheet != nil && anchors["knowledge.ask"] != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let ask = try XCTUnwrap(anchors["knowledge.ask"])
        try InspectorPanelTestSupport.click(ask.bounds, in: ask, window: sheet)
        try await wait { environment.searchSession.knowledge.phase == .ready }
        InspectorPanelTestSupport.settle(sheet)
        XCTAssertEqual(environment.searchSession.knowledge.answer?.paragraphs.first?.text, "周五验收。")
        try screenshot(sheet, name: "answer")
        let citation = try XCTUnwrap(anchors["knowledge.source.S1"])
        try InspectorPanelTestSupport.click(citation.bounds, in: citation, window: sheet)
        try await wait { window.attachedSheet == nil }
        XCTAssertEqual(environment.navigation.destination, .notes)
        XCTAssertEqual(environment.notesWorkspace.selectedID, id)
        XCTAssertEqual(environment.taskWorkspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.count, 0)
    }

    func testNoteAIPaneShowsDraftAndSaveCreatesNewNoteWithoutSwitchingContext() async throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案"; $0.document = NativeDocument(plainText: "核对成本。发送报价。") }
        let original = try XCTUnwrap(environment.notesWorkspace.selected)
        environment.navigation.destination = .notes
        var anchors: [String: NSView] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        let aiButton = try XCTUnwrap(anchors["note.ai"])
        XCTAssertTrue(aiButton.window === window)
        try InspectorPanelTestSupport.click(aiButton.bounds, in: aiButton, window: window)
        try await wait { anchors["note.ai.pane"] != nil && anchors["note.ai.organize"]?.window === window }
        try screenshot(window, name: "note-ai-pane")
        let organize = try XCTUnwrap(anchors["note.ai.organize"])
        try InspectorPanelTestSupport.click(organize.bounds, in: organize, window: window)
        try await wait("save button") { anchors["note.ai.save"] != nil }
        let editorText = window.contentView.map { self.descendants($0) }?
            .compactMap { $0 as? NSTextView }.contains { $0.string.contains("发送报价") } ?? false
        XCTAssertTrue(editorText)
        XCTAssertEqual(environment.notesWorkspace.notes.count, 1)
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == id }, original)
        try screenshot(window, name: "note-ai-draft")
        let save = try XCTUnwrap(anchors["note.ai.save"])
        try InspectorPanelTestSupport.click(save.bounds, in: save, window: window)
        try await wait { environment.notesWorkspace.notes.count == 2 }
        XCTAssertEqual(environment.notesWorkspace.selected?.title, "海鸥方案")
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == id }, original)
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id != id }?.title, "海鸥方案（要点）")
    }

    func testNoteAIPaneExtractsTasksEditsDraftAndKeepsAppliedState() async throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案"; $0.document = NativeDocument(plainText: "核对成本。发送报价。") }
        environment.navigation.destination = .notes
        var anchors: [String: NSView] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        let aiButton = try XCTUnwrap(anchors["note.ai"])
        try InspectorPanelTestSupport.click(aiButton.bounds, in: aiButton, window: window)
        try await wait("pane actions") { anchors["note.ai.tasks"]?.window === window }
        let extract = try XCTUnwrap(anchors["note.ai.tasks"])
        try InspectorPanelTestSupport.click(extract.bounds, in: extract, window: window)
        try await wait("create button") { anchors["note.ai.create"]?.window === window }
        XCTAssertEqual(environment.taskWorkspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.count, 0)
        try screenshot(window, name: "note-ai-tasks")

        let firstDraft = try XCTUnwrap(anchors["note.ai.draft.0"])
        try InspectorPanelTestSupport.click(firstDraft.bounds, in: firstDraft, window: window)
        try await wait("draft editor") { anchors["note.ai.draftEditor"] != nil }
        XCTAssertNil(anchors["note.ai.draftEditor.deadline"], "没有截止日期时不应显示额外入口")
        let body = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView))
            .compactMap { $0 as? NSTextView }
            .first { $0.isEditable && $0.string.contains("核对成本。") && !$0.string.contains("发送报价") })
        body.window?.makeFirstResponder(body)
        body.selectAll(nil)
        body.insertText("补充：先核对明细。", replacementRange: body.selectedRange())
        InspectorPanelTestSupport.settle(window)
        try screenshot(window, name: "note-ai-draft-editor")
        try InspectorPanelTestSupport.clickButton(containing: "优先级", in: window)
        // 面板通过主队列异步就位；async 测试里先让出一拍再轮询。
        try await _Concurrency.Task.sleep(for: .milliseconds(120))
        let priorityPanel = try InspectorPanelTestSupport.panel(title: "优先级", below: window)
        XCTAssertTrue(priorityPanel.isVisible, "草稿弹框的旗子应打开与任务详情同款优先级浮层")
        try InspectorPanelTestSupport.sendEscape(to: priorityPanel)
        try await _Concurrency.Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(priorityPanel.isVisible)
        let closeEditor = try XCTUnwrap(anchors["note.ai.draftEditor.close"])
        try InspectorPanelTestSupport.click(closeEditor.bounds, in: closeEditor, window: window)
        InspectorPanelTestSupport.settle(window)
        try screenshot(window, name: "note-ai-editor-closed")
        try await wait("create button") { anchors["note.ai.create"]?.window === window }

        let create = try XCTUnwrap(anchors["note.ai.create"])
        try InspectorPanelTestSupport.click(create.bounds, in: create, window: window)
        try await wait("two created tasks") { environment.taskWorkspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.count == 2 }
        let edited = try XCTUnwrap(environment.taskWorkspace.allTasks.first {
            !$0.isNoteTask && $0.deletedAt == nil && $0.title == "核对成本"
        })
        XCTAssertTrue(edited.document.plainText.contains("补充：先核对明细。"))
        XCTAssertTrue(anchors["note.ai.pane"]?.window === window)
        try screenshot(window, name: "note-ai-created")

        let undo = try XCTUnwrap(anchors["note.ai.undoCreated"])
        try InspectorPanelTestSupport.click(undo.bounds, in: undo, window: window)
        try await wait("tasks undone") { environment.taskWorkspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil }.count == 0 }
    }

    func testNoteAIPaneCanReplaceCurrentBodyAfterConfirmation() async throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案"; $0.document = NativeDocument(plainText: "核对成本。发送报价。") }
        environment.navigation.destination = .notes
        var anchors: [String: NSView] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        let aiButton = try XCTUnwrap(anchors["note.ai"])
        try InspectorPanelTestSupport.click(aiButton.bounds, in: aiButton, window: window)
        try await wait("pane actions") { anchors["note.ai.organize"]?.window === window }
        let organize = try XCTUnwrap(anchors["note.ai.organize"])
        try InspectorPanelTestSupport.click(organize.bounds, in: organize, window: window)
        try await wait("save button") { anchors["note.ai.save"]?.window === window }
        let replace = try XCTUnwrap(anchors["note.ai.replace"])
        try InspectorPanelTestSupport.click(replace.bounds, in: replace, window: window)
        try await wait("replace alert") { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let alertText = sheet.contentView.map { self.descendants($0) } ?? []
        let confirm = alertText.compactMap { $0 as? NSButton }.first { $0.title == "替换" }
        XCTAssertNotNil(confirm)
        confirm?.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        try await wait("body replaced") {
            environment.notesWorkspace.notes.first { $0.id == id }?.document.plainText.contains("要点") == true
        }
        XCTAssertEqual(environment.notesWorkspace.notes.count, 1)
        XCTAssertEqual(environment.notesWorkspace.selectedID, id)
        try screenshot(window, name: "note-ai-replaced")
    }

    func testMeetingCitationScrollsToEarlierSpeechInFullShell() async throws {
        let environment = try environment()
        environment.meetingStore.create()
        for index in 0..<70 {
            environment.meetingStore.appendTranscriptForTesting("第 \(index) 段：核对海鸥项目方案和客户需求，周五验收。", speaker: "未区分")
        }
        let meeting = try XCTUnwrap(environment.meetingStore.selected)
        let line = meeting.transcript[12]
        var anchors: [String: NSView] = [:]
        let root = RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1400, height: 850)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1400, height: 850)
        defer { window.contentView = nil; window.close() }
        environment.navigation.destination = .meetings
        try await wait {
            guard let last = anchors["meeting.line.\(meeting.transcript.last!.id)"] else { return false }
            return !last.bounds.intersection(last.visibleRect).isEmpty
        }
        let last = try XCTUnwrap(anchors["meeting.line.\(meeting.transcript.last!.id)"])
        XCTAssertFalse(last.bounds.intersection(last.visibleRect).isEmpty)
        XCTAssertTrue(environment.openKnowledgeSource(KnowledgePassage(id: "S1", kind: .meeting,
            resourceID: meeting.id, lineID: line.id, title: meeting.title, content: line.text, date: meeting.createdAt, location: "00:00")))
        try await wait {
            guard let target = anchors["meeting.line.\(line.id)"] else { return false }
            return !target.bounds.intersection(target.visibleRect).isEmpty
        }
        InspectorPanelTestSupport.settle(window)
        let target = try XCTUnwrap(anchors["meeting.line.\(line.id)"])
        XCTAssertFalse(target.bounds.intersection(target.visibleRect).isEmpty, "来源发言必须滚入可见区域")
        try screenshot(window, name: "meeting-source")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
