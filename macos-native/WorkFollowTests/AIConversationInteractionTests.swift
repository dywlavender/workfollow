import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationInteractionTests: XCTestCase {
    private func wait(_ label: String = "", _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(15))
        }
        XCTFail("Conversation window did not settle: \(label)")
    }

    private func fixture() throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-conversation-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pi = directory.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json,pathlib,sys
        args=sys.argv
        file=pathlib.Path(args[args.index('--session')+1])
        messages=json.loads(file.read_text()) if file.exists() else []
        for line in sys.stdin:
            request=json.loads(line)
            messages.append(request['message']);file.write_text(json.dumps(messages))
            text='第'+str(len(messages))+'轮回复：清楚的虚构文字'
            print(json.dumps({'type':'message_start','message':{'role':'assistant'}}),flush=True)
            print(json.dumps({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':text}}),flush=True)
            print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: pi, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pi.path)
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        environment.meetingStore.configuration.executable = pi.path
        addTeardownBlock { AISelectionWindowController.shared.close(); try? FileManager.default.removeItem(at: directory) }
        return environment
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func testStandaloneChatInFullShellSendsTwoTurnsAndStartsNewConversation() async throws {
        let environment = try fixture()
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        try await wait { anchors["ai.chat.send"] != nil }
        XCTAssertNotNil(anchors["ai.chat.page"])
        XCTAssertNotNil(anchors["ai.chat.history"], "空历史也应有可见入口")
        let model = environment.aiChat.current
        model.input = "虚构项目的第一问"
        try await _Concurrency.Task.sleep(for: .milliseconds(40))
        let send = try XCTUnwrap(anchors["ai.chat.send"])
        try InspectorPanelTestSupport.click(send.bounds, in: send, window: window)
        try await wait { !model.isRunning && model.record.messages.count == 2 }
        XCTAssertEqual(model.latestResult, "第1轮回复：清楚的虚构文字")
        let input = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
        input.string = "这是后续问题"; input.didChangeText()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: event)
        try await wait { !model.isRunning && model.record.messages.count == 4 }
        XCTAssertEqual(model.latestResult, "第2轮回复：清楚的虚构文字")
        let button = try XCTUnwrap(anchors["ai.chat.new"])
        try InspectorPanelTestSupport.click(button.bounds, in: button, window: window)
        try await wait { environment.aiChat.current.record.id != model.record.id }
        XCTAssertTrue(environment.aiChat.current.record.messages.isEmpty)
        XCTAssertEqual(environment.aiChat.records.count, 1)
        environment.aiChat.current.input = "另一段独立对话"
        let secondID = environment.aiChat.current.record.id
        let secondSendID = "ai.chat.send.\(secondID)"
        try await wait("new conversation composer") { anchors[secondSendID]?.window === window }
        let sendSecond = try XCTUnwrap(anchors[secondSendID])
        try InspectorPanelTestSupport.click(sendSecond.bounds, in: sendSecond, window: window)
        try await wait("new conversation reply") { !environment.aiChat.current.isRunning && environment.aiChat.records.count == 2 }
        let historyID = "ai.chat.history.\(model.record.id)"
        try await wait("history row") { anchors[historyID] != nil }
        let history = try XCTUnwrap(anchors[historyID])
        try InspectorPanelTestSupport.click(history.bounds, in: history, window: window)
        try await wait("select previous conversation") { environment.aiChat.current.record.id == model.record.id }
        XCTAssertEqual(environment.aiChat.current.record.messages.count, 4)
        XCTAssertEqual(environment.aiChat.current.latestResult, "第2轮回复：清楚的虚构文字")
    }

    func testSelectedTextOpensFloatingConversationAndReplacementIsUndoable() async throws {
        let environment = try fixture()
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.title = "虚构笔记"; $0.document = NativeDocument(plainText: "前文。原句。后文。") }
        environment.navigation.destination = .notes
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTextView }.first)
        editor.setSelectedRange((editor.string as NSString).range(of: "原句"))
        var anchors: [String: NSView] = [:]
        AISelectionWindowController.shared.actionObservation = { anchors[$0] = $1 }
        defer { AISelectionWindowController.shared.actionObservation = nil }
        let selectedRect = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        let location = window.convertPoint(fromScreen: NSPoint(x: selectedRect.minX + 3, y: selectedRect.midY))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: location,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 0))
        let menu = try XCTUnwrap(editor.menu(for: event))
        let index = try XCTUnwrap(menu.items.firstIndex(where: { $0.title == "AI 润色" }))
        menu.performActionForItem(at: index)
        let panel = try XCTUnwrap(AISelectionWindowController.shared.panel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(AISelectionWindowController.shared.model?.context, "原句")
        try await wait { anchors["ai.selection.replace"] != nil }
        let replace = try XCTUnwrap(anchors["ai.selection.replace"])
        try InspectorPanelTestSupport.click(replace.bounds, in: replace, window: panel)
        try await wait { AISelectionWindowController.shared.panel == nil }
        XCTAssertEqual(editor.string, "前文。第1轮回复：清楚的虚构文字。后文。")
        editor.undoDocumentEdit()
        XCTAssertEqual(editor.string, "前文。原句。后文。")
    }
}
