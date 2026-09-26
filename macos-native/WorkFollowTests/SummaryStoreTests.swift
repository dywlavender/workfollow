import XCTest
@testable import WorkFollow

@MainActor
final class SummaryStoreTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    // MARK: Helpers

    private func makeStore(clock: @escaping () -> Date) -> SummaryStore {
        SummaryStore(clock: clock, directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Save

    func testSaveCreatesEntryThenUpdateAdvancesUpdatedAt() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = makeStore { now }

        store.save(content: "  第一篇摘要  ", dayKey: "2026-01-15")
        XCTAssertEqual(store.entry(for: "2026-01-15")?.content, "第一篇摘要")
        XCTAssertEqual(store.entry(for: "2026-01-15")?.updatedAt, now)

        now = now.addingTimeInterval(120)
        store.save(content: "更新后的摘要", dayKey: "2026-01-15")
        XCTAssertEqual(store.entry(for: "2026-01-15")?.content, "更新后的摘要")
        XCTAssertEqual(store.entry(for: "2026-01-15")?.updatedAt, now)
        XCTAssertEqual(store.entries.map(\.dayKey), ["2026-01-15"])
    }

    func testEmptyContentDeletesEntry() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = makeStore { now }

        store.save(content: "有内容的一天", dayKey: "2026-01-15")
        XCTAssertNotNil(store.entry(for: "2026-01-15"))

        store.save(content: "   \n\t ", dayKey: "2026-01-15")
        XCTAssertNil(store.entry(for: "2026-01-15"))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEntriesStaySortedByDayKeyDescending() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = makeStore { now }

        store.save(content: "later", dayKey: "2026-01-20")
        store.save(content: "earlier", dayKey: "2026-01-05")
        store.save(content: "newest month", dayKey: "2026-02-01")
        XCTAssertEqual(store.entries.map(\.dayKey), ["2026-02-01", "2026-01-20", "2026-01-05"])
    }

    // MARK: Month grouping

    func testEntriesInMonthReturnsOnlyThatMonthNewestFirst() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = makeStore { now }
        store.save(content: "september first", dayKey: "2026-09-03")
        store.save(content: "september last", dayKey: "2026-09-28")
        store.save(content: "august", dayKey: "2026-08-31")
        store.save(content: "october", dayKey: "2026-10-01")

        XCTAssertEqual(store.entries(inMonth: date(2026, 9, 15), calendar: calendar).map(\.dayKey),
                       ["2026-09-28", "2026-09-03"])
        XCTAssertEqual(store.entries(inMonth: date(2026, 10, 2), calendar: calendar).map(\.dayKey),
                       ["2026-10-01"])
        XCTAssertTrue(store.entries(inMonth: date(2025, 9, 1), calendar: calendar).isEmpty)
    }

    // MARK: Day keys

    func testDayKeyHelpersFormatAndParseWithInjectedCalendar() {
        let instant = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26,
                                                         hour: 23, minute: 30))!
        XCTAssertEqual(SummaryStore.dayKey(instant, calendar: calendar), "2026-09-26")
        XCTAssertEqual(SummaryStore.date(fromDayKey: "2026-09-26", calendar: calendar),
                       calendar.startOfDay(for: instant))
        XCTAssertNil(SummaryStore.date(fromDayKey: "not-a-day", calendar: calendar))
    }

    // MARK: Persistence

    func testFlushPersistsEntriesForTheNextStoreInstance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SummaryStore(clock: { now }, directory: directory)

        store.save(content: "持久化的摘要", dayKey: "2026-01-15")
        let done = expectation(description: "flush")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        let reloaded = SummaryStore(clock: { now }, directory: directory)
        XCTAssertEqual(reloaded.entry(for: "2026-01-15")?.content, "持久化的摘要")
        XCTAssertEqual(reloaded.entries.map(\.dayKey), ["2026-01-15"])
    }
}
