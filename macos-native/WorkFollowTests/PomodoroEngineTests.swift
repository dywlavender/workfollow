import XCTest
@testable import WorkFollow

@MainActor
final class PomodoroEngineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Helpers

    /// 注入可手动推进的 clock，返回引擎与以秒推进时间的闭包。
    private func makeEngine(focusMinutes: Int = 25, breakMinutes: Int = 5,
                            longBreakMinutes: Int = 15, longBreakInterval: Int = 4)
        -> (engine: PomodoroEngine, advance: (TimeInterval) -> Void) {
        var now = base
        let settings = PomodoroSettings(focusMinutes: focusMinutes, breakMinutes: breakMinutes,
                                        longBreakMinutes: longBreakMinutes,
                                        longBreakInterval: longBreakInterval)
        let engine = PomodoroEngine(settings: settings, clock: { now })
        return (engine, { now = now.addingTimeInterval($0) })
    }

    // MARK: 时长校验

    func testStartRejectsFocusMinutesOutsideAllowedRange() {
        let (engine, _) = makeEngine()
        for minutes in [0, 4, 181, 1000] {
            XCTAssertFalse(engine.start(focusMinutes: minutes))
        }
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.settings.focusMinutes, 25)

        let (minimum, _) = makeEngine()
        XCTAssertTrue(minimum.start(focusMinutes: 5))
        XCTAssertEqual(minimum.remainingSeconds, 5 * 60)

        let (maximum, _) = makeEngine()
        XCTAssertTrue(maximum.start(focusMinutes: 180))
        XCTAssertEqual(maximum.remainingSeconds, 180 * 60)
        XCTAssertFalse(maximum.start())  // 会话进行中拒绝再次开始
    }

    // MARK: 完整流转

    func testCompletedFocusProducesRecordThenBreakThenReturnsReady() {
        let (engine, advance) = makeEngine()
        let taskID = UUID()
        XCTAssertTrue(engine.start(taskID: taskID, focusMinutes: 25))

        advance(25 * 60 - 1)
        XCTAssertNil(engine.handleCompletion())
        XCTAssertEqual(engine.phase, .focusing)

        advance(1)
        let record = engine.handleCompletion()
        XCTAssertEqual(record?.taskID, taskID)
        XCTAssertEqual(record?.startedAt, base)
        XCTAssertEqual(record?.minutes, 25)
        XCTAssertEqual(record?.completed, true)
        XCTAssertEqual(engine.phase, .breaking)
        XCTAssertFalse(engine.isLongBreak)
        XCTAssertEqual(engine.remainingSeconds, 5 * 60)

        advance(5 * 60)
        XCTAssertNil(engine.handleCompletion())
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.remainingSeconds, 0)
    }

    // MARK: 暂停与恢复

    func testPauseFreezesRemainingAndResumeShiftsEndByPausedDuration() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))

        advance(10 * 60)
        XCTAssertTrue(engine.pause())
        XCTAssertEqual(engine.phase, .pausedFocus)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)

        advance(7 * 60)  // 暂停期间时间流逝不影响剩余
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)

        XCTAssertTrue(engine.resume())
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)

        advance(2 * 60)
        XCTAssertEqual(engine.remainingSeconds, 13 * 60)
        XCTAssertNil(engine.handleCompletion())
    }

    func testPauseAndResumeAlsoApplyToBreak() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(25 * 60)
        _ = engine.handleCompletion()
        XCTAssertEqual(engine.phase, .breaking)

        advance(2 * 60)
        XCTAssertTrue(engine.pause())
        XCTAssertEqual(engine.phase, .pausedBreak)
        XCTAssertEqual(engine.remainingSeconds, 3 * 60)

        advance(10 * 60)
        XCTAssertEqual(engine.remainingSeconds, 3 * 60)

        XCTAssertTrue(engine.resume())
        advance(3 * 60)
        XCTAssertEqual(engine.phase, .breaking)  // 恢复后到点但需显式完成
        advance(1)
        XCTAssertNil(engine.handleCompletion())
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: 放弃

    func testGiveUpUnderFiveMinutesProducesNoRecord() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(4 * 60 + 59)
        XCTAssertNil(engine.giveUp())
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.remainingSeconds, 0)
    }

    func testGiveUpAtOrAboveFiveMinutesRecordsElapsedMinutes() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(12 * 60 + 30)
        let record = engine.giveUp()
        XCTAssertEqual(record?.startedAt, base)
        XCTAssertEqual(record?.minutes, 12)
        XCTAssertEqual(record?.completed, false)
        XCTAssertEqual(engine.phase, .idle)
    }

    func testPausedSecondsDoNotCountTowardGiveUpRecord() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(6 * 60)
        XCTAssertTrue(engine.pause())
        advance(10 * 60)  // 暂停 10 分钟不计入专注
        XCTAssertEqual(engine.giveUp()?.minutes, 6)
    }

    // MARK: 长休息

    func testLongBreakTriggersOnIntervalPomodoro() {
        let (engine, advance) = makeEngine(longBreakMinutes: 15, longBreakInterval: 2)

        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(25 * 60)
        _ = engine.handleCompletion()
        XCTAssertFalse(engine.isLongBreak)
        XCTAssertEqual(engine.remainingSeconds, 5 * 60)
        advance(5 * 60)
        _ = engine.handleCompletion()

        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(25 * 60)
        _ = engine.handleCompletion()
        XCTAssertTrue(engine.isLongBreak)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60)
        advance(15 * 60)
        _ = engine.handleCompletion()

        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(25 * 60)
        _ = engine.handleCompletion()
        XCTAssertFalse(engine.isLongBreak)
    }

    // MARK: 提前完成

    func testFinishEarlyRecordsElapsedMinutesAndEntersBreak() {
        let (engine, advance) = makeEngine()
        XCTAssertTrue(engine.start(focusMinutes: 25))
        advance(18 * 60)
        let record = engine.finishEarly()
        XCTAssertEqual(record?.startedAt, base)
        XCTAssertEqual(record?.minutes, 18)
        XCTAssertEqual(record?.completed, true)
        XCTAssertEqual(engine.phase, .breaking)

        let (paused, advancePaused) = makeEngine()
        XCTAssertTrue(paused.start(focusMinutes: 25))
        advancePaused(60)
        XCTAssertTrue(paused.pause())
        XCTAssertEqual(paused.finishEarly()?.minutes, 1)
        XCTAssertEqual(paused.phase, .breaking)
    }

    // MARK: Store

    func testStoreRecordsFocusLifecycleAndDeletesRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = base
        let store = FocusStore(clock: { now }, directory: directory)

        XCTAssertFalse(store.start(minutes: 4))  // 越界拒绝
        XCTAssertTrue(store.records.isEmpty)

        XCTAssertTrue(store.start(minutes: 5))
        XCTAssertEqual(store.phase, .focusing)
        XCTAssertEqual(store.remainingSeconds, 5 * 60)
        now = now.addingTimeInterval(2 * 60)
        XCTAssertNil(store.giveUp())  // 不足 5 分钟不产生记录
        XCTAssertTrue(store.records.isEmpty)

        XCTAssertTrue(store.start(minutes: 5))
        now = now.addingTimeInterval(5 * 60)
        store.refresh()
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.phase, .breaking)
        XCTAssertEqual(store.todayPomodoros, 1)
        XCTAssertEqual(store.todayMinutes, 5)
        now = now.addingTimeInterval(5 * 60)
        store.refresh()
        XCTAssertEqual(store.phase, .idle)

        XCTAssertTrue(store.start(minutes: 5))
        now = now.addingTimeInterval(4 * 60 + 30)
        XCTAssertEqual(store.finishEarly()?.minutes, 5)
        XCTAssertEqual(store.phase, .breaking)
        XCTAssertEqual(store.todayPomodoros, 2)
        XCTAssertEqual(store.todayMinutes, 10)
        XCTAssertEqual(store.records.count, 2)

        let deletedID = try XCTUnwrap(store.records.last?.id)
        store.deleteRecord(deletedID)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.todayPomodoros, 1)
        XCTAssertEqual(store.todayMinutes, 5)

        let done = expectation(description: "flush")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        let reloaded = FocusStore(clock: { now }, directory: directory)
        XCTAssertEqual(reloaded.records, store.records)
        XCTAssertEqual(reloaded.preferences.focusMinutes, 5)
    }

    // MARK: 自动开始下一番茄

    func testBreakEndAutoStartsNextPomodoroWithSameTaskWhenEnabled() {
        let (engine, advance) = makeEngine(focusMinutes: 5, breakMinutes: 5)
        engine.apply(PomodoroSettings(focusMinutes: 5, breakMinutes: 5, longBreakMinutes: 15,
                                      longBreakInterval: 4, autoStartNextPomodoro: true))
        let taskID = UUID()
        XCTAssertTrue(engine.start(taskID: taskID, focusMinutes: 5))
        advance(5 * 60)
        XCTAssertNotNil(engine.handleCompletion())  // 专注完成 → 进入休息
        XCTAssertEqual(engine.phase, .breaking)
        advance(5 * 60)
        XCTAssertNil(engine.handleCompletion())     // 休息到点 → 自动开始下一番茄
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.currentTaskID, taskID)  // 同一任务续上
        XCTAssertEqual(engine.remainingSeconds, 5 * 60)
    }

    func testBreakEndStaysIdleWhenAutoStartDisabled() {
        let (engine, advance) = makeEngine(focusMinutes: 5, breakMinutes: 5)
        XCTAssertTrue(engine.start(taskID: UUID(), focusMinutes: 5))
        advance(5 * 60)
        _ = engine.handleCompletion()
        XCTAssertEqual(engine.phase, .breaking)
        advance(5 * 60)
        _ = engine.handleCompletion()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.currentTaskID)
    }
}
