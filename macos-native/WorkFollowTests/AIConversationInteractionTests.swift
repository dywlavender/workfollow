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
        let secondID = environment.aiChat.current.record.id
        let secondSendID = "ai.chat.send.\(secondID)"
        try await wait("new conversation composer") { anchors[secondSendID]?.window === window }
        let secondInput = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
        secondInput.string = "另一段独立对话"; secondInput.didChangeText()
        try await _Concurrency.Task.sleep(for: .milliseconds(40))
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
        let deleteID = "ai.chat.delete.\(model.record.id)"
        let delete = try XCTUnwrap(anchors[deleteID])
        try InspectorPanelTestSupport.click(delete.bounds, in: delete, window: window)
        func dialog(_ title: String) -> NSPanel? {
            (window.childWindows ?? []).compactMap { $0 as? NSPanel }
                .first { $0.title == title && $0.isVisible }
        }
        try await wait("delete confirmation") { dialog("删除这段对话？") != nil }
        let cancelDialog = try XCTUnwrap(dialog("删除这段对话？"))
        try await wait("cancel button") {
            guard let anchor = anchors["dialog.button.取消"] else { return false }
            return anchor.window === cancelDialog && anchor.bounds.width >= 68 && anchor.bounds.height >= 30
        }
        InspectorPanelTestSupport.settle(cancelDialog)
        let cancelButton = try XCTUnwrap(anchors["dialog.button.取消"])
        try InspectorPanelTestSupport.click(cancelButton.bounds, in: cancelButton, window: cancelDialog)
        try await wait("cancel deletion") { !cancelDialog.isVisible }
        XCTAssertEqual(environment.aiChat.records.count, 2)
        try InspectorPanelTestSupport.click(delete.bounds, in: delete, window: window)
        try await wait("delete confirmation again") { dialog("删除这段对话？") != nil }
        let confirmDialog = try XCTUnwrap(dialog("删除这段对话？"))
        try await wait("confirm button") {
            guard let anchor = anchors["dialog.button.删除"] else { return false }
            return anchor.window === confirmDialog && anchor.bounds.width >= 68 && anchor.bounds.height >= 30
        }
        InspectorPanelTestSupport.settle(confirmDialog)
        let confirmButton = try XCTUnwrap(anchors["dialog.button.删除"])
        try InspectorPanelTestSupport.click(confirmButton.bounds, in: confirmButton, window: confirmDialog)
        try await wait("confirm dismissed") { !confirmDialog.isVisible }
        try await wait("deleted conversation") { environment.aiChat.records.count == 1 }
        XCTAssertEqual(environment.aiChat.current.record.id, secondID)
        XCTAssertEqual(environment.aiChat.current.latestResult, "第1轮回复：清楚的虚构文字")
        let sessionFile = environment.aiChat.sessionDirectory.appendingPathComponent("chat")
            .appendingPathComponent(model.record.id.uuidString + ".jsonl")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionFile.path))
    }

    @MainActor
    private final class PendingReply {
        var continuation: CheckedContinuation<String, Never>?
        var starts = 0

        func generate() async -> String {
            starts += 1
            return await withCheckedContinuation { continuation = $0 }
        }

        func finish() {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: "虚构长任务已完成")
        }
    }

    func testWideHistoryKeepsRunningSpinnerAcrossSwitchNewAndReturnThenRemovesIt() async throws {
        try await exerciseRunningHistory(width: 1150, narrow: false)
    }

    func testNarrowHistoryKeepsRunningSpinnerAcrossSwitchNewAndReturnThenRemovesIt() async throws {
        try await exerciseRunningHistory(width: 720, narrow: true)
    }

    private func exerciseRunningHistory(width: CGFloat, narrow: Bool) async throws {
        let environment = try fixture()
        let store = environment.aiChat
        let other = store.current
        other.input = "另一段已完成的虚构对话"
        other.send { _, _, _, _, _ in "另一段对话的回复" }
        try await wait("seed completed history") { !other.isRunning && other.latestResult != nil }
        store.newConversation()
        let running = store.current, reply = PendingReply()
        defer { running.stop(); reply.finish() }
        running.input = "这是需要等待完成的虚构长任务，用于检查历史标题旁的状态"
        running.send { _, _, _, _, updates in
            updates(AITextUpdate(kind: "text", text: "虚构任务仍在执行"))
            return await reply.generate()
        }
        try await wait("held streaming reply") {
            reply.continuation != nil && running.record.messages.last?.text == "虚构任务仍在执行"
        }
        XCTAssertEqual(store.runningIDs, [running.record.id])
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: width, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 740)
        defer { window.contentView = nil; window.close() }
        let spinnerID = "ai.chat.running.\(running.record.id)"
        let rowID = "ai.chat.history.\(running.record.id)"
        let deleteID = "ai.chat.delete.\(running.record.id)"

        // Anchors are retained by this dictionary after SwiftUI removes them. Check
        // attachment AND visibility, not dictionary membership, especially for popups.
        func visible(_ id: String) -> Bool {
            guard let view = anchors[id], let owner = view.window, owner.isVisible,
                  !view.isHiddenOrHasHiddenAncestor else { return false }
            return !view.bounds.intersection(view.visibleRect).isEmpty
        }
        func click(_ id: String) async throws {
            try await wait("visible \(id)") { visible(id) }
            let owner = try XCTUnwrap(anchors[id]?.window)
            InspectorPanelTestSupport.settle(owner)
            try await wait("laid out \(id)") {
                guard let view = anchors[id], view.window === owner else { return false }
                return visible(id) && view.bounds.width > 0 && view.bounds.height > 0
                    && view.visibleRect.insetBy(dx: -1, dy: -1).contains(view.bounds)
            }
            let view = try XCTUnwrap(anchors[id])
            try InspectorPanelTestSupport.click(view.bounds, in: view, window: owner)
        }
        func openHistory() async throws {
            if narrow && !visible("ai.chat.new") { try await click("ai.chat.history.toggle") }
            try await wait("visible history") { visible("ai.chat.new") && visible(rowID) }
            if narrow {
                XCTAssertFalse(anchors[rowID]?.window === window, "窄布局应在历史弹层中显示同一行")
            } else {
                XCTAssertTrue(anchors[rowID]?.window === window, "宽布局应在侧栏中显示同一行")
            }
        }
        func assertSpinner() async throws {
            try await wait("visible running spinner") { visible(spinnerID) }
            let spinner = try XCTUnwrap(anchors[spinnerID])
            let row = try XCTUnwrap(anchors[rowID]), trash = try XCTUnwrap(anchors[deleteID])
            XCTAssertTrue(spinner.window === row.window)
            let spinnerFrame = spinner.convert(spinner.bounds, to: nil)
            let rowFrame = row.convert(row.bounds, to: nil)
            let trashFrame = trash.convert(trash.bounds, to: nil)
            XCTAssertTrue(rowFrame.insetBy(dx: -1, dy: -1).contains(spinnerFrame), "转圈应在可点击选择区域内")
            XCTAssertFalse(spinnerFrame.intersects(trashFrame), "转圈不能遮挡删除按钮")
            XCTAssertLessThanOrEqual(spinnerFrame.width, 20, "历史行应使用小号原生转圈")
            XCTAssertFalse(visible("ai.chat.running.\(other.record.id)"), "已完成会话不应有转圈")
            XCTAssertTrue(running.isRunning)
            XCTAssertEqual(reply.starts, 1, "切换不得重启同一轮请求")
        }

        try await openHistory()
        try await assertSpinner()
        try await click("ai.chat.history.\(other.record.id)")
        try await wait("switch while streaming") { store.current === other }
        try await openHistory()
        try await assertSpinner() // Unselected and not hovered: running is not selection state.
        try await click(spinnerID) // Clicking the indicator must still select the row.
        try await wait("return to live model") { store.current === running }
        XCTAssertEqual(store.current.record.messages.last?.text, "虚构任务仍在执行")

        // The adjacent delete control must retain its own click target. Cancelling
        // its confirmation must neither select another record nor stop generation.
        try await openHistory()
        try await click(deleteID)
        try await wait("running conversation delete confirmation") {
            visible("dialog.button.取消") && anchors["dialog.button.取消"]?.window?.title == "删除这段对话？"
        }
        let confirmation = try XCTUnwrap(anchors["dialog.button.取消"]?.window)
        try await wait("laid out cancel button") {
            guard let button = anchors["dialog.button.取消"] else { return false }
            return button.window === confirmation && button.bounds.width >= 68 && button.bounds.height >= 30
        }
        InspectorPanelTestSupport.settle(confirmation)
        let cancelButton = try XCTUnwrap(anchors["dialog.button.取消"])
        try InspectorPanelTestSupport.click(cancelButton.bounds, in: cancelButton, window: confirmation)
        try await wait("delete cancellation") { !confirmation.isVisible }
        XCTAssertTrue(store.current === running)
        XCTAssertTrue(running.isRunning)
        XCTAssertEqual(store.records.count, 2)

        try await openHistory()
        try await click("ai.chat.new")
        try await wait("new while streaming") { store.current.record.id != running.record.id }
        let draft = store.current
        XCTAssertTrue(draft.record.messages.isEmpty)
        XCTAssertFalse(draft.isRunning)
        draft.input = "保留新会话的未发送草稿"
        try await openHistory()
        try await assertSpinner()
        try await click(spinnerID)
        try await wait("return after creating new") { store.current === running }
        XCTAssertEqual(store.current.record.messages.count, 2)
        XCTAssertEqual(store.current.record.messages.last?.state, .generating)

        // Complete while another conversation is selected and history is visible;
        // this catches stale status caused by observing only store.current.
        try await openHistory()
        try await click("ai.chat.history.\(other.record.id)")
        try await wait("switch away before completion") { store.current === other }
        try await openHistory()
        try await assertSpinner()
        reply.finish()
        try await wait("background completion removes spinner") {
            !running.isRunning && store.runningIDs.isEmpty && !visible(spinnerID)
        }
        XCTAssertFalse(store.isAnyRunning)
        XCTAssertTrue(store.current === other)
        XCTAssertEqual(draft.input, "保留新会话的未发送草稿")
        XCTAssertEqual(running.latestResult, "虚构长任务已完成")
        XCTAssertTrue(visible(rowID), "完成仅移除转圈，不应移除历史行")
        try await click(rowID)
        try await wait("return to completed conversation") { store.current === running }
        XCTAssertEqual(store.current.latestResult, "虚构长任务已完成")
        try await openHistory()
        XCTAssertFalse(visible(spinnerID), "重新打开历史不应恢复过期转圈")
    }

    /// 选区 AI 不再弹独立浮窗：结果落在笔记右侧 AI 栏，「替换」写回原选区且可撤销。
    /// 两轮润色后每条结果各自绑定选区快照：动作按条出现在结果下方，互不覆盖，
    /// 回写第一轮仍落在第一轮的选区上。真实 Milkdown 编辑器 + 真实窗口 + 真实上下文菜单。
    func testSelectedTextOpensNoteAIPaneAndReplacementIsUndoable() async throws {
        let environment = try fixture()
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.title = "虚构笔记"; $0.document = NativeDocument(plainText: "前文。原句。后文。") }
        environment.navigation.destination = .notes
        var anchors: [String: [NSView]] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0, default: []].append($1) })
            .frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        let editor = try await MilkdownTestSupport.editorAsync(in: host, id: noteID)
        func polish(_ text: String) throws {
            try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: text))
            try MilkdownTestSupport.script(editor, "document.querySelector('.ProseMirror').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:100,clientY:60}))")
            try MilkdownTestSupport.chooseMenu(editor, title: "AI 润色")
        }
        try polish("原句")
        let model = NoteAIConversationStore.shared.model(for: noteID)
        try await wait("右栏选区会话") { !model.conversation.record.messages.isEmpty && !model.selectionTargets.isEmpty }
        XCTAssertNil(AISelectionWindowController.shared.panel, "笔记页的选区 AI 不应再弹独立浮窗")
        try await wait("AI 栏已展开") { anchors["note.ai.pane"]?.last?.window === window }
        XCTAssertEqual(model.conversation.submittedSource?.kind, "selection")
        XCTAssertEqual(model.conversation.submittedSource?.content, "原句")
        XCTAssertNil(model.conversation.submittedSource?.id, "带 id 会把选区结果误投影成替换整篇正文的卡片")
        XCTAssertTrue(model.exchanges.isEmpty)
        try await wait("第一轮生成完成") { !model.isRunning }
        // SwiftUI 重渲染会重复上报同一按钮，按去重后的对象数判断。
        try await wait("第一轮替换按钮") { Set((anchors["ai.selection.replace"] ?? []).map(ObjectIdentifier.init)).count >= 1 }

        // 第二轮换一段选区再润色：两条结果各自绑定快照，动作各自成组、互不覆盖。
        try polish("后文")
        try await wait("第二轮生成完成") {
            !model.isRunning && model.conversation.latestWritingResult == "第2轮回复：清楚的虚构文字"
        }
        try await wait("第二轮替换按钮") { Set((anchors["ai.selection.replace"] ?? []).map(ObjectIdentifier.init)).count >= 2 }
        let assistantMessages = model.conversation.record.messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 2)
        let firstTarget = try XCTUnwrap(model.selectionTarget(for: assistantMessages[0]), "第一轮快照仍可解析")
        let secondTarget = try XCTUnwrap(model.selectionTarget(for: assistantMessages[1]), "第二轮快照仍可解析")
        XCTAssertTrue(firstTarget !== secondTarget, "两轮各自持有快照")

        // 回写第一轮：仍落在第一轮的选区（原句），不碰第二轮的（后文）。
        let replace = try XCTUnwrap(anchors["ai.selection.replace"]?.first, "第一轮的动作行")
        try InspectorPanelTestSupport.click(replace.bounds, in: replace, window: window)
        try await wait("回写第一轮原选区") { editor.document.plainText == "前文。第1轮回复：清楚的虚构文字。后文。" }
        // 回写在 JS 应用阶段就可见，消费发生在桥接回包之后，这里等消费落地。
        try await wait("消费第一轮快照") { model.selectionTarget(for: assistantMessages[0]) == nil }
        XCTAssertNotNil(model.selectionTarget(for: assistantMessages[1]), "第二轮快照不受影响")
        try MilkdownTestSupport.command(editor, "undo")
        XCTAssertEqual(editor.document.plainText, "前文。原句。后文。")
        model.stop(); model.clearSelectionTargets()
    }

    func testSelectionContextMenuOffersTranslateWithDistinctPreset() async throws {
        XCTAssertEqual(MilkdownWebView.selectionIntent(for: "ai.translate"), .translate)
        XCTAssertEqual(MilkdownWebView.selectionIntent(for: "ai.summarize"), .organize)
        XCTAssertEqual(MilkdownWebView.selectionIntent(for: "ai.polish"), .polish)
        let environment = try fixture()
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.document = NativeDocument(plainText: "前文。原句。后文。") }
        environment.navigation.destination = .notes
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        let editor = try await MilkdownTestSupport.editorAsync(in: host, id: noteID)
        try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: "原句"))
        try MilkdownTestSupport.script(editor, "document.querySelector('.ProseMirror').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:100,clientY:60}))")
        try MilkdownTestSupport.chooseMenu(editor, title: "AI 翻译")
        let model = NoteAIConversationStore.shared.model(for: noteID)
        try await wait("翻译进入右栏") { !model.conversation.record.messages.isEmpty }
        XCTAssertNil(AISelectionWindowController.shared.panel)
        XCTAssertEqual(model.conversation.record.messages.first?.text, AIConversationPreset.translate.question,
                       "翻译入口要携带中英互译问句，而不是润色问句")
        XCTAssertEqual(model.conversation.submittedSource?.content, "原句")
        XCTAssertEqual(model.conversation.submittedPreset, .translate)
        // fixture 返回的是纯文本（模型没按 workfollow-note 结果块的格式回）。
        // 翻译也必须投影成可采纳文稿，否则右栏不会出现"替换 / 插入"，
        // 用户拿到的就是一段只能复制、写不回选区的译文。
        try await wait("翻译结果可采纳") { !model.isRunning && model.conversation.latestWritingResult != nil }
        XCTAssertEqual(model.conversation.latestWritingResult, "第1轮回复：清楚的虚构文字")
        try await wait("翻译的替换按钮") { anchors["ai.selection.replace"] != nil }
        let replace = try XCTUnwrap(anchors["ai.selection.replace"])
        try InspectorPanelTestSupport.click(replace.bounds, in: replace, window: window)
        try await wait("翻译回写原选区") { editor.document.plainText == "前文。第1轮回复：清楚的虚构文字。后文。" }
        try await wait("消费翻译快照") { model.selectionTargets.isEmpty }
        model.stop(); model.clearSelectionTargets()
    }

    // MARK: - 会话窗的收起规则（没有右侧 AI 栏的宿主仍用独立浮窗）

    /// 笔记页的选区 AI 已改派右侧 AI 栏；任务详情等宿主没有这一栏，仍开浮窗。
    /// 下面几条浮窗收起回归用「不带 onSelectionAI 的独立编辑器」做宿主，
    /// 既保住原有覆盖面，也不会把右栏行为和弹层规则混在一起。
    private func plainEditorHost() -> (NSHostingView<AnyView>, NSWindow, UUID) {
        let id = UUID()
        let host = NSHostingView(rootView: AnyView(
            DocumentEditor(documentID: id, document: NativeDocument(plainText: "前文。原句。后文。"),
                           onDocumentChange: { _ in }, onEscape: { .keepInspector },
                           onEditingChanged: { _ in })
                .frame(width: 700, height: 400)))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 700, height: 400)
        return (host, window, id)
    }

    private func openSelectionConversation(in host: NSView, noteID: UUID) async throws {
        let editor = try await MilkdownTestSupport.editorAsync(in: host, id: noteID)
        try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: "原句"))
        try MilkdownTestSupport.script(editor, "document.querySelector('.ProseMirror').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:100,clientY:60}))")
        try MilkdownTestSupport.chooseMenu(editor, title: "AI 润色")
        try await wait("AI 润色会话窗未打开") { AISelectionWindowController.shared.panel != nil }
    }

    /// 切页面隐藏同一份会话，切回原样恢复，不重新生成。
    /// 笔记页不再有浮窗，这里直接驱动控制器的切页钩子，规则本身仍在生效。
    func testPageSwitchHidesAndRestoresSelectionConversation() async throws {
        let environment = try fixture(); defer { _ = environment }
        let (host, window, id) = plainEditorHost()
        defer { window.contentView = nil; window.close() }

        try await openSelectionConversation(in: host, noteID: id)
        let panel = try XCTUnwrap(AISelectionWindowController.shared.panel)
        let model = try XCTUnwrap(AISelectionWindowController.shared.model)

        AISelectionWindowController.shared.hideForPageSwitch()
        try await wait("切页后会话窗未隐藏") {
            AISelectionWindowController.shared.panel === panel && !panel.isVisible
        }
        XCTAssertTrue(AISelectionWindowController.shared.model === model, "隐藏不应销毁会话")
        // 隐藏期间 key window 变化也不会把这个会话窗收掉。
        PopupInteractionRegistry.shared.dismissOutsideFamily(of: window)
        XCTAssertTrue(AISelectionWindowController.shared.panel === panel)

        AISelectionWindowController.shared.restoreIfNeeded()
        try await wait("切回后会话窗未恢复") {
            AISelectionWindowController.shared.panel === panel && panel.isVisible
        }
        XCTAssertTrue(AISelectionWindowController.shared.model === model, "恢复应是同一份会话，不重新生成")
    }

    /// 和其它弹层一致：Esc 与点浮窗以外都能收起会话窗。
    func testEscapeAndOutsideClickCloseSelectionConversation() async throws {
        let environment = try fixture(); defer { _ = environment }
        let (host, window, id) = plainEditorHost()
        defer { window.contentView = nil; window.close() }

        try await openSelectionConversation(in: host, noteID: id)
        let panel = try XCTUnwrap(AISelectionWindowController.shared.panel)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: panel))
        try await wait("Esc 后会话窗未关闭") { AISelectionWindowController.shared.panel == nil }

        try await openSelectionConversation(in: host, noteID: id)
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 420, y: 180), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        _ = PopupInteractionRegistry.shared.routeMouseDown(outside)
        try await wait("点外部后会话窗未关闭") { AISelectionWindowController.shared.panel == nil }
    }

    /// 切到别的 App 不打断流式生成：失焦清场豁免会话窗，点主窗口仍按弹层规则收起。
    func testAppDeactivationKeepsSelectionConversation() async throws {
        let environment = try fixture(); defer { _ = environment }
        let (host, window, id) = plainEditorHost()
        defer { window.contentView = nil; window.close() }

        try await openSelectionConversation(in: host, noteID: id)
        let panel = try XCTUnwrap(AISelectionWindowController.shared.panel)
        PopupInteractionRegistry.shared.dismissAll()
        PopupInteractionRegistry.shared.dismissOutsideFamily(of: nil)
        XCTAssertTrue(AISelectionWindowController.shared.panel === panel, "应用失焦不该收起正在生成的会话窗")
        XCTAssertTrue(panel.isVisible)

        // key window 归属变化也不该销毁会话窗：它不是锚在控件上的弹层。
        PopupInteractionRegistry.shared.dismissOutsideFamily(of: window)
        XCTAssertTrue(AISelectionWindowController.shared.panel === panel)

        // 点浮窗以外（.outsideClick）才收起。
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 420, y: 180), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        _ = PopupInteractionRegistry.shared.routeMouseDown(outside)
        try await wait("点主窗口后会话窗未关闭") { AISelectionWindowController.shared.panel == nil }
    }

    /// 真实失焦/恢复的回归：App 隐藏再恢复后，会话窗应仍可见、生成结果仍在。
    /// 用 hide/unhide 触发 didResignActive，不切到别的 App、不每次截屏；
    /// 真机截图由验收时单独留图（/tmp/wf-ai-window.png）。
    func testRealAppSwitchKeepsConversationVisible() async throws {
        let environment = try fixture(); defer { _ = environment }
        let (host, window, id) = plainEditorHost()
        defer { window.contentView = nil; window.close() }

        try await openSelectionConversation(in: host, noteID: id)
        let panel = try XCTUnwrap(AISelectionWindowController.shared.panel)
        NSApp.activate(ignoringOtherApps: true)
        try await _Concurrency.Task.sleep(for: .milliseconds(150))
        let activeBefore = NSApp.isActive
        NSApp.hide(nil)
        try await _Concurrency.Task.sleep(for: .milliseconds(400))
        let activeDuring = NSApp.isActive
        NSApp.unhide(nil)
        try await _Concurrency.Task.sleep(for: .milliseconds(300))

        print("[WF-LIVE] active before=\(activeBefore) while hidden=\(activeDuring) after=\(NSApp.isActive)")
        XCTAssertTrue(AISelectionWindowController.shared.panel === panel, "App 失焦再恢复后会话窗应还在")
        XCTAssertTrue(panel.isVisible)
        XCTAssertNotNil(AISelectionWindowController.shared.model, "生成会话不应被中断")
        print("[WF-LIVE] panel=\(panel.title) frame=\(panel.frame) visible=\(panel.isVisible)")
    }
}
