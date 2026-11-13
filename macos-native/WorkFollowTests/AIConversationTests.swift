import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Conversation did not settle")
    }

    func testMultipleTurnsSharePiSessionAndStreamBeforeCompletion() async throws {
        let model = AIConversationModel(scene: .selection, context: "虚构选区")
        var calls: [UUID] = []
        let generate: AIConversationModel.Generate = { id, scene, context, message, updates in
            calls.append(id)
            XCTAssertEqual(scene, .selection); XCTAssertEqual(context, "虚构选区")
            updates(.init(kind: "text", text: "正在改写", message: nil))
            try await _Concurrency.Task.sleep(for: .milliseconds(60))
            return "完整结果：" + message
        }
        model.input = "请润色"; model.send(using: generate)
        try await wait { model.record.messages.last?.text == "正在改写" }
        XCTAssertTrue(model.isRunning); XCTAssertNil(model.latestResult)
        try await wait { !model.isRunning }
        model.input = "更简洁"; model.send(using: generate)
        try await wait { !model.isRunning }
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(model.record.messages.count, 4)
        XCTAssertEqual(model.latestResult, "完整结果：更简洁")
    }

    func testStopPreservesPartialAndIgnoresLateReplyWhileNextTurnCompletes() async throws {
        let model = AIConversationModel()
        var resume: CheckedContinuation<String, Never>?
        model.input = "第一问"
        model.send { _, _, _, _, updates in
            updates(.init(kind: "text", text: "部分回复", message: nil))
            return await withCheckedContinuation { resume = $0 }
        }
        try await wait { resume != nil && model.record.messages.last?.text == "部分回复" }
        model.stop()
        XCTAssertEqual(model.record.messages.last?.state, .stopped)
        XCTAssertEqual(model.record.messages.last?.text, "部分回复")
        model.input = "第二问"; model.send { _, _, _, _, _ in "第二答" }
        try await wait { !model.isRunning }
        resume?.resume(returning: "过时回复")
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.latestResult, "第二答")
        XCTAssertEqual(model.record.messages[1].state, .stopped)
    }

    func testErrorKeepsQuestionAndAllowsNextMessage() async throws {
        let model = AIConversationModel()
        model.input = "虚构问题"
        model.send { _, _, _, _, _ in throw AIBackendError.disconnected }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.record.messages.first?.text, "虚构问题")
        XCTAssertEqual(model.record.messages.last?.state, .failed)
        XCTAssertNotNil(model.record.messages.last?.error); XCTAssertNil(model.latestResult)
        model.input = "再试一次"; XCTAssertTrue(model.canSend)
    }

    func testNoteSidebarFollowupsShareContextAndResetStartsAnotherSession() async throws {
        let model = NoteAIConversationModel()
        let context = NoteAIContext(noteID: UUID(), title: "虚构笔记", content: "等待核对。",
                                    referenceDate: Date(), existingTitles: [])
        var ids: [UUID?] = []
        let generate: AIConversationModel.Generate = { id, _, _, _, _ in ids.append(id); return "笔记结果" }
        model.ask(.polish, context: context, using: generate)
        try await wait { !model.isRunning }
        model.input = "再简洁一点"; model.send(context: context, using: generate)
        try await wait { !model.isRunning }
        XCTAssertNotNil(ids[0]); XCTAssertEqual(ids[0], ids[1])
        model.reset(); model.ask(.organize, context: context, using: generate)
        try await wait { !model.isRunning }
        XCTAssertNotEqual(ids[1], ids[2])
    }

    func testHistorySurvivesRelaunchAndNewConversationHasIndependentID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory)
        let firstID = store.current.record.id
        store.current.input = "第一份虚构问题"; store.current.send { _, _, _, _, _ in "第一答" }
        try await wait { !store.current.isRunning }
        store.newConversation()
        XCTAssertNotEqual(store.current.record.id, firstID)
        store.current.input = "第二份虚构问题"; store.current.send { _, _, _, _, _ in "第二答" }
        try await wait { !store.current.isRunning }
        let project = try XCTUnwrap(store.projects.create("项目甲"))
        store.projects.move(firstID, to: project)
        await withCheckedContinuation { resume in store.flush { error in XCTAssertNil(error); resume.resume() } }
        let restored = AIChatStore(directory: directory)
        XCTAssertEqual(restored.records.count, 2)
        XCTAssertEqual(restored.current.latestResult, "第二答")
        XCTAssertEqual(restored.projects.folderID(for: firstID), project)
        XCTAssertNil(restored.projects.folderID(for: restored.current.record.id))
        restored.select(firstID)
        XCTAssertEqual(restored.current.latestResult, "第一答")
        restored.projects.remove(project)
        XCTAssertNil(restored.projects.folderID(for: firstID))
        XCTAssertEqual(restored.current.latestResult, "第一答")
        await withCheckedContinuation { resume in restored.flush { error in XCTAssertNil(error); resume.resume() } }
    }

    func testSwitchingAndNewConversationKeepBackgroundStreamDraftAndReceipts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-switch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), first = store.current
        var resume: CheckedContinuation<String, Never>?
        var updates: (@Sendable (AITextUpdate) -> Void)?
        defer { first.stop(); resume?.resume(returning: "清理") }
        first.input = "第一问"
        first.send { _, _, _, _, receive in
            updates = receive
            receive(.init(kind: "text", text: "部分回复"))
            return await withCheckedContinuation { resume = $0 }
        }
        try await wait { resume != nil && first.record.messages.last?.text == "部分回复" }
        first.input = "下一问草稿"
        let attachment = directory.appendingPathComponent("草稿.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "虚构附件".write(to: attachment, atomically: true, encoding: .utf8)
        first.attachments.add(files: [attachment])
        try await wait { !first.attachments.isImporting }
        let files = first.attachments.items
        XCTAssertEqual(files.count, 1)
        store.newConversation()
        let second = store.current
        second.input = "第二问"; second.send { _, _, _, _, _ in "第二答" }
        try await wait { !second.isRunning }
        XCTAssertTrue(first.isRunning)
        XCTAssertEqual(store.runningIDs, [first.record.id]); XCTAssertTrue(store.isAnyRunning)
        store.select(first.record.id)
        XCTAssertTrue(store.current === first)
        XCTAssertEqual(first.input, "下一问草稿"); XCTAssertEqual(first.attachments.items, files)
        store.select(second.record.id)
        updates?(.init(kind: "text", text: "后台继续回复"))
        let undoID = UUID()
        store.recordAction(.init(title: "虚构笔记", details: "已保存", undoID: undoID), conversationID: first.record.id)
        store.markUndone(undoID)
        try await wait { store.records.first(where: { $0.id == first.record.id })?.messages.last?.text == "后台继续回复" }
        let completion = resume; resume = nil; completion?.resume(returning: "第一答已完成")
        try await wait { !first.isRunning && store.runningIDs.isEmpty }
        XCTAssertFalse(store.isAnyRunning); XCTAssertTrue(store.current === second)
        let saved = try XCTUnwrap(store.records.first(where: { $0.id == first.record.id }))
        XCTAssertEqual(saved.messages.last?.text, "第一答已完成")
        XCTAssertEqual(saved.messages.last?.actions?.first?.undone, true)
        await withCheckedContinuation { continuation in store.flush { error in XCTAssertNil(error); continuation.resume() } }
        let restored = AIChatStore(directory: directory)
        restored.select(first.record.id)
        XCTAssertEqual(restored.current.latestResult, "第一答已完成")
        XCTAssertEqual(restored.current.record.messages.last?.actions?.first?.undone, true)
        XCTAssertTrue(restored.runningIDs.isEmpty)
    }

    /// 后台完成的会话产生未读点：选中即清、手动停止不留点、未读状态跨启动保留。
    func testBackgroundCompletionMarksUnviewedUntilSelectionAndSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-unviewed-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), first = store.current
        var resume: CheckedContinuation<String, Never>?
        var stoppedResume: CheckedContinuation<String, Never>?
        defer {
            first.stop()
            resume?.resume(returning: "清理"); stoppedResume?.resume(returning: "清理")
        }
        first.input = "第一问"
        first.send { _, _, _, _, _ in await withCheckedContinuation { resume = $0 } }
        try await wait { resume != nil }
        store.newConversation()
        let second = store.current
        second.input = "第二问"; second.send { _, _, _, _, _ in "第二答" }
        try await wait { !second.isRunning }
        XCTAssertTrue(store.unviewedIDs.isEmpty, "选中会话完成不应产生未读点")
        let completion = resume; resume = nil; completion?.resume(returning: "第一答已完成")
        try await wait { !first.isRunning && store.unviewedIDs.contains(first.record.id) }

        // 点开查看后未读点消失；手动停止只是结束，不算完成输出，不留点。
        store.select(first.record.id)
        XCTAssertFalse(store.unviewedIDs.contains(first.record.id))
        first.input = "第三问"
        first.send { _, _, _, _, _ in await withCheckedContinuation { stoppedResume = $0 } }
        try await wait { stoppedResume != nil }
        store.newConversation()
        first.stop()
        try await wait { !first.isRunning && !store.unviewedIDs.contains(first.record.id) }
        XCTAssertEqual(first.record.messages.last?.state, .stopped)

        // 再跑一轮后台完成，重启后未读点保留，但选中的会话不带点，点开即清。
        first.input = "第四问"
        first.send { _, _, _, _, _ in await withCheckedContinuation { resume = $0 } }
        try await wait { resume != nil }
        let final = resume; resume = nil; final?.resume(returning: "第四答已完成")
        try await wait { !first.isRunning && store.unviewedIDs.contains(first.record.id) }
        await withCheckedContinuation { continuation in store.flush { _ in continuation.resume() } }
        let restored = AIChatStore(directory: directory)
        XCTAssertTrue(restored.unviewedIDs.contains(first.record.id), "未读点应跨启动保留")
        XCTAssertFalse(restored.unviewedIDs.contains(restored.current.record.id), "选中的会话不应带未读点")
        restored.select(first.record.id)
        XCTAssertFalse(restored.unviewedIDs.contains(first.record.id))
    }

    func testConcurrentConversationsStopAndDeleteOnlyTheirOwnExecution() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-concurrent-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), first = store.current
        var firstResume: CheckedContinuation<String, Never>?
        var secondResume: CheckedContinuation<String, Never>?
        first.input = "第一问"
        first.send { _, _, _, _, _ in await withCheckedContinuation { firstResume = $0 } }
        try await wait { firstResume != nil }
        store.newConversation()
        let second = store.current
        defer {
            first.stop(); second.stop()
            firstResume?.resume(returning: "清理"); secondResume?.resume(returning: "清理")
        }
        second.input = "第二问"
        second.send { _, _, _, _, _ in await withCheckedContinuation { secondResume = $0 } }
        try await wait { secondResume != nil }
        XCTAssertEqual(store.runningIDs, [first.record.id, second.record.id])
        store.select(first.record.id); first.stop()
        XCTAssertTrue(second.isRunning)
        XCTAssertEqual(store.runningIDs, [second.record.id]); XCTAssertTrue(store.isAnyRunning)
        await store.delete(second.record.id) { _ in }
        XCTAssertFalse(second.isRunning); XCTAssertTrue(store.runningIDs.isEmpty)
        XCTAssertTrue(store.current === first); XCTAssertFalse(store.isAnyRunning)
        let late = secondResume; secondResume = nil; late?.resume(returning: "迟到回复")
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.records.map(\.id), [first.record.id])
    }

    func testBackgroundFailureClearsRunningStateAndDeleteReusesAnotherRunningModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-background-failure-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), first = store.current
        var resume: CheckedContinuation<Void, Never>?
        defer { first.stop(); resume?.resume() }
        first.input = "第一问"
        first.send { _, _, _, _, _ in
            await withCheckedContinuation { resume = $0 }
            throw AIBackendError.disconnected
        }
        try await wait { resume != nil }
        store.newConversation()
        let second = store.current
        second.input = "第二问"; second.send { _, _, _, _, _ in "第二答" }
        try await wait { !second.isRunning }
        await store.delete(second.record.id) { _ in }
        XCTAssertTrue(store.current === first); XCTAssertTrue(first.isRunning)
        store.newConversation()
        let completion = resume; resume = nil; completion?.resume()
        try await wait { !first.isRunning }
        XCTAssertTrue(store.runningIDs.isEmpty); XCTAssertFalse(store.isAnyRunning)
        XCTAssertEqual(store.records.first?.messages.last?.state, .failed)
        XCTAssertNotEqual(store.current.record.id, first.record.id)
    }

    func testRelaunchDoesNotRestoreBackgroundExecutionIndicators() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-restore-running-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), first = store.current
        var resume: CheckedContinuation<String, Never>?
        defer { first.stop(); resume?.resume(returning: "清理") }
        first.input = "第一问"
        first.send { _, _, _, _, _ in await withCheckedContinuation { resume = $0 } }
        try await wait { resume != nil }
        store.newConversation()
        store.current.input = "第二问"; store.current.send { _, _, _, _, _ in "第二答" }
        try await wait { !store.current.isRunning }
        await withCheckedContinuation { continuation in store.flush { _ in continuation.resume() } }
        let restored = AIChatStore(directory: directory)
        XCTAssertFalse(restored.isAnyRunning); XCTAssertTrue(restored.runningIDs.isEmpty)
        XCTAssertEqual(restored.records.first(where: { $0.id == first.record.id })?.messages.last?.state, .stopped)
        restored.select(first.record.id)
        XCTAssertFalse(restored.current.isRunning)
        XCTAssertFalse(restored.current === first)
    }

    func testDeletingHistoryKeepsCurrentOrSelectsRemainingAndSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-delete-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory)
        var ids: [UUID] = []
        for question in ["第一段", "第二段", "第三段"] {
            ids.append(store.current.record.id)
            store.current.input = question; store.current.send { _, _, _, _, _ in "虚构回答" }
            try await wait { !store.current.isRunning }
            if question != "第三段" { store.newConversation() }
        }
        var removed: [UUID] = []
        await store.delete(ids[0]) { removed.append($0) }
        XCTAssertEqual(store.current.record.id, ids[2])
        await store.delete(ids[2]) { removed.append($0) }
        XCTAssertEqual(store.current.record.id, ids[1])
        XCTAssertEqual(store.current.latestResult, "虚构回答")
        await withCheckedContinuation { resume in store.flush { error in XCTAssertNil(error); resume.resume() } }
        let restored = AIChatStore(directory: directory)
        XCTAssertEqual(restored.records.map(\.id), [ids[1]])
        XCTAssertEqual(restored.current.record.id, ids[1])
        await restored.delete(ids[1]) { removed.append($0) }
        XCTAssertEqual(removed, [ids[0], ids[2], ids[1]])
        XCTAssertTrue(restored.records.isEmpty)
        XCTAssertTrue(restored.current.record.messages.isEmpty)
        XCTAssertFalse(ids.contains(restored.current.record.id))
        await withCheckedContinuation { resume in restored.flush { error in XCTAssertNil(error); resume.resume() } }
        XCTAssertTrue(AIChatStore(directory: directory).records.isEmpty)
    }

    func testDeletingRunningConversationStopsAndIgnoresLateReply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-chat-delete-running-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIChatStore(directory: directory), model = store.current
        var resume: CheckedContinuation<String, Never>?
        model.input = "虚构问题"
        model.send { _, _, _, _, _ in await withCheckedContinuation { resume = $0 } }
        try await wait { resume != nil }
        await store.delete(model.record.id) { _ in }
        XCTAssertFalse(model.isRunning)
        XCTAssertNotEqual(store.current.record.id, model.record.id)
        resume?.resume(returning: "迟到的回复")
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(store.records.isEmpty)
        await withCheckedContinuation { resume in store.flush { error in XCTAssertNil(error); resume.resume() } }
        XCTAssertTrue(AIChatStore(directory: directory).records.isEmpty)
    }

    func testSelectionReplacementAndInsertionKeepSurroundingTextAndUndo() async throws {
        let id = UUID(), handle = DocumentEditorHandle()
        var document = NativeDocument(plainText: "开头。原来的文字。结尾。")
        let host = NSHostingView(rootView: DocumentEditor(documentID: id, document: document,
            onDocumentChange: { document = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in }, handle: handle))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 800, height: 500)
        defer { window.contentView = nil; window.close() }
        let editor = try await MilkdownTestSupport.editorAsync(in: host, id: id)
        try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: "原来的文字"))
        let target = try XCTUnwrap(AISelectionTarget(editor: editor, selection: MilkdownTestSupport.selection(editor)))
        let replaced = await target.applyAsync("润色后的文字", inserting: false)
        XCTAssertTrue(replaced); await editor.flush()
        XCTAssertEqual(editor.document.plainText, "开头。润色后的文字。结尾。")
        try MilkdownTestSupport.command(editor, "undo")
        XCTAssertEqual(editor.document.plainText, "开头。原来的文字。结尾。")
        try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: "原来的文字"))
        let insert = try XCTUnwrap(AISelectionTarget(editor: editor, selection: MilkdownTestSupport.selection(editor)))
        let inserted = await insert.applyAsync("新增文字", inserting: true)
        XCTAssertTrue(inserted); await editor.flush()
        XCTAssertEqual(editor.document.plainText, "开头。原来的文字\n新增文字。结尾。")
        try MilkdownTestSupport.command(editor, "undo")
        try MilkdownTestSupport.select(editor, (editor.document.plainText as NSString).range(of: "原来的文字"))
        let stale = try XCTUnwrap(AISelectionTarget(editor: editor, selection: MilkdownTestSupport.selection(editor)))
        let other = UUID()
        editor.bind(.init(id: other, document: .empty, profile: .init(), readOnly: false, fontSize: 14,
            onChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in }), handle: handle)
        _ = try await MilkdownTestSupport.editorAsync(in: host, id: other)
        let rejected = await stale.applyAsync("不能写到其他笔记", inserting: false)
        XCTAssertFalse(rejected)
    }

    func testCompletedReplyStampsOutputTimeAndSurvivesPersistence() async throws {
        let model = AIConversationModel()
        model.input = "第一问"
        model.send { _, _, _, _, _ in "第一答" }
        XCTAssertNil(model.record.messages.last?.completedAt)
        try await wait { !model.isRunning }
        let reply = try XCTUnwrap(model.record.messages.last)
        XCTAssertEqual(reply.state, .complete)
        let stamp = try XCTUnwrap(reply.completedAt)
        XCTAssertLessThanOrEqual(abs(stamp.timeIntervalSinceNow), 5)

        let data = try JSONEncoder().encode(model.record)
        let restored = try JSONDecoder().decode(AIConversationRecord.self, from: data)
        XCTAssertEqual(restored.messages.last?.completedAt, stamp)

        // 旧快照没有 completedAt 键：解码为 nil，不影响其余字段。
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var messages = legacy["messages"] as! [[String: Any]]
        messages[messages.count - 1].removeValue(forKey: "completedAt")
        legacy["messages"] = messages
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyRecord = try JSONDecoder().decode(AIConversationRecord.self, from: legacyData)
        XCTAssertNil(legacyRecord.messages.last?.completedAt)
        XCTAssertEqual(legacyRecord.messages.last?.text, "第一答")
    }

    func testStoppedAndFailedRepliesAlsoStampOutputTime() async throws {
        let stopped = AIConversationModel()
        stopped.input = "问"
        stopped.send { _, _, _, _, updates in
            updates(.init(kind: "text", text: "部分", message: nil))
            try await _Concurrency.Task.sleep(for: .milliseconds(200))
            return "完整"
        }
        try await wait { stopped.record.messages.last?.text == "部分" }
        stopped.stop()
        XCTAssertNotNil(stopped.record.messages.last?.completedAt)

        let failed = AIConversationModel()
        failed.input = "问"
        failed.send { _, _, _, _, _ in throw AIBackendError.disconnected }
        try await wait { !failed.isRunning }
        XCTAssertEqual(failed.record.messages.last?.state, .failed)
        XCTAssertNotNil(failed.record.messages.last?.completedAt)
    }

    func testCompletedAtLabelScalesFromTimeToDateAcrossDaysAndYears() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 30))!
        func label(_ components: DateComponents) -> String? {
            var message = AIConversationMessage(role: .assistant, text: "答")
            message.completedAt = calendar.date(from: components)
            return message.completedAtLabel(now: now, calendar: calendar)
        }
        XCTAssertEqual(label(DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 5)), "09:05")
        XCTAssertEqual(label(DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 59)), "11月11日 23:59")
        XCTAssertEqual(label(DateComponents(year: 2025, month: 1, day: 2, hour: 8, minute: 0)), "2025年1月2日 08:00")
        var noStamp = AIConversationMessage(role: .assistant, text: "答")
        noStamp.completedAt = nil
        XCTAssertNil(noStamp.completedAtLabel(now: now, calendar: calendar))
    }
}
