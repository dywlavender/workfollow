import XCTest
@testable import WorkFollow

@MainActor
final class NoteAIConversationTests: XCTestCase {
    private func context() -> NoteAIContext {
        .init(noteID: UUID(), title: "海鸥方案", content: "周五发送报价。核对成本。", referenceDate: Date(), existingTitles: [])
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Open note conversation did not settle")
    }
    func testCanChatBeforeSelectingAnAction() async throws {
        let model = NoteAIConversationModel(), source = context()
        model.input = "你觉得这个方案怎么样？"
        XCTAssertTrue(model.canSend)
        model.send(context: source) { _, scene, _, question, _ in
            XCTAssertEqual(scene, .note)
            XCTAssertNil(model.conversation.submittedPreset)
            XCTAssertEqual(model.conversation.submittedSource?.id, source.noteID)
            XCTAssertEqual(question, "你觉得这个方案怎么样？")
            return "可以先核对成本，再决定报价。"
        }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.conversation.latestResult, "可以先核对成本，再决定报价。")
        XCTAssertTrue(model.exchanges.isEmpty)
    }
    func testExtractionIsOneQuestionAndFollowingDiscussionStaysOpen() async throws {
        let model = NoteAIConversationModel(), source = context()
        var presets: [AIConversationPreset?] = [], sessions: [UUID] = []
        let generate: AIConversationModel.Generate = { id, _, _, _, _ in
            sessions.append(id); presets.append(model.conversation.submittedPreset)
            if model.conversation.submittedPreset == .extract {
                return #"{"tasks":[{"title":"发送报价","date":"2026-10-30","priority":"high","quote":"周五发送报价。"}]}"#
            }
            return "需要先确认报价范围。"
        }
        model.ask(.extract, context: source, using: generate)
        try await wait { !model.isRunning }
        XCTAssertEqual(model.exchanges.first?.taskSession?.drafts.first?.title, "发送报价")
        XCTAssertEqual(model.exchanges.first?.taskSession?.drafts.first?.priority, .high)
        model.input = "为什么你认为这件事需要确认？"
        model.send(context: source, using: generate)
        try await wait { !model.isRunning }
        XCTAssertEqual(presets, [.extract, nil])
        XCTAssertEqual(sessions.first, sessions.last)
        XCTAssertEqual(model.exchanges.count, 1)
        XCTAssertEqual(model.conversation.latestResult, "需要先确认报价范围。")
    }
    func testFollowupCanUpdateCandidateWithoutSelectingAnAction() async throws {
        let model = NoteAIConversationModel(), source = context()
        model.ask(.extract, context: source) { _, _, _, _, _ in
            #"{"tasks":[{"title":"发送报价","quote":"周五发送报价。"}]}"#
        }
        try await wait { !model.isRunning }
        model.input = "把日期改到下周三"
        model.send(context: source) { _, _, _, _, _ in
            "已调整候选日期。\n```workfollow-tasks\n{\"tasks\":[{\"title\":\"发送报价\",\"date\":\"2026-11-04\",\"quote\":\"周五发送报价。\"}]}\n```"
        }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.exchanges.count, 2)
        XCTAssertNotNil(model.exchanges.last?.taskSession?.drafts.first?.schedule.dueAt)
        XCTAssertEqual(model.conversation.latestResult, "已调整候选日期。")
    }
    func testWritingResultRemainsEditableAndNextQuestionIsOrdinaryChat() async throws {
        let model = NoteAIConversationModel(), source = context()
        model.ask(.polish, context: source) { _, _, _, _, _ in "润色后的正文" }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.exchanges.first?.rewriteSession?.draft, "润色后的正文")
        model.exchanges.first?.rewriteSession?.draft = "手动修改后的正文"
        model.input = "为什么用这个表达？"
        model.send(context: source) { _, _, _, _, _ in "这个表达更简洁。" }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.exchanges.count, 1)
        XCTAssertEqual(model.exchanges.first?.rewriteSession?.draft, "手动修改后的正文")
        XCTAssertEqual(model.conversation.latestResult, "这个表达更简洁。")
    }
    func testStopAndRetryUseSharedConversationWithOriginalPreset() async throws {
        let model = NoteAIConversationModel(), source = context()
        var calls = 0
        let generate: AIConversationModel.Generate = { _, _, _, _, updates in
            calls += 1
            XCTAssertEqual(model.conversation.submittedPreset, .organize)
            if calls == 1 {
                updates(.init(kind: "text", text: "已写出的部分", message: nil))
                try await _Concurrency.Task.sleep(for: .seconds(30))
            }
            return "完整正文"
        }
        model.ask(.organize, context: source, using: generate)
        try await wait { model.conversation.record.messages.last?.text == "已写出的部分" }
        model.stop()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.conversation.record.messages.last?.state, .stopped)
        XCTAssertEqual(model.conversation.record.messages.last?.text, "已写出的部分")
        XCTAssertTrue(model.exchanges.isEmpty)
        let messageID = try XCTUnwrap(model.conversation.record.messages.last?.id)
        model.retry(messageID: messageID, using: generate)
        try await wait { !model.isRunning }
        XCTAssertEqual(model.exchanges.first?.rewriteSession?.draft, "完整正文")
        XCTAssertEqual(calls, 2)
    }
    func testNewConversationClearsResultsAndHasAnotherIdentity() async throws {
        let model = NoteAIConversationModel(), source = context()
        model.ask(.organize, context: source) { _, _, _, _, _ in "要点" }
        try await wait { !model.isRunning }
        let id = model.conversation.record.id
        model.reset()
        XCTAssertNotEqual(model.conversation.record.id, id)
        XCTAssertTrue(model.exchanges.isEmpty)
        model.input = "普通提问"
        XCTAssertTrue(model.canSend)
    }
    func testNativeAdoptionFeedsActualSavedIDsIntoNextQuestion() async throws {
        let model = NoteAIConversationModel(), source = context()
        model.ask(.extract, context: source) { _, _, _, _, _ in
            #"{"tasks":[{"title":"发送报价","quote":"周五发送报价。"}]}"#
        }
        try await wait { !model.isRunning }
        let saved = UUID()
        model.exchanges.first?.markApplied([saved])
        model.input = "把刚创建的待办改到明天"
        model.send(context: source) { _, _, context, _, _ in
            XCTAssertTrue(context.contains(NativeResourceLink.task(saved).url.absoluteString))
            XCTAssertTrue(context.contains("已创建为待办"))
            return "已读取保存的记录。"
        }
        try await wait { !model.isRunning }
    }
}
