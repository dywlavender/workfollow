import XCTest
@testable import WorkFollow

@MainActor
final class FocusPresetLibraryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        value.firstWeekday = 1
        return value
    }
    private var base: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))! }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("focus-library-\(UUID().uuidString)")
    }
    private func flush(_ store: FocusStore) async {
        let done = expectation(description: "focus library persisted")
        store.flush { error in XCTAssertNil(error); done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
    }

    func testIdleEntryUsesLibraryAndTaskStartOrRestoredSessionUsesTimer() async {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertEqual(store.workspacePage, .library)
        XCTAssertTrue(store.activeTimers.isEmpty)
        store.showTimerWorkspace()
        XCTAssertEqual(store.workspacePage, .timer, "Empty library can still expand an idle timer")
        store.showPresetLibrary()
        let taskID = UUID()
        XCTAssertTrue(store.start(taskID: taskID, minutes: 25))
        XCTAssertEqual(store.workspacePage, .timer)
        now = base.addingTimeInterval(90); XCTAssertTrue(store.pause())
        let timing = store.sessionTiming
        store.showPresetLibrary()
        XCTAssertEqual(store.phase, .pausedFocus)
        await flush(store)

        let restored = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertEqual(restored.workspacePage, .timer)
        XCTAssertEqual(restored.phase, .pausedFocus)
        XCTAssertEqual(restored.sessionTiming, timing)
        XCTAssertEqual(restored.currentTaskID, taskID)
        XCTAssertEqual(restored.elapsedSeconds, 90)
    }

    func testRestoredCompletionOpensTimerEvenIfItsLastDisplayWasTheLibrary() async throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(300); store.refresh()
        let id = try XCTUnwrap(store.completedRecord?.id)
        store.showPresetLibrary()
        await flush(store)

        let restored = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertEqual(restored.workspacePage, .timer)
        XCTAssertEqual(restored.completionContext?.recordID, id)
        XCTAssertEqual(restored.completedRecord?.id, id)
        XCTAssertTrue(restored.pendingBreak)
        XCTAssertEqual(restored.records.count, 1)
    }

    func testBrowsingDoesNotChangeDefaultsAndPlayStartsOnlyThatPresetInTheSharedSession() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        let taskID = UUID()
        XCTAssertTrue(store.setFocusMinutes(180))
        XCTAssertTrue(store.addTimer(name: "阅读", emoji: "📚", stopwatch: false, minutes: 10, taskID: taskID))
        XCTAssertTrue(store.addTimer(name: "写作", emoji: "💻", stopwatch: false, minutes: 50))
        let reading = store.timers[0], writing = store.timers[1]
        let defaults = store.preferences

        store.selectPresetForDetails(reading.id)
        XCTAssertEqual(store.workspacePage, .library)
        XCTAssertEqual(store.browsedPresetID, reading.id)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.preferences, defaults)
        XCTAssertEqual(store.presentation.displaySeconds, 180 * 60)
        XCTAssertTrue(store.startTimerPreset(reading.id))
        XCTAssertEqual(store.workspacePage, .timer)
        XCTAssertEqual(store.currentSessionPresetID, reading.id)
        XCTAssertEqual(store.currentTaskID, taskID)
        XCTAssertEqual(store.phaseSeconds, 600)
        XCTAssertEqual(store.preferences, defaults)

        store.showPresetLibrary()
        store.selectPresetForDetails(writing.id)
        now = base.addingTimeInterval(15); store.refresh()
        XCTAssertEqual(store.currentSessionPresetID, reading.id)
        XCTAssertEqual(store.currentTaskID, taskID)
        XCTAssertEqual(store.phaseSeconds, 600)
        XCTAssertEqual(store.elapsedSeconds, 15)
        XCTAssertEqual(store.browsedPresetID, writing.id)
        XCTAssertEqual(store.preferences, defaults)
        store.selectPresetForDetails(reading.id)
        store.showTimerWorkspace()
        XCTAssertEqual(store.elapsedSeconds, 15)
        XCTAssertTrue(store.pause())
        XCTAssertTrue(store.perform(.end))
        XCTAssertEqual(store.workspacePage, .library)
        XCTAssertEqual(store.browsedPresetID, reading.id, "Short end keeps the preset detail selected in the library")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.preferences, defaults)
    }

    func testReturningToLibraryAndReopeningCompletionKeepsTheSameRecordAndPendingExtraClock() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.addTimer(name: "五分钟", emoji: "🍅", stopwatch: false, minutes: 5))
        let preset = store.timers[0]
        XCTAssertTrue(store.startTimerPreset(preset.id))
        now = base.addingTimeInterval(300); store.refresh()
        let record = try XCTUnwrap(store.completedRecord)

        store.showPresetLibrary()
        XCTAssertEqual(store.browsedPresetID, preset.id)
        now = base.addingTimeInterval(330); store.refresh()
        store.showTimerWorkspace()

        XCTAssertEqual(store.workspacePage, .timer)
        XCTAssertEqual(store.completionContext?.recordID, record.id)
        XCTAssertEqual(store.completedRecord, record)
        XCTAssertEqual(store.availableExtraSeconds, 30)
        XCTAssertTrue(store.pendingBreak)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).totalActiveSeconds, 300)
    }

    func testStopwatchPresetPlayKeepsDefaultPomodoroAndSavesItsPresetSource() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertTrue(store.setFocusMinutes(180))
        XCTAssertTrue(store.addTimer(name: "自由写作", emoji: "💻", stopwatch: true, minutes: 0))
        let preset = store.timers[0]
        store.selectPresetForDetails(preset.id)
        XCTAssertEqual(store.presentation.mode, .pomodoro)
        XCTAssertEqual(store.presentation.displaySeconds, 180 * 60)

        XCTAssertTrue(store.startTimerPreset(preset.id))
        now = base.addingTimeInterval(90); store.refresh()

        XCTAssertEqual(store.presentation.mode, .stopwatch)
        XCTAssertEqual(store.presentation.displaySeconds, 90)
        XCTAssertFalse(store.preferences.stopwatchMode)
        XCTAssertEqual(store.preferences.focusMinutes, 180)
        XCTAssertTrue(store.perform(.end))
        let record = try XCTUnwrap(store.completedRecord)
        XCTAssertEqual(record.activeSeconds, 90)
        XCTAssertEqual(record.details?.presetID, preset.id)
        XCTAssertEqual(record.creditedPomodoros, 0)
    }

    func testPresetStatisticsUseFullHistoryAndCalendarPeriodRatherThanTheVisiblePage() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let preset = FocusStore.TimerPreset(id: UUID(), emoji: "📚", name: "阅读", stopwatch: false, minutes: 10)
        let other = FocusStore.TimerPreset(id: UUID(), emoji: "💻", name: "写作", stopwatch: false, minutes: 30)
        let today = calendar.startOfDay(for: base)
        var records = (0..<60).map { index in
            record(presetID: preset.id,
                start: calendar.date(byAdding: .day, value: -(index / 2 + 1), to: today)!.addingTimeInterval(Double(index % 2 + 9) * 3_600),
                seconds: 60)
        }
        records.append(record(presetID: preset.id, start: base.addingTimeInterval(-320), seconds: 320))
        records.append(record(presetID: other.id, start: base.addingTimeInterval(-1_800), seconds: 1_800))
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try JSONEncoder().encode(FocusStore.Archive(records: records, timers: [preset, other]))
            .write(to: path.appendingPathComponent("focus.json"))
        let store = FocusStore(clock: { self.base }, calendar: calendar, directory: path)
        await store.resetHistory()
        XCTAssertEqual(store.visibleRecords.count, 50)
        store.setRecordFilter(FocusRecordFilter(taskID: UUID()))

        let month = store.presetStatistics(presetID: preset.id, period: .month)
        let week = store.presetStatistics(presetID: preset.id, period: .week)

        XCTAssertEqual(month.focusDays, 31)
        XCTAssertEqual(month.totalActiveSeconds, 3_920)
        XCTAssertEqual(month.todayActiveSeconds, 320)
        XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(month.records.count, 29)
        XCTAssertEqual(month.periodActiveSeconds, 2_000)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.records.count, 9)
        XCTAssertEqual(week.periodActiveSeconds, 800)
        XCTAssertEqual(month.days.reduce(0) { $0 + $1.activeSeconds }, month.periodActiveSeconds)
        XCTAssertTrue(month.records.allSatisfy { $0.details?.presetID == preset.id })
    }

    func testPresetDetailsRefreshThroughManualRecordEditArchiveRestoreAndDeletion() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { self.base }, calendar: calendar, directory: path)
        XCTAssertTrue(store.setFocusMinutes(180))
        XCTAssertTrue(store.addTimer(name: "阅读", emoji: "📚", stopwatch: false, minutes: 10))
        var preset = store.timers[0]
        var draft = FocusRecordDraft(now: base, presetID: preset.id)
        draft.startedAt = base.addingTimeInterval(-600); draft.endedAt = base; draft.creditedPomodoros = 1
        XCTAssertTrue(store.saveRecordDraft(draft))
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).todayActiveSeconds, 600)
        var edit = FocusRecordDraft(record: try XCTUnwrap(store.record(id: draft.id)))
        edit.startedAt = calendar.date(byAdding: .day, value: -1, to: base)!.addingTimeInterval(-1_200)
        edit.endedAt = edit.startedAt.addingTimeInterval(1_200)
        edit.note = "昨日阅读"
        XCTAssertTrue(store.saveRecordDraft(edit))
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).todayActiveSeconds, 0)
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).totalActiveSeconds, 1_200)
        preset.name = "阅读与笔记"; preset.minutes = 20
        XCTAssertTrue(store.updateTimer(preset))
        XCTAssertEqual(store.preferences.focusMinutes, 180)

        store.archiveTimer(preset.id)
        XCTAssertTrue(store.activeTimers.isEmpty)
        XCTAssertEqual(store.archivedTimers.count, 1)
        XCTAssertFalse(store.startTimerPreset(preset.id))
        store.selectPresetForDetails(preset.id)
        XCTAssertEqual(store.presetLibrarySection, .archived)
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).totalActiveSeconds, 1_200)
        XCTAssertTrue(store.restoreTimer(preset.id))
        XCTAssertEqual(store.activeTimers.first?.name, "阅读与笔记")
        XCTAssertTrue(store.archivedTimers.isEmpty)
        var extra = FocusRecordDraft(now: base, presetID: preset.id)
        extra.startedAt = base.addingTimeInterval(-300); extra.endedAt = base
        XCTAssertTrue(store.saveRecordDraft(extra))
        let statistics = store.presetStatistics(presetID: preset.id)
        XCTAssertEqual(statistics.focusDays, 2)
        XCTAssertEqual(statistics.totalActiveSeconds, 1_500)
        XCTAssertEqual(statistics.todayActiveSeconds, 300)
        store.deleteRecord(draft.id)
        XCTAssertEqual(store.presetStatistics(presetID: preset.id).totalActiveSeconds, 300)
        await flush(store)
        let restored = FocusStore(clock: { self.base }, calendar: calendar, directory: path)
        XCTAssertEqual(restored.activeTimers.first?.name, "阅读与笔记")
        XCTAssertEqual(restored.presetStatistics(presetID: preset.id).totalActiveSeconds, 300)
    }

    func testExpandedIdleNotePersistsAndMovesIntoTheNextSession() async throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, calendar: calendar, directory: path)
        store.showPresetLibrary(); store.showTimerWorkspace()
        XCTAssertEqual(store.workspacePage, .timer)
        XCTAssertEqual(store.displayedSessionTiming?.phase, .idle)
        XCTAssertNil(store.displayedSessionTiming?.projectedEndAt)
        store.updateCurrentSessionNote("待开始的想法")
        await flush(store)
        let restored = FocusStore(clock: { now }, calendar: calendar, directory: path)
        XCTAssertEqual(restored.workspacePage, .library, "An idle draft is not a running or completed session")
        XCTAssertEqual(restored.currentSessionNote, "待开始的想法")
        XCTAssertTrue(restored.start(stopwatch: true))
        now = base.addingTimeInterval(90)
        let completed = try XCTUnwrap(restored.finishEarly())
        XCTAssertEqual(completed.activeSeconds, 90)
        XCTAssertEqual(completed.note, "待开始的想法")
    }

    private func record(presetID: UUID, start: Date, seconds: Int) -> PomodoroRecord {
        PomodoroRecord(id: UUID(), taskID: nil, startedAt: start,
            minutes: FocusAccountingPolicy.displayedMinutes(seconds: seconds), completed: true,
            details: FocusRecordDetails(mode: .pomodoro, source: .manual, termination: .manualEntry,
                endedAt: start.addingTimeInterval(TimeInterval(seconds)), activeSeconds: seconds, pausedSeconds: 0,
                pauseRanges: [], targetSeconds: nil, presetID: presetID, creditedPomodoros: 1,
                accountingPolicyVersion: FocusAccountingPolicy.version, precision: .second))
    }
}
