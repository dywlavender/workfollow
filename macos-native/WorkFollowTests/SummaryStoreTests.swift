import XCTest
@testable import WorkFollow

@MainActor
final class SummaryStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value
    }
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))! }
    private func flush(_ store: SummaryStore) async {
        await withCheckedContinuation { continuation in
            store.flush { error in XCTAssertNil(error); continuation.resume() }
        }
    }
    private func folder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name + "-" + UUID().uuidString)
    }

    func testJournalAndDisplayOptionsPersistIndependently() async {
        let directory = folder("summary-store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryStore(clock: { self.monday }, directory: directory)
        var options = SummaryDocumentOptions.standard
        options.grouping = .list
        options.filter.status = .completed
        options.includesNextWeek = true
        store.save(content: "周一手记", dayKey: "2026-10-19")
        store.updateOptions(options)
        await flush(store)

        let restored = SummaryStore(directory: directory)
        XCTAssertEqual(restored.entry(for: "2026-10-19")?.content, "周一手记")
        XCTAssertEqual(restored.options, options)
        XCTAssertEqual(restored.entries.count, 1)

        restored.updateOptions(.standard)
        restored.save(content: "补充记录", dayKey: "2026-10-19")
        XCTAssertEqual(restored.options, .standard)
        XCTAssertEqual(restored.entry(for: "2026-10-19")?.content, "补充记录")
    }

    func testListScopeIsNeverBakedIntoTheSavedRecipe() async {
        let directory = folder("summary-options")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryStore(directory: directory)
        var options = SummaryDocumentOptions.standard
        options.filter.listName = "工作"
        options.grouping = .priority
        store.updateOptions(options)
        XCTAssertNil(store.options.filter.listName)
        XCTAssertEqual(store.options.grouping, .priority)
        await flush(store)
        let restored = SummaryStore(directory: directory)
        XCTAssertNil(restored.options.filter.listName)
        XCTAssertEqual(restored.options.grouping, .priority)
    }

    func testGeneratedSummaryIsNotStoredAsAJournalOrSnapshot() async {
        let directory = folder("summary-live")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryStore(clock: { self.monday }, directory: directory)
        let builder = WeeklyReportBuilder(calendar: calendar)
        let task = Task(id: UUID(), title: "实时摘要任务", tags: [], list: TaskList(name: "工作"),
                        priority: .medium, schedule: .init(dueAt: monday), status: .active,
                        childOrder: 0, createdAt: monday, updatedAt: monday)
        _ = builder.document(for: builder.report(tasks: [task], weekOf: monday))
        await flush(store)
        let restored = SummaryStore(directory: directory)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("weekly-summaries.json").path))
    }
}
