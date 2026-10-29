import XCTest
@testable import WorkFollow

@MainActor
final class NoteAIConversationTests: XCTestCase {
    private func context(instruction: String = "") -> NoteAIContext {
        NoteAIContext(noteID: UUID(), title: "海鸥方案",
                      content: "周五发送报价。核对成本。",
                      referenceDate: Date(timeIntervalSince1970: 1_793_000_000),
                      existingTitles: [])
    }

    private func generators(tasks: @escaping (AITaskRequest) -> String = { _ in
        #"{"tasks":[{"title":"发送报价","date":"2026-10-30","due":null,"priority":"high","quote":"周五发送报价。"}]}"#
    }, rewrite: @escaping (NoteRewriteRequest) -> String = { _ in "整理后的正文" },
       recorded: Instructions = Instructions()) -> NoteAIGenerators {
        NoteAIGenerators(
            tasks: { request, _ in
                recorded.append(request.instruction)
                return tasks(request)
            },
            rewrite: { request, _ in
                recorded.append(request.instruction)
                return rewrite(request)
            })
    }

    private final class Instructions {
        private(set) var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }

    private func waitFor(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("conversation did not settle")
    }

    private func tasksReady(_ session: AITaskDraftSession?) -> Bool {
        guard let session else { return false }
        if case .ready = session.phase { return true }
        return false
    }

    private func rewriteReady(_ session: NoteRewriteSession?) -> Bool {
        guard let session else { return false }
        if case .ready = session.phase { return true }
        return false
    }

    func testExtractKeepsInstructionAndReRunsLastAction() async throws {
        let model = NoteAIConversationModel()
        let recorded = Instructions()
        let input = context()
        let output = generators(recorded: recorded)

        let first = try XCTUnwrap(model.run(action: .extract, context: input,
                                            instruction: "只提取工作", generators: output))
        try await waitFor { self.tasksReady(first.taskSession) }
        XCTAssertEqual(recorded.values, ["只提取工作"])
        XCTAssertEqual(first.taskSession?.drafts.count, 1)
        XCTAssertEqual(first.taskSession?.drafts.first?.title, "发送报价")
        XCTAssertEqual(first.taskSession?.drafts.first?.priority, .high)
        XCTAssertNotNil(first.taskSession?.drafts.first?.plan.schedule.dueAt)

        model.input = "更短"
        let second = try XCTUnwrap(model.rerunLast(context: input, generators: output))
        try await waitFor { self.tasksReady(second.taskSession) }
        XCTAssertEqual(model.exchanges.count, 2)
        XCTAssertEqual(second.action, .extract)
        XCTAssertEqual(second.instruction, "更短")
        XCTAssertEqual(recorded.values, ["只提取工作", "更短"])
    }

    func testRewriteCarriesInstructionAndKeepsDraftEditable() async throws {
        let model = NoteAIConversationModel()
        let recorded = Instructions()
        let exchange = try XCTUnwrap(model.run(action: .polish, context: context(),
                                               instruction: "保留专有名词",
                                               generators: generators(recorded: recorded)))
        try await waitFor { self.rewriteReady(exchange.rewriteSession) }
        XCTAssertEqual(recorded.values, ["保留专有名词"])
        XCTAssertEqual(exchange.rewriteRequest?.instruction, "保留专有名词")
        XCTAssertEqual(exchange.rewriteSession?.draft, "整理后的正文")
    }

    func testConcurrentActionIsIgnoredWhileGenerating() async throws {
        let model = NoteAIConversationModel()
        let output = NoteAIGenerators(
            tasks: { _, _ in
                try await _Concurrency.Task.sleep(nanoseconds: 40_000_000)
                return #"{"tasks":[]}"#
            },
            rewrite: { _, _ in "正文" })
        let first = try XCTUnwrap(model.run(action: .extract, context: context(),
                                            instruction: "", generators: output))
        XCTAssertNil(model.run(action: .polish, context: context(), instruction: "",
                               generators: output))
        XCTAssertEqual(model.exchanges.count, 1)
        try await waitFor { self.tasksReady(first.taskSession) }
    }
}
