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

    // MARK: 补记与聚合

    func testManualRecordAndWeeklyTotals() {
        var now = base
        let store = FocusStore(clock: { now }, directory: makeDirectory())
        let a = UUID(), b = UUID()
        XCTAssertTrue(store.addRecord(taskID: a, startedAt: base.addingTimeInterval(-3600), minutes: 25))
        XCTAssertTrue(store.addRecord(taskID: b, startedAt: base.addingTimeInterval(-7200), minutes: 10))
        XCTAssertFalse(store.addRecord(taskID: nil,
                                       startedAt: base.addingTimeInterval(-400 * 24 * 3600),
                                       minutes: 10))  // 超出最近 7 天拒绝
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
        XCTAssertEqual(store.phase, .breaking)
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
