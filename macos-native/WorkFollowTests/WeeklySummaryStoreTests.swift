import XCTest
@testable import WorkFollow

@MainActor
final class WeeklySummaryStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value
    }
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))! }
    private func flush(_ store: SummaryStore) async {
        await withCheckedContinuation { continuation in
            store.flush { error in XCTAssertNil(error); continuation.resume() }
        }
    }

    func testWeeklyScopesAndMondayJournalPersistIndependently() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("weekly-summary-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SummaryStore(clock: { self.monday }, directory: folder)
        let week = NativeDocument(plainText: "本周整体成果与复盘")
        store.save(content: "周一手记", dayKey: "2026-10-19")
        store.saveWeekly(document: week, weekKey: "2026-10-19")
        store.saveWeekly(document: .init(plainText: "工作清单周报"), weekKey: "2026-10-19", scopeID: "work", listName: "工作")
        store.saveWeekly(document: .init(plainText: "下周计划"), weekKey: "2026-10-26")
        await flush(store)
        let reloaded = SummaryStore(directory: folder)
        XCTAssertEqual(reloaded.entry(for: "2026-10-19")?.content, "周一手记")
        XCTAssertEqual(reloaded.weeklyEntry(weekKey: "2026-10-19")?.document, week)
        XCTAssertEqual(reloaded.weeklyEntry(weekKey: "2026-10-19", scopeID: "work")?.document.plainText, "工作清单周报")
        XCTAssertEqual(reloaded.weeklyEntries.count, 3)
        reloaded.save(content: "修改周一手记", dayKey: "2026-10-19")
        XCTAssertEqual(reloaded.weeklyEntry(weekKey: "2026-10-19")?.document, week)
    }

    func testIdentifiableLegacyWeeklyDocumentIsCopiedWithoutDeletingJournal() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("weekly-migration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SummaryStore(directory: folder)
        let builder = SummaryReviewBuilder(clock: { self.monday }, calendar: calendar)
        let legacy = builder.document(for: builder.review(for: [], weekOf: monday))
        store.save(document: legacy, dayKey: "2026-10-19")
        store.migrateLegacyWeekly(weekStart: monday, calendar: calendar)
        XCTAssertEqual(store.weeklyEntry(weekKey: "2026-10-19")?.document, legacy)
        XCTAssertEqual(store.entry(for: "2026-10-19")?.resolvedDocument, legacy)
        store.saveWeekly(document: .init(plainText: "人工修订周报"), weekKey: "2026-10-19")
        store.migrateLegacyWeekly(weekStart: monday, calendar: calendar)
        XCTAssertEqual(store.weeklyEntry(weekKey: "2026-10-19")?.document.plainText, "人工修订周报")
        store.save(content: "普通周一日记", dayKey: "2026-10-26")
        let next = calendar.date(byAdding: .day, value: 7, to: monday)!
        store.migrateLegacyWeekly(weekStart: next, calendar: calendar)
        XCTAssertNil(store.weeklyEntry(weekKey: "2026-10-26"))
    }

    func testSavedReportRemainsASnapshotAfterOriginalTaskChangesWeek() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("weekly-snapshot-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SummaryStore(directory: folder)
        let workspace = TaskWorkspaceModel(clock: { self.monday }, calendar: calendar, seedDemoData: false)
        let id = workspace.createWeeklyTask(title: "原定任务", list: "工作", weekOf: monday)!
        let builder = WeeklyReportBuilder(calendar: calendar)
        let document = builder.document(for: builder.report(tasks: workspace.allTasks, weekOf: monday))
        store.saveWeekly(document: document, weekKey: "2026-10-19")
        _ = workspace.planTasks([id], weekOf: calendar.date(byAdding: .day, value: 7, to: monday)!)
        let updated = builder.document(for: builder.report(tasks: workspace.allTasks, weekOf: monday), preserving: document)
        XCTAssertTrue(updated.plainText.contains("已结转到"))
        XCTAssertEqual(store.weeklyEntry(weekKey: "2026-10-19")?.document, document)
    }

    func testLegacyAIOrManuallyRetitledWeeklyDocumentIsRetained() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("weekly-freeform-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SummaryStore(directory: folder)
        let edited = NativeDocument(plainText: "去掉自动标题后的手写总结，包含原有 AI 整理内容。")
        store.save(document: edited, dayKey: "2026-10-19")
        store.migrateLegacyWeekly(weekStart: monday, calendar: calendar)
        XCTAssertEqual(store.weeklyEntry(weekKey: "2026-10-19")?.document, edited)
        XCTAssertEqual(store.entry(for: "2026-10-19")?.resolvedDocument, edited)
    }
}
