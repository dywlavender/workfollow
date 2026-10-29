import XCTest
@testable import WorkFollow

/// Explicit opt-in, fictional corpus only. Runs production retrieval, native
/// transport and the bundled backend against the user's chosen local Pi model.
@MainActor
final class AIWorkflowLiveTests: XCTestCase {
    func testFictionalCorpusAndNotesThroughRealPi() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard variables["WORKFOLLOW_AI_WORKFLOW_LIVE"] == "1" else {
            throw XCTSkip("Enable WORKFOLLOW_AI_WORKFLOW_LIVE=1 for fictional real-model tests")
        }
        let model = try XCTUnwrap(variables["WORKFOLLOW_AI_LIVE_MODEL"])
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf:
            repo.appendingPathComponent("backend/tests/fixtures/ai-workflow-fictional.json"))) as? [String: String])
        let output = URL(fileURLWithPath: variables["WORKFOLLOW_AI_LIVE_OUTPUT"] ??
            FileManager.default.temporaryDirectory.appendingPathComponent("workfollow-ai-workflow-live.json").path)
        var records: [[String: Any]] = []
        func save() {
            try? JSONSerialization.data(withJSONObject: ["data": "fictional only", "model": model, "results": records], options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
        }
        defer { save() }
        var client = SummaryPiOptimizer(); client.model = model
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-29T12:00:00+08:00"))
        let task = Task(id: UUID(), title: "海鸥验收", document: NativeDocument(plainText: "验收负责人未指定。"), list: TaskList(name: "海鸥项目"),
            priority: .high, schedule: TaskSchedule(), parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        let old = Note(id: UUID(), title: "海鸥旧计划", document: NativeDocument(plainText: "2026-10-23：海鸥项目原计划在11月2日周一验收。"), folder: "工作", updatedAt: now.addingTimeInterval(-86400 * 6))
        var meeting = MeetingRecord(title: "海鸥验收会议", createdAt: now)
        meeting.minutes = "旧纪要：11月2日验收，预算已经批准。"
        meeting.transcript = [.init(speaker: "未区分", text: "2026-10-29：11月2日周一验收的安排取消，改为10月30日周五15点验收。18000元只是备选报价，预算尚未批准。", offset: 50)]
        let unrelated = Note(id: UUID(), title: "燕子预算", document: NativeDocument(plainText: "燕子预算已经批准。"), folder: "工作", updatedAt: now)
        let corpus = KnowledgeCorpus(tasks: [task], notes: [old, unrelated], meetings: [meeting], currentList: nil, now: now)
        let queries = ["海鸥项目最终何时验收，验收任务是否已经完成？预算是否获批？", "海鸥验收项目的合同编号是多少？"]
        for (index, question) in queries.enumerated() {
            let sources = try corpus.search(question).sources
            let started = Date()
            do {
                let answer = try await client.answer(question: question, sources: sources)
                let paragraphs = answer.paragraphs.map { paragraph in
                    ["text": paragraph.text, "citations": paragraph.citations.map { ["source": $0.source, "quote": $0.quote] }] as [String: Any]
                }
                records.append(["case": index == 0 ? "retrieved_knowledge" : "missing_fact", "question": question,
                    "sources": sources.map(\.parameters), "result": ["paragraphs": paragraphs, "insufficient": answer.insufficient], "seconds": Date().timeIntervalSince(started)])
                save()
                if index == 0 {
                    XCTAssertTrue(sources.contains { $0.kind == .task })
                    XCTAssertTrue(sources.contains { $0.lineID != nil })
                    XCTAssertFalse(answer.insufficient)
                    let text = answer.paragraphs.map(\.text).joined()
                    XCTAssertTrue(text.contains("周五") || text.contains("10月30") || text.contains("10-30"))
                    XCTAssertTrue(text.contains("未完成"))
                    XCTAssertTrue(text.contains("未批准") || text.contains("未获批") || text.contains("没有获批"))
                } else { XCTAssertTrue(answer.insufficient) }
                print("Fictional live \(index): \(String(format: "%.2f", Date().timeIntervalSince(started))) seconds")
            } catch {
                records.append(["case": index == 0 ? "retrieved_knowledge" : "missing_fact", "question": question,
                    "sources": sources.map(\.parameters), "error": error.localizedDescription, "seconds": Date().timeIntervalSince(started)])
                save(); XCTFail("Real Pi question failed: \(error.localizedDescription)")
            }
        }
        let notes: [(String, String, NoteRewriteRequest.Action)] = [
            ("organize", try XCTUnwrap(fixture["shortNote"]), .organize),
            ("polish", try XCTUnwrap(fixture["shortNote"]), .polish),
            ("long_polish", try XCTUnwrap(fixture["longNote"]), .polish),
        ]
        for (name, content, action) in notes {
            let request = NoteRewriteRequest(noteID: UUID(), title: "虚构：海鸥项目", content: content, action: action)
            let started = Date()
            do {
                func generate() async throws -> String {
                    try await client.rewriteNote(request) { event in
                        if let text = event.text { print("Fictional live \(name): \(text.count) characters") }
                    }
                }
                let text = try await generate()
                var record: [String: Any] = ["case": name, "sourceCharacters": content.count, "result": ["text": text], "seconds": Date().timeIntervalSince(started)]
                if name == "long_polish" {
                    let missing = (1...24).map { String(format: "SEAGULL-%03d", $0) }.filter { !text.contains($0) }
                    record["missingIDs"] = missing
                    XCTAssertTrue(missing.isEmpty, "Missing material records: \(missing)")
                    XCTAssertTrue(text.contains("2026-11-06") && text.contains("17:30"))
                    XCTAssertTrue(text.contains("尚未审批") || text.contains("未批准") || text.contains("未获批"))
                } else {
                    XCTAssertTrue(text.contains("李敏") && text.contains("18000"))
                    XCTAssertTrue(text.contains("未批准") || text.contains("未获批"))
                }
                records.append(record); save()
            } catch {
                records.append(["case": name, "error": error.localizedDescription, "seconds": Date().timeIntervalSince(started)])
                save(); XCTFail("Real Pi note failed: \(error.localizedDescription)")
            }
        }
    }
}
