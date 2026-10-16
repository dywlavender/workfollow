import XCTest
@testable import WorkFollow

@MainActor
final class FocusStoreTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Helpers

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    private func flush(_ store: FocusStore) {
        let flushed = expectation(description: "flush")
        store.flush { _ in flushed.fulfill() }
        wait(for: [flushed], timeout: 5)
    }

    // MARK: 会话快照

    func testSessionSnapshotSurvivesReinit() {
        var now = base
        let directory = makeDirectory()
        let store = FocusStore(clock: { now }, directory: directory)
        let taskID = UUID()
        XCTAssertTrue(store.start(taskID: taskID, minutes: 25))
        now = base.addingTimeInterval(60)
        store.refresh()
        XCTAssertEqual(store.remainingSeconds, 24 * 60)
        flush(store)

        let restored = FocusStore(clock: { now }, directory: directory)
        XCTAssertEqual(restored.phase, .focusing)
        XCTAssertEqual(restored.currentTaskID, taskID)
        XCTAssertEqual(restored.remainingSeconds, 24 * 60)

        now = base.addingTimeInterval(26 * 60)
        restored.refresh()
        XCTAssertEqual(restored.phase, .breaking)  // 离开期间到点 → 正常进入休息
        XCTAssertNil(restored.currentTaskID)
    }

    func testIdleSnapshotClearsOnRestore() {
        var now = base
        let directory = makeDirectory()
        let store = FocusStore(clock: { now }, directory: directory)
        XCTAssertTrue(store.start(taskID: nil, minutes: 10))
        now = base.addingTimeInterval(350)  // ≥5 分钟（留档门槛）且未到点
        store.refresh()
        XCTAssertNotNil(store.giveUp())  // 保留一条未完成记录
        flush(store)

        let restored = FocusStore(clock: { now }, directory: directory)
        XCTAssertEqual(restored.phase, .idle)
    }

    func testSessionTimingPresentationTracksStartPauseAndResumedProjectedEnd() {
        var now = date(2026, 9, 30, 13, 30)
        let store = FocusStore(clock: { now }, directory: makeDirectory())

        XCTAssertTrue(store.start(minutes: 25))
        XCTAssertEqual(store.sessionTiming?.projectedEndAt, date(2026, 9, 30, 13, 55))

        now = date(2026, 9, 30, 13, 35)
        store.refresh()
        XCTAssertTrue(store.pause())
        XCTAssertEqual(store.sessionTiming?.phase, .pausedFocus)
        XCTAssertEqual(store.sessionTiming?.pausedAt, now)
        XCTAssertEqual(store.sessionTiming?.remainingSeconds, 20 * 60)

        now = date(2026, 9, 30, 13, 45)
        XCTAssertEqual(store.sessionTiming?.projectedEndAt, date(2026, 9, 30, 13, 55))
        XCTAssertTrue(store.resume())
        XCTAssertEqual(store.sessionTiming?.phase, .focusing)
        XCTAssertEqual(store.sessionTiming?.remainingSeconds, 20 * 60)
        XCTAssertEqual(store.sessionTiming?.projectedEndAt, date(2026, 9, 30, 14, 5))
    }

    func testFocusNoteSurvivesReloadAndMovesToAbandonedRecord() {
        var now = date(2026, 9, 30, 13, 30)
        let directory = makeDirectory()
        let store = FocusStore(clock: { now }, directory: directory)
        XCTAssertTrue(store.start(minutes: 25))
        store.updateCurrentSessionNote("  先整理评审要点  \n")
        flush(store)

        let restored = FocusStore(clock: { now }, directory: directory)
        XCTAssertEqual(restored.currentSessionNote, "  先整理评审要点  \n")

        now = date(2026, 9, 30, 13, 35)
        restored.refresh()
        let record = restored.giveUp()
        XCTAssertEqual(record?.completed, false)
        XCTAssertEqual(record?.note, "先整理评审要点")
        XCTAssertEqual(restored.records.first?.note, "先整理评审要点")
        XCTAssertEqual(restored.currentSessionNote, "")
    }

    func testNaturalCompletionArchivesSessionNoteOnCompletedRecord() {
        var now = date(2026, 9, 30, 13, 30)
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        XCTAssertTrue(store.start(minutes: 5))
        store.updateCurrentSessionNote("完成后的笔记")

        now = date(2026, 9, 30, 13, 35)
        store.refresh()

        XCTAssertEqual(store.phase, .breaking)
        XCTAssertEqual(store.records.first?.completed, true)
        XCTAssertEqual(store.records.first?.note, "完成后的笔记")
        XCTAssertEqual(store.currentSessionNote, "")
    }

    func testShortAbandonedSessionDoesNotCreateRecordButClearsItsNote() {
        var now = date(2026, 9, 30, 13, 30)
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        XCTAssertTrue(store.start(minutes: 25))
        store.updateCurrentSessionNote("短暂记录")
        now = date(2026, 9, 30, 13, 32)
        store.refresh()

        XCTAssertNil(store.giveUp())
        XCTAssertEqual(store.currentSessionNote, "")
        XCTAssertTrue(store.records.isEmpty)
    }

    // MARK: 补记与聚合

    func testManualRecordAndWeeklyTotals() {
        var now = base
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        let a = UUID(), b = UUID()
        XCTAssertTrue(store.addRecord(taskID: a, startedAt: base.addingTimeInterval(-3600), minutes: 25))
        XCTAssertTrue(store.addRecord(taskID: b, startedAt: base.addingTimeInterval(-7200), minutes: 10))
        XCTAssertTrue(store.addRecord(taskID: nil,
                                      startedAt: base.addingTimeInterval(-400 * 24 * 3600),
                                      minutes: 10))  // 完整补记允许选择历史日期
        XCTAssertFalse(store.addRecord(taskID: nil, startedAt: base, minutes: 0))  // 分钟越界拒绝

        let totals = store.weeklyTaskTotals()
        XCTAssertEqual(totals.first?.taskID, a)
        XCTAssertEqual(totals.first?.minutes, 25)
        XCTAssertEqual(totals.count, 2)
    }

    // MARK: 常用专注

    func testAddApplyAndDeleteTimers() {
        let store = FocusStore(clock: { self.base }, directory: makeDirectory())
        XCTAssertTrue(store.addTimer(name: "晨间写作", emoji: "📚", stopwatch: false, minutes: 50))
        XCTAssertTrue(store.addTimer(name: "随手记", emoji: "😀", stopwatch: true, minutes: 0))
        XCTAssertFalse(store.addTimer(name: "   ", emoji: "😀", stopwatch: false, minutes: 25))   // 名称必填
        XCTAssertFalse(store.addTimer(name: "越界", emoji: "😀", stopwatch: false, minutes: 999))  // 分钟越界

        XCTAssertEqual(store.timers.count, 2)
        store.applyTimerPreset(store.timers[0])
        XCTAssertTrue(store.preferences.stopwatchMode == false)
        XCTAssertEqual(store.preferences.focusMinutes, 50)
        store.applyTimerPreset(store.timers[1])
        XCTAssertTrue(store.preferences.stopwatchMode)

        store.deleteTimer(store.timers[0].id)
        XCTAssertEqual(store.timers.count, 1)
        XCTAssertEqual(store.timers.first?.name, "随手记")
    }

    func testLargeHistoryPagesKeepCompleteStatisticsAndPreserveUnloadedRecords() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let taskID = UUID()
        let records = (0..<10_000).map { index in
            PomodoroRecord(id: UUID(), taskID: taskID,
                           startedAt: base.addingTimeInterval(-Double(index + 1)),
                           minutes: 2, completed: index % 2 == 0, note: "记录\(index)")
        }
        var archive = FocusStore.Archive(records: records)
        archive.preferences.dailyGoal = 12
        try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent("focus.json"))
        // One-time migration; steady startup must hydrate metadata, not payloads.
        _ = FocusStore(clock: { self.base }, directory: directory)
        let store = FocusStore(clock: { self.base }, directory: directory)
        XCTAssertEqual(store.hydratedRecordCount, 0)
        XCTAssertEqual(store.allTimeMinutes, 20_000)
        XCTAssertEqual(store.allTimePomodoros, 5_000)
        XCTAssertEqual(store.preferences.dailyGoal, 12)
        XCTAssertEqual(store.weeklyTaskTotals().first?.minutes, 20_000)
        await store.resetHistory()
        XCTAssertEqual(store.visibleRecords.count, 50)
        XCTAssertEqual(store.visibleRecords.first?.id, records.first?.id)
        XCTAssertEqual(store.hydratedRecordCount, 51)
        await store.loadMoreHistory()
        XCTAssertEqual(store.visibleRecords.count, 100)
        XCTAssertEqual(Set(store.visibleRecords.map(\.id)).count, 100)
        XCTAssertEqual(store.allTimeMinutes, 20_000)

        // Delete an ID outside visible pages; totals must still update correctly.
        store.deleteRecord(records[9_998].id)
        XCTAssertEqual(store.allTimeMinutes, 19_998)
        XCTAssertEqual(store.allTimePomodoros, 4_999)
        XCTAssertTrue(store.addRecord(taskID: taskID, startedAt: base.addingTimeInterval(-600), minutes: 10))
        XCTAssertEqual(store.allTimeMinutes, 20_008)
        XCTAssertEqual(store.allTimePomodoros, 5_000)
        XCTAssertTrue(store.setDailyGoal(9))
        flush(store)
        let reloaded = FocusStore(clock: { self.base }, directory: directory)
        XCTAssertEqual(reloaded.hydratedRecordCount, 0)
        XCTAssertEqual(reloaded.allTimeMinutes, 20_008)
        XCTAssertEqual(reloaded.allTimePomodoros, 5_000)
        XCTAssertEqual(reloaded.preferences.dailyGoal, 9)
        XCTAssertEqual(reloaded.records.count, 10_000)
        XCTAssertFalse(reloaded.records.contains { $0.id == records[9_998].id })
    }

    func testDailyStatisticsIncludeUnloadedHistoryAndRefreshOnlyAcrossDays() throws {
        var now = base
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let records = [
            PomodoroRecord(id: UUID(), startedAt: today, minutes: 25, completed: true),
            PomodoroRecord(id: UUID(), startedAt: yesterday, minutes: 10, completed: false)
        ]
        try JSONEncoder().encode(FocusStore.Archive(records: records))
            .write(to: directory.appendingPathComponent("focus.json"))
        let store = FocusStore(clock: { now }, directory: directory)
        XCTAssertEqual(store.todayMinutes, 25)
        XCTAssertEqual(store.todayPomodoros, 1)
        XCTAssertEqual(store.recentDailyStats(days: 2).map(\.minutes), [10, 25])
        let queries = store.statisticsQueryCount
        XCTAssertTrue(store.start(minutes: 5))
        for second in 1...100 {
            now = base.addingTimeInterval(Double(second))
            store.refresh()
        }
        _ = store.giveUp()
        XCTAssertEqual(store.statisticsQueryCount, queries, "Timer refresh must not query history each second")
        XCTAssertEqual(store.hydratedRecordCount, 0)
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        store.refresh()
        XCTAssertEqual(store.todayMinutes, 0)
        XCTAssertEqual(store.todayPomodoros, 0)
        XCTAssertEqual(store.statisticsQueryCount, queries + 1)
        XCTAssertEqual(store.allTimeMinutes, 35)
    }

    func testSQLiteVersionTwoUpgradeBackfillsMetricsWithoutChangingPayloadOrPreferences() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("focus.sqlite")
        let db = try SQLiteDatabase(url: url)
        let record = PomodoroRecord(id: UUID(), startedAt: base.addingTimeInterval(-60),
                                    minutes: 35, completed: true, note: "旧数据库正文")
        let payload = try JSONEncoder().encode(record)
        var archive = FocusStore.Archive()
        archive.preferences.dailyGoal = 11
        try db.execute("CREATE TABLE records(id TEXT PRIMARY KEY,position INTEGER NOT NULL,occurred_at REAL NOT NULL,task_id TEXT,payload BLOB NOT NULL)")
        try db.execute("CREATE TABLE state(key TEXT PRIMARY KEY,value BLOB NOT NULL)")
        try db.execute("INSERT INTO records VALUES (?,0,?,NULL,?)",
                       [.text(record.id.uuidString), .real(record.startedAt.timeIntervalSince1970), .blob(payload)])
        try db.execute("INSERT INTO state VALUES ('initialized',X'01')")
        try db.execute("INSERT INTO state VALUES ('metadata',?)", [.blob(try JSONEncoder().encode(archive))])
        try db.execute("PRAGMA user_version=2")
        let store = FocusStore(clock: { self.base }, directory: directory)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.allTimeMinutes, 35)
        XCTAssertEqual(store.allTimePomodoros, 1)
        XCTAssertEqual(store.preferences.dailyGoal, 11)
        XCTAssertEqual(try db.rows("SELECT payload FROM records").first?[0], payload)
        XCTAssertEqual(try db.rows("PRAGMA user_version").first?[0], Data("3".utf8))
        XCTAssertEqual(store.records, [record])
        let reloaded = FocusStore(clock: { self.base }, directory: directory)
        XCTAssertEqual(reloaded.hydratedRecordCount, 0)
        XCTAssertEqual(reloaded.allTimeMinutes, 35)
    }

    // MARK: 正计时

    func testStopwatchRecordsElapsedMinutes() {
        var now = base
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        XCTAssertTrue(store.setStopwatchMode(true))
        let taskID = UUID()
        XCTAssertTrue(store.start(taskID: taskID))
        now = base.addingTimeInterval(90)
        store.refresh()
        XCTAssertEqual(store.phase, .focusing)
        XCTAssertEqual(store.elapsedSeconds, 90)

        let record = store.finishEarly()
        XCTAssertEqual(record?.minutes, 2)  // ceil(90 / 60)
        XCTAssertEqual(record?.taskID, taskID)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(record?.mode, .stopwatch)
        XCTAssertEqual(record?.activeSeconds, 90)
        XCTAssertEqual(store.todayPomodoros, 0)
    }

    // MARK: 运行中换绑

    func testReattachMovesRecordOwnership() {
        var now = base
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        let a = UUID(), b = UUID()
        XCTAssertTrue(store.start(taskID: a, minutes: 5))
        XCTAssertTrue(store.reattach(taskID: b))
        now = base.addingTimeInterval(5 * 60)
        store.refresh()

        XCTAssertEqual(store.phase, .breaking)
        let record = store.recordGroups.first?.records.first
        XCTAssertEqual(record?.taskID, b)
        XCTAssertEqual(record?.completed, true)
    }
}
