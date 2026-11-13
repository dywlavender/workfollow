import XCTest
@testable import WorkFollow

@MainActor
final class AssistantKnowledgeIntegrationTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-knowledge-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testIndexUsesOriginalParagraphAndReflectsPendingAndCommittedEdits() throws {
        let repository = SQLiteWorkspaceRepository(directory: try directory())
        let target = DocumentBlock(kind: .paragraph, runs: [.init(text: "项目周会确认 WF-102 验收通过。")])
        let document = NativeDocument(blocks: [
            .init(kind: .heading(2), runs: [.init(text: "验收记录")]),
            .init(kind: .paragraph, runs: [.init(text: String(repeating: "这是背景材料。", count: 100))]),
            target,
            .init(kind: .paragraph, runs: [.init(text: String(repeating: "这是后续记录。", count: 100))])
        ])
        let note = Note(id: UUID(), title: "海鸥记录", document: document, folder: "工作", updatedAt: Date())
        let task = note.migratedTask()
        try repository.replace(NativeWorkspaceSnapshot(tasks: [task], notes: [], notesMergedIntoTasks: true))
        XCTAssertTrue(try repository.buildKnowledgeIndexStep())
        let index = repository.knowledgeIndex
        let hit = try XCTUnwrap(index.search(["周会"], literal: "周会")?.first)
        XCTAssertEqual(hit.blockID, target.id)
        XCTAssertEqual(hit.excerpt(matching: ["周会"])?.text, target.plainText)
        XCTAssertEqual(index.search(["WF-102"], literal: "WF-102")?.first?.resourceID, note.id)
        let result = try KnowledgeCorpus(tasks: [], notes: [note], meetings: [], index: index).search("周会")
        XCTAssertEqual(result.sources.first?.blockID, target.id)
        XCTAssertEqual(result.sources.first?.url?.host, "note")

        var edited = task
        edited.document = NativeDocument(plainText: "新内容 青竹402")
        let changes = TaskChangeSet(updatedFrom: task, to: edited)
        index.track(changes)
        XCTAssertEqual(index.search(["周会"], literal: "周会")?.count, 0)
        XCTAssertEqual(index.search(["青竹402"], literal: "青竹402")?.first?.resourceID, note.id)
        var batch = SQLiteWorkspaceRepository.Batch()
        batch.tasks[note.id] = try XCTUnwrap(changes.entries.first)
        try repository.apply(batch)
        let reopened = SQLiteWorkspaceRepository(directory: repository.directory).knowledgeIndex
        XCTAssertEqual(reopened.search(["青竹402"], literal: "青竹402")?.first?.resourceID, note.id)
        XCTAssertEqual(reopened.search(["周会"], literal: "周会")?.count, 0)

        edited.deletedAt = Date()
        batch.tasks[note.id] = try XCTUnwrap(TaskChangeSet(updatedFrom: try XCTUnwrap(changes.entries.first?.after), to: edited).entries.first)
        try repository.apply(batch)
        XCTAssertEqual(reopened.search(["青竹402"], literal: "青竹402")?.count, 0)
    }

    func testExplicitDeadlineFilterUsesDeadlineEvenWhenScheduleIsSet() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z"))
        let later = now.addingTimeInterval(7 * 86400)
        let task = Task(id: UUID(), title: "海鸥验收", list: .inbox, priority: .high,
            schedule: TaskSchedule(dueAt: later, hasTime: true, deadlineAt: now), parentID: nil, childOrder: 0,
            createdAt: now, updatedAt: now)
        let workspace = TaskWorkspaceModel(initialTasks: [task])
        let service = NativeAutomationService(tasks: workspace, notes: NotesWorkspaceModel(taskWorkspace: workspace), directory: try directory())
        let range = ["from": "2026-11-11T00:00:00Z", "to": "2026-11-12T00:00:00Z", "completed": "false"]
        XCTAssertEqual(try service.filteredTasks(range.merging(["date-field": "deadline"]) { _, new in new }).map(\.id), [task.id])
        XCTAssertTrue(try service.filteredTasks(range.merging(["date-field": "schedule"]) { _, new in new }).isEmpty)
    }

    func testSearchRecallAndLatencyOnTheSameWorkspace() throws {
        let repository = SQLiteWorkspaceRepository(directory: try directory())
        let now = Date()
        let tasks = (101...420).map { number in
            Task(id: UUID(), title: "虚构资料 \(number)",
                document: NativeDocument(plainText: String(repeating: "背景资料介绍验收过程。", count: 68) + "\n工单 WF-\(number) 验收完成。"),
                list: .inbox, priority: .none, schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                createdAt: now, updatedAt: now)
        }
        try repository.replace(NativeWorkspaceSnapshot(tasks: tasks, notes: []))
        let deferred = try XCTUnwrap(try repository.load(deferred: true)?.tasks)
        while try !repository.buildKnowledgeIndexStep() {}
        var baseline: [Double] = [], indexed: [Double] = []
        for number in 101...124 {
            let query = "WF-\(number)"
            let expected = "task-" + tasks[number - 101].id.uuidString
            let start = ProcessInfo.processInfo.systemUptime
            let before = CommandPaletteProjection.entries(query: query, tasks: deferred, notes: [],
                creationList: TaskList.inbox.name, schedulesForToday: false)
            let middle = ProcessInfo.processInfo.systemUptime
            let hits = repository.knowledgeIndex.search([query], literal: query)
            let after = CommandPaletteProjection.entries(query: query, tasks: deferred, notes: [],
                creationList: TaskList.inbox.name, schedulesForToday: false, indexedHits: hits)
            baseline.append((middle - start) * 1000)
            indexed.append((ProcessInfo.processInfo.systemUptime - middle) * 1000)
            XCTAssertTrue(before.prefix(5).contains { $0.id == expected })
            XCTAssertEqual(after.first?.id, expected)
            XCTAssertTrue(after.first?.snippet?.contains(query) == true)
        }
        func p95(_ durations: [Double]) -> String {
            String(format: "%.2f", durations.sorted()[Int(ceil(Double(durations.count) * 0.95)) - 1])
        }
        print("检索对照（320 条虚构资料、24 个不同编号）P95：原搜索 \(p95(baseline)) ms，全文索引 \(p95(indexed)) ms")
    }

    func testFollowUpKeepsOriginalLineAndDoesNotReissueHandledRevision() async throws {
        let directory = try directory()
        let store = MeetingFollowUpStore(directory: directory)
        try store.setEnabled(true)
        var meeting = MeetingRecord(title: "虚构验收会")
        let line = MeetingTranscriptLine(speaker: "刘工", text: "周三 16:00 前发验收清单", offset: 42)
        meeting.transcript = [line]
        let request = AITaskRequest(source: .meeting(meeting.id), title: meeting.title, content: line.text, referenceDate: Date())
        var calls = 0
        store.generate(for: meeting, request: request, isCurrent: { true }) { _ in
            calls += 1
            return #"{"tasks":[{"title":"发验收清单","due":"2026-11-11T16:00:00+08:00","quote":"周三 16:00 前发验收清单"}]}"#
        }
        for _ in 0..<100 where store.pending.isEmpty { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        let batch = try XCTUnwrap(store.pending.first)
        let draft = try XCTUnwrap(batch.drafts.first)
        XCTAssertEqual(draft.sourceLineID, line.id)
        XCTAssertNotNil(draft.schedule.deadlineAt)
        XCTAssertEqual(MeetingFollowUpStore(directory: directory).pending.first?.drafts.first?.id, draft.id)
        try store.dismiss(batch)
        let reopened = MeetingFollowUpStore(directory: directory)
        reopened.generate(for: meeting, request: request, isCurrent: { true }) { _ in
            calls += 1
            return #"{"tasks":[]}"#
        }
        await _Concurrency.Task.yield()
        XCTAssertTrue(reopened.pending.isEmpty)
        XCTAssertEqual(calls, 1)
    }
}
