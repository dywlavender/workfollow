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
        await withCheckedContinuation { resume in store.flush { error in XCTAssertNil(error); resume.resume() } }
        let restored = AIChatStore(directory: directory)
        XCTAssertEqual(restored.records.count, 2)
        XCTAssertEqual(restored.current.latestResult, "第二答")
        restored.select(firstID)
        XCTAssertEqual(restored.current.latestResult, "第一答")
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
        let editor = try XCTUnwrap(handle.textView)
        editor.setSelectedRange((editor.string as NSString).range(of: "原来的文字"))
        let target = try XCTUnwrap(AISelectionTarget(editor: editor))
        XCTAssertTrue(target.apply("润色后的文字", inserting: false))
        XCTAssertEqual(editor.string, "开头。润色后的文字。结尾。")
        editor.undoDocumentEdit()
        XCTAssertEqual(editor.string, "开头。原来的文字。结尾。")
        editor.setSelectedRange((editor.string as NSString).range(of: "原来的文字"))
        let insert = try XCTUnwrap(AISelectionTarget(editor: editor))
        XCTAssertTrue(insert.apply("新增文字", inserting: true))
        XCTAssertEqual(editor.string, "开头。原来的文字\n新增文字。结尾。")
        editor.undoDocumentEdit()
        let stale = try XCTUnwrap(AISelectionTarget(editor: editor))
        editor.documentIdentity = UUID()
        XCTAssertFalse(stale.apply("不能写到其他笔记", inserting: false))
    }
}
