import XCTest
@testable import WorkFollow

/// P1：清单摘要持久化、延迟读取与 v2→v3 摘要回填。
@MainActor
final class ChecklistPersistenceTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let completed = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_700_003_600)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecklistPersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func task() -> Task {
        var task = Task(id: UUID(), title: "清单持久化",
                        document: NativeDocument(blocks: [
                            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成")],
                                          checklist: ChecklistItemMeta(completedAt: completed)),
                            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待办")],
                                          checklist: ChecklistItemMeta(reminderAt: reminder))
                        ]),
                        list: .inbox, priority: .none, schedule: TaskSchedule(),
                        parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        task.kind = .checklist
        return task
    }

    func testDeferredSummaryExposesProgressAndReminderWithoutHydratingBody() throws {
        let original = task()
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))

        let lazy = try XCTUnwrap(repository.loadDeferred()?.tasks.first)
        XCTAssertFalse(lazy.document.isLoaded)
        XCTAssertEqual(repository.documentReadCount, 0)

        let summary = try XCTUnwrap(lazy.document.checklistSummary)
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.reminders.count, 1)
        XCTAssertEqual(summary.reminders.first?.title, "待办")
        XCTAssertEqual(summary.reminders.first?.fireDate, reminder)
        XCTAssertEqual(repository.documentReadCount, 0, "读摘要不能水合正文")

        let loaded = try XCTUnwrap(repository.load()?.tasks.first)
        XCTAssertEqual(loaded.document.blocks[0].checklist?.completedAt, completed)
        XCTAssertEqual(loaded.document.blocks[1].checklist?.reminderAt, reminder)
    }

    func testVersionTwoSummaryWithoutChecklistBackfillsOnOpen() throws {
        let original = task()
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: [original], notes: []))

        let url = directory.appendingPathComponent(SQLiteWorkspaceRepository.filename)
        let db = try SQLiteDatabase(url: url)
        let blob = try XCTUnwrap(try db.rows("SELECT document_summary FROM tasks").first?[0] ?? nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: blob) as? [String: Any])
        json.removeValue(forKey: "checklist")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        try db.execute("UPDATE tasks SET document_summary=?", [.blob(stripped)])
        try db.execute("PRAGMA user_version=2")

        let reopened = NativePreviewRepository(directory: directory)
        let lazy = try XCTUnwrap(reopened.loadDeferred()?.tasks.first)
        let summary = try XCTUnwrap(lazy.document.checklistSummary)
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(reopened.documentReadCount, 0, "迁移直接读文档行，不经过延迟加载器")

        let dbAfter = try SQLiteDatabase(url: url)
        XCTAssertEqual(try dbAfter.rows("PRAGMA user_version").first?[0], Data("3".utf8))
    }
}
