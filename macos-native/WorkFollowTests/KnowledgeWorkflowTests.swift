import XCTest
@testable import WorkFollow

@MainActor
final class KnowledgeWorkflowTests: XCTestCase {
    private func environment() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("knowledge-workflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try NativePreviewRepository(directory: root).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(directory: root); environment.focusStore.notifier = nil
        return environment
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("AI workflow did not settle")
    }
    private var answer: KnowledgeAnswer { .init(paragraphs: [.init(text: "周五验收。", citations: [.init(source: "S1", quote: "周五验收。")])], insufficient: false, sourceIDs: ["S1"]) }

    func testNoSourcesDoesNotInvokeModelAndFailureCanBeRetried() async throws {
        let session = KnowledgeAnswerSession()
        let empty = KnowledgeCorpus(tasks: [], notes: [], meetings: [], currentList: nil)
        var calls = 0
        session.ask(question: "海鸥方案", corpus: empty) { _, _, _ in calls += 1; return self.answer }
        try await wait { session.phase == .noResults }
        XCTAssertEqual(calls, 0)
        let note = Note(id: UUID(), title: "海鸥方案", document: NativeDocument(plainText: "周五验收。"), folder: "工作", updatedAt: Date())
        let corpus = KnowledgeCorpus(tasks: [], notes: [note], meetings: [], currentList: nil)
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in throw SummaryPiError.timedOut }
        try await wait { if case .failed = session.phase { true } else { false } }
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in self.answer }
        try await wait { session.phase == .ready }
        XCTAssertEqual(session.answer, answer)
    }

    func testLateResponseOfCancelledQuestionCannotReplaceNewAnswer() async throws {
        let note = Note(id: UUID(), title: "海鸥方案", document: NativeDocument(plainText: "周五验收。"), folder: "工作", updatedAt: Date())
        let corpus = KnowledgeCorpus(tasks: [], notes: [note], meetings: [], currentList: nil)
        let session = KnowledgeAnswerSession()
        var reply: CheckedContinuation<KnowledgeAnswer, Never>?
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in
            await withCheckedContinuation { reply = $0 }
        }
        try await wait { reply != nil }
        session.ask(question: "海鸥", corpus: corpus) { _, _, _ in self.answer }
        try await wait { session.phase == .ready }
        reply?.resume(returning: .init(paragraphs: [], insufficient: true, sourceIDs: []))
        try await _Concurrency.Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(session.question, "海鸥")
        XCTAssertEqual(session.answer, answer)
    }

    func testRepeatedQuestionWhileBusyDoesNotRestartModelAndRateLimitBlocksImmediateRetry() async throws {
        let note = Note(id: UUID(), title: "海鸥方案", document: NativeDocument(plainText: "周五验收。"), folder: "工作", updatedAt: Date())
        let corpus = KnowledgeCorpus(tasks: [], notes: [note], meetings: [], currentList: nil)
        let session = KnowledgeAnswerSession()
        var reply: CheckedContinuation<KnowledgeAnswer, Error>?
        var calls = 0
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { reply = $0 }
        }
        try await wait { reply != nil }
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in calls += 1; return self.answer }
        XCTAssertEqual(calls, 1)
        reply?.resume(throwing: AIBackendError.service(code: "rate_limited", message: "速率限制", retryAfter: 30))
        try await wait { if case .failed = session.phase { true } else { false } }
        XCTAssertNotNil(session.retryAt)
        session.ask(question: "海鸥方案", corpus: corpus) { _, _, _ in calls += 1; return self.answer }
        XCTAssertEqual(calls, 1)
    }

    func testNoteCancellationRejectsLateProgressAndRetryCanFinish() async throws {
        let session = NoteRewriteSession()
        let request = NoteRewriteRequest(noteID: UUID(), title: "海鸥", content: "原文", action: .polish)
        var callback: (@Sendable (AITextUpdate) -> Void)?
        let first = _Concurrency.Task {
            await session.generate(request: request) { _, progress in
                callback = progress
                progress(.init(kind: "text", text: "正在输出的草稿"))
                try await _Concurrency.Task.sleep(for: .seconds(10))
                return "不应采用"
            }
        }
        try await wait { session.preview == "正在输出的草稿" }
        first.cancel(); await first.value
        XCTAssertTrue(session.draft.isEmpty)
        await session.generate(request: request) { _, _ in "完整结果" }
        callback?(.init(kind: "text", text: "取消后的旧消息"))
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.draft, "完整结果")
        XCTAssertTrue(session.preview.isEmpty)
    }

    func testSourceNavigationClearsNoteFiltersAndReturnsToAnswer() throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create(folder: "工作")
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案" }
        environment.notesWorkspace.folderFilter = "其他"
        environment.notesWorkspace.favoritesOnly = true
        let source = KnowledgePassage(id: "S1", kind: .note, resourceID: id, title: "海鸥方案", content: "原文", date: Date(), location: "工作")
        environment.commandPalettePresented = true
        XCTAssertTrue(environment.openKnowledgeSource(source))
        XCTAssertEqual(environment.navigation.destination, .notes)
        XCTAssertEqual(environment.notesWorkspace.selectedID, id)
        XCTAssertNil(environment.notesWorkspace.folderFilter)
        XCTAssertFalse(environment.notesWorkspace.favoritesOnly)
        XCTAssertFalse(environment.commandPalettePresented)
        environment.feedback.openDestination()
        XCTAssertTrue(environment.commandPalettePresented)
    }

    func testMeetingSourceRevealsSpecificLineAndTasksUseOriginalSpeech() throws {
        let environment = try environment()
        let store = environment.meetingStore; store.create()
        store.appendTranscriptForTesting("周五验收。", speaker: "未区分")
        store.editMinutes("错误旧纪要：周一验收。")
        let meeting = try XCTUnwrap(store.selected)
        let request = environment.aiTaskRequest(for: meeting)
        XCTAssertTrue(request.content.contains("周五验收。"))
        XCTAssertFalse(request.content.contains("周一验收。"))
        let lineID = try XCTUnwrap(meeting.transcript.first?.id)
        let source = KnowledgePassage(id: "S1", kind: .meeting, resourceID: meeting.id, lineID: lineID,
            title: meeting.title, content: "周五验收。", date: meeting.createdAt, location: "00:00")
        XCTAssertTrue(environment.openKnowledgeSource(source))
        XCTAssertEqual(environment.navigation.destination, .meetings)
        XCTAssertEqual(store.transcriptRevealRequest?.lineID, lineID)
        let first = store.transcriptRevealRequest
        store.revealTranscript(meetingID: meeting.id, lineID: lineID)
        XCTAssertNotEqual(store.transcriptRevealRequest, first, "同一来源可再次定位")
    }

    func testNoteAIAdoptionPreservesSourceAndCreatesFormattedLinkedNote() throws {
        let environment = try environment()
        let id = environment.notesWorkspace.create(folder: "工作")
        environment.notesWorkspace.edit(id) { $0.title = "海鸥方案"; $0.document = NativeDocument(plainText: "原始正文和附件应保留。") }
        let original = try XCTUnwrap(environment.notesWorkspace.selected)
        let request = NoteRewriteRequest(noteID: id, title: original.title, content: original.document.plainText, action: .organize)
        let nextID = try environment.notesWorkspace.createAIRewrite("# 要点\n- 核对成本。", request: request)
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == id }, original)
        let next = try XCTUnwrap(environment.notesWorkspace.notes.first { $0.id == nextID })
        XCTAssertEqual(next.folder, original.folder)
        XCTAssertEqual(next.title, "海鸥方案（要点）")
        XCTAssertTrue(next.document.blocks.contains { if case .heading = $0.kind { true } else { false } })
        XCTAssertTrue(next.document.blocks.flatMap(\.runs).contains { $0.marks.contains(.link(NativeResourceLink.note(id).url.absoluteString)) })
    }
}
